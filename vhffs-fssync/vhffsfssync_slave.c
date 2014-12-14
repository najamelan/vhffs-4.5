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
#define _ATFILE_SOURCE

#define DEBUG_NET 0
#define DEBUG_EVENTS 0

#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <fcntl.h>
#include <dirent.h>
#include <string.h>
#include <errno.h>
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
#include <getopt.h>
#include <utime.h>
#include <sys/time.h>


#ifdef CHECK
int vhffsfssync_progress=0;
char vhffsfssync_progresschar[] = { '/', '-', '\\', '|', '\0' };
#endif

/* -- network stuff -- */
// huge buffer size reduce syscalls
#define VHFFSFSSYNC_NET_RECV_CHUNK 65536
#define VHFFSFSSYNC_NET_RECV_OVERFLOW 104857600

typedef struct {
	char *data_buffer;
	ssize_t data_len;
	ssize_t data_cur;
} vhffsfssync_net_message;

typedef struct {
	int fd;
	struct sockaddr_in sockaddr;

	char *recvbuf;
	uint32_t recvbuf_begin;
	uint32_t recvbuf_end;

	FILE *chunk_file;
	ssize_t chunk_stilltoread;

	vhffsfssync_net_message **messages;
	uint32_t messages_begin;
	uint32_t messages_end;

	GHashTable *openfiles;

	double limitrate_speed;
	double limitrate_sleep;
	double limitrate_timeprev;
} vhffsfssync_conn;

// network protos
int vhffsfssync_net_send_data(vhffsfssync_conn *conn, char *data, ssize_t len);
void vhffsfssync_net_destroy_message(vhffsfssync_conn *conn, vhffsfssync_net_message *msg);
int vhffsfssync_net_send(vhffsfssync_conn *conn);

// events protos
int vhffsfssync_remove(char *pathname);
int vhffsfssync_mkdir(char *pathname, int long long mtime, int mode, int uid, int gid);
int vhffsfssync_checkfile(vhffsfssync_conn *conn, char *path, char *type, int long long size, int long long mtime, int mode, int uid, int gid);
int vhffsfssync_event(vhffsfssync_conn *conn, char *event);
int vhffsfssync_parse(vhffsfssync_conn *conn);

// misc
double vhffsfssync_time();
static void usage_exit(int ret_code, char *progname);
int vhffsfssync_preserve;
int vhffsfssync_preventloop;
long long int vhffsfssync_host;

/* ------------------------------------------------------------ */

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

inline int vhffsfssync_net_send_event(vhffsfssync_conn *conn, char *data)  {
	return vhffsfssync_net_send_data(conn, data, vhffsfssync_net_event_len(data));
}

// !!!!!! the buffer is freed when the message has been sent, DON'T send static string and DON'T free() the data yourself
int vhffsfssync_net_send_data(vhffsfssync_conn *conn, char *data, ssize_t len)  {
	vhffsfssync_net_message *msg;
	if(!conn || !data || len <= 0) return -1;

	msg = malloc(sizeof(vhffsfssync_net_message));
	msg->data_buffer = data;
	msg->data_len = len;
	msg->data_cur = 0;
	if( !(conn->messages_end & 0x03FF) )
		conn->messages = realloc( conn->messages, (((conn->messages_end >>10) +1) <<10) * sizeof(vhffsfssync_net_message*) );
	conn->messages[conn->messages_end] = msg;
	conn->messages_end++;

	return 0;
}


void vhffsfssync_net_destroy_message(vhffsfssync_conn *conn, vhffsfssync_net_message *msg) {
	free(msg->data_buffer);
	free(msg);
}


int vhffsfssync_net_send(vhffsfssync_conn *conn)  {
	gboolean full = FALSE;

	if(!conn || conn->fd < 0) return -1;
#if DEBUG_NET
	printf("--------------------------------------------------\n");
	printf("conn: %d, to: %s\n", conn->fd, inet_ntoa(conn->sockaddr.sin_addr));
#endif
	while(!full && conn->messages)  {
		vhffsfssync_net_message *msg = conn->messages[conn->messages_begin];
		ssize_t written;
		ssize_t lentowrite;

#if DEBUG_NET
		printf("  buffer: %ld bytes, %ld already written\n", (long int)msg->data_len, (long int)msg->data_cur);
#endif
		/* try to empty the buffer */
		lentowrite = msg->data_len - msg->data_cur;
		written = write(conn->fd, msg->data_buffer + msg->data_cur, lentowrite);
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
					return -1;
			}
		}
		else {
			msg->data_cur += written;
#if DEBUG_NET
			printf("    %ld bytes written on %ld bytes\n", (long int)written, (long int)lentowrite);
#endif
			/* the buffer is not empty yet (but the SendQ into the kernel is) */
			if(written < lentowrite) {
				full = TRUE;
			}
			/* buffer is now empty */
			else {
				vhffsfssync_net_destroy_message(conn, msg);

				conn->messages_begin++;
				if(conn->messages_begin == conn->messages_end) {
					conn->messages_begin = 0;
					conn->messages_end = 0;
					free(conn->messages);
					conn->messages = NULL;
					break;
				}
				if(conn->messages_begin == 0x0400) {
					void *cur, *end;
					conn->messages_begin = 0;
					conn->messages_end -= 0x0400;
					cur = conn->messages;
					end = conn->messages + conn->messages_end;
					for( ; cur < end ; cur += 0x0400*sizeof(void*) )
						memcpy(cur, cur + 0x0400*sizeof(void*), 0x0400*sizeof(void*) );
					conn->messages = realloc( conn->messages, (((conn->messages_end >>10) +1) <<10) * sizeof(vhffsfssync_net_message*) );
				}
			}
		}
	}

	return 0;
}

