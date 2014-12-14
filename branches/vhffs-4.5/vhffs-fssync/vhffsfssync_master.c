/*
 *  VHFFSFSSYNC: Scalable file system replication over TCP
 *
 *  Copyright 2008-2011  Sylvain Rochet <gradator@gradator.net>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see http://www.gnu.org/licenses/.
 */

#ifndef __linux__
#error This software is only running on Linux-based OS, bye!
#endif

#define _FILE_OFFSET_BITS 64
#define _BSD_SOURCE

#define DEBUG_NET 0
#define DEBUG_INOTIFY 0
#define DEBUG_EVENTS 0
//#define NDEBUG

#include <assert.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <fcntl.h>
#include <dirent.h>
#include <string.h>
#include <errno.h>
#include <sys/inotify.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <glib.h>
#include <sys/select.h>
#include <signal.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/sendfile.h>
#include <getopt.h>


/* -- inotify stuff -- */

#define VHFFSFSSYNC_BUF_LEN 4096
#define VHFFSFSSYNC_WATCH_MASK_FILE IN_ATTRIB|IN_MODIFY|IN_DONT_FOLLOW
#define VHFFSFSSYNC_WATCH_MASK_DIR IN_ATTRIB|IN_CREATE|IN_DELETE|IN_MOVED_FROM|IN_MOVED_TO|IN_DONT_FOLLOW|IN_ONLYDIR

// each monitor entry is associated with a path, we need to keep it to compute the path
//char **vhffsfssync_wd_to_watch = NULL;
//int vhffsfssync_wd_to_watch_len = 0;  // number of allocated paths
GHashTable *vhffsfssync_wd_to_watch;


typedef struct vhffsfssync_watch_ {
	int wd;
	char *name;
	struct vhffsfssync_watch_ *parent;
} vhffsfssync_watch;

// return a timestamp in ms (it loops for 100000 sec)
/*inline int vhffsfssync_timestamp()  {
	struct timeval tv;
	gettimeofday(&tv, NULL);
 	return (tv.tv_sec%100000)*1000+tv.tv_usec/1000;
}*/

struct vhffsfssync_cookie {
	uint32_t id;
	vhffsfssync_watch *watch;
	char *filename;
	gboolean isdir;
};
static struct vhffsfssync_cookie vhffsfssync_cookie;

// protos
char *vhffsfssync_pathname(vhffsfssync_watch *watch, const char *filename);
vhffsfssync_watch *vhffsfssync_add_watch(int inotifyfd, vhffsfssync_watch *parent, const char *dirname, uint32_t mask);
int vhffsfssync_del_watch(int inotifyfd, vhffsfssync_watch *watch);
vhffsfssync_watch *vhffsfssync_add_watch_recursively(int inotifyfd, vhffsfssync_watch *parent, const char *dirname);
int vhffsfssync_manage_event_remove(int inotifyfd, vhffsfssync_watch *watch, char *filename);
int vhffsfssync_manage_event_create(int inotifyfd, vhffsfssync_watch *watch, char *filename);
int vhffsfssync_manage_event(int inotifyfd, struct inotify_event *event);
int vhffsfssync_fake_events_recursively(int inotifyfd, vhffsfssync_watch *watch);


/* -- network stuff -- */
// huge buffer size reduce syscalls
#define VHFFSFSSYNC_NET_MESSAGE_FILE_CHUNK 65536
#define VHFFSFSSYNC_NET_RECV_CHUNK 65536
#define VHFFSFSSYNC_NET_RECV_OVERFLOW 10485760

GList *vhffsfssync_conns;

typedef struct {
	int fd;
	struct sockaddr_in sockaddr;
	uint32_t order;

	char *recvbuf;
	uint32_t recvbuf_begin;
	uint32_t recvbuf_end;

	char **delayedevents;
	uint32_t delayedevents_begin;
	uint32_t delayedevents_end;

	GList *messages;
	uint32_t messages_num;

	GList *fullviewtree;
	GList *fullviewcur;
	int8_t fullviewtimerset;
} vhffsfssync_conn;


/* message - generic */
typedef unsigned short int msg_family_t;
enum  {
	VHFFSFSSYNC_NET_MESSAGE_UNSPEC=0,
	VHFFSFSSYNC_NET_MESSAGE_DATA,
	VHFFSFSSYNC_NET_MESSAGE_FILE
};

/* message - priorities */
enum  {
	VHFFSFSSYNC_NET_PRIO_HIGHEST=100,   // values < 100 may be used internally, please don't set anything below 100 or die!
	VHFFSFSSYNC_NET_PRIO_HIGH,          // values >= 1000 are used for files, don't use them too
	VHFFSFSSYNC_NET_PRIO_MEDIUM,
	VHFFSFSSYNC_NET_PRIO_LOW,
	VHFFSFSSYNC_NET_PRIO_LOWEST
};


#define __VHFFSFSSYNC_NET_MESSAGE_COMMON(msg_prefix) \
  msg_family_t msg_prefix##family;  \
  uint32_t msg_prefix##priority; \
  uint32_t msg_prefix##order

#define __VHFFSFSSYNC_NET_MESSAGE_COMMON_SIZE ( sizeof (msg_family_t) + sizeof(uint32_t) + sizeof(uint32_t) )

typedef struct {
	__VHFFSFSSYNC_NET_MESSAGE_COMMON(msg_);
	char msg_data[64];
} vhffsfssync_net_message;

/* message - common data */
typedef struct {
	__VHFFSFSSYNC_NET_MESSAGE_COMMON(data_);
	char *data_buffer;
	ssize_t data_len;
	ssize_t data_cur;

	/* pad to size of `vhffsfssync_net_message'  */
	unsigned char sin_zero[ sizeof(vhffsfssync_net_message)
	 - __VHFFSFSSYNC_NET_MESSAGE_COMMON_SIZE
	 - sizeof(char*)
	 - sizeof(ssize_t)
	 - sizeof(ssize_t) ];
} vhffsfssync_net_message_data;

/* net - filehandle */
typedef struct {
	char *file_pathname;
	int file_fd;
	int ref;
	struct stat file_stat;
} vhffsfssync_net_file;

GHashTable *vhffsfssync_net_files;


/* message - file */
typedef struct {
	__VHFFSFSSYNC_NET_MESSAGE_COMMON(file_);
	vhffsfssync_net_file *file;
	off_t file_offset;
	ssize_t file_chunksize;
	ssize_t file_chunkcur;

	/* pad to size of `vhffsfssync_net_message'  */
	unsigned char sin_zero[ sizeof(vhffsfssync_net_message)
	 - __VHFFSFSSYNC_NET_MESSAGE_COMMON_SIZE
	 - sizeof(vhffsfssync_net_file*)
	 - sizeof(off_t)
	 - sizeof(ssize_t)
	 - sizeof(ssize_t) ];
} vhffsfssync_net_message_file;



// protos
void vhffsfssync_net_conn_disable(vhffsfssync_conn *conn);
void vhffsfssync_net_conn_destroy(vhffsfssync_conn *conn);
inline vhffsfssync_net_message *vhffsfssync_net_new_message(vhffsfssync_conn *conn, msg_family_t family, uint32_t priority);
gint vhffsfssync_net_message_insert_compare(gconstpointer a, gconstpointer b);
inline void vhffsfssync_net_destroy_message(vhffsfssync_conn *conn, vhffsfssync_net_message *msg);
int vhffsfssync_net_send_data(vhffsfssync_conn *conn, char *data, ssize_t len, uint32_t priority);
void vhffsfssync_net_destroy_data(vhffsfssync_conn *conn, vhffsfssync_net_message_data *datamsg);
//inline int vhffsfssync_net_send_string(vhffsfssync_conn *conn, char *data, uint32_t priority) ;
inline ssize_t vhffsfssync_net_event_len(char *data);
inline int vhffsfssync_net_send_event(vhffsfssync_conn *conn, char *data, uint32_t priority);
//void vhffsfssync_net_broadcast_string(char *data, uint32_t priority);
void vhffsfssync_net_broadcast_event(char *data, uint32_t priority);
int vhffsfssync_net_send_file(vhffsfssync_conn *conn, char *pathname);
void vhffsfssync_net_destroy_file(vhffsfssync_conn *conn, vhffsfssync_net_message_file *filemsg);
vhffsfssync_net_file *vhffsfssync_net_file_open(const char *pathname);
int vhffsfssync_net_file_close(vhffsfssync_net_file *file);
int vhffsfssync_net_remove_file(vhffsfssync_conn *conn, char *pathname);
void vhffsfssync_net_broadcast_file(char *pathname);
char *vhffsfssync_net_parent_attrib(char *pathname);
int vhffsfssync_net_send(vhffsfssync_conn *conn);
int vhffsfssync_net_recv_event(vhffsfssync_conn *conn, char *event);
int vhffsfssync_net_parse(vhffsfssync_conn *conn);
int vhffsfssync_net_parse_delayed(vhffsfssync_conn *conn);
int vhffsfssync_net_fullview(vhffsfssync_conn *conn, char *pathname);
void vhffsfssync_net_fullview_alarmsignal(int signo);


// misc
static void usage_exit(int ret_code, char *progname);

/* ----------------------------------------- */