#ifndef CHECK
/* ---------------------------------------- */
int vhffsfssync_remove(char *pathname)  {
	struct stat st;

	if(! lstat(pathname, &st) )  {

		if( S_ISDIR(st.st_mode) )  {
			DIR *d;
			struct dirent *dir;

			d = opendir(pathname);
			if(d) {
				while( (dir = readdir(d)) )  {
					if( strcmp(dir->d_name, ".") && strcmp(dir->d_name, "..") )  {
						char *path;
						path = g_strdup_printf("%s/%s", pathname, dir->d_name);
						vhffsfssync_remove(path);
						free(path);
					}
				}
				closedir(d);
				if( rmdir(pathname) < 0)  {
					fprintf(stderr, "cannot rmdir() '%s': %s\n", pathname, strerror(errno));
				}
			}
			else {
				fprintf(stderr, "cannot opendir() '%s': %s\n", pathname, strerror(errno));
			}
		}
		else {
			if( unlink(pathname) < 0)  {
				fprintf(stderr, "cannot unlink() '%s': %s\n", pathname, strerror(errno));
			}
		}
	}
	else {
		if(errno != ENOENT) {
			fprintf(stderr, "cannot lstat() '%s': %s\n", pathname, strerror(errno));
			return -1;
		}
	}

	return 0;
}


// the content of pathname is modified
int vhffsfssync_mkdir(char *pathname, int long long mtime, int mode, int uid, int gid)  {
	char *cur, *dirs[64];
	int i, fd, fd_, argc;

	argc = 0;
	cur = pathname;
	while(*cur != '\0' && argc < 64) {
		for( ; *cur != '/' && *cur != '\0' ; cur++ );
		dirs[argc++] = pathname;
		if( *cur == '/' ) {
			*cur = '\0';
			pathname = ++cur;
		}
	}

	fd = AT_FDCWD;
	for(i = 0 ; i < argc ; i++) {
		mkdirat(fd, dirs[i], 0755);
		fd_ = openat(fd, dirs[i], 0);
		if(fd >= 0) close(fd);
		fd = fd_;
		if(fd < 0)  {
			fprintf(stderr, "openat() failed on %s: %s\n", dirs[i], strerror(errno));
			break;
		}
	}
	if(fd >= 0) {
		if(i == argc) {
			struct timeval tv[2];

			tv[0].tv_sec = (time_t)mtime;
			tv[0].tv_usec = 0;
			tv[1].tv_sec = (time_t)mtime;
			tv[1].tv_usec = 0;
			futimes(fd, &tv[0]);

			if(vhffsfssync_preserve)  {
				if( fchmod(fd, mode) ) {
					fprintf(stderr, "fchmod() failed on %s: %s\n", pathname, strerror(errno));
				}
				if( fchown(fd, uid, gid) ) {
					fprintf(stderr, "fchown() failed on %s: %s\n", pathname, strerror(errno));
				}
			}
		}
		close(fd);
	}
	if(i != argc) return -1;

	return 0;
}
#endif


int vhffsfssync_checkfile(vhffsfssync_conn *conn, char *path, char *type, int long long size, int long long mtime, int mode, int uid, int gid) {
	gboolean fetch = FALSE;
	struct stat st;

	//printf("%s\n", path);

	// file or link
	if(! lstat(path, &st) )  {
		char *type_ = "unknown";

		if( S_ISDIR(st.st_mode) )  {
			type_ = "dir";
		}
		else if( S_ISREG(st.st_mode) )  {
			type_ = "file";
		}
		else if( S_ISLNK(st.st_mode) )  {
			type_ = "link";
		}
		/* we don't need other file types (chr, block, fifo, socket, ...) */

		if(strcmp(type, type_)) {
#ifndef CHECK
			vhffsfssync_remove(path);
#else
			printf("\033[2K\033[0Gtype mismatch - ");
#endif
			fetch = TRUE;
		}
		else if(!S_ISDIR(st.st_mode) && st.st_size != size) {
			fetch = TRUE;
#ifdef CHECK
			printf("\033[2K\033[0Gsize mismatch - ");
#endif
		}
		else if(st.st_mtime != mtime) {
			fetch = TRUE;
#ifdef CHECK
			printf("\033[2K\033[0Gmtime mismatch - ");
#endif
		}

		if(!fetch && vhffsfssync_preserve) {
			if(!S_ISLNK(st.st_mode) && (st.st_mode&07777) != mode) {
#ifndef CHECK
				if( chmod(path, mode) ) {
					fprintf(stderr, "chmod() failed on %s: %s\n", path, strerror(errno));
				}
#else
				printf("\033[2K\033[0Gmode mismatch - %s\n", path);
#endif
			}
			if(st.st_uid != uid || st.st_gid != gid) {
#ifndef CHECK
				if( lchown(path, uid, gid) ) {
					fprintf(stderr, "lchown() failed on %s: %s\n", path, strerror(errno));
				}
#else
				printf("\033[2K\033[0Guid or gid mismatch - %s\n", path);
#endif
			}
		}
	}
	else {
		if(errno == ENOENT) {
			fetch = TRUE;
#ifdef CHECK
			printf("\033[2K\033[0Gfile not found - ");
#endif
		}
		else {
			fprintf(stderr, "cannot lstat() '%s': %s\n", path, strerror(errno));
			return -1;
		}
	}
	if(fetch) {
#ifndef CHECK
		vhffsfssync_net_send_event(conn, g_strdup_printf("get%c%s%c", '\0', path, '\0') );
#else
		printf("%s\n", path);
#endif
	}


	return 0;
}

#ifndef CHECK
int vhffsfssync_event(vhffsfssync_conn *conn, char *event)  {
	char *cur, **args = NULL;
	int argalloc = 0, argc = 0;
	int ret = 0;

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
		printf("%s ", args[i]);
	}
	printf("\n");