/* -- network stuff -- */
void vhffsfssync_net_conn_disable(vhffsfssync_conn *conn)  {
	GList *msgs, *lst, *lst2;

	if(conn->fd >= 0) {
#if DEBUG_NET
		printf("Byebye %s... (used fd %d)\n", inet_ntoa(conn->sockaddr.sin_addr), conn->fd);
#endif
		shutdown(conn->fd, SHUT_RDWR);
		close(conn->fd);
	}
	conn->fd = -1;

	while( (msgs = g_list_first(conn->messages)) )  {
		vhffsfssync_net_destroy_message(conn, (vhffsfssync_net_message*)msgs->data );
	}

	conn->fullviewcur = NULL;
	conn->fullviewtimerset = 0;
	while( (lst = g_list_first(conn->fullviewtree)) ) {
		while( (lst2 = g_list_first(lst->data)) ) {
			free(lst2->data);
			lst->data = g_list_delete_link(lst->data, lst2);
		}
		conn->fullviewtree = g_list_delete_link(conn->fullviewtree, lst);
	}

	if(conn->delayedevents) {
		uint32_t i;
		for(i = conn->delayedevents_begin ; i < conn->delayedevents_end ; i++)
			free(conn->delayedevents[i]);
		free(conn->delayedevents);
	}
	conn->delayedevents = NULL;
	conn->delayedevents_begin = 0;
	conn->delayedevents_end = 0;

	if(conn->recvbuf) free(conn->recvbuf);
	conn->recvbuf = NULL;
	conn->recvbuf_begin = 0;
	conn->recvbuf_end = 0;
}


void vhffsfssync_net_conn_destroy(vhffsfssync_conn *conn)  {
	vhffsfssync_conns = g_list_remove(vhffsfssync_conns, conn);
	vhffsfssync_net_conn_disable(conn);
	free(conn);
}


inline vhffsfssync_net_message *vhffsfssync_net_new_message(vhffsfssync_conn *conn, msg_family_t family, uint32_t priority)  {
	vhffsfssync_net_message *msg;
	msg = malloc( sizeof(vhffsfssync_net_message) );
	msg->msg_family = family;
	msg->msg_priority = priority;
	msg->msg_order = conn->order++;
	return msg;
}


gint vhffsfssync_net_message_insert_compare(gconstpointer a, gconstpointer b)  {
	vhffsfssync_net_message *first = (vhffsfssync_net_message*)a;
	vhffsfssync_net_message *second = (vhffsfssync_net_message*)b;

	if(first->msg_priority != second->msg_priority) {
		// lowest priority is preferred
		if(first->msg_priority < second->msg_priority)
			return -1;
		else
			return 1;

		// Don't expect to do 'return first->msg_priority - second->msg_priority;'
		// even if this seems more convenient, because msg->msg_priority is
		// an __unsigned__ long integer, you also have to return a signed long integer value
	}
	else {
		// lowest order is preferred
		if(first->msg_order < second->msg_order)
			return -1;
		else
			return 1;

		// Don't expect to do 'return first->msg_order - second->msg_order;'
		// for the same reasons explained above
	}
	return 0;
}


inline void vhffsfssync_net_destroy_message(vhffsfssync_conn *conn, vhffsfssync_net_message *msg) {
	if(msg->msg_family == VHFFSFSSYNC_NET_MESSAGE_DATA)  {
		vhffsfssync_net_destroy_data(conn, (vhffsfssync_net_message_data*)msg);
	}
	else if(msg->msg_family == VHFFSFSSYNC_NET_MESSAGE_FILE)  {
		vhffsfssync_net_destroy_file(conn, (vhffsfssync_net_message_file*)msg);
	}
}


// !!!!!! the buffer is freed when the message has been sent, DON'T send static string and DON'T free() the data yourself
int vhffsfssync_net_send_data(vhffsfssync_conn *conn, char *data, ssize_t len, uint32_t priority)  {
	vhffsfssync_net_message_data *msg;
	if(!conn || !data || len <= 0) return -1;

	msg = (vhffsfssync_net_message_data*)vhffsfssync_net_new_message(conn, VHFFSFSSYNC_NET_MESSAGE_DATA, priority);
	msg->data_buffer = data;
	msg->data_len = len;
	msg->data_cur = 0;
	conn->messages = g_list_insert_sorted(conn->messages, msg, vhffsfssync_net_message_insert_compare);
	conn->messages_num++;

	return 0;
}


void vhffsfssync_net_destroy_data(vhffsfssync_conn *conn, vhffsfssync_net_message_data *datamsg)  {
	conn->messages = g_list_remove(conn->messages, (vhffsfssync_net_message*)datamsg);
	conn->messages_num--;
	free(datamsg->data_buffer);
	free(datamsg);
}

/*
inline int vhffsfssync_net_send_string(vhffsfssync_conn *conn, char *data, uint32_t priority)  {
	return vhffsfssync_net_send_data(conn, data, strlen(data), priority);
}
*/

/* our events use \0 as a delimiter, a double \0 is the end of the event */
inline ssize_t vhffsfssync_net_event_len(char *data)  {
	ssize_t len = 0;
	do {
		len += strlen(data+len);  //glibc strlen() is incredibly fast, we use it as much as possible
		len++;
	} while( *(data+len) );
	len++;
	return len;
}

inline int vhffsfssync_net_send_event(vhffsfssync_conn *conn, char *data, uint32_t priority)  {

	if(!data) return -1;

	return vhffsfssync_net_send_data(conn, data, vhffsfssync_net_event_len(data), priority);
}

/*
void vhffsfssync_net_broadcast_string(char *data, uint32_t priority)  {

	GList *conns;
	for(conns = g_list_first(vhffsfssync_conns) ; conns ; )  {
		vhffsfssync_conn *conn = conns->data;
		conns = g_list_next(conns);

		vhffsfssync_net_send_string(conn, strdup(data), priority);
	}
	free(data);
}
*/

void vhffsfssync_net_broadcast_event(char *data, uint32_t priority)  {

	GList *conns;
	ssize_t len;

	if(!data) return;

	len = vhffsfssync_net_event_len(data);
	for(conns = g_list_first(vhffsfssync_conns) ; conns ; )  {
		vhffsfssync_conn *conn = conns->data;
		char *d;
		conns = g_list_next(conns);

		d = malloc(len);
		memcpy(d, data, len);
		vhffsfssync_net_send_data(conn, d, len, priority);
	}
	free(data);
}


// prototype is simple, files are always the lowest of the lowest priority messages
int vhffsfssync_net_send_file(vhffsfssync_conn *conn, char *pathname)  {
	vhffsfssync_net_message_file *msg;
	uint32_t maxprio = -1;  // 4294967295
	vhffsfssync_net_file *file;

	if(!conn || !pathname)
		return -1;

	file = vhffsfssync_net_file_open(pathname);
	if(!file)
		return -1;

	//printf("%d SENDING FILE %s\n", conn->fd, pathname);
	vhffsfssync_net_send_event(conn, g_strdup_printf("open%c%s%c%d%c%d%c%d%c", '\0', pathname, '\0', file->file_stat.st_mode&07777, '\0', file->file_stat.st_uid, '\0', file->file_stat.st_gid, '\0') , VHFFSFSSYNC_NET_PRIO_MEDIUM);
	vhffsfssync_net_send_event(conn, vhffsfssync_net_parent_attrib(pathname) , VHFFSFSSYNC_NET_PRIO_MEDIUM);

	// the size of the file is the priority (small files are sent with more priority)
	// but don't set the priority too low, low value can be used for anything else
	msg = (vhffsfssync_net_message_file*)vhffsfssync_net_new_message(conn, VHFFSFSSYNC_NET_MESSAGE_FILE, MAX(MIN(file->file_stat.st_size, maxprio),1000) );
	msg->file = file;
	msg->file_offset = 0;
	msg->file_chunksize = -1;
	msg->file_chunkcur = 0;
	conn->messages = g_list_insert_sorted(conn->messages, msg, vhffsfssync_net_message_insert_compare);
	conn->messages_num++;

	return 0;
}


void vhffsfssync_net_destroy_file(vhffsfssync_conn *conn, vhffsfssync_net_message_file *filemsg)  {

	struct stat st;
	time_t mtime;

	conn->messages = g_list_remove(conn->messages, (vhffsfssync_net_message*)filemsg);
	conn->messages_num--;

	/* we need to finish the chunk anyway */
	if(filemsg->file_chunksize > 0) {
		off_t len = filemsg->file_chunksize - filemsg->file_chunkcur;
		if(len > 0) {
			char *data = malloc(len);
			memset(data, 0, len);
			vhffsfssync_net_send_data(conn, data, len, 0);
		}
	}

	if( lstat(filemsg->file->file_pathname, &st) < 0 ) {
		mtime = filemsg->file->file_stat.st_mtime;
	} else {
		mtime = st.st_mtime;
	}

	vhffsfssync_net_send_event(conn, g_strdup_printf("close%c%s%c%ld%c", '\0', filemsg->file->file_pathname, '\0', mtime, '\0') , VHFFSFSSYNC_NET_PRIO_MEDIUM);
	vhffsfssync_net_file_close(filemsg->file);
	free(filemsg);
}


vhffsfssync_net_file *vhffsfssync_net_file_open(const char *pathname)  {
	vhffsfssync_net_file *file;
	struct stat st;
	int fd;

	if(!pathname)
		return NULL;

	file = g_hash_table_lookup(vhffsfssync_net_files, pathname);
	if(file) {
		file->ref++;
		return file;
	}

	if( lstat(pathname, &st) < 0 ) {
		fprintf(stderr, "lstat() failed on %s: %s\n", pathname, strerror(errno));
		return NULL;
	}

	/* only copy regular files */
	if(! S_ISREG(st.st_mode) ) {
		fprintf(stderr, "%s is not a regular file\n", pathname);
		return NULL;
	}

	fd = open(pathname, O_RDONLY);
	if(fd < 0) {
		fprintf(stderr, "open() failed on %s: %s\n", pathname, strerror(errno));
		return NULL;
	}

	file = malloc(sizeof(vhffsfssync_net_file));
	file->file_fd = fd;
	file->file_pathname = strdup(pathname);
	memcpy(&file->file_stat, &st, sizeof(struct stat));
	file->ref = 1;
	g_hash_table_insert(vhffsfssync_net_files, file->file_pathname, file);
	return file;
}


int vhffsfssync_net_file_close(vhffsfssync_net_file *file)  {
	int r;

	if(!file)
		return -1;

	file->ref--;
	if(file->ref)
		return 0;

	g_hash_table_remove(vhffsfssync_net_files, file->file_pathname);

	if(file->file_fd >= 0) {
		r = close(file->file_fd);
		if(r) fprintf(stderr, "close() failed: %s\n", strerror(errno));
	}

	free(file->file_pathname);
	free(file);
	return r;
}


void vhffsfssync_net_broadcast_file(char *pathname)  {

	GList *conns;

	// if the file is being sent, cancel it
	for(conns = g_list_first(vhffsfssync_conns) ; conns ; )  {
		vhffsfssync_conn *conn = conns->data;
		conns = g_list_next(conns);
		vhffsfssync_net_remove_file(conn, pathname);
	}

	for(conns = g_list_first(vhffsfssync_conns) ; conns ; )  {
		vhffsfssync_conn *conn = conns->data;
		conns = g_list_next(conns);
		vhffsfssync_net_send_file(conn, pathname);
	}
}


int vhffsfssync_net_remove_file(vhffsfssync_conn *conn, char *pathname)  {
	GList *msgs;
	for(msgs = g_list_first(conn->messages) ; msgs ; )  {
		vhffsfssync_net_message *msg = msgs->data;
		msgs = g_list_next(msgs);

		if(msg->msg_family == VHFFSFSSYNC_NET_MESSAGE_FILE)  {
			vhffsfssync_net_message_file *filemsg = (vhffsfssync_net_message_file*)msg;
			if(filemsg->file && !strcmp(filemsg->file->file_pathname, pathname)) {
				//printf("%d CANCELLING %s\n", conn->fd, pathname);
				vhffsfssync_net_destroy_file(conn, filemsg);
			}
		}
	}
	return 0;
}


char *vhffsfssync_net_parent_attrib(char *pathname)  {
	char *cur;
	struct stat st;
	char *ret = NULL;

	for( cur = pathname+strlen(pathname) ; *cur != '/' ; cur-- );
	*cur = '\0';

	if( !lstat(pathname, &st) )  {
		ret = g_strdup_printf("attrib%c%s%c%ld%c%d%c%d%c%d%c", '\0', pathname, '\0', st.st_mtime, '\0', st.st_mode&07777, '\0', st.st_uid, '\0', st.st_gid, '\0');
	}
	else {
		if(errno == ENOENT) {
			// file already disappeared (common for temporary files)
		} else {
			fprintf(stderr, "cannot lstat() '%s': %s\n", pathname, strerror(errno));
		}
	}

	*cur = '/';
	return ret;
}


int vhffsfssync_net_send(vhffsfssync_conn *conn)  {
	GList *msgs;
	gboolean full = FALSE;

	if(!conn || conn->fd < 0) return -1;
#if DEBUG_NET
	printf("--------------------------------------------------\n");
	printf("conn: %d, to: %s\n", conn->fd, inet_ntoa(conn->sockaddr.sin_addr));
#endif
	while(!full  &&  conn->fd >= 0  &&  (msgs = g_list_first(conn->messages)) )  {
		vhffsfssync_net_message *msg = msgs->data;
#if DEBUG_NET
 		printf("  family: %d , priority: %d , order: %d\n", msg->msg_family, msg->msg_priority, msg->msg_order);
#endif
		// data
		if(msg->msg_family == VHFFSFSSYNC_NET_MESSAGE_DATA)  {
			vhffsfssync_net_message_data *datamsg;
			ssize_t written;
			ssize_t lentowrite;

			// we need to make sure that the message will not be truncated, we set the current message to the highest priority
			msg->msg_priority = 0;

			datamsg = (vhffsfssync_net_message_data*)msg;
#if DEBUG_NET
			printf("    buffer: %ld bytes, %ld already written\n", (long int)datamsg->data_len, (long int)datamsg->data_cur);
#endif
			/* try to empty the buffer */
			lentowrite = datamsg->data_len - datamsg->data_cur;
			written = write(conn->fd, datamsg->data_buffer + datamsg->data_cur, lentowrite);
			if(written < 0) {
				switch(errno)  {
					case EAGAIN:
					case EINTR:
#if DEBUG_NET
						printf("=====> EAGAIN on write()\n");
#endif
						full = TRUE;
						break;
					default:
						fprintf(stderr, "write() failed on socket %d: %s\n", conn->fd, strerror(errno));
						vhffsfssync_net_conn_disable(conn);
				}
			}
			else {
				datamsg->data_cur += written;
#if DEBUG_NET
				printf("      %ld bytes written on %ld bytes\n", (long int)written, (long int)lentowrite);
#endif
				/* the buffer is not empty yet (but the SendQ into the kernel is full) */
				if(written < lentowrite) {
					full = TRUE;
				}
				/* buffer is now empty */
				else {
					vhffsfssync_net_destroy_data(conn, datamsg);
				}
			}
		}

		// file
		else if(msg->msg_family == VHFFSFSSYNC_NET_MESSAGE_FILE)  {
			vhffsfssync_net_message_file *filemsg;
			ssize_t written;
			ssize_t lentowrite;

			filemsg = (vhffsfssync_net_message_file*)msg;

			// we need to open the file
/*			if(filemsg->file->file_fd < 0) {
				filemsg->file->file_fd = open(filemsg->file->file_pathname, O_RDONLY);
				if(filemsg->file->file_fd < 0) {
					fprintf(stderr, "open() failed on %s: %s\n", filemsg->file->file_pathname, strerror(errno));
					vhffsfssync_net_destroy_file(conn, filemsg);
					continue;
				}
			} */
#if DEBUG_NET
			printf("    file: %s, offset = %lld, size = %lld\n", filemsg->file->file_pathname, (long long int)filemsg->file_offset, (long long int)filemsg->file->file_stat.st_size);
#endif
			/* new chunk */
			if(filemsg->file_chunksize < 0)  {
				lentowrite = filemsg->file_chunksize = MIN(VHFFSFSSYNC_NET_MESSAGE_FILE_CHUNK, filemsg->file->file_stat.st_size - filemsg->file_offset);
				filemsg->file_chunkcur = 0;
				// we need to make sure that the chunk will not be truncated, we set the current message to the highest priority
				msg->msg_priority = 1;
				vhffsfssync_net_send_event(conn, g_strdup_printf("write%c%s%c%lld%c%ld%c", '\0', filemsg->file->file_pathname, '\0', (long long int)filemsg->file_offset, '\0', (long int)filemsg->file_chunksize, '\0') , 0);
				// we need to reset here in order to consider the new priorities
				continue;
			}
			/* the previous chunk was partially sent */
			else  {
				lentowrite = filemsg->file_chunksize - filemsg->file_chunkcur;
			}

			/* try to send the file */
			written = sendfile(conn->fd, filemsg->file->file_fd, &filemsg->file_offset, lentowrite);
			if(written < 0) {
				switch(errno)  {
					case EAGAIN:
					case EINTR:
#if DEBUG_NET
						printf("=====> EAGAIN on sendfile()\n");
#endif
						full = TRUE;
						break;
					default:
						fprintf(stderr, "sendfile() failed from file %s to socket %d: %s\n", filemsg->file->file_pathname, conn->fd, strerror(errno));
						vhffsfssync_net_conn_disable(conn);
				}
			}
			else {
#if DEBUG_NET
				printf("      %ld bytes written, we are at offset %lld\n", (long int)written, (long long int)filemsg->file_offset);
#endif
				filemsg->file_chunkcur += written;

				/* end of file or file completed */
				if( written == 0 || filemsg->file_offset == filemsg->file->file_stat.st_size )  {
					vhffsfssync_net_destroy_file(conn, filemsg);
				}

				/* the chunk is not fully sent yet */
				else if(written < lentowrite) {
					full = TRUE;
				}

				/* the chunk is sent */
				else if(written == lentowrite) {
					uint32_t maxprio = -1;  // 4294967295

					filemsg->file_chunksize = -1;
					filemsg->file_chunkcur = 0;

					// reschedule this file to a nicer priority
					msg->msg_priority = MAX(MIN(filemsg->file->file_stat.st_size - filemsg->file_offset, maxprio), 1000);
					conn->messages = g_list_remove(conn->messages, msg);
					conn->messages = g_list_insert_sorted(conn->messages, msg, vhffsfssync_net_message_insert_compare);
				}
			}
		}

		// I don't want to stay in this jail
		else full = TRUE;
	}

	return 0;
}