#endif

	if(!strcmp(args[0], "remove")) {
		char *pathname = args[1];
		vhffsfssync_remove(pathname);
	}
	else if(!strcmp(args[0], "create")) {
		char *pathname = args[1];
		int long long mtime = atoll(args[2]);
		int mode = atol(args[3]);
		int uid = atol(args[4]);
		int gid = atol(args[5]);
		int fd;

		if(!vhffsfssync_preserve)
			mode = 0644;

		fd = open(pathname, O_CREAT|O_WRONLY|O_TRUNC, mode);
		if(fd >= 0) {
			struct timeval tv[2];

			tv[0].tv_sec = (time_t)mtime;
			tv[0].tv_usec = 0;
			tv[1].tv_sec = (time_t)mtime;
			tv[1].tv_usec = 0;

			if( futimes(fd, tv) ) {
				fprintf(stderr, "futimes() failed on %s: %s\n", pathname, strerror(errno));
			}

			if(vhffsfssync_preserve)  {
				if( fchmod(fd, mode) ) {
					fprintf(stderr, "fchmod() failed on %s: %s\n", pathname, strerror(errno));
				}
				if( fchown(fd, uid, gid) ) {
					fprintf(stderr, "fchown() failed on %s: %s\n", pathname, strerror(errno));
				}
			}

			close(fd);
		}
		else {
			fprintf(stderr, "open() failed on %s: %s\n", pathname, strerror(errno));
		}
	}
	else if(!strcmp(args[0], "open")) {
		char *pathname = args[1];
		int mode = atol(args[2]);
		int uid = atol(args[3]);
		int gid = atol(args[4]);
		int fd;

 		if(!vhffsfssync_preserve)
			mode = 0644;

		if( !g_hash_table_lookup(conn->openfiles, pathname) ) {

			fd = open(pathname, O_CREAT|O_WRONLY|O_TRUNC, mode);
			if(fd >= 0) {
				FILE *f;

				if(vhffsfssync_preserve)  {
					if( fchmod(fd, mode) ) {
						fprintf(stderr, "fchmod() failed on %s: %s\n", pathname, strerror(errno));
					}
					if( fchown(fd, uid, gid) ) {
						fprintf(stderr, "fchown() failed on %s: %s\n", pathname, strerror(errno));
					}
				}

				f = fdopen(fd, "w");
				if(f) {
					g_hash_table_insert(conn->openfiles, strdup(pathname), f);
				}
				else {
					fprintf(stderr, "fdopen() failed on %s: %s\n", pathname, strerror(errno));
					close(fd);
				}
			}
			else {
				fprintf(stderr, "open() failed on %s: %s\n", pathname, strerror(errno));
			}
		}
	}
	else if(!strcmp(args[0], "close")) {
		char *pathname = args[1];
		int long long mtime = atoll(args[2]);
		FILE *f;

		f = g_hash_table_lookup(conn->openfiles, pathname);
		if(f) {
			struct timeval tv[2];

			// we need to flush the data before changing mtime
			fflush(f);

			tv[0].tv_sec = (time_t)mtime;
			tv[0].tv_usec = 0;
			tv[1].tv_sec = (time_t)mtime;
			tv[1].tv_usec = 0;

			if( futimes(fileno(f), tv) ) {
				fprintf(stderr, "futimes() failed on %s: %s\n", pathname, strerror(errno));
			}
		}
		g_hash_table_remove(conn->openfiles, pathname);
	}
	else if(!strcmp(args[0], "mkdir")) {
		char *path = args[1];
		int long long mtime = atoll(args[2]);
		int mode = atol(args[3]);
		int uid = atol(args[4]);
		int gid = atol(args[5]);

		vhffsfssync_mkdir(path, mtime, mode, uid, gid);
	}
	else if(!strcmp(args[0], "symlink")) {
		char *from = args[1];
		char *to = args[2];
		int long long mtime = atoll(args[3]);
		int uid = atol(args[4]);
		int gid = atol(args[5]);
		struct stat st;

		if(! lstat(from, &st) )  {
			vhffsfssync_remove(from);
		}
		if( symlink(to, from) )  {
			fprintf(stderr, "symlink() failed on %s -> %s: %s\n", from, to, strerror(errno));
		} else {
			struct timeval tv[2];

			tv[0].tv_sec = (time_t)mtime;
			tv[0].tv_usec = 0;
			tv[1].tv_sec = (time_t)mtime;
			tv[1].tv_usec = 0;

			lutimes(from, &tv[0]);

			if(vhffsfssync_preserve)  {
				if( lchown(from, uid, gid) ) {
					fprintf(stderr, "lchown() failed on %s: %s\n", from, strerror(errno));
				}
			}
		}
	}
	else if(!strcmp(args[0], "move")) {
		char *from = args[1];
		char *to = args[2];
		if( rename(from, to) ) {
			fprintf(stderr, "rename() failed from %s to %s: %s\n", from, to, strerror(errno));
			if( errno == ENOENT ) {
				vhffsfssync_net_send_event(conn, g_strdup_printf("get%c%s%c", '\0', to, '\0') );
			}
		}
	}
	else if(!strcmp(args[0], "write")) {
		char *pathname = args[1];
		off_t offset = atoll(args[2]);
		ssize_t size = atol(args[3]);
		int fd;

		//printf("FILE: %s %lld %d\n", pathname, offset, size);

		conn->chunk_stilltoread = size;

		conn->chunk_file = g_hash_table_lookup(conn->openfiles, pathname);
		if(!conn->chunk_file) {
			int flags;

			flags = O_CREAT|O_WRONLY;
			if(!size) flags |= O_TRUNC;   // just in case

			fd = open(pathname, flags, 0644);
			if(fd >= 0) {
				FILE *f = fdopen(fd, "w");
				if(f) {
					g_hash_table_insert(conn->openfiles, strdup(pathname), f);
					conn->chunk_file = f;
				}
				else {
					fprintf(stderr, "fdopen() failed on %s: %s\n", pathname, strerror(errno));
					close(fd);
				}
			}
			else {
				fprintf(stderr, "open() failed on %s: %s\n", pathname, strerror(errno));
			}
		}

		if(conn->chunk_file  &&  fseeko(conn->chunk_file, offset, SEEK_SET) < 0 ) {
			fprintf(stderr, "fseeko() on %lld failed on file %s: %s\n", (long long int)offset, pathname, strerror(errno));
			g_hash_table_remove(conn->openfiles, pathname);
			conn->chunk_file = NULL;
		}
	}
	else if(!strcmp(args[0], "attrib")) {
		char *pathname = args[1];
		int long long mtime = atoll(args[2]);
		int mode = atol(args[3]);
		int uid = atol(args[4]);
		int gid = atol(args[5]);
		struct timeval tv[2];

		tv[0].tv_sec = (time_t)mtime;
		tv[0].tv_usec = 0;
		tv[1].tv_sec = (time_t)mtime;
		tv[1].tv_usec = 0;

		lutimes(pathname, &tv[0]);

		if(vhffsfssync_preserve)  {
			struct stat st;

			if(! lstat(pathname, &st) )  {

				if( !S_ISLNK(st.st_mode) )  {
					if( chmod(pathname, mode) ) {
						fprintf(stderr, "chmod() failed on %s: %s\n", pathname, strerror(errno));
					}
				}

				if( lchown(pathname, uid, gid) ) {
					fprintf(stderr, "lchown() failed on %s: %s\n", pathname, strerror(errno));
				}
			}
		}
	}
	else if(!strcmp(args[0], "ls")) {
		char *root = args[1];
		int long long mtime = atoll(args[2]);
		int mode = atol(args[3]);
		int uid = atol(args[4]);
		int gid = atol(args[5]);
		char *root_ = strdup(root);

		if(! vhffsfssync_mkdir(root, mtime, mode, uid, gid) ) {
			int i;
			GHashTable *filesindex;
			DIR *d;

			// build an index with all files
			filesindex = g_hash_table_new_full(g_str_hash, g_str_equal, NULL, NULL);

			// check each file
			for( i = 6 ; i < argc ; i+=7 ) {
				char *path;
				g_hash_table_insert(filesindex, args[i], args[i]);

				path = g_strdup_printf("%s/%s", root_, args[i]);
				vhffsfssync_checkfile(conn, path, args[i+1], atoll(args[i+2]), atoll(args[i+3]), atol(args[i+4]), atol(args[i+5]), atol(args[i+6]) );
				free(path);
			}

			// check for removed files
			d = opendir(root_);
			if(d) {
				struct dirent *dir;
				while( (dir = readdir(d)) )  {
					if(strcmp(dir->d_name, ".") && strcmp(dir->d_name, "..") )  {
						if(! g_hash_table_lookup(filesindex, dir->d_name) )  {
							char *path = g_strdup_printf("%s/%s", root_, dir->d_name);
							//printf("Deleting %s\n", path);
							vhffsfssync_remove(path);
							free(path);
						}
					}
				}
				closedir(d);
			}
			g_hash_table_destroy(filesindex);
		}
		free(root_);
	}
	else if(!strcmp(args[0], "time")) {
		time_t sec;
		struct timeval tv;
		gettimeofday(&tv, NULL);
		sec = atol(args[1]);
		if( abs(tv.tv_sec - sec) > 10 ) {
			fprintf(stderr, "The slave timestamp is not synchronous with the master timestamp\n");
			ret = -1;
		}
		else {
			vhffsfssync_net_send_event(conn, g_strdup_printf("fulltree%c", '\0') );
		}
	}
	else if(!strcmp(args[0], "hello")) {
		long long int seenhost = atoll(args[1]);

		if(vhffsfssync_preventloop && vhffsfssync_host == seenhost) {
			fprintf(stderr, "The slave is connecting on the same host (loopback) and loop protection is enabled\n");
			ret = -1;
		}
		else {
			vhffsfssync_net_send_event(conn, g_strdup_printf("time%c", '\0') );
		}
	}
	else {
		fprintf(stderr, "Received unhandled event: %s\n", args[0]);
		ret = -1;
	}

	free(args);
	return ret;
}
#endif