#if 0
int vhffsfssync_net_write(vhffsfssync_conn *conn, char *buffer, ssize_t len)  {

	ssize_t written = -1;

	/* new data to send */
	if(buffer  &&  len > 0)  {
		written = 0;
		// buffer is empty, try to send the data directly (it avoids copying the data twice)
		if(conn->sendbuf_size == 0)  {
			written = write(conn->fd, buffer, len);
			if(written < 0)  {
				switch(errno)  {
					case EAGAIN:
					case EINTR:
						printf("=====> EAGAIN on write()\n");
						break;
					default:
						fprintf(stderr, "write() failed on socket %d: %s\n", conn->fd, strerror(errno));
				}
				written = 0;
			}
		}

		printf("%d bytes written on %d bytes\n", written, len);

		/* this is the case if the buffer is not empty, or if the write failed, or if the write didn't write everything */
		if(written < len) {
			ssize_t lentobuf = len-written;
			printf("buffering %d bytes\n", lentobuf);

			/* As you may have noticed, the buffer is only growing as long as it still
			 * contains data to be sent, here we try to deal with that, as it needs data
			 * to be copied, we hope that it is not going to happen very often
			 */

			conn->sendbuf = realloc(conn->sendbuf, conn->sendbuf_size+lentobuf);
			memcpy(conn->sendbuf+conn->sendbuf_size, buffer+written, lentobuf);
			conn->sendbuf_size += lentobuf;
			printf("buffer size = %d\n", conn->sendbuf_size);
		}
	}

	/* try to empty the buffer */
	if(!buffer  &&  len == 0  &&  conn->sendbuf_size > 0) {
		ssize_t lentowrite = conn->sendbuf_size - conn->sendbuf_cur;
		written = write(conn->fd, conn->sendbuf + conn->sendbuf_cur, lentowrite);
		if(written < 0) {
			switch(errno)  {
				case EAGAIN:
				case EINTR:
					printf("=====> EAGAIN on write()\n");
					break;
				default:
					fprintf(stderr, "write() failed on socket %d: %s\n", conn->fd, strerror(errno));
			}
			written = 0;
		}

		if(written > 0)  {
			printf("%d bytes written on %d bytes\n", written, lentowrite);

			/* the buffer is not empty yet */
			if(written < lentowrite) {
				conn->sendbuf_cur += written;
			}
			/* buffer is now empty */
			else {
				printf("buffer is now empty\n");
				free(conn->sendbuf);
				conn->sendbuf = NULL;
				conn->sendbuf_cur = 0;
				conn->sendbuf_size = 0;
			}
		}
	}

	return written;
}
#endif


int vhffsfssync_net_recv_event(vhffsfssync_conn *conn, char *event)  {
	char *cur, **args = NULL;
	int argalloc = 0, argc = 0;

	do {
		for(cur = event ; *cur++ != '\0' ; );

		if(argc >= argalloc)  {
			argalloc = ( (argc >>8) +1) <<8;
			args = realloc( args, argalloc * sizeof(char*) );
		}

		args[argc++] = event;
		event = cur;
	} while(*event);
	if(!argc) return -1;

#if DEBUG_EVENTS
	int i;
	for(i = 0 ; i < argc ; i++) {
		fprintf(stderr, "%s ", args[i]);
	}
	fprintf(stderr, "\n");
#endif

	if(!strcmp(args[0], "get")) {
		char *pathname = args[1];
		struct stat st;

		//printf("> %s\n", pathname);

		if(! lstat(pathname, &st) )  {

			if( S_ISREG(st.st_mode) )  {
				// if the file is being sent, cancel it
				vhffsfssync_net_remove_file(conn, pathname);
				vhffsfssync_net_send_file(conn, pathname);
			}
			else if( S_ISDIR(st.st_mode) )  {
				vhffsfssync_net_send_event(conn, g_strdup_printf("mkdir%c%s%c%ld%c%d%c%d%c%d%c", '\0', pathname, '\0', st.st_mtime, '\0', st.st_mode&07777, '\0', st.st_uid, '\0', st.st_gid, '\0') , VHFFSFSSYNC_NET_PRIO_MEDIUM);
				vhffsfssync_net_send_event(conn, vhffsfssync_net_parent_attrib(pathname) , VHFFSFSSYNC_NET_PRIO_MEDIUM);
			}
			else if( S_ISLNK(st.st_mode) )  {
				char *linkto;
				linkto = malloc(st.st_size +1);
				if( readlink(pathname, linkto, st.st_size) >= 0 )  {
					linkto[st.st_size] = '\0';
					vhffsfssync_net_send_event(conn, g_strdup_printf("symlink%c%s%c%s%c%ld%c%d%c%d%c", '\0', pathname, '\0', linkto, '\0', st.st_mtime, '\0', st.st_uid, '\0', st.st_gid, '\0') , VHFFSFSSYNC_NET_PRIO_MEDIUM);
					vhffsfssync_net_send_event(conn, vhffsfssync_net_parent_attrib(pathname) , VHFFSFSSYNC_NET_PRIO_MEDIUM);
				}
				free(linkto);
			}
			/* we don't need other file types (chr, block, fifo, socket, ...) */
		}
	}
	else if(!strcmp(args[0], "fulltree")) {
		// the client requested a full tree of all available files
		if(!conn->fullviewtree) vhffsfssync_net_fullview(conn, ".");
/*		GList *lst;

		for( lst = g_list_first(conn->fullviewtree) ; lst ; lst = g_list_next(lst) )  {
			GList *lst2;
			printf("DEPTH..... N = %d\n", g_list_length(g_list_first(lst->data)));
			for(lst2 = g_list_first(lst->data) ; lst2 ; lst2 = g_list_next(lst2) )  {
				printf("DIR........ %s\n", (char*)lst2->data);
			}
		}
*/
	}
	else if(!strcmp(args[0], "time")) {
		struct timeval tv;
		gettimeofday(&tv, NULL);
		vhffsfssync_net_send_event(conn, g_strdup_printf("time%c%ld%c", '\0', tv.tv_sec, '\0') , VHFFSFSSYNC_NET_PRIO_HIGH);
	}
	else if(!strcmp(args[0], "hello")) {
		// nice to meet you
	}
	else {
		fprintf(stderr, "conn %d, received unhandled event: %s\n", conn->fd, args[0]);
	}

	free(args);
	return 0;
}


int vhffsfssync_net_parse(vhffsfssync_conn *conn)  {
	char *cur, *end;

	//fprintf(stderr, "Buffer %d\n", conn->recvbuf_len);

	/* parse the buffer */
	cur = conn->recvbuf + conn->recvbuf_begin;
	end = conn->recvbuf + conn->recvbuf_end; //beware: end can be outside the buffer, you should NOT read *end

	while(cur < end)  {
		char *begin;
		// find "\0\0"
		for(begin = cur ; ( cur < end && *cur++ != '\0' ) || ( cur < end && *cur++ != '\0' ) ; );

		if( !*(cur-2) && !*(cur-1) ) {
			register uint32_t len = cur - begin;

			if(!conn->delayedevents  &&  conn->messages_num < 20) {
				vhffsfssync_net_recv_event(conn, begin);
			}
			else {
				// system is overloaded, queue this event in delayed events
				if( !(conn->delayedevents_end & 0x03FF) ) {
					//printf("==> %d events, %d allocated\n", conn->delayedevents_end, ( (conn->delayedevents_end >>10) +1) <<10);
					conn->delayedevents = realloc( conn->delayedevents, (((conn->delayedevents_end >>10) +1) <<10) * sizeof(char*) );
				}
				conn->delayedevents[conn->delayedevents_end] = malloc(len);
				memcpy(conn->delayedevents[conn->delayedevents_end], begin, len);
				conn->delayedevents_end++;
			}
			conn->recvbuf_begin += len;
			begin = cur;
		}

		if(cur == end)  {
			register uint32_t len = end - begin;
			//fprintf(stderr, "Not parsed %d\n", len);

			if(len) {
				if(len > VHFFSFSSYNC_NET_RECV_OVERFLOW)
					return -1;

				// copy the data that is not parsed to the begin of the buffer if the data don't overlap
				if(len <= conn->recvbuf_begin) {
					//printf("Realloc to %d bytes\n", len);
					memcpy(conn->recvbuf, begin, len);
					conn->recvbuf = realloc( conn->recvbuf , len );
					conn->recvbuf_begin = 0;
					conn->recvbuf_end = len;
				}
			}
			else {
				free(conn->recvbuf);
				conn->recvbuf = NULL;
				conn->recvbuf_begin = 0;
				conn->recvbuf_end = 0;
			}
			break;
		}
	}

	//printf("==> finished with %d delayed events\n", conn->delayedevents_end - conn->delayedevents_begin);
	return 0;
}


int vhffsfssync_net_parse_delayed(vhffsfssync_conn *conn)  {

	//fprintf(stderr, "Delayed %d, begin %d, end %d\n", conn->delayedevents_end - conn->delayedevents_begin, conn->delayedevents_begin, conn->delayedevents_end);

	/* try to parse delayed events */
	while(conn->delayedevents && conn->messages_num < 20) {

		vhffsfssync_net_recv_event(conn, conn->delayedevents[conn->delayedevents_begin]);
		free(conn->delayedevents[conn->delayedevents_begin]);
		conn->delayedevents_begin++;

		if(conn->delayedevents_begin == conn->delayedevents_end) {
			conn->delayedevents_begin = 0;
			conn->delayedevents_end = 0;
			free(conn->delayedevents);
			conn->delayedevents = NULL;
			break;
		}

		if(conn->delayedevents_begin == 0x0400) {
			void *cur, *end;

			conn->delayedevents_begin = 0;
			conn->delayedevents_end -= 0x0400;

			cur = conn->delayedevents;
			end = conn->delayedevents + conn->delayedevents_end;
			//printf("AA> sizeofvoid: %d, events: %d, grmbl= %d, buffer = %lu, cur = %lu, end = %lu\n", sizeof(char*), conn->delayedevents_end - conn->delayedevents_begin, (conn->delayedevents_end - conn->delayedevents_begin) * sizeof(void*), (unsigned long)conn->delayedevents, (unsigned long)cur, (unsigned long)end);
 			for( ; cur < end ; cur += 0x0400*sizeof(void*) ) {
				//printf("Copie from %lu to %lu, %d bytes\n", (unsigned long)(cur+0x0400*sizeof(void*)), (unsigned long)cur, (cur+0x0400*sizeof(void*))-cur);
				memcpy(cur, cur + 0x0400*sizeof(void*), 0x0400*sizeof(void*) );
			}

			//printf("XX: begin = %d, end = %d\n", conn->delayedevents_begin, conn->delayedevents_end);
			//printf("XX> %d events, %d allocated, %d bytes allocated\n", conn->delayedevents_end, ( ( conn->delayedevents_end >>10) +1) <<10 ,  (((conn->delayedevents_end >>10) +1) <<10) * sizeof(char*)  );
			conn->delayedevents = realloc( conn->delayedevents, (((conn->delayedevents_end >>10) +1) <<10) * sizeof(char*) );
		}
	}

	return 0;
}