#ifdef CHECK
int vhffsfssync_event(vhffsfssync_conn *conn, char *event)  {
	char *cur, **args = NULL;
	int argalloc = 0, argc = 0;
	int ret = 0;

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
		printf("%s ", args[i]);
	}
	printf("\n");
#endif

	if(!strcmp(args[0], "remove")) {
	}
	else if(!strcmp(args[0], "create")) {
	}
	else if(!strcmp(args[0], "open")) {
	}
	else if(!strcmp(args[0], "close")) {
	}
	else if(!strcmp(args[0], "mkdir")) {
	}
	else if(!strcmp(args[0], "symlink")) {
	}
	else if(!strcmp(args[0], "move")) {
	}
	else if(!strcmp(args[0], "write")) {
		ssize_t size = atol(args[3]);
		conn->chunk_stilltoread = size;
	}
	else if(!strcmp(args[0], "attrib")) {
	}
	else if(!strcmp(args[0], "ls")) {
		char *root, *root_;
		struct stat st;

		root = args[1];
		root_ = strdup(root);

		if( !vhffsfssync_progresschar[ ++vhffsfssync_progress ] ) vhffsfssync_progress=0;
		//printf("\033[2K\033[0G%s - ", root);
		printf("\033[2K\033[0G%c", vhffsfssync_progresschar[ vhffsfssync_progress ] );
		fflush(stdout);

		if( lstat(root, &st) ) {
			printf("%s not found on slave\n", root );
		}
		else {
			int i;
			GHashTable *filesindex;
			DIR *d;

			// build an index with all files
			filesindex = g_hash_table_new_full(g_str_hash, g_str_equal, NULL, NULL);

			// check each file
			for( i = 6 ; i < argc ; i+=7 ) {
				char *path;
				g_hash_table_insert(filesindex, args[i], args[i]);

				path = g_strdup_printf("%s/%s", root_, args[i]);
				vhffsfssync_checkfile(conn, path, args[i+1], atoll(args[i+2]), atoll(args[i+3]), atol(args[i+4]), atol(args[i+5]), atol(args[i+6]) );
				free(path);
			}

			// check for removed files
			d = opendir(root_);
			if(d) {
				struct dirent *dir;
				while( (dir = readdir(d)) )  {
					if(strcmp(dir->d_name, ".") && strcmp(dir->d_name, "..") )  {
						if(! g_hash_table_lookup(filesindex, dir->d_name) )  {
							char *path = g_strdup_printf("%s/%s", root_, dir->d_name);
							printf("%s found on slave, not present on master\n", path );
							free(path);
						}
					}
				}
				closedir(d);
			}
			else {
				printf("%s is not a directory\n", root );
			}
			g_hash_table_destroy(filesindex);
		}
		free(root_);
	}
	else if(!strcmp(args[0], "time")) {
		time_t sec;
		struct timeval tv;
		gettimeofday(&tv, NULL);
		sec = atol(args[1]);
		if( abs(tv.tv_sec - sec) > 10 ) {
			fprintf(stderr, "The slave timestamp is not synchronous with the master timestamp\n");
			ret = -1;
		}
		else {
			vhffsfssync_net_send_event(conn, g_strdup_printf("fulltree%c", '\0') );
		}
	}
	else if(!strcmp(args[0], "hello")) {
		vhffsfssync_net_send_event(conn, g_strdup_printf("time%c", '\0') );
	}
	else {
		fprintf(stderr, "Received unhandled event: %s\n", args[0]);
		ret = -1;
	}

	free(args);
	return ret;
}
#endif