int vhffsfssync_net_fullview(vhffsfssync_conn *conn, char *pathname)  {

	/*
	 *  We need to keep the state of recursivity across runs
	 *
	 *  Only directories are interesting, so we store the current
	 *  directories tree in linked lists
	 *
	 *  The format is as follow:
	 *  list[
	 *           ["./usr", "./bin", "./boot", "./dev", "./etc", "./home", "./lib", "./home", ...],
	 *           ["./usr/include", "./usr/bin", "./usr/sbin", "./usr/lib", "./usr/man", ...],
	 *           ["./usr/include/linux", "./usr/include/sys", "./usr/include/bits", "./usr/include/netinet", ...],
	 *           ["./usr/include/linux/netfilter", "./usr/include/linux/usb", "./usr/include/linux/sunrpc" , ...]
	 *      ];
	 *
	 *  The first entry of each list is the current entry, so here it is:
	 *     /usr/include/linux/netfilter/
	 *
	 *  Entries are deleted when everything is done
	 *
	 *  (Yes, I write comments when I am brainstorming)
	 */

	GList *ldirs = NULL;

	if(pathname) {
		DIR *d;

		//printf("LOOKUP: %s\n", pathname);

		d = opendir(pathname);
		if(d) {
			struct stat st;

			if(!lstat(pathname, &st) )  {
				struct dirent *dir;
				GString *msg;

				msg = g_string_sized_new(1024);
				g_string_append_printf(msg, "ls%c%s%c%ld%c%d%c%d%c%d%c", '\0', pathname, '\0', st.st_mtime, '\0', st.st_mode&07777, '\0', st.st_uid, '\0', st.st_gid, '\0');

				while( (dir = readdir(d)) ) {
					if( strcmp(dir->d_name, ".") && strcmp(dir->d_name, "..") ) {
						char *path = g_strdup_printf("%s/%s", pathname, dir->d_name);

						if(! lstat(path, &st) )  {
							if( S_ISDIR(st.st_mode) )  {
								// register a new directory
								ldirs = g_list_append(ldirs, g_strdup(path));
								g_string_append_printf(msg, "%s%cdir%c0%c%ld%c%d%c%d%c%d%c", dir->d_name, '\0', '\0', '\0', st.st_mtime, '\0', st.st_mode&07777, '\0', st.st_uid, '\0', st.st_gid, '\0');
							}
							else if( S_ISREG(st.st_mode) )  {
								g_string_append_printf(msg, "%s%cfile%c%lld%c%ld%c%d%c%d%c%d%c", dir->d_name, '\0', '\0', (long long int)st.st_size, '\0', st.st_mtime, '\0', st.st_mode&07777, '\0', st.st_uid, '\0', st.st_gid, '\0');
							}
							else if( S_ISLNK(st.st_mode) )  {
								g_string_append_printf(msg, "%s%clink%c%lld%c%ld%c%d%c%d%c%d%c", dir->d_name, '\0', '\0', (long long int)st.st_size, '\0', st.st_mtime, '\0', st.st_mode&07777, '\0', st.st_uid, '\0', st.st_gid, '\0');
							}
							/* we don't need other file types (chr, block, fifo, socket, ...) */
						}
						else {
							fprintf(stderr, "cannot lstat() '%s': %s\n", path, strerror(errno));
						}
						free(path);
					}
				}

				vhffsfssync_net_send_event(conn, g_string_free(msg, FALSE) , VHFFSFSSYNC_NET_PRIO_MEDIUM);

			} else {
				fprintf(stderr, "cannot lstat() '%s': %s\n", pathname, strerror(errno));
			}

			closedir(d);

			// any subdirectories ?
			if(ldirs) {
				// register the list to the pseudo-tree
				conn->fullviewtree = g_list_append(conn->fullviewtree, g_list_last(ldirs));
				//printf("Depth: %d, entries here = %d\n", g_list_length(conn->fullviewtree), g_list_length(ldirs));
			}
		}
	}
	// recover recursion
	else {
		GList *lst;
		if(!conn->fullviewcur) {
			lst = g_list_first(conn->fullviewtree);
		}
		else {
			lst = g_list_next(conn->fullviewcur);
		}
		if(lst) {
			ldirs = g_list_first(lst->data);
			//printf("RECOVERING: %s\n", (char*)ldirs->data);
			if(g_list_next(lst))  {
				conn->fullviewcur = lst;
			}
			else {
				//printf("RECOVERED\n");
				conn->fullviewcur = NULL;
				conn->fullviewtimerset = 0;
			}
		}
	}

	//printf("Depth: %d, entries here = %d\n", g_list_length(conn->fullviewtree), g_list_length(ldirs));

	// subdirs ?
	if(ldirs) {

		while( (ldirs = g_list_first(ldirs)) ) {
			int r;
			char *path = ldirs->data;

			//printf("%s\n", path);

			// we can cancel the recursion here at anytime
 			if(conn->messages_num < 10 && conn->fullviewtimerset > 0) {
				// do nothing, this is here because it matchs most of the time
			}
			else {
				if(conn->messages_num >= 10 || conn->fullviewtimerset < 0) {
					//printf("%ld: CANCELLED, nums=%d, timer=%d\n", time(NULL), conn->messages_num, conn->fullviewtimerset);
					signal(SIGALRM, SIG_IGN);
					conn->fullviewcur = NULL;
					conn->fullviewtimerset = 0;
					return 1;
				}

				if(conn->fullviewtimerset == 0) {
					struct sigaction act;
					act.sa_handler = vhffsfssync_net_fullview_alarmsignal;
					sigemptyset(&act.sa_mask);
					act.sa_flags = SA_RESETHAND;
					sigaction(SIGALRM, &act, NULL);
					conn->fullviewtimerset = 1;
					alarm(1);
				}
			}

			//printf("A: %p\n", conn->fullviewcur);
			if(!conn->fullviewcur)  {
				r = vhffsfssync_net_fullview(conn, path);
			}
			else {
				r = vhffsfssync_net_fullview(conn, NULL);
				//printf("B: %p\n", conn->fullviewcur);
			}

			// rollback
			if(r) {
				//printf("Depth: %d, entries here = %d\n", g_list_length(conn->fullviewtree), g_list_length(ldirs));
				//printf("ROLLBACK: %s\n", path);
				return r;
			}

			//printf("DELETE %s\n", path);
			ldirs = g_list_delete_link(ldirs, ldirs);
			free(path);

			//printf("Depth: %d, entries here = %d\n", g_list_length(conn->fullviewtree), g_list_length(ldirs));
		}
		conn->fullviewtree = g_list_delete_link(conn->fullviewtree, g_list_last(conn->fullviewtree) );
	}

	if(!conn->fullviewtree)  {
//		printf("%ld: CLEAN UP SUCCESSFULL\n", time(NULL));
		conn->fullviewcur = NULL;
		conn->fullviewtimerset = 0;
		signal(SIGALRM, SIG_IGN);
	}
	return 0;
}


void vhffsfssync_net_fullview_alarmsignal(int signo)  {

	GList *conns;
	for(conns = g_list_first(vhffsfssync_conns) ; conns ; )  {
		vhffsfssync_conn *conn = conns->data;
		conns = g_list_next(conns);
		if( conn->fullviewtimerset > 0)
			conn->fullviewtimerset = -1;
	}
}


/* -- inotify stuff -- */

char *vhffsfssync_pathname(vhffsfssync_watch *watch, const char *filename)  {

	GString *pathname;
	char **dirnames, **curnames, **endnames;
	uint32_t a;

	a = 16;
	dirnames = malloc( a * sizeof(char*) );
	curnames = dirnames;
	endnames = dirnames+a;

	if(filename) {
		*(curnames++) = (char*)filename;
	}

	while(watch) {
		if(curnames == endnames) {
			a += 16;
			dirnames = realloc( dirnames, a * sizeof(char*) );
			curnames = dirnames+a-16;
			endnames = dirnames+a;
		}
		*(curnames++) = watch->name;
		watch = watch->parent;
	}

	pathname = g_string_sized_new(256);
	curnames--;
	g_string_append(pathname, *(curnames--) );
	while( curnames >= dirnames ) {
		g_string_append_c(pathname, '/');
		g_string_append(pathname, *(curnames--)  );
	}
	free(dirnames);

	return g_string_free(pathname, FALSE);
}