int vhffsfssync_parse(vhffsfssync_conn *conn)  {
	char *cur, *end;

	//printf("Buffer %d, stilltoread: %d\n", conn->buf_len, conn->chunk_stilltoread);

	/* parse the buffer */
	cur = conn->recvbuf + conn->recvbuf_begin;
	end = conn->recvbuf + conn->recvbuf_end; //beware: end can be outside the buffer, you should NOT read *end

	while(cur < end)  {

		// text mode
		if(!conn->chunk_stilltoread)  {
			char *begin;
			// find "\0\0"
			for(begin = cur ; ( cur < end && *cur++ != '\0' ) || ( cur < end && *cur++ != '\0' ) ; );

			if( !*(cur-2) && !*(cur-1) ) {
				if( vhffsfssync_event(conn, begin) )
					return -1;
				conn->recvbuf_begin += (cur - begin);
				begin = cur;
			}

			if(cur == end)  {
				register uint32_t len = end - begin;
				//fprintf(stderr, "Not parsed %d, begin is %d, end id %d\n", len, conn->recvbuf_begin, conn->recvbuf_end);

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

		// binary mode (receiving a chunk)
		else {
			size_t canread = MIN(conn->chunk_stilltoread, end-cur);
			conn->chunk_stilltoread -= canread;
#if DEBUG_EVENTS
			printf("binary mode: read: %ld stilltoread: %ld\n", (long int)canread, (long int)conn->chunk_stilltoread);
#endif
			if(conn->chunk_file) {
				size_t len = fwrite(cur, 1, canread, conn->chunk_file);
#if DEBUG_EVENTS
				printf("  written: %ld\n", (long int)len);
#endif
				if(len != canread)  {
					fprintf(stderr, "fwrite() failed: %s\n", strerror(errno));
				}
				if(!conn->chunk_stilltoread) {
					conn->chunk_file = NULL;
				}
			}
			cur += canread;
			conn->recvbuf_begin += canread;

			// all the data have been read, resetting buffer
			if(cur == end) {
				free(conn->recvbuf);
				conn->recvbuf = NULL;
				conn->recvbuf_begin = 0;
				conn->recvbuf_end = 0;
				break;
			}
		}
	}

	return 0;
}


double vhffsfssync_time()  {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec + tv.tv_usec / 1e6;
}


static void usage_exit(int ret_code, char *progname)  {
	printf ("Usage: %s [OPTION]... HOST[:PORT] DIRECTORY\n"
		"Remote synchronous file-copying tool, this is the client (the slave)\n\n"
		"  -f, --foreground\tDo not daemonise the client, display errors on the console\n"
		"  -t, --timeout=s\tConnection timeout in seconds, default is 3600s, 0 disable keepalive\n"
		"  -r, --limit-rate=kB/s\tLimit I/O bandwidth; kBytes per second\n"
		"  -p, --preserve\tPreserve owners, groups and permissions\n"
		"      --prevent-loop\tAbort if the host seen by the master is the host we are connecting to (loopback)\n"
		"      --pidfile=PATH\tWrite the pid to that file\n"
		"  -h, --help\t\tDisplay this help and exit\n"
		"  -v, --version\t\tOutput version information and exit\n",
		progname);
	exit(ret_code);
}


int main(int argc, char *argv[])  {

	int flags;
	vhffsfssync_conn *conn;
	char *cur;

	int foreground = 0;
	char *host = NULL;
	int port = 4567;
	char *root = NULL;
	int timeout = 3600;
	int limitrate = 0;
	FILE *pidfile = NULL;

	vhffsfssync_preserve = 0;
	vhffsfssync_preventloop = 0;
#ifdef CHECK
	foreground = 1;
#endif

	struct option long_options[] = {
		{ "foreground", no_argument, NULL, 'f' },
		{ "timeout", required_argument, NULL, 't' },
		{ "limit-rate", required_argument, NULL, 'r' },
		{ "preserve", no_argument, NULL, 'p' },
		{ "prevent-loop", no_argument, NULL, 1000 },
		{ "pidfile", required_argument, NULL, 1001 },
		{ "help", no_argument, NULL, 'h' },
		{ "version", no_argument, NULL, 'v' },
		{ 0, 0, 0, 0 }
	};

	while(1) {
		int option_index = 0, c;
		c = getopt_long(argc, argv, "ft:r:phv", long_options, &option_index);
		if(c == -1)
			break;

		switch(c) {
			case 'f':
				foreground = 1;
				break;

			case 't':
				timeout = atoi(optarg);
				break;

			case 'r':
				limitrate = atoi(optarg)*1000;
				break;

			case 'p':
				vhffsfssync_preserve = 1;
				break;

			case 1000:
				vhffsfssync_preventloop = 1;
				break;

			case 1001:
				pidfile = fopen(optarg, "w");
				break;

			case 'h':
				usage_exit(0, argv[0]);

			case 'v':
#ifdef VERSION
				fputs("vhffsfssync_slave " VERSION "\n", stdout);
#else
				fputs("vhffsfssync_slave\n", stdout);
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

	if(optind != argc-2)
		usage_exit(1, argv[0]);

	host = argv[optind++];
	for(cur=host ; *cur ; cur++)  {
		if(*cur == ':')  {
			*cur = '\0';
			port = atoi(++cur);
			break;
		}
	}

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

	// so that open() and mkdir() will not enforce wanted mode with mode&~umask
	umask(0);

	/* chdir() to the filesystem to write the data */
	if( chdir(root) < 0 ) {
		fprintf(stderr, "cannot chdir() to %s: %s\n", root, strerror(errno));
		return -1;
	}
	if( chroot(".") < 0 ) {
		fprintf(stderr, "cannot chroot() to %s: %s\n", root, strerror(errno));
		// disable permissions, owners and groups preservation if we are not root
#ifndef CHECK
		vhffsfssync_preserve = 0;
#endif
		//return -1;
	}
	root = ".";

	/* -- network stuff -- */
	signal(SIGPIPE, SIG_IGN);
	conn = malloc(sizeof(vhffsfssync_conn));
	conn->fd = -1;
	memset((char*)&conn->sockaddr, 0, sizeof(conn->sockaddr));
	conn->recvbuf = NULL;
	conn->recvbuf_begin = 0;
	conn->recvbuf_end = 0;
	conn->chunk_stilltoread = 0;
	conn->chunk_file = NULL;
	conn->messages = NULL;
	conn->messages_begin = 0;
	conn->messages_end = 0;
	conn->openfiles = NULL;
	conn->limitrate_speed = (double)limitrate;
	conn->limitrate_sleep = 0;
	conn->limitrate_timeprev = vhffsfssync_time();

	/* -- main loop -- */
	while(1)  {
		int opt;

		/* clean the previous connection */
		if(conn->fd >= 0) {
			shutdown(conn->fd, SHUT_RDWR);
			close(conn->fd);
		}
		conn->fd = -1;

		if(conn->openfiles) g_hash_table_destroy( conn->openfiles );
		conn->openfiles = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, (gpointer)fclose);
		conn->chunk_file = NULL;

		if(conn->messages) {
			uint32_t i;
			for(i = conn->messages_begin ; i < conn->messages_end ; i++)
				vhffsfssync_net_destroy_message(conn,  conn->messages[i]);
			free(conn->messages);
		}
		conn->messages = NULL;
		conn->messages_begin = 0;
		conn->messages_end = 0;

		if(conn->recvbuf) free(conn->recvbuf);
		conn->recvbuf = NULL;
		conn->recvbuf_begin = 0;
		conn->recvbuf_end = 0;
		conn->chunk_stilltoread = 0;

		conn->limitrate_speed = (double)limitrate;
		conn->limitrate_sleep = 0;
		conn->limitrate_timeprev = vhffsfssync_time();

		/* connect */
		memset((char*)&conn->sockaddr, 0, sizeof(conn->sockaddr));
		inet_aton(host, &conn->sockaddr.sin_addr);
		conn->sockaddr.sin_family = AF_INET;
		conn->sockaddr.sin_port = htons(port);

		conn->fd = socket(conn->sockaddr.sin_family, SOCK_STREAM, IPPROTO_TCP);
		if(conn->fd < 0)  {
			fprintf(stderr, "socket() failed: %s\n", strerror(errno));
			return -1;
		}

		/* use TCP keepalive */
		if(timeout) {
			opt = 1;
			if( setsockopt(conn->fd, SOL_SOCKET, SO_KEEPALIVE, (char*)&opt, sizeof(opt) ) )  {
				fprintf(stderr, "setsockopt() SO_KEEPALIVE failed on socket %d: %s\n", conn->fd, strerror(errno));
			}

			/* start keepalive at 9/10 of the timeout value. If timeout is too low, reserve 10s for keepalive probes */
			opt = timeout-timeout/10;
			if(opt > timeout-10) opt = timeout-10;
 			if(opt <= 0) opt=1;
			if( setsockopt(conn->fd, SOL_TCP, TCP_KEEPIDLE, (char*)&opt, sizeof(opt) ) )  {
				fprintf(stderr, "setsockopt() TCP_KEEPIDLE failed on socket %d: %s\n", conn->fd, strerror(errno));
			}

			/* consider session down after 10 missed probes */
			opt = 10;
			if( setsockopt(conn->fd, SOL_TCP, TCP_KEEPCNT, (char*)&opt, sizeof(opt) ) )  {
				fprintf(stderr, "setsockopt() TCP_KEEPCNT failed on socket %d: %s\n", conn->fd, strerror(errno));
			}

			/* 10 probes in 1/10 of total time = 1/100 of total time interval between probes */
			opt = timeout/100;
			if(!opt) opt=1;
			if( setsockopt(conn->fd, SOL_TCP, TCP_KEEPINTVL, (char*)&opt, sizeof(opt) ) )  {
				fprintf(stderr, "setsockopt() TCP_KEEPINTVL failed on socket %d: %s\n", conn->fd, strerror(errno));
			}
		}

		if( connect(conn->fd, (struct sockaddr*)&conn->sockaddr, sizeof(conn->sockaddr)) < 0 )  {

			fprintf(stderr, "connect() failed: %s\n", strerror(errno));
			goto disconnected;
		}

		/* set newfd to non-blocking */
		flags = fcntl(conn->fd, F_GETFL);
		if(flags >= 0) {
			flags |= O_NONBLOCK;
			fcntl(conn->fd, F_SETFL, flags);
		}

		/* connected */
		vhffsfssync_host = (long long int)ntohl(conn->sockaddr.sin_addr.s_addr);
		vhffsfssync_net_send_event(conn, g_strdup_printf("hello%c", '\0') );

		/* -- the real main loop starts here -- */
		while(1)  {
			int max_fd = 0;
			fd_set readfs;
			fd_set writefs;
			//struct timeval tv;
			int ret;

			FD_ZERO(&readfs);
			FD_ZERO(&writefs);

			FD_SET(conn->fd, &readfs);
			if(conn->messages) FD_SET(conn->fd, &writefs);
			if(conn->fd > max_fd) max_fd = conn->fd;

			//tv.tv_sec = 3600;
			//tv.tv_usec = 0;
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
				/* data to read ?, give give ! */
				if(FD_ISSET(conn->fd, &readfs)  )  {
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
								goto disconnected;
						}
					}
					else if(len == 0) {
						goto disconnected;
					}
					else {
						//fprintf(stdout, "Read %d, buffer is %lu, begin is %lu, end is %lu\n", len, (unsigned long)conn->recvbuf, (unsigned long)conn->recvbuf_begin, (unsigned long)conn->recvbuf_end);
						conn->recvbuf_end += len;
						if( vhffsfssync_parse(conn) )
							goto disconnected;

						if(limitrate > 0)  {
							double current, delta, delta_t, a;

							// computing download rate
							current = vhffsfssync_time();
							delta_t = current - conn->limitrate_timeprev;
							conn->limitrate_timeprev = current;

							a = delta_t/2.0; // consider elapsed time, speed is roughly computed over 2 seconds
							if(a > 1.0) a = 1.0;
							else if(a < 0.0) a = 0.0; // might happens
							conn->limitrate_speed = (conn->limitrate_speed * (1.0-a)) + (((double)len / delta_t) * a);
							//printf("%.2f MB/s\n", conn->limitrate_speed/1000/1000 );

							delta = conn->limitrate_speed - (double)limitrate;  // delta is in bytes/s
							conn->limitrate_sleep += delta * 0.01;
							//printf("%.2f ms\n", conn->limitrate_sleep/1000 );
							if(conn->limitrate_sleep > 1000000.0) conn->limitrate_sleep = 1000000.0;
							if(conn->limitrate_sleep > 0.0) usleep((int)conn->limitrate_sleep);
						}
					}
				}

				/* data to send ?, send send ! */
				if(conn->messages && FD_ISSET(conn->fd, &writefs)  )  {
					if( vhffsfssync_net_send(conn) ) {
						goto disconnected;
					}
				}
			}
		}
// YES, I am evil, I am using goto and I don't care about !
disconnected:
#if DEBUG_NET
		printf("Byebye %s... (used fd %d)\n", inet_ntoa(conn->sockaddr.sin_addr), conn->fd);
#endif
		sleep(1);
	}

	return 0;
}