vhffsfssync_watch *vhffsfssync_add_watch(int inotifyfd, vhffsfssync_watch *parent, const char *name, uint32_t mask)  {

	int wd;
	char *pathname;
	vhffsfssync_watch *watch;

	pathname = vhffsfssync_pathname(parent, name);
#if DEBUG_INOTIFY
	printf("t+ %s\n", pathname);
#endif

	wd = inotify_add_watch(inotifyfd, pathname, mask);
	if(wd < 0) {
		if(errno == ENOSPC)  {
			fprintf(stderr, "Maximum number of watches reached, consider adding more...\n");
		}
		free(pathname);
		return NULL;
	}

 	if( (watch = g_hash_table_lookup(vhffsfssync_wd_to_watch, &wd)) ) {

		// this was already watched, update name and reattach to the new parent
		free(watch->name);
		watch->name = g_strdup(name);
		watch->parent = parent;

#if DEBUG_INOTIFY
		printf("u+ %d %s\n", wd, pathname);
#endif
		free(pathname);
		return watch;
	}

	watch = malloc(sizeof(vhffsfssync_watch));
	watch->wd = wd;
	watch->name = g_strdup(name);
	watch->parent = parent;

//	_wd = g_new(int, 1);
//	*_wd = wd;
	g_hash_table_insert(vhffsfssync_wd_to_watch, &watch->wd, watch);

//	if(wd >= vhffsfssync_wd_to_watch_len)  {
//		vhffsfssync_wd_to_watch_len = ( (wd >>10) +1) <<10;
//		vhffsfssync_wd_to_watch = realloc( vhffsfssync_wd_to_watch, vhffsfssync_wd_to_watch_len * sizeof(void*) );
//	}
//	vhffsfssync_wd_to_watch[wd] = strdup(pathname);
#if DEBUG_INOTIFY
	printf("a+ %d %s\n", wd, pathname);
#endif
	free(pathname);
	return watch;
}


int vhffsfssync_del_watch(int inotifyfd, vhffsfssync_watch *watch)  {

#if DEBUG_INOTIFY
	char *pathname = vhffsfssync_pathname(watch, NULL);
	printf("- %d %s\n", watch->wd, pathname);
	free(pathname);
#endif
	g_hash_table_remove(vhffsfssync_wd_to_watch, &watch->wd);
	inotify_rm_watch(inotifyfd, watch->wd);
	free(watch->name);
	free(watch);
	return 0;
}


vhffsfssync_watch *vhffsfssync_add_watch_recursively(int inotifyfd, vhffsfssync_watch *parent, const char *dirname)  {

	vhffsfssync_watch *watch;
	char *pathname;
	DIR *d;

	watch = vhffsfssync_add_watch(inotifyfd, parent, dirname, VHFFSFSSYNC_WATCH_MASK_DIR);
	if(!watch) return NULL;

	pathname = vhffsfssync_pathname(parent, dirname);
	d = opendir(pathname);
	free(pathname);
	if(d) {
		struct dirent *dir;
		while( (dir = readdir(d)) )  {
			if( strcmp(dir->d_name, ".") && strcmp(dir->d_name, "..") )  {
				/* We need to watch every file due to a kernel limitation.
				 * When a file is modified through its inode reference we do not know
				 * the filename hence we do not receive an inotify event about it.
				 * For example this is the case when a file is modified through NFS.
				 */
				
				/* If the filesystem supports dirent->d_type */
				if(dir->d_type != DT_UNKNOWN) {
					if( dir->d_type == DT_REG || dir->d_type == DT_LNK ) {
						if( !vhffsfssync_add_watch(inotifyfd, watch, dir->d_name, VHFFSFSSYNC_WATCH_MASK_FILE) )
							return NULL;
					}
					else if(dir->d_type == DT_DIR) {
						if( !vhffsfssync_add_watch_recursively(inotifyfd, watch, dir->d_name) )
							return NULL;
					}
					/* we don't need other file types (chr, block, fifo, socket, ...) */
				
				// If the filesystem does NOT support dirent->d_type
				} else {
					struct stat st;
					if( !lstat(dir->d_name, &st) ) {
						if( S_ISREG(st.st_mode) || S_ISLNK(st.st_mode) ) {
							if( !vhffsfssync_add_watch(inotifyfd, watch, dir->d_name, VHFFSFSSYNC_WATCH_MASK_FILE) )
								return NULL;
						}
						else if(S_ISDIR(st.st_mode)) {
							if( !vhffsfssync_add_watch_recursively(inotifyfd, watch, dir->d_name) )
								return NULL;
						}
						/* we don't need other file types (chr, block, fifo, socket, ...) */
					}
				}

			}
		}
		closedir(d);
	}

	return watch;
}


int vhffsfssync_manage_event_remove(int inotifyfd, vhffsfssync_watch *watch, char *filename)  {
	char *pathname;
	GList *conns;

	pathname = vhffsfssync_pathname(watch, filename);

#if DEBUG_INOTIFY
	printf("==> REMOVE %s\n", pathname);
#endif

	/* connections */
	for(conns = g_list_first(vhffsfssync_conns) ; conns ; )  {
		vhffsfssync_conn *conn = conns->data;
		conns = g_list_next(conns);
		vhffsfssync_net_remove_file(conn, pathname);
		vhffsfssync_net_send_event(conn, g_strdup_printf("remove%c%s%c", '\0', pathname, '\0') , VHFFSFSSYNC_NET_PRIO_MEDIUM);
		vhffsfssync_net_send_event(conn, vhffsfssync_net_parent_attrib(pathname) , VHFFSFSSYNC_NET_PRIO_MEDIUM);
	}

	free(pathname);
	return 0;
}


int vhffsfssync_manage_event_create(int inotifyfd, vhffsfssync_watch *watch, char *filename)  {
	struct stat st;
	char *pathname;

	pathname = vhffsfssync_pathname(watch, filename);

	if(! lstat(pathname, &st) )  {

		if( S_ISREG(st.st_mode) )  {
#if DEBUG_INOTIFY
			printf("==> CREATE %s\n", pathname);
#endif
			vhffsfssync_add_watch(inotifyfd, watch, filename, VHFFSFSSYNC_WATCH_MASK_FILE);
			if(!st.st_size)  {
				vhffsfssync_net_broadcast_event( g_strdup_printf("create%c%s%c%ld%c%d%c%d%c%d%c", '\0', pathname, '\0', st.st_mtime, '\0', st.st_mode&07777, '\0', st.st_uid, '\0', st.st_gid, '\0') , VHFFSFSSYNC_NET_PRIO_MEDIUM);
				vhffsfssync_net_broadcast_event( vhffsfssync_net_parent_attrib(pathname) , VHFFSFSSYNC_NET_PRIO_MEDIUM);
			}
			else {
				vhffsfssync_net_broadcast_file(pathname);
			}
		}

		else if( S_ISDIR(st.st_mode) )  {
			vhffsfssync_watch *newwatch;
#if DEBUG_INOTIFY
			printf("==> MKDIR %s\n", pathname);
#endif
			newwatch = vhffsfssync_add_watch(inotifyfd, watch, filename, VHFFSFSSYNC_WATCH_MASK_DIR);
			vhffsfssync_net_broadcast_event( g_strdup_printf("mkdir%c%s%c%ld%c%d%c%d%c%d%c", '\0', pathname, '\0', st.st_mtime, '\0', st.st_mode&07777, '\0', st.st_uid, '\0', st.st_gid, '\0') , VHFFSFSSYNC_NET_PRIO_MEDIUM);
			vhffsfssync_net_broadcast_event( vhffsfssync_net_parent_attrib(pathname) , VHFFSFSSYNC_NET_PRIO_MEDIUM);
			/* there is a short delay between the mkdir() and the add_watch(),
			   we need to send events about the data which have already been written */
			vhffsfssync_fake_events_recursively( inotifyfd, newwatch );
		}

		else if( S_ISLNK(st.st_mode) )  {
			char *linkto;
			int ret;
			linkto = malloc(st.st_size +1);
			ret = readlink(pathname, linkto, st.st_size);
			if( ret >= 0 )  {
				linkto[st.st_size] = '\0';
#if DEBUG_INOTIFY
				printf("==> SYMLINK %s -> %s\n", pathname, linkto);
#endif
				vhffsfssync_add_watch(inotifyfd, watch, filename, VHFFSFSSYNC_WATCH_MASK_FILE);
				vhffsfssync_net_broadcast_event( g_strdup_printf("symlink%c%s%c%s%c%ld%c%d%c%d%c", '\0', pathname, '\0', linkto, '\0', st.st_mtime, '\0', st.st_uid, '\0', st.st_gid, '\0') , VHFFSFSSYNC_NET_PRIO_MEDIUM);
				vhffsfssync_net_broadcast_event( vhffsfssync_net_parent_attrib(pathname) , VHFFSFSSYNC_NET_PRIO_MEDIUM);
			}
			free(linkto);
			if(ret < 0) {
				if(errno == ENOENT) {
					// file already disappeared (common for temporary files)
				} else {
					fprintf(stderr, "cannot readlink() '%s': %s\n", pathname, strerror(errno));
					free(pathname);
					return -1;
				}
			}

		}
		/* we don't need other file types (chr, block, fifo, socket, ...) */
	}
	else {
		if(errno == ENOENT) {
			// file already disappeared (common for temporary files)
		} else {
			fprintf(stderr, "cannot lstat() '%s': %s\n", pathname, strerror(errno));
			free(pathname);
			return -1;
		}
	}

	free(pathname);
	return 0;
}


int vhffsfssync_manage_event(int inotifyfd, struct inotify_event *event)  {

	vhffsfssync_watch *watch;
	char *pathname;
#if DEBUG_INOTIFY
	printf("wd=%d mask=%x cookie=%d len=%d", event->wd, event->mask, event->cookie, event->len);
	if(event->len > 0) printf(" name=%s", event->name);
	printf("\n");
#endif

	if(event->wd < 0) {
		fprintf(stderr, "Maximum number of events reached, some events are lost\n");
		return -1;
	}

	// DROP useless dir events (we are going to receive the same event on the file watch)
	if( event->len > 0 && event->mask & IN_ATTRIB ) {
		return 0;
	}

	watch = g_hash_table_lookup(vhffsfssync_wd_to_watch, &event->wd);
	assert( watch != NULL );

	if(event->len > 0)  {
		pathname = vhffsfssync_pathname(watch, event->name);
	} else {
		pathname = vhffsfssync_pathname(watch, NULL);
	}

	// this event is not waiting for a cookie, delete file if necessary (IN_MOVED_FROM not followed with IN_MOVED_TO)
	if( !(event->mask & IN_MOVED_TO) && vhffsfssync_cookie.id )  {

		vhffsfssync_manage_event_remove(inotifyfd, vhffsfssync_cookie.watch, vhffsfssync_cookie.filename);
		vhffsfssync_cookie.id = 0;
		free(vhffsfssync_cookie.filename);
	}

	// new mtime, mode, owner, group (and also other stuff like atime, but we are not using them)
	if( event->mask & IN_ATTRIB )  {
		struct stat st;
#if DEBUG_INOTIFY
		printf("IN_ATTRIB\n");
#endif
		if(! lstat(pathname, &st) )  {
			vhffsfssync_net_broadcast_event( g_strdup_printf("attrib%c%s%c%ld%c%d%c%d%c%d%c", '\0', pathname, '\0', st.st_mtime, '\0', st.st_mode&07777, '\0', st.st_uid, '\0', st.st_gid, '\0') , VHFFSFSSYNC_NET_PRIO_MEDIUM);
		}
		else {
			if(errno == ENOENT) {
				// file already disappeared (common for temporary files)
			} else {
				fprintf(stderr, "cannot lstat() '%s': %s\n", pathname, strerror(errno));
			}
		}

	// new file, directory, or symlink
	} else if( event->mask & IN_CREATE )  {
#if DEBUG_INOTIFY
		printf("IN_CREATE\n");
#endif
		vhffsfssync_manage_event_create(inotifyfd, watch, event->name);

	// deleted file, directory or symlink
	} else if( event->mask & IN_DELETE )  {
#if DEBUG_INOTIFY
		printf("IN_DELETE\n");
#endif
		vhffsfssync_manage_event_remove(inotifyfd, watch, event->name);

	// file modified
	} else if( event->mask & IN_MODIFY )  {
#if DEBUG_INOTIFY
		printf("IN_MODIFY\n");
		/* we can send the data here */
		printf("==> SEND %s\n", pathname);
#endif
		vhffsfssync_net_broadcast_file(pathname);

	// file/symlink/directory moved
	//
	// only from: delete the file/symlink/directory
	// only to: create the file/symlink/directory
	// both: mv the directory, delete and create file/symlink
	//
	} else if( event->mask & IN_MOVED_FROM )  {
#if DEBUG_INOTIFY
		printf("IN_MOVED_FROM\n");
#endif
		// set the cookie
		vhffsfssync_cookie.id = event->cookie;
		vhffsfssync_cookie.watch = watch;
		vhffsfssync_cookie.filename = strdup(event->name);
		vhffsfssync_cookie.isdir = !!( event->mask & IN_ISDIR );

	} else if( event->mask & IN_MOVED_TO )  {
#if DEBUG_INOTIFY
		printf("IN_MOVED_TO\n");
#endif
		// mv
		if(vhffsfssync_cookie.id == event->cookie)  {
#if DEBUG_INOTIFY
			char *tmp = vhffsfssync_pathname(vhffsfssync_cookie.watch, vhffsfssync_cookie.filename);
			printf("==> MOVE (%d -> %d) %s -> %s  (used cookie %d)\n", vhffsfssync_cookie.watch->wd, watch->wd, tmp, pathname, vhffsfssync_cookie.id);
			free(tmp);
#endif
			if( vhffsfssync_cookie.isdir )  {

				char *frompathname = vhffsfssync_pathname(vhffsfssync_cookie.watch, vhffsfssync_cookie.filename);
				vhffsfssync_add_watch(inotifyfd, watch, event->name, VHFFSFSSYNC_WATCH_MASK_DIR);
				vhffsfssync_net_broadcast_event( g_strdup_printf("move%c%s%c%s%c", '\0', frompathname, '\0', pathname, '\0') , VHFFSFSSYNC_NET_PRIO_MEDIUM);
				vhffsfssync_net_broadcast_event( vhffsfssync_net_parent_attrib(frompathname) , VHFFSFSSYNC_NET_PRIO_MEDIUM);
				vhffsfssync_net_broadcast_event( vhffsfssync_net_parent_attrib(pathname) , VHFFSFSSYNC_NET_PRIO_MEDIUM);
				free(frompathname);
			}
			else {
				vhffsfssync_manage_event_remove(inotifyfd, vhffsfssync_cookie.watch, vhffsfssync_cookie.filename);
				vhffsfssync_manage_event_create(inotifyfd, watch, event->name);
			}

			vhffsfssync_cookie.id = 0;
			free(vhffsfssync_cookie.filename);
		}
		// create
		else  {
			vhffsfssync_manage_event_create(inotifyfd, watch, event->name);
		}

	// watch deleted, clean it
	} else if( event->mask & IN_IGNORED )  {
#if DEBUG_INOTIFY
		printf("IN_IGNORED\n");
#endif
		vhffsfssync_del_watch(inotifyfd, watch);

	// this event is not handled, this should not happen
	} else {
#if DEBUG_INOTIFY
		printf("OOOOOOOPPPSS!!!!!\n");
#endif
	}

	free(pathname);
	return 0;
}


int vhffsfssync_fake_events_recursively(int inotifyfd, vhffsfssync_watch *watch)  {
	DIR *d;
	char *pathname;

	pathname = vhffsfssync_pathname(watch, NULL);
	d = opendir(pathname);
	free(pathname);

	if(d) {
		struct dirent *dir;
		while( (dir = readdir(d)) ) {
			if( strcmp(dir->d_name, ".") && strcmp(dir->d_name, "..") ) {
				// recursivity is done through vhffsfssync_manage_event_create()
				// which calls this function
				vhffsfssync_manage_event_create(inotifyfd, watch, dir->d_name);
			}
		}
		closedir(d);
	}

	return 0;
}


static void usage_exit(int ret_code, char *progname)  {
	printf ("Usage: %s [OPTION]... DIRECTORY\n"
		"Remote synchronous file-copying tool, this is the server (the master)\n\n"
		"  -f, --foreground\tDon't daemonise the server, display errors on the console\n"
		"  -b, --bind=IP\t\tListen to the specified IP address\n"
		"  -p, --port=PORT\tListen to this port\n"
		"      --pidfile=PATH\tWrite the pid to that file\n"
		"  -h, --help\t\tDisplay this help and exit\n"
		"  -v, --version\t\tOutput version information and exit\n",
		progname);
	exit(ret_code);
}


int main(int argc, char *argv[])  {

	int inotifyfd, flags;
	vhffsfssync_watch *watch;

	int listenfd, opt;
	struct sockaddr_in src;

	int foreground = 0;
	uint32_t bindaddr = INADDR_ANY;
	uint16_t bindport = 4567;
	char *root = NULL;
	FILE *pidfile = NULL;

	struct option long_options[] = {
		{ "foreground", no_argument, NULL, 'f' },
		{ "bind", required_argument, NULL, 'b' },
		{ "port", required_argument, NULL, 'p' },
		{ "pidfile", required_argument, NULL, 1000 },
		{ "help", no_argument, NULL, 'h' },
		{ "version", no_argument, NULL, 'v' },
		{ 0, 0, 0, 0 }
	};

	while(1) {
		int option_index = 0, c;
		c = getopt_long(argc, argv, "fb:p:hv", long_options, &option_index);
		if(c == -1)
			break;

		switch(c) {
			case 'f':
				foreground = 1;
				break;

			case 'b':
				bindaddr = inet_addr(optarg);
				break;

			case 'p':
				bindport = atoi(optarg);
				break;

			case 1000:
				pidfile = fopen(optarg, "w");
				break;

			case 'h':
				usage_exit(0, argv[0]);

			case 'v':
#ifdef VERSION
				fputs("vhffsfssync_master " VERSION "\n", stdout);
#else
				fputs("vhffsfssync_master\n", stdout);
#endif
				exit(0);

			case '?':
				/* `getopt_long' already printed an error message. */
				fprintf(stderr,"Try `%s --help' for more information.\n", argv[0]);
				exit(1);

			default:
				abort();
		}
	}

	if(optind != argc-1)
		usage_exit(1, argv[0]);

	root = argv[optind++];

	if(!foreground) {
		close(STDIN_FILENO);
		close(STDOUT_FILENO);
		close(STDERR_FILENO);
		if(fork()) exit(0);
	}

	/* write the pidfile */
	if(pidfile) {
		char *tmp = g_strdup_printf("%d\n", getpid() );
		fwrite(tmp, strlen(tmp), 1, pidfile);
		free(tmp);
		fclose(pidfile);
	}

	/* chdir() to the filesystem to monitor */
	if(!root) return -1;
	if( root[strlen(root)-1] == '/' ) root[strlen(root)-1] = '\0';
#if DEBUG_INOTIFY
	printf("Monitoring %s\n", root);
#endif
	if( chdir(root) < 0 ) {
		fprintf(stderr, "cannot chdir() to %s: %s\n", root, strerror(errno));
		return -1;
	}
	if( chroot(".") < 0 ) {
		fprintf(stderr, "cannot chroot() to %s: %s\n", root, strerror(errno));
		//return -1;
	}
	root = ".";

	/* -- inotify stuff -- */

	vhffsfssync_wd_to_watch = g_hash_table_new_full(g_int_hash, g_int_equal, NULL, NULL);
	vhffsfssync_cookie.watch = NULL;
	vhffsfssync_cookie.id = 0;
	vhffsfssync_cookie.filename = NULL;

	inotifyfd = inotify_init();

	/* set inotifyfd to non-blocking */
	flags = fcntl(inotifyfd, F_GETFL);
	if(flags >= 0) {
		flags |= O_NONBLOCK;
		fcntl(inotifyfd, F_SETFL, flags);
	}

	watch = vhffsfssync_add_watch_recursively(inotifyfd, NULL, root);
	if(!watch)  {
		fprintf(stderr, "Maximum number of watches probably reached, consider adding more or fixing what is being wrong before running me again (strace is your friend)... byebye!\n");
		return -1;
	}

	/* -- network stuff -- */
	vhffsfssync_conns = NULL;
	vhffsfssync_net_files = g_hash_table_new_full(g_str_hash, g_str_equal, NULL, NULL);

	signal(SIGPIPE, SIG_IGN);

	/* listening for network connections */
	if( (listenfd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP) ) < 0) {
		fprintf(stderr, "socket() failed: %s\n", strerror(errno));
		return -1;
	}

	/* set listenfd to non-blocking */
	flags = fcntl(listenfd, F_GETFL);
	if(flags >= 0) {
		flags |= O_NONBLOCK;
		fcntl(listenfd, F_SETFL, flags);
	}

	/* add the ability to listen on a TIME_WAIT */
	opt = 1;
	if( setsockopt(listenfd, SOL_SOCKET, SO_REUSEADDR, (char*)&opt, sizeof(opt) ) )  {
		fprintf(stderr, "setsockopt() failed on socket %d: %s\n", listenfd, strerror(errno));
	}

	memset((char*)&src, 0, sizeof(src));
	src.sin_addr.s_addr = bindaddr;
	src.sin_family = AF_INET;
	src.sin_port = htons(bindport);
	if( bind(listenfd, (struct sockaddr*)&src, sizeof(src) ) < 0) {
		fprintf(stderr, "bind() failed on socket %d: %s\n", listenfd, strerror(errno));
		return -1;
	}

	if( listen(listenfd, SOMAXCONN) < 0) {
		fprintf(stderr, "listen() failed on socket %d: %s\n", listenfd, strerror(errno));
		return -1;
	}

#if DEBUG_NET
	printf("Listening on %s:%d\n", inet_ntoa(src.sin_addr), bindport);
#endif

	printf("Ready\n");

	/* -- main loop -- */
	while(1)  {
		int max_fd = 0;
		fd_set readfs;
		fd_set writefs;
		GList *conns;
		int ret;

		FD_ZERO(&readfs);
		FD_ZERO(&writefs);

		/* inotify events */
		FD_SET(inotifyfd, &readfs);
		if(inotifyfd > max_fd) max_fd = inotifyfd;

		/* new connections */
		FD_SET(listenfd, &readfs);
		if(listenfd > max_fd) max_fd = listenfd;

		/* connections */
		for(conns = g_list_first(vhffsfssync_conns) ; conns ; )  {
			vhffsfssync_conn *conn = conns->data;
			conns = g_list_next(conns);

			/* this connnection was disabled, destroy it */
			if(conn->fd < 0) {
				vhffsfssync_net_conn_destroy(conn);
				continue;
			}

			//printf("%d -> %d\n", conn->fd, conn->messages_num);

			FD_SET(conn->fd, &readfs);
			if( conn->messages
			    || (conn->fullviewtree && conn->messages_num < 10)
			    || (conn->delayedevents && conn->messages_num < 20) )
				FD_SET(conn->fd, &writefs);
			if(conn->fd > max_fd) max_fd = conn->fd;
		}

		ret = select(max_fd + 1, &readfs, &writefs, NULL, NULL);
		if(ret < 0)  {
			switch(errno)  {
				case EAGAIN:
				case EINTR:
					break;
				default:
					fprintf(stderr, "select() failed: %s\n", strerror(errno));
			}
		}
		if(ret > 0)  {
			/* inotify events */
			if( FD_ISSET(inotifyfd, &readfs) )  {
				char buf[VHFFSFSSYNC_BUF_LEN];
				ssize_t len;

				len = read(inotifyfd, buf, VHFFSFSSYNC_BUF_LEN);
				if(len < 0)  {
					switch(errno)  {
						case EAGAIN:
						case EINTR:
							break;
						default:
							fprintf(stderr, "read() failed on inotify fd(%d): %s\n", inotifyfd, strerror(errno));
					}
				}
				else {
					char *cur = buf;
					while(len > 0)  {
						int register next;
						struct inotify_event *ie;

						ie = (struct inotify_event*)cur;
						vhffsfssync_manage_event( inotifyfd, ie );
						next = sizeof(struct inotify_event);
						next += ie->len;
						len -= next;
						cur += next;
					}
				}
			}

			/* new connections */
			if( FD_ISSET(listenfd, &readfs) )  {
				struct sockaddr_in addr;
				int newfd, flags;
				socklen_t addr_len;
				vhffsfssync_conn *conn;
				//struct hostent *ent;

				addr_len = sizeof(addr);
				memset((char*)&addr, 0, addr_len);
				newfd = accept(listenfd, (struct sockaddr*)&addr, &addr_len);
				if(newfd <= 0)  {
					switch(errno)  {
						case EAGAIN:
						case EINTR:
							break;
						default:
							fprintf(stderr, "accept() failed on listen fd(%d): %s\n", listenfd, strerror(errno));
					}
				}
				else {
					// We don't need the reverse DNS, the code here is for learning purpose
					//ent = gethostbyaddr((const void*)&addr.sin_addr, sizeof(sizeof(addr.sin_addr)), AF_INET);
					//if(ent) printf("And you are %s\n", ent->h_name);

					/* set newfd to non-blocking */
					flags = fcntl(newfd, F_GETFL);
					if(flags >= 0) {
						flags |= O_NONBLOCK;
						fcntl(newfd, F_SETFL, flags);
					}

					/* register the connection */
					conn = malloc(sizeof(vhffsfssync_conn));
					conn->fd = newfd;
					memcpy((char*)&conn->sockaddr, (char*)&addr, addr_len);
					conn->order = 0;
					conn->recvbuf = NULL;
					conn->recvbuf_begin = 0;
					conn->recvbuf_end = 0;
					conn->delayedevents = NULL;
					conn->delayedevents_begin = 0;
					conn->delayedevents_end = 0;
					conn->messages = NULL;
					conn->messages_num = 0;
					conn->fullviewtree = NULL;
					conn->fullviewcur = NULL;
					conn->fullviewtimerset = 0;
					vhffsfssync_conns = g_list_append(vhffsfssync_conns, conn);
#if DEBUG_NET
					printf("Welcome %s ! (using fd %d)\n", inet_ntoa(conn->sockaddr.sin_addr), conn->fd);
#endif
					vhffsfssync_net_send_event(conn, g_strdup_printf("hello%c%lld%c", '\0', (long long int)ntohl(conn->sockaddr.sin_addr.s_addr), '\0') , VHFFSFSSYNC_NET_PRIO_HIGHEST);
				}
			}

			/* connections */
			for(conns = g_list_first(vhffsfssync_conns) ; conns ; )  {
				vhffsfssync_conn *conn = conns->data;
				conns = g_list_next(conns);

				/* data to read ?, give give ! */
				if( FD_ISSET(conn->fd, &readfs)  )  {
					ssize_t len;

					//fprintf(stdout, "Alloc %d bytes\n", conn->recvbuf_end + VHFFSFSSYNC_NET_RECV_CHUNK);
					conn->recvbuf = realloc( conn->recvbuf , conn->recvbuf_end + VHFFSFSSYNC_NET_RECV_CHUNK );
					len = read(conn->fd, conn->recvbuf+conn->recvbuf_end, VHFFSFSSYNC_NET_RECV_CHUNK);
					if(len < 0)  {
						switch(errno)  {
							case EAGAIN:
							case EINTR:
								break;
							default:
								fprintf(stdout, "read() failed on socket %d: %s\n", conn->fd, strerror(errno));
								vhffsfssync_net_conn_disable(conn);
						}
					}
					else if(len == 0) {
						vhffsfssync_net_conn_disable(conn);
					}
					else {
						//fprintf(stdout, "Read %d, buffer is %lu, begin is %lu, end is %lu\n", len, (unsigned long)conn->recvbuf, (unsigned long)conn->recvbuf_begin, (unsigned long)conn->recvbuf_end);
						conn->recvbuf_end += len;
						if( vhffsfssync_net_parse(conn) )
							vhffsfssync_net_conn_disable(conn);
					}
				}

				/* try to send more data */
				if( conn->messages  &&  FD_ISSET(conn->fd, &writefs) )
					vhffsfssync_net_send(conn);

				/* continue the fullview if needed */
				if( conn->fullviewtree  &&  conn->messages_num < 10 )
					vhffsfssync_net_fullview(conn, NULL);

				/* try to parse more data */
				if( conn->delayedevents  &&  conn->messages_num < 20 )
					vhffsfssync_net_parse_delayed(conn);
			}
		}
	}

	return 0;
}
