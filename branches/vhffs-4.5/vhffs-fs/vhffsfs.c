/*
 *  VHFFSFS: Virtual chroot for your users, using FUSE !
 *
 *  Copyright 2007-2010  Sylvain Rochet <gradator@gradator.net>
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

#define VHFFSFS_MAXCONNDB 5
// TODO: use a randomised temporary directory
#define VHFFSFS_EMPTYDIR "/tmp/emptydir"

#define _GNU_SOURCE

#if HAVE_CONFIG_H
#include <config.h>
#else
#error You have to run configure script before building the sources
#endif

#include <fuse.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <stdlib.h>
#include <fcntl.h>
#include <dirent.h>
#include <errno.h>

#if TIME_WITH_SYS_TIME
#   include <sys/time.h>
#   include <time.h>
#else
#   if HAVE_SYS_TIME_H
#       include <sys/time.h>
#   else
#       include <time.h>
#   endif /* HAVE_SYS_TIME_H */
#endif /* TIME_WITH_SYS_TIME */

#ifdef HAVE_SYS_XATTR_H
#   include <sys/xattr.h>
#endif

#include <pthread.h>
#include <signal.h>

#define CREATE_OK 1024
#define REMOVE_OK 2048
#define CHMOD_OK 4096

#if defined(WITH_CACHE) || defined(WITH_CHECKQUOTA_CACHE)
#include <glib.h>
#endif

#ifdef WITH_CHECKQUOTA
#include <sys/quota.h>
#ifdef WITH_CHECKQUOTA_RPC
#include <rpc/rpc.h>
#include "rquota.h"
typedef u_int64_t qsize_t;
#endif
#endif

#include <postgresql/libpq-fe.h>
#include "md5.h"

#ifdef WITH_CACHE
typedef struct {
	char *query;
	PGresult *result;
	time_t arrival;
	int ref;
} vhffsfs_cache_query;
#endif

#ifdef WITH_CHECKQUOTA_CACHE
typedef struct {
	gid_t gid;
	char *path;
	char *key;
	struct dqblk *dq;
	time_t arrival;
	int ref;
} vhffsfs_cache_quota;
#endif

struct vhffsfs {
	pthread_mutex_t pg_lock[VHFFSFS_MAXCONNDB];
	PGconn *pg_conn[VHFFSFS_MAXCONNDB];
	char *grouppath;
	char *webspath;
	char *repositoriespath;
	char *dbhost;
	int dbport;
	char *dbuser;
	char *dbpass;
	char *dbname;
	int dbtimeout;
	char *dbconninfo;
	mode_t forcemodefile;
	mode_t forcemodedir;
	mode_t clearmodefile;
	mode_t clearmodedir;
#ifdef WITH_CACHE
	GHashTable *cachequeries;
	GPtrArray* cachekeys;
	pthread_mutex_t cachelock;
	int cachethreadstarted;
#endif
#ifdef WITH_CHECKQUOTA
	char *datablockdev;
	char *repositoriesblockdev;
	char *dataprefixpath;
	char *repositoriesprefixpath;
#ifdef WITH_CHECKQUOTA_RPC
	char *datarpcserver;
	char *datarpcpath;
	char *repositoriesrpcserver;
	char *repositoriesrpcpath;
#endif
#ifdef WITH_CHECKQUOTA_CACHE
	GHashTable *quotacacheused;
	GPtrArray* quotacachekeys;
	pthread_mutex_t quotacachelock;
	int quotacachethreadstarted;
#endif
#endif
};

static struct vhffsfs vhffsfs;

#if defined(WITH_CACHE) || defined(WITH_CHECKQUOTA_CACHE)
time_t vhffsfs_cache_arrival()  {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	return tv.tv_sec;
}

int vhffsfs_cache_timeout(time_t arrival, time_t timeout)  {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	if(tv.tv_sec - arrival >= timeout) return 1;
	return 0;
}
#endif

#ifdef WITH_CACHE
static inline void vhffsfs_cache_lock()  {
	pthread_mutex_lock(&vhffsfs.cachelock);
}

static inline void vhffsfs_cache_unlock()  {
	pthread_mutex_unlock(&vhffsfs.cachelock);
}

PGresult *vhffsfs_cache_add(char *query, PGresult *result)  {
	vhffsfs_cache_query *vcq;
	vhffsfs_cache_lock();
	vcq = g_hash_table_lookup(vhffsfs.cachequeries, query);
	if(vcq) {
		vcq->ref++;
		vhffsfs_cache_unlock();
		PQclear(result);
		return vcq->result;
	}
#ifdef WITH_CACHE_DEBUG
	printf("CACHE: ADDING: '%s'\n", query);
#endif
	vcq = malloc(sizeof(vhffsfs_cache_query));
	vcq->query = strdup(query);
	vcq->result = result;
	vcq->arrival = vhffsfs_cache_arrival();
	vcq->ref = 1;
	g_hash_table_insert(vhffsfs.cachequeries, vcq->query, vcq);
	g_ptr_array_add(vhffsfs.cachekeys, vcq->query);
	vhffsfs_cache_unlock();
	return vcq->result;
}

void vhffsfs_cache_del(char *query)  {
	vhffsfs_cache_query *vcq;
	vhffsfs_cache_lock();
	vcq = g_hash_table_lookup(vhffsfs.cachequeries, query);
	// non existing or still referenced
	if(!vcq || vcq->ref > 0) {
		vhffsfs_cache_unlock();
		return;
	}
#ifdef WITH_CACHE_DEBUG
	printf("CACHE: DELETING: '%s'\n", query);
#endif
	g_ptr_array_remove_fast(vhffsfs.cachekeys, vcq->query);
	g_hash_table_remove(vhffsfs.cachequeries, vcq->query);
	free(vcq->query);
	PQclear(vcq->result);
	free(vcq);
	vhffsfs_cache_unlock();
}

PGresult *vhffsfs_cache_lookup(char *query)  {
	vhffsfs_cache_lock();
	vhffsfs_cache_query *vcq = g_hash_table_lookup(vhffsfs.cachequeries, query);
	if(vcq) {
		// timeout
		if(vhffsfs_cache_timeout(vcq->arrival, VHFFSFS_CACHE_QUERY_TIMEOUT)) {
#ifdef WITH_CACHE_DEBUG
			fprintf(stdout, "CACHE: TIMEOUT: '%s'\n", query);
#endif
			vhffsfs_cache_unlock();
			vhffsfs_cache_del(query);
			return NULL;
		}
		// cache hit
#ifdef WITH_CACHE_DEBUG
		fprintf(stdout, "CACHE: HIT: '%s'\n", query);
#endif
		vcq->ref++;
		vhffsfs_cache_unlock();
		return vcq->result;
	}
	// cache miss
#ifdef WITH_CACHE_DEBUG
	fprintf(stdout, "CACHE: MISS: '%s'\n", query);
#endif
	vhffsfs_cache_unlock();
	return NULL;
}

void vhffsfs_cache_unref(char *query)  {
	vhffsfs_cache_lock();
	vhffsfs_cache_query *vcq = g_hash_table_lookup(vhffsfs.cachequeries, query);
	if(vcq && vcq->ref > 0) vcq->ref--;
	else {
		if(!vcq) fprintf(stderr, "CACHE: CORRUPT: '%s': NOT IN TABLE\n", query);
		else fprintf(stderr, "CACHE: CORRUPT: '%s': REF IS ALREADY SET TO 0\n", query);
	}
	vhffsfs_cache_unlock();
}


static void *vhffsfs_cache_flush(void *data_)
{
	(void) data_;

	while(1) {
		GPtrArray *keys;
		int i;

		sleep(VHFFSFS_CACHE_QUERY_FLUSH_EVERY);

		keys = g_ptr_array_sized_new(4096);

		//printf("FLUSH CACHE\n");

		// copy keys
		vhffsfs_cache_lock();
		for(i = 0 ; i < vhffsfs.cachekeys->len ; i++)  {
			g_ptr_array_add(keys, strdup(vhffsfs.cachekeys->pdata[i]));
		}
		vhffsfs_cache_unlock();

		// sleep a bit to not lock the cache too much
		sleep(1);

		for(i = 0 ; i < keys->len ; i++)  {
			char *query = keys->pdata[i];
			vhffsfs_cache_query *vcq;

			vhffsfs_cache_lock();
			vcq = g_hash_table_lookup(vhffsfs.cachequeries, query);
			if(vcq && vhffsfs_cache_timeout(vcq->arrival, VHFFSFS_CACHE_QUERY_TIMEOUT))  {
#ifdef WITH_CACHE_DEBUG
				fprintf(stdout, "CACHE: TIMEOUT: '%s'\n", query);
#endif
				vhffsfs_cache_unlock();
				vhffsfs_cache_del(query);
			}
			else vhffsfs_cache_unlock();

			free(query);
			//sleep a bit to not lock the cache too much
			usleep(100000);
		}

		g_ptr_array_free(keys, TRUE);
	}
	return NULL;
}


static int vhffsfs_start_cache_flush_thread(void)
{
	int err;
	pthread_t thread_id;
	sigset_t oldset;
	sigset_t newset;

	if(vhffsfs.cachethreadstarted) return 0;

	sigemptyset(&newset);
	sigaddset(&newset, SIGTERM);
	sigaddset(&newset, SIGINT);
	sigaddset(&newset, SIGHUP);
	sigaddset(&newset, SIGQUIT);
	pthread_sigmask(SIG_BLOCK, &newset, &oldset);
	err = pthread_create(&thread_id, NULL, vhffsfs_cache_flush, NULL);
	if(err) {
		fprintf(stderr, "Failed to create thread: %s\n", strerror(err));
		return -EIO;
	}
	pthread_detach(thread_id);
	pthread_sigmask(SIG_SETMASK, &oldset, NULL);
	vhffsfs.cachethreadstarted = 1;
	return 0;
}
#endif


PGresult *vhffsfs_PGQuery(char *query)  {

	int i;
	PGresult *res;

#ifdef WITH_CACHE
	// try to fetch query from cache
	res = vhffsfs_cache_lookup(query);
	if(res) return res;
#endif

	do {
		for(i = 0 ; i < VHFFSFS_MAXCONNDB && pthread_mutex_trylock(&vhffsfs.pg_lock[i]) ; i++);
	// all slots used, sleep for 100ms and try again
	} while(i == VHFFSFS_MAXCONNDB && !usleep(100000));

	// something very weird happened
	if(i == VHFFSFS_MAXCONNDB) return NULL;

	// wait until we are connected to the pgsql server
	while(!vhffsfs.pg_conn[i]  ||  PQstatus(vhffsfs.pg_conn[i]) != CONNECTION_OK)  {
		vhffsfs.pg_conn[i] = PQconnectdb(vhffsfs.dbconninfo);

		if(PQstatus(vhffsfs.pg_conn[i]) != CONNECTION_OK)  {
			fprintf(stderr, "SLOT[%d]: CONNECT FAILED '%s': %s\n", i, PQdb(vhffsfs.pg_conn[i]), PQerrorMessage(vhffsfs.pg_conn[i]));
			PQfinish(vhffsfs.pg_conn[i]);
			sleep(1);
		}
		else {
			fprintf(stdout, "SLOT[%d]: CONNECT '%s'\n", i, PQdb(vhffsfs.pg_conn[i]));
		}
	}

	res = PQexec(vhffsfs.pg_conn[i], query);
	if(PQresultStatus(res) != PGRES_TUPLES_OK)
	{
		fprintf(stderr, "SLOT[%d]: QUERY: '%s' failed: %s\n", i, query, PQerrorMessage(vhffsfs.pg_conn[i]));
		PQclear(res);
		res=NULL;
	}
	else {
		//fprintf(stdout, "SLOT[%d]: QUERY: '%s'\n", i, query);
#ifdef WITH_CACHE
		// fill cache
		res = vhffsfs_cache_add(query, res);
#endif
	}

	pthread_mutex_unlock(&vhffsfs.pg_lock[i]);
	return res;
}

static inline void vhffsfs_PGClear(char *query, PGresult *result)  {
#ifdef WITH_CACHE
	vhffsfs_cache_unref(query);
#else
	PQclear(result);
#endif
}


char *vhffsfs_gethomedir()  {
	char query[128];
	PGresult *res;
	char *homedir=NULL;

	snprintf(query, 128, "SELECT u.homedir FROM vhffs_users u INNER JOIN vhffs_object o ON o.object_id=u.object_id WHERE o.state=6 AND u.uid = %d", fuse_get_context()->uid);
	res=vhffsfs_PGQuery(query);
	if(!res) return NULL;

	if(PQnfields(res) == 1 && PQntuples(res) == 1)
		homedir = strdup(PQgetvalue(res, 0, 0));

	vhffsfs_PGClear(query, res);
	return homedir;
}


char *vhffsfs_getgroupdir(char *group)  {

	char query[256];
	PGresult *res;
	char *groupname=NULL;
	char *groupdir=NULL;
	char *cur;

	// check if group match ^[a-z0-9]+$ to prevent SQL injections
	for(cur = group ; *cur ; cur++)
 		if(! ( (*cur >= 'a' && *cur <= 'z') || (*cur >= '0' && *cur <= '9') ) ) return NULL;

	snprintf(query, 256, "SELECT g.groupname FROM vhffs_groups g INNER JOIN vhffs_user_group ug ON ug.gid=g.gid INNER JOIN vhffs_object o ON o.object_id=g.object_id WHERE ug.uid = %d AND o.state=6 AND g.groupname='%s'", fuse_get_context()->uid, group);
	res=vhffsfs_PGQuery(query);
	if(!res) return NULL;

	if(PQnfields(res) == 1 && PQntuples(res) == 1)
		groupname = PQgetvalue(res, 0, 0);

	if(groupname)  {
		groupdir = malloc(strlen(vhffsfs.grouppath)+strlen(groupname)+6);
		sprintf(groupdir, "%s/%c/%c/%s", vhffsfs.grouppath, groupname[0], groupname[1], groupname);
	}

	vhffsfs_PGClear(query, res);
	return groupdir;
}


gid_t vhffsfs_getgroupgid(char *group)  {

	char query[256];
	PGresult *res;
	gid_t gid=0;
	char *cur;

	// check if group match ^[a-z0-9]+$ to prevent SQL injections
	for(cur = group ; *cur ; cur++)
		if(! ( (*cur >= 'a' && *cur <= 'z') || (*cur >= '0' && *cur <= '9') ) ) return 0;

	snprintf(query, 256, "SELECT g.gid FROM vhffs_groups g INNER JOIN vhffs_user_group ug ON ug.gid=g.gid INNER JOIN vhffs_object o ON o.object_id=g.object_id WHERE ug.uid = %d AND o.state=6 AND g.groupname='%s' ", fuse_get_context()->uid, group);
	res=vhffsfs_PGQuery(query);
	if(!res) return 0;

	if(PQnfields(res) == 1 && PQntuples(res) == 1)
		gid = atoi(PQgetvalue(res, 0, 0));

	vhffsfs_PGClear(query, res);
	return gid;
}


char *vhffsfs_getwebdir(char *group, char *website)  {

	char query[256];
	PGresult *res;
	char *servername=NULL;
	char *webdir=NULL;
	char *cur;

	// check if group match ^[a-z0-9]+$ to prevent SQL injections
	for(cur = group ; *cur ; cur++)
 		if(! ( (*cur >= 'a' && *cur <= 'z') || (*cur >= '0' && *cur <= '9') ) ) return NULL;

	// check if website match ^[a-z0-9\-\.]+$ to prevent SQL injections
	for(cur = website ; *cur ; cur++)
 		if(! ( (*cur >= 'a' && *cur <= 'z') || (*cur >= '0' && *cur <= '9') || *cur == '-' || *cur == '.') ) return NULL;

	snprintf(query, 256, "SELECT servername FROM vhffs_httpd h INNER JOIN vhffs_object o ON o.object_id=h.object_id INNER JOIN vhffs_groups g ON g.gid=o.owner_gid WHERE o.state=6 AND g.groupname='%s' AND servername='%s'", group, website);
	res=vhffsfs_PGQuery(query);
	if(!res) return NULL;

	if(PQnfields(res) == 1 && PQntuples(res) == 1)
		servername = PQgetvalue(res, 0, 0);

	if(servername)  {
		MD5_CTX context;
		unsigned char digest[16];

		webdir = malloc(strlen(vhffsfs.webspath)+strlen(servername)+11);
		MD5Init(&context);
		MD5Update(&context, (unsigned char*)servername, strlen(servername));
		MD5Final(digest, &context);
		sprintf(webdir, "%s/%02x/%02x/%02x/%s", vhffsfs.webspath, digest[0], digest[1], digest[2], servername);
	}

	vhffsfs_PGClear(query, res);
	return webdir;
}


char *vhffsfs_getrepositorydir(char *group, char *name)  {

	char query[256];
	PGresult *res;
	char *reponame=NULL;
	char *repodir=NULL;
	char *cur;

	// check if group match ^[a-z0-9]+$ to prevent SQL injections
	for(cur = group ; *cur ; cur++)
 		if(! ( (*cur >= 'a' && *cur <= 'z') || (*cur >= '0' && *cur <= '9') ) ) return NULL;

	// check if name match ^[a-z0-9]+$ to prevent SQL injections
	for(cur = name ; *cur ; cur++)
 		if(! ( (*cur >= 'a' && *cur <= 'z') || (*cur >= '0' && *cur <= '9') ) ) return NULL;

	snprintf(query, 256, "SELECT name FROM vhffs_repository r INNER JOIN vhffs_object o ON o.object_id=r.object_id INNER JOIN vhffs_groups g ON g.gid=o.owner_gid WHERE o.state=6 AND g.groupname='%s' AND r.name='%s'", group, name);
	res=vhffsfs_PGQuery(query);
	if(!res) return NULL;

	if(PQnfields(res) == 1 && PQntuples(res) == 1)
		reponame = PQgetvalue(res, 0, 0);

	if(reponame)  {
		repodir = malloc(strlen(vhffsfs.repositoriespath)+strlen(reponame)+2);
		sprintf(repodir, "%s/%s", vhffsfs.repositoriespath, reponame);
	}

	vhffsfs_PGClear(query, res);
	return repodir;
}


char **vhffsfs_getusergroups(uid_t uid)  {

	char query[256];
	PGresult *res;
	char **groups=NULL;

	snprintf(query, 256, "SELECT g.groupname FROM vhffs_groups g INNER JOIN vhffs_user_group ug ON ug.gid=g.gid INNER JOIN vhffs_object o ON o.object_id=g.object_id WHERE o.state=6 AND ug.uid=%d", uid);
	res=vhffsfs_PGQuery(query);
	if(!res) return NULL;

	if(PQnfields(res) == 1)  {
		int i, x;
		groups = malloc((PQntuples(res)*2+1)*sizeof(char*));
		*(groups+PQntuples(res)*2) = '\0';

		for(i = x = 0 ; i < PQntuples(res) ; i++, x+=2)  {
			char *groupname = PQgetvalue(res, i, 0);
			if(groupname)  {
				char *groupdir = malloc(strlen(vhffsfs.grouppath)+strlen(groupname)+6);
				sprintf(groupdir, "%s/%c/%c/%s", vhffsfs.grouppath, groupname[0], groupname[1], groupname);
				*(groups+x) = strdup(groupname);
				*(groups+x+1) = groupdir;
			}
		}
	}

	vhffsfs_PGClear(query, res);
	return groups;
}


char **vhffsfs_getgroupservices(gid_t gid)  {

	char query1[256], query2[256];
	PGresult *res1,*res2;
	char **services=NULL;

	// fetch websites
	snprintf(query1, 256, "SELECT servername FROM vhffs_httpd h INNER JOIN vhffs_object o ON o.object_id=h.object_id WHERE o.state=6 AND o.owner_gid=%d", gid);
	res1=vhffsfs_PGQuery(query1);
	if(!res1) return NULL;

	// fetch repositories
	snprintf(query2, 256, "SELECT name FROM vhffs_repository r INNER JOIN vhffs_object o ON o.object_id=r.object_id WHERE o.state=6 AND o.owner_gid=%d", gid);
	res2=vhffsfs_PGQuery(query2);
	if(!res2) {
		vhffsfs_PGClear(query1, res1);
		return NULL;
	}

	if(PQnfields(res1) == 1  &&  PQnfields(res2) == 1)  {
		int i, x=0;
		int nb = PQntuples(res1)+PQntuples(res2);

		services = malloc((nb*2+1)*sizeof(char*) );
		*(services+nb*2) = '\0';

		// websites
		for(i = 0 ; i < PQntuples(res1) ; i++, x+=2)  {
			char *servername = PQgetvalue(res1, i, 0);
			if(servername)  {
				char *displayedname;
				char *webdir;
				MD5_CTX context;
				unsigned char digest[16];

				displayedname = malloc(strlen(servername)+5);
				sprintf(displayedname, "%s-web", servername);

				webdir = malloc(strlen(vhffsfs.webspath)+strlen(servername)+11);
				MD5Init(&context);
				MD5Update(&context, (unsigned char*)servername, strlen(servername));
				MD5Final(digest, &context);
				sprintf(webdir, "%s/%02x/%02x/%02x/%s", vhffsfs.webspath, digest[0], digest[1], digest[2], servername);

				*(services+x) = displayedname;
				*(services+x+1) = webdir;
			}
		}

		// repositories
		for(i = 0 ; i < PQntuples(res2) ; i++, x+=2)  {
			char *reponame = PQgetvalue(res2, i, 0);
			if(reponame)  {
				char *displayedname;
				char *repodir;

 				displayedname = malloc(strlen(reponame)+12);
				sprintf(displayedname, "%s-repository", reponame);

				repodir = malloc(strlen(vhffsfs.repositoriespath)+strlen(reponame)+2);
				sprintf(repodir, "%s/%s", vhffsfs.repositoriespath, reponame);

				*(services+x) = displayedname;
				*(services+x+1) = repodir;
			}
		}
	}

	vhffsfs_PGClear(query1, res1);
	vhffsfs_PGClear(query2, res2);
	return services;
}


// path must be an absolute allocated path, without symlink
// content of path is modified and is left modified if right checks fails
int vhffsfs_checkperm_with_realpath(char *path, uid_t uid, gid_t gid, int mode) {

	char *cur, *parent;
	struct stat st;

	if(!path || *path == '\0' || *path != '/') {
		errno = ENOENT;
		return -1;
	}

	for(parent=path, cur=path+1 ; *cur ; cur++ ) {
		if(*cur == '/') {
			*cur = '\0';

			if( lstat(path, &st) ) {
				// lstat() handles ENOENT and so on then set errno
				return -1;
			}

			if(!S_ISDIR(st.st_mode)) {
				errno = ENOTDIR;
				return -1;
			}

			if(st.st_uid == uid) {
				if(!(st.st_mode & S_IXUSR)) {
					errno = EACCES;
					return -1;
				}
			} else if(st.st_gid == gid) {
				if(!(st.st_mode & S_IXGRP)) {
					errno = EACCES;
					return -1;
				}
			} else {
				if(!(st.st_mode & S_IXOTH)) {
					errno = EACCES;
					return -1;
				}
			}
			*cur = '/';
			parent = cur;
		}
	}

	if( mode & (CREATE_OK|REMOVE_OK) )  {
		*parent = '\0';

		if( lstat(path, &st) ) {
			return -1;
		}

		if(st.st_uid == uid) {
			if(!(st.st_mode & S_IWUSR)) {
				errno = EACCES;
				return -1;
			}
		} else if(st.st_gid == gid) {
			if(!(st.st_mode & S_IWGRP)) {
				errno = EACCES;
				return -1;
			}
		} else {
			if(!(st.st_mode & S_IWOTH)) {
				errno = EACCES;
				return -1;
			}
		}

		*parent = '/';
		return 0;
	}

	if( lstat(path, &st) ) {
		return -1;
	}

	if(mode == F_OK) {
		return 0;
	}

	if(mode & CHMOD_OK) {
		if(st.st_uid != uid) {
			errno = EACCES;
			return -1;
		}
		return 0;
	}

	if(mode & R_OK) {
		if(st.st_uid == uid) {
			if(!(st.st_mode & S_IRUSR)) {
				errno = EACCES;
				return -1;
			}
		} else if(st.st_gid == gid) {
			if(!(st.st_mode & S_IRGRP)) {
				errno = EACCES;
				return -1;
			}
		} else {
			if(!(st.st_mode & S_IROTH)) {
				errno = EACCES;
				return -1;
			}
		}
	}

	if(mode & W_OK) {
		if(st.st_uid == uid) {
			if(!(st.st_mode & S_IWUSR)) {
				errno = EACCES;
				return -1;
			}
		} else if(st.st_gid == gid) {
			if(!(st.st_mode & S_IWGRP)) {
				errno = EACCES;
				return -1;
			}
		} else {
			if(!(st.st_mode & S_IWOTH)) {
				errno = EACCES;
				return -1;
			}
		}
	}

	if(mode & X_OK) {
		if(st.st_uid == uid) {
			if(!(st.st_mode & S_IXUSR)) {
				errno = EACCES;
				return -1;
			}
		} else if(st.st_gid == gid) {
			if(!(st.st_mode & S_IXGRP)) {
				errno = EACCES;
				return -1;
			}
		} else {
			if(!(st.st_mode & S_IXOTH)) {
				errno = EACCES;
				return -1;
			}
		}
	}

	return 0;
}


// return the real path
char *vhffsfs_realpath(const char *path, uid_t *ruid, gid_t *rgid, int access)  {
	char *begin, *cur;
	char *first=NULL;
	char *homedir;
	char *rpath=NULL;
	uid_t uid;
	gid_t gid;

	//printf("======= PATH: %s\n", path);
	//printf("======= UID: %d\n", fuse_get_context()->uid);
	//printf("======= GID: %d\n", fuse_get_context()->gid);

	// path empty
	if(*(path+0) == '\0') {
		errno = ENOENT;
		return NULL;
	}
	// set uid and gid
	uid = fuse_get_context()->uid;
	if(ruid) *ruid = uid;
	gid = fuse_get_context()->gid;
	if(rgid) *rgid = gid;
	// fetch homedir
	homedir = vhffsfs_gethomedir();
	if(!homedir) return strdup(VHFFSFS_EMPTYDIR);
	// -- parse path
	// /                   | home directory ----------------------------|
	// /first              | home file | group directory ---------------|
	// /first/second       | home file | group file | service directory |
	// /first/second/third | home file | group file | service file -----|

	// get first node
	cur = (char*)path;
	if(*cur++)  {
		for(begin = cur ; *cur && *cur != '/'; cur++);
		if(cur != begin) first = strndup(begin, cur - begin);
	}

	// home directory
	if(!first) rpath = strdup(homedir);

	// FIRST EXIST BELOW

	// so, try to fetch group directory
	else {
		char *groupdir = vhffsfs_getgroupdir(first);

		// home file
		if(!groupdir)  {
			rpath = malloc(strlen(homedir)+strlen(begin)+2);
			sprintf(rpath, "%s/%s", homedir, begin);
		}

		else {
			char *groupname = first;
			char *second=NULL;

			// set gid
			gid = vhffsfs_getgroupgid(groupname);
			if(rgid) *rgid = gid;

			// get second node
			if(*cur++) {
				for(begin = cur ; *cur && *cur != '/'; cur++);
				if(cur != begin) second = strndup(begin, cur - begin);
			}

			// group directory
			if(!second) rpath = strdup(groupdir);

			// SECOND EXIST BELOW

			// so, try to fetch service directory
			else {
				char *servicedir=NULL;
				char *servicetype, *servicename;

				// fetch servicetype and servicename
				for(servicetype = servicename = second ; *servicetype ; servicetype++);
				for(; servicetype > second && *servicetype != '-' ; servicetype--);
				if(*servicetype == '-') *servicetype++ = '\0';

				if(!strcmp(servicetype, "web")) {
					servicedir = vhffsfs_getwebdir(groupname, servicename);
				} else if(!strcmp(servicetype, "repository")) {
					servicedir = vhffsfs_getrepositorydir(groupname, servicename);
				}

				// group file
				if(!servicedir)  {
					rpath = malloc(strlen(groupdir)+strlen(begin)+2);
					sprintf(rpath, "%s/%s", groupdir, begin);
				}

				else {
					char *third=NULL;

					// get third node
					if(*cur++) third = strdup(cur);

					// service directory
					if(!third) rpath = strdup(servicedir);

					// THIRD EXIST BELOW
					else {
						rpath = malloc(strlen(servicedir)+strlen(third)+2);
						sprintf(rpath, "%s/%s", servicedir, third);

						free(third);
					}
					free(servicedir);
				}
				free(second);
			}
			free(groupdir);
		}
		free(first);
	}
	free(homedir);

	if( vhffsfs_checkperm_with_realpath(rpath, uid, gid, access) ) {
		free(rpath);
		return NULL;
	}

	//printf("======= RETURN: %s\n\n", rpath);
	return rpath;
}


char **vhffsfs_virtualdirs(const char *path)  {

	char *groupname;
	char *cur;
	gid_t gid;

	// path empty
	if(*path == '\0') return NULL;

	// get groupname
	groupname = (char*)path+1;
	if(!*groupname)
		return vhffsfs_getusergroups(fuse_get_context()->uid);

	// don't do group lookup if the path is not a group directory
	for(cur = groupname ; *cur ; cur++)
		if( *cur == '/' ) return NULL;

	gid = vhffsfs_getgroupgid(groupname);
	if(gid > 0)
		return vhffsfs_getgroupservices(gid);

	return NULL;
}


#ifdef WITH_CHECKQUOTA
#ifdef WITH_CHECKQUOTA_CACHE
static inline void vhffsfs_checkquota_cache_lock()  {
	pthread_mutex_lock(&vhffsfs.quotacachelock);
}

static inline void vhffsfs_checkquota_cache_unlock()  {
	pthread_mutex_unlock(&vhffsfs.quotacachelock);
}

char *vhffsfs_checkquota_genkey(gid_t gid, char *path)  {
	int len;
	if(!path) return NULL;
	len = strlen(path)+10+1+1; /* path + any 32 bits number + '_' + '\0' */
	char *key = malloc(len);
	snprintf(key, len, "%.10u_%s", gid, path);
	return key;
}

struct dqblk *vhffsfs_checkquota_cache_add(char *key, gid_t gid, char *path, struct dqblk *dq)  {
	vhffsfs_cache_quota *vcq;
	vhffsfs_checkquota_cache_lock();
	vcq = g_hash_table_lookup(vhffsfs.quotacacheused, key);
	if(vcq) {
		vcq->ref++;
		vhffsfs_checkquota_cache_unlock();
		free(dq);
		return vcq->dq;
	}
#ifdef WITH_CHECKQUOTA_CACHE_DEBUG
	fprintf(stdout, "QUOTACACHE: ADDING: %s [ %d , %s ]\n", key, gid, path);
	fprintf(stdout, "QUOTACACHE: VALUES:  blocks hard: %lld  soft: %lld  cur: %lld   files hard: %lld  soft: %lld  cur: %lld\n", dq->dqb_bhardlimit, dq->dqb_bsoftlimit, dq->dqb_curspace, dq->dqb_ihardlimit, dq->dqb_isoftlimit, dq->dqb_curinodes);
#endif
	vcq = malloc(sizeof(vhffsfs_cache_quota));
	vcq->gid = gid;
	vcq->path = path;
	vcq->dq = dq;
	vcq->arrival = vhffsfs_cache_arrival();
	vcq->ref = 1;
	vcq->key = strdup(key);
	g_hash_table_insert(vhffsfs.quotacacheused, vcq->key, vcq);
	g_ptr_array_add(vhffsfs.quotacachekeys, vcq->key);
	vhffsfs_checkquota_cache_unlock();
	return vcq->dq;
}

void vhffsfs_checkquota_cache_del(char *key)  {
	vhffsfs_cache_quota *vcq;
	vhffsfs_checkquota_cache_lock();
	vcq = g_hash_table_lookup(vhffsfs.quotacacheused, key);
	// non existing or still referenced
	if(!vcq || vcq->ref > 0) {
		vhffsfs_checkquota_cache_unlock();
		return;
	}
#ifdef WITH_CHECKQUOTA_CACHE_DEBUG
	printf("QUOTACACHE: DELETING: %s\n", key);
#endif
	g_ptr_array_remove_fast(vhffsfs.quotacachekeys, vcq->key);
	g_hash_table_remove(vhffsfs.quotacacheused, vcq->key);
	free(vcq->dq);
	free(vcq->key);
	free(vcq);
	vhffsfs_checkquota_cache_unlock();
}

struct dqblk *vhffsfs_checkquota_cache_lookup(char *key)  {
	vhffsfs_checkquota_cache_lock();
	vhffsfs_cache_quota *vcq = g_hash_table_lookup(vhffsfs.quotacacheused, key);
	if(vcq) {
		// timeout
		if(vhffsfs_cache_timeout(vcq->arrival, VHFFSFS_CHECKQUOTA_CACHE_TIMEOUT)) {
#ifdef WITH_CHECKQUOTA_CACHE_DEBUG
			fprintf(stdout, "QUOTACACHE: TIMEOUT: %s\n", key);
#endif
			vhffsfs_checkquota_cache_unlock();
			vhffsfs_checkquota_cache_del(key);
			return NULL;
		}
		// cache hit
#ifdef WITH_CHECKQUOTA_CACHE_DEBUG
		fprintf(stdout, "QUOTACACHE: HIT: %s\n", key);
		fprintf(stdout, "QUOTACACHE: VALUES:  blocks hard: %lld  soft: %lld  cur: %lld   files hard: %lld  soft: %lld  cur: %lld\n", vcq->dq->dqb_bhardlimit, vcq->dq->dqb_bsoftlimit, vcq->dq->dqb_curspace, vcq->dq->dqb_ihardlimit, vcq->dq->dqb_isoftlimit, vcq->dq->dqb_curinodes);
#endif
		vcq->ref++;
		vhffsfs_checkquota_cache_unlock();
		return vcq->dq;
	}
	// cache miss
#ifdef WITH_CHECKQUOTA_CACHE_DEBUG
	fprintf(stdout, "QUOTACACHE: MISS: %s\n", key);
#endif
	vhffsfs_checkquota_cache_unlock();
	return NULL;
}

void vhffsfs_checkquota_cache_unref(char *key)  {
	vhffsfs_checkquota_cache_lock();
	vhffsfs_cache_quota *vcq = g_hash_table_lookup(vhffsfs.quotacacheused, key);
	if(vcq && vcq->ref > 0) vcq->ref--;
	else {
		if(!vcq) fprintf(stderr, "CACHE: CORRUPT: '%s': NOT IN TABLE\n", key);
		else fprintf(stderr, "CACHE: CORRUPT: '%s': REF IS ALREADY SET TO 0\n", key);
	}
	vhffsfs_checkquota_cache_unlock();
}


static void *vhffsfs_checkquota_cache_flush(void *data_)
{
	(void) data_;

	while(1) {
		GPtrArray *keys;
		int i;

		sleep(VHFFSFS_CHECKQUOTA_CACHE_REFRESH);

		keys = g_ptr_array_sized_new(4096);

		//printf("FLUSH CACHE\n");

		// copy keys
		vhffsfs_checkquota_cache_lock();
		for(i = 0 ; i < vhffsfs.quotacachekeys->len ; i++)  {
			g_ptr_array_add(keys, strdup(vhffsfs.quotacachekeys->pdata[i]));
		}
		vhffsfs_checkquota_cache_unlock();

		// sleep a bit to not lock the cache too much
		sleep(1);

		for(i = 0 ; i < keys->len ; i++)  {
			char *key = keys->pdata[i];

			vhffsfs_cache_quota *vcq;

			vhffsfs_checkquota_cache_lock();
			vcq = g_hash_table_lookup(vhffsfs.quotacacheused, key);
			if(vcq && vhffsfs_cache_timeout(vcq->arrival, VHFFSFS_CHECKQUOTA_CACHE_TIMEOUT))  {
#ifdef WITH_CHECKQUOTA_CACHE_DEBUG
				fprintf(stdout, "QUOTACACHE: TIMEOUT: %d, %s\n", vcq->gid, vcq->path);
#endif
				vhffsfs_checkquota_cache_unlock();
				vhffsfs_checkquota_cache_del(key);
			}
			else vhffsfs_checkquota_cache_unlock();

			free(key);
			//sleep a bit to not lock the cache too much
			usleep(100000);
		}

		g_ptr_array_free(keys, TRUE);
	}
	return NULL;
}


static int vhffsfs_checkquota_start_cache_flush_thread(void)
{
	int err;
	pthread_t thread_id;
	sigset_t oldset;
	sigset_t newset;

	if(vhffsfs.quotacachethreadstarted) return 0;

	sigemptyset(&newset);
	sigaddset(&newset, SIGTERM);
	sigaddset(&newset, SIGINT);
	sigaddset(&newset, SIGHUP);
	sigaddset(&newset, SIGQUIT);
	pthread_sigmask(SIG_BLOCK, &newset, &oldset);
	err = pthread_create(&thread_id, NULL, vhffsfs_checkquota_cache_flush, NULL);
	if(err) {
		fprintf(stderr, "Failed to create thread: %s\n", strerror(err));
		return -EIO;
	}
	pthread_detach(thread_id);
	pthread_sigmask(SIG_SETMASK, &oldset, NULL);
	vhffsfs.quotacachethreadstarted = 1;
	return 0;
}
#endif


/* return an allocated dqblk struct or NULL if something failed (errno is set) */
struct dqblk *vhffsfs_checkquotagid_blockdev(char *blockdev, gid_t gid)  {

	struct dqblk *dq;
	if(!blockdev || !gid)  {
		errno = EINVAL;
		return NULL;
	}

	dq = malloc(sizeof(struct dqblk));
	if( quotactl(QCMD(Q_GETQUOTA, GRPQUOTA), blockdev, gid, (caddr_t)dq) ) {
		free(dq);
		return NULL;
	}
	return dq;
}


#ifdef WITH_CHECKQUOTA_RPC
/* return an allocated dqblk struct or NULL if something failed (errno is set) */
struct dqblk *vhffsfs_checkquotagid_rpc(char *rpcserver, char *path, gid_t gid)  {

	CLIENT *clnt;
	struct dqblk *dq;

	if(!rpcserver || !path || !gid)  {
		errno = EINVAL;
		return NULL;
	}

	if( (clnt = clnt_create(rpcserver, RQUOTAPROG, EXT_RQUOTAVERS, "udp"))  !=  NULL)  {

		union {
			getquota_args arg;
			ext_getquota_args ext_arg;
		} args;
		struct timeval timeout = { 10, 0 };
		ext_getquota_args *argp;
		getquota_rslt clnt_res;
		int res;

		args.ext_arg.gqa_pathp = path;
		args.ext_arg.gqa_id = gid;
		args.ext_arg.gqa_type = GRPQUOTA;

		clnt->cl_auth = authunix_create_default();
		clnt_control(clnt, CLSET_TIMEOUT, (caddr_t)&timeout);

		//result = rquotaproc_getquota_2(&args.ext_arg, clnt);  // non-thread safe, rewritten below
		argp = &args.ext_arg;
		res = clnt_call(clnt, RQUOTAPROC_GETQUOTA, (xdrproc_t)xdr_ext_getquota_args, (caddr_t)argp, (xdrproc_t)xdr_getquota_rslt, (caddr_t)&clnt_res, timeout);

		auth_destroy(clnt->cl_auth);
		clnt_destroy(clnt);

		if(res == RPC_SUCCESS && clnt_res.status == Q_OK)  {

			struct rquota *n = &clnt_res.getquota_rslt_u.gqr_rquota;
			if(!n) {
				errno = EIO;
				return NULL;
			}

			/* printf("QUOTA -> GID: %d, HARDB: %d, SOFTB: %d, CURB: %d\n", gid, n->rq_bhardlimit, n->rq_bsoftlimit, n->rq_curblocks );
			 * printf("QUOTA -> GID: %d, HARDF: %d, SOFTF: %d, CURF: %d\n", gid, n->rq_fhardlimit, n->rq_fsoftlimit, n->rq_curfiles );
			 */

			dq = malloc(sizeof(struct dqblk));
			dq->dqb_bhardlimit = n->rq_bhardlimit;
			dq->dqb_bsoftlimit = n->rq_bsoftlimit;
			dq->dqb_curspace = n->rq_curblocks << 10;
			dq->dqb_ihardlimit = n->rq_fhardlimit;
			dq->dqb_isoftlimit = n->rq_fsoftlimit;
			dq->dqb_curinodes = n->rq_curfiles;
			dq->dqb_btime = n->rq_btimeleft;
			dq->dqb_itime = n->rq_ftimeleft;
			dq->dqb_valid = 0;
			return dq;
		}

		errno = EIO;
		return NULL;
	}

	errno = EIO;
	return NULL;
}
#endif

/* return 0 if the gid is not over quota, 1 if over quota, -errno in case of error */
int vhffsfs_checkquota_gid_with_realpath(char *realpath, gid_t gid, size_t newbytes, int newfiles)  {
	int mode = 0;  /* 0 = do nothing, 1 = data, 2 = repository */
	struct dqblk *dq = NULL;
	int ret = 0;
#ifdef WITH_CHECKQUOTA_CACHE
	char *key = NULL;
#endif

	if(!realpath) return -EINVAL;
	if(!vhffsfs.dataprefixpath) return 0;

	if(!vhffsfs.repositoriesprefixpath)  {
		if( !strncmp(vhffsfs.dataprefixpath, realpath, strlen(vhffsfs.dataprefixpath)) )  {
			mode = 1;
		}
	}
	else if( strlen(vhffsfs.repositoriesprefixpath) > strlen(vhffsfs.dataprefixpath) )  {
		/* check repository before */
		if( !strncmp(vhffsfs.repositoriesprefixpath, realpath, strlen(vhffsfs.repositoriesprefixpath)) )  {
			mode = 2;
		} else if( !strncmp(vhffsfs.dataprefixpath, realpath, strlen(vhffsfs.dataprefixpath)) )  {
			mode = 1;
		}
	}
	else  {
		/* check data before */
		if( !strncmp(vhffsfs.dataprefixpath, realpath, strlen(vhffsfs.dataprefixpath)) )  {
			mode = 1;
		} else if( !strncmp(vhffsfs.repositoriesprefixpath, realpath, strlen(vhffsfs.repositoriesprefixpath)) )  {
			mode = 2;
		}
	}

#ifdef WITH_CHECKQUOTA_CACHE
	/* data */
	if(mode == 1)  {
		key = vhffsfs_checkquota_genkey(gid, vhffsfs.dataprefixpath);
	}
	/* repository */
	else if(mode == 2 )  {
		key = vhffsfs_checkquota_genkey(gid, vhffsfs.repositoriesprefixpath);
	}

	// try to fetch quota from cache
	dq = vhffsfs_checkquota_cache_lookup(key);
	if(dq)  {
		/* we should lock here but an error in quota computation is not important at all */
		dq->dqb_curspace += newbytes;
		dq->dqb_curinodes += newfiles;
		if(dq->dqb_curspace>>10 > dq->dqb_bhardlimit  ||  dq->dqb_curinodes > dq->dqb_ihardlimit) ret = 1;
		vhffsfs_checkquota_cache_unref(key);
		free(key);
		return ret;
	}
#endif


	/* data */
	if(mode == 1)  {
		if(vhffsfs.datablockdev)  {
			dq = vhffsfs_checkquotagid_blockdev(vhffsfs.datablockdev, gid);
		}
#ifdef WITH_CHECKQUOTA_RPC
		else if(vhffsfs.datarpcserver && vhffsfs.datarpcpath)  {
			dq = vhffsfs_checkquotagid_rpc(vhffsfs.datarpcserver, vhffsfs.datarpcpath, gid);
		}
#endif
	}
	/* repository */
	else if(mode == 2 )  {
		if(vhffsfs.repositoriesblockdev)  {
			dq = vhffsfs_checkquotagid_blockdev(vhffsfs.repositoriesblockdev, gid);
		}
#ifdef WITH_CHECKQUOTA_RPC
		else if(vhffsfs.repositoriesrpcserver && vhffsfs.repositoriesrpcpath)  {
			dq = vhffsfs_checkquotagid_rpc(vhffsfs.repositoriesrpcserver, vhffsfs.repositoriesrpcpath, gid);
		}
#endif
	}


	if(!dq) {
		fprintf(stderr, "vhffsfs: quota: %s\n", strerror(errno));
	}
	else  {
#ifdef WITH_CHECKQUOTA_CACHE
		char *path;
		/* fill the cache */
		/* data */
		if(mode == 1)  {
			path = vhffsfs.dataprefixpath;
		}
		/* repository */
		else if(mode == 2 )  {
			path = vhffsfs.repositoriesprefixpath;
		}

		dq = vhffsfs_checkquota_cache_add(key, gid, path, dq);
#endif
		dq->dqb_curspace += newbytes;
		dq->dqb_curinodes += newfiles;
		if(dq->dqb_curspace>>10 > dq->dqb_bhardlimit  ||  dq->dqb_curinodes > dq->dqb_ihardlimit) ret = 1;
#ifdef WITH_CHECKQUOTA_CACHE
		vhffsfs_checkquota_cache_unref(key);
		free(key);
#else
		free(dq);
#endif
	}

	return ret;
}
#endif


static void *vhffsfs_init(void)
{
#ifdef WITH_CACHE
	// create cache flush thread
	vhffsfs_start_cache_flush_thread();
#endif
#ifdef WITH_CHECKQUOTA_CACHE
	// create cache flush thread for quota
	vhffsfs_checkquota_start_cache_flush_thread();
#endif
	return NULL;
}


static int vhffsfs_getattr(const char *path, struct stat *stbuf)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, F_OK);
	if(!rpath) return -errno;

	res = lstat(rpath, stbuf);
	free(rpath);

	if(res == -1) return -errno;
	// force find -noleaf
	stbuf->st_nlink = 1;
	return 0;
}


static int vhffsfs_fgetattr(const char *path, struct stat *stbuf, struct fuse_file_info *fi)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, F_OK);
	if(!rpath) return -errno;
	free(rpath);

	res = fstat(fi->fh, stbuf);

	if(res == -1) return -errno;
	// force find -noleaf
	stbuf->st_nlink = 1;
	return 0;
}


static int vhffsfs_access(const char *path, int mask)
{
//	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, mask);
	if(!rpath) return -errno;

//	res = access(rpath, mask);
	free(rpath);

//	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_readlink(const char *path, char *buf, size_t size)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, R_OK);
	if(!rpath) return -errno;

	res = readlink(rpath, buf, size - 1);
	free(rpath);

	if(res == -1) return -errno;
	buf[res] = '\0';
	return 0;
}


static int vhffsfs_opendir(const char *path, struct fuse_file_info *fi)
{
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, R_OK);
	if(!rpath) return -errno;

	DIR *dp = opendir(rpath);
	free(rpath);

	if(dp == NULL) return -errno;
	fi->fh = (unsigned long) dp;
	return 0;
}


static inline DIR *get_dirp(struct fuse_file_info *fi)
{
	return (DIR *) (uintptr_t) fi->fh;
}


static int vhffsfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler, off_t offset, struct fuse_file_info *fi)
{
	DIR *dp = get_dirp(fi);
	struct dirent *de;
	char **vdirs;

	while ((de = readdir(dp)) != NULL) {
		struct stat st;
		memset(&st, 0, sizeof(st));
		st.st_ino = de->d_ino;
		st.st_mode = de->d_type << 12;
		if (filler(buf, de->d_name, &st, 0))
			break;
	}

	// add virtual directories
	vdirs = vhffsfs_virtualdirs(path);
	if(vdirs)  {
		char **cur;
		for(cur = vdirs ; *cur ; cur+=2)  {
			char *vname = *cur;
			char *vpath = *(cur+1);

			struct stat st;
			stat(vpath, &st);
			filler(buf, vname, &st, 0);

			free(vname);
			free(vpath);
		}
		free(vdirs);
	}

	return 0;
}


static int vhffsfs_releasedir(const char *path, struct fuse_file_info *fi)
{
	DIR *dp = get_dirp(fi);
	(void) path;
	closedir(dp);
	return 0;
}


static int vhffsfs_mknod(const char *path, mode_t mode, dev_t rdev)
{
/* -- DISABLED - user must not be allowed to create that !
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, W_OK);
	if(!rpath) return -errno;

#ifdef WITH_CHECKQUOTA
	res = vhffsfs_checkquota_gid_with_realpath(rpath, gid, 0, 1);
	if(res)  {
		free(rpath);
		return -EDQUOT;
	}
#endif

	if (S_ISFIFO(mode))
		res = mkfifo(rpath, mode);
	else
		res = mknod(rpath, mode, rdev);

	if(res == -1) return -errno;
	return 0;
*/
	return -EACCES;
}


static int vhffsfs_mkdir(const char *path, mode_t mode)
{
	int res;
	char *rpath;
	uid_t uid;
	gid_t gid;

	rpath = vhffsfs_realpath(path, &uid, &gid, CREATE_OK);
	if(!rpath) return -errno;

#ifdef WITH_CHECKQUOTA
	res = vhffsfs_checkquota_gid_with_realpath(rpath, gid, 0, 1);
	if(res)  {
		free(rpath);
		return -EDQUOT;
	}
#endif

	res = mkdir(rpath, mode);
	if(res == 0) {
		struct stat st;
		lchown(rpath, uid, gid);
		stat(rpath, &st);
		st.st_mode &= vhffsfs.clearmodedir;
		st.st_mode |= vhffsfs.forcemodedir;
		chmod(rpath, st.st_mode);
	}
	free(rpath);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_unlink(const char *path)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, REMOVE_OK);
	if(!rpath) return -errno;

	res = unlink(rpath);
	free(rpath);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_rmdir(const char *path)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, REMOVE_OK);
	if(!rpath) return -errno;

	res = rmdir(rpath);
	free(rpath);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_symlink(const char *from, const char *to)
{
	int res;
	char *rto;
	uid_t uid;
	gid_t gid;

	rto = vhffsfs_realpath(to, &uid, &gid, CREATE_OK);
	if(!rto) return -errno;

#ifdef WITH_CHECKQUOTA
	res = vhffsfs_checkquota_gid_with_realpath(rto, gid, 0, 1);
	if(res) {
		free(rto);
		return -EDQUOT;
	}
#endif

	res = symlink(from, rto);
	if(res == 0) lchown(rto, uid, gid);
	free(rto);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_rename(const char *from, const char *to)
{
	int res;
	char *rfrom, *rto;

	rfrom = vhffsfs_realpath(from, NULL, NULL, REMOVE_OK);
	if(!rfrom) return -errno;

	rto = vhffsfs_realpath(to, NULL, NULL, CREATE_OK);
	if(!rto) {
		free(rfrom);
		return -errno;
	}

	res = rename(rfrom, rto);
	free(rfrom);
	free(rto);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_link(const char *from, const char *to)
{
	int res;
	char *rfrom, *rto;
	uid_t uid;
	gid_t gid;

	rfrom = vhffsfs_realpath(from, NULL, NULL, F_OK);
	if(!rfrom) return -errno;

	rto = vhffsfs_realpath(to, &uid, &gid, CREATE_OK);
	if(!rto) {
		free(rfrom);
		return -errno;
	}

#ifdef WITH_CHECKQUOTA
	res = vhffsfs_checkquota_gid_with_realpath(rto, gid, 0, 1);
	if(res)  {
		free(rfrom);
		free(rto);
		return -EDQUOT;
	}
#endif

	res = link(rfrom, rto);
	if(res == 0) lchown(rto, uid, gid);
	free(rfrom);
	free(rto);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_chmod(const char *path, mode_t mode)
{
	int res;
	char *rpath;
	struct stat st;

	rpath = vhffsfs_realpath(path, NULL, NULL, CHMOD_OK);
	if(!rpath) return -errno;

	stat(rpath, &st);
	if( S_ISDIR(st.st_mode) ) {
		mode &= vhffsfs.clearmodedir;
		mode |= vhffsfs.forcemodedir;
	} else {
		mode &= vhffsfs.clearmodefile;
		mode |= vhffsfs.forcemodefile;
	}
	res = chmod(rpath, mode);
	free(rpath);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_chown(const char *path, uid_t uid, gid_t gid)
{
// disabled for now, needs intensive group checking and is pretty useless as groups are correctly assigned
// should we break unix way and allow chown of files owner to group members ?
/*	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, W_OK);
	if(!rpath) return -errno;

	res = lchown(rpath, uid, gid);
	free(rpath);

	if(res == -1) return -errno;
	return 0; */
	return -EACCES;
}


static int vhffsfs_truncate(const char *path, off_t size)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, W_OK);
	if(!rpath) return -errno;

	res = truncate(rpath, size);
	free(rpath);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_ftruncate(const char *path, off_t size, struct fuse_file_info *fi)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, W_OK);
	if(!rpath) return -errno;
	free(rpath);

	res = ftruncate(fi->fh, size);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_utime(const char *path, struct utimbuf *buf)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, W_OK);
	if(!rpath) return -errno;

	res = utime(rpath, buf);
	free(rpath);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_create(const char *path, mode_t mode, struct fuse_file_info *fi)
{
	int fd;
	char *rpath;
	uid_t uid;
	gid_t gid;
	int res;

	rpath = vhffsfs_realpath(path, &uid, &gid, CREATE_OK);
	if(!rpath) return -errno;

#ifdef WITH_CHECKQUOTA
	res = vhffsfs_checkquota_gid_with_realpath(rpath, gid, 0, 1);
	if(res)  {
		free(rpath);
		return -EDQUOT;
	}
#endif

	fd = open(rpath, fi->flags, mode);
	if(fd >= 0) {
		struct stat st;
		lchown(rpath, uid, gid);
		stat(rpath, &st);
		st.st_mode &= vhffsfs.clearmodefile;
		st.st_mode |= vhffsfs.forcemodefile;
		chmod(rpath, st.st_mode);
	}
	free(rpath);

	if(fd == -1) return -errno;
	fi->fh = fd;
	return 0;
}


static int vhffsfs_open(const char *path, struct fuse_file_info *fi)
{
	int fd;
	char *rpath;
	int mode = R_OK;

	if(fi->flags & O_WRONLY) {
		mode = W_OK;
	}
	else if(fi->flags & O_RDWR) {
		mode = R_OK|W_OK;
	}

	rpath = vhffsfs_realpath(path, NULL, NULL, mode);
	if(!rpath) return -errno;

	fd = open(rpath, fi->flags);
	free(rpath);

	if(fd == -1) return -errno;
	fi->fh = fd;
	return 0;
}


static int vhffsfs_read(const char *path, char *buf, size_t size, off_t offset, struct fuse_file_info *fi)
{
	int res;

	(void) path;
	res = pread(fi->fh, buf, size, offset);

	if(res == -1) res = -errno;
	return res;
}


static int vhffsfs_write(const char *path, const char *buf, size_t size, off_t offset, struct fuse_file_info *fi)
{
	int res;

#ifdef WITH_CHECKQUOTA
	uid_t uid;
	gid_t gid;
	char *rpath;

	rpath = vhffsfs_realpath(path, &uid, &gid, F_OK);
	if(!rpath) return -errno;

	res = vhffsfs_checkquota_gid_with_realpath(rpath, gid, size, 0);
	free(rpath);
	if(res) return -EDQUOT;
#endif

	(void) path;
	res = pwrite(fi->fh, buf, size, offset);

	if(res == -1) res = -errno;
	return res;
}


static int vhffsfs_statfs(const char *path, struct statvfs *stbuf)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, R_OK);
	if(!rpath) return -errno;

	res = statvfs(rpath, stbuf);
	free(rpath);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_release(const char *path, struct fuse_file_info *fi)
{
	(void) path;
	close(fi->fh);

	return 0;
}


static int vhffsfs_fsync(const char *path, int isdatasync, struct fuse_file_info *fi)
{
	int res;
	(void) path;

#ifndef HAVE_FDATASYNC
	(void) isdatasync;
#else
	if(isdatasync)
		res = fdatasync(fi->fh);
	else
#endif
		res = fsync(fi->fh);

	if(res == -1) return -errno;
	return 0;
}


#ifdef HAVE_SYS_XATTR_H
/* xattr operations are optional and can safely be left unimplemented */
static int vhffsfs_setxattr(const char *path, const char *name, const char *value, size_t size, int flags)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, W_OK);
	if(!rpath) return -errno;

	res = lsetxattr(rpath, name, value, size, flags);
	free(rpath);

	if(res == -1) return -errno;
	return 0;
}


static int vhffsfs_getxattr(const char *path, const char *name, char *value, size_t size)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, R_OK);
	if(!rpath) return -errno;

	res = lgetxattr(rpath, name, value, size);
	free(rpath);

	if(res == -1) return -errno;
	return res;
}


static int vhffsfs_listxattr(const char *path, char *list, size_t size)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, R_OK);
	if(!rpath) return -errno;

	res = llistxattr(rpath, list, size);
	free(rpath);

	if(res == -1) return -errno;
	return res;
}


static int vhffsfs_removexattr(const char *path, const char *name)
{
	int res;
	char *rpath;

	rpath = vhffsfs_realpath(path, NULL, NULL, W_OK);
	if(!rpath) return -errno;

	res = lremovexattr(rpath, name);
	free(rpath);

	if(res == -1) return -errno;
	return 0;
}
#endif /* HAVE_SYS_XATTR_H */


static struct fuse_operations vhffsfs_oper = {
	.init		= vhffsfs_init,
	.getattr	= vhffsfs_getattr,
	.fgetattr	= vhffsfs_fgetattr,
	.access		= vhffsfs_access,
	.readlink	= vhffsfs_readlink,
	.opendir	= vhffsfs_opendir,
	.readdir	= vhffsfs_readdir,
	.releasedir	= vhffsfs_releasedir,
	.mknod		= vhffsfs_mknod,
	.mkdir		= vhffsfs_mkdir,
	.symlink	= vhffsfs_symlink,
	.unlink		= vhffsfs_unlink,
	.rmdir		= vhffsfs_rmdir,
	.rename		= vhffsfs_rename,
	.link		= vhffsfs_link,
	.chmod		= vhffsfs_chmod,
	.chown		= vhffsfs_chown,
	.truncate	= vhffsfs_truncate,
	.ftruncate	= vhffsfs_ftruncate,
	.utime		= vhffsfs_utime,
	.create		= vhffsfs_create,
	.open		= vhffsfs_open,
	.read		= vhffsfs_read,
	.write		= vhffsfs_write,
	.statfs		= vhffsfs_statfs,
	.release	= vhffsfs_release,
	.fsync		= vhffsfs_fsync,
#ifdef HAVE_SYS_XATTR_H
	.setxattr	= vhffsfs_setxattr,
	.getxattr	= vhffsfs_getxattr,
	.listxattr	= vhffsfs_listxattr,
	.removexattr	= vhffsfs_removexattr,
#endif
};

int vhffsfs_readconfig(char *conffile)  {

	FILE *conf;
	char line[128];

	conf = fopen(conffile, "r");
	if(!conf) return -1;

	while( fgets(line, 128, conf) )  {
		line[strlen(line)-1] = '\0';
		if(line[0] == '#')  {  }
		else if(!strncmp("grouppath ", line, 10))  {
			vhffsfs.grouppath = strdup(line+10);
		}
		else if(!strncmp("webspath ", line, 9))  {
			vhffsfs.webspath = strdup(line+9);
		}
		else if(!strncmp("repositoriespath ", line, 17))  {
			vhffsfs.repositoriespath = strdup(line+17);
		}
		else if(!strncmp("dbhost ", line, 7))  {
			vhffsfs.dbhost = strdup(line+7);
		}
		else if(!strncmp("dbport ", line, 7))  {
			vhffsfs.dbport = atoi(line+7);
		}
		else if(!strncmp("dbuser ", line, 7))  {
			vhffsfs.dbuser = strdup(line+7);
		}
		else if(!strncmp("dbpass ", line, 7))  {
			vhffsfs.dbpass = strdup(line+7);
		}
		else if(!strncmp("dbname ", line, 7))  {
			vhffsfs.dbname = strdup(line+7);
		}
		else if(!strncmp("dbtimeout ", line, 10))  {
			vhffsfs.dbtimeout = atoi(line+10);
		}
		else if(!strncmp("forcemodefile ", line, 14))  {
                     vhffsfs.forcemodefile = strtoul(line+14, NULL, 8);
		}
		else if(!strncmp("forcemodedir ", line, 13))  {
                     vhffsfs.forcemodedir = strtoul(line+13, NULL, 8);
		}
		else if(!strncmp("clearmodefile ", line, 14))  {
                     vhffsfs.clearmodefile = ~strtoul(line+14, NULL, 8);
		}
		else if(!strncmp("clearmodedir ", line, 13))  {
                     vhffsfs.clearmodedir = ~strtoul(line+13, NULL, 8);
		}
#ifdef WITH_CHECKQUOTA
		else if(!strncmp("datablockdev ", line, 13))  {
                     vhffsfs.datablockdev = strdup(line+13);
		}
		else if(!strncmp("repositoriesblockdev ", line, 21))  {
                     vhffsfs.repositoriesblockdev = strdup(line+21);
		}
		else if(!strncmp("dataprefixpath ", line, 15))  {
                     vhffsfs.dataprefixpath = strdup(line+15);
		}
		else if(!strncmp("repositoriesprefixpath ", line, 23))  {
                     vhffsfs.repositoriesprefixpath = strdup(line+23);
		}
#ifdef WITH_CHECKQUOTA_RPC
		else if(!strncmp("datarpcserver ", line, 14))  {
                     vhffsfs.datarpcserver = strdup(line+14);
		}
		else if(!strncmp("datarpcpath ", line, 12))  {
                     vhffsfs.datarpcpath = strdup(line+12);
		}
		else if(!strncmp("repositoriesrpcserver ", line, 22))  {
                     vhffsfs.repositoriesrpcserver = strdup(line+22);
		}
		else if(!strncmp("repositoriesrpcpath ", line, 20))  {
                     vhffsfs.repositoriesrpcpath = strdup(line+20);
		}
#endif
#endif
	}

	fclose(conf);
	return 0;
}

int main(int argc, char *argv[])
{
	int i, res;
	struct stat st;

	// create empty directory
	stat(VHFFSFS_EMPTYDIR, &st);
	if(!S_ISDIR(st.st_mode))  {
		res = mkdir(VHFFSFS_EMPTYDIR, 0700);
		if(res)  {
			printf("Unable to create empty directory: '%s': %s\n", VHFFSFS_EMPTYDIR, strerror(errno));
			exit(1);
		}
	}

	// init vhffsfs struct
	for(i = 0 ; i < VHFFSFS_MAXCONNDB ; i++)   {
		vhffsfs.pg_conn[i] = NULL;
		pthread_mutex_init(&vhffsfs.pg_lock[i], NULL);
	}
	vhffsfs.grouppath = "/data/groups";
	vhffsfs.webspath = "/data/web";
	vhffsfs.repositoriespath = "/data/repository";
	vhffsfs.dbhost = "127.0.0.1";
	vhffsfs.dbport = 5432;
	vhffsfs.dbuser = "vhffs";
	vhffsfs.dbpass = "pass";
	vhffsfs.dbname = "vhffs";
	vhffsfs.dbtimeout = 30;
//	vhffsfs.defaultrightfile = 00664;
//	vhffsfs.defaultrightdir = 02775;
	vhffsfs.forcemodefile = 00400;
	vhffsfs.forcemodedir = 02700;
	vhffsfs.clearmodefile = ~07002;
	vhffsfs.clearmodedir = ~05002;
#ifdef WITH_CACHE
	vhffsfs.cachequeries = g_hash_table_new(g_str_hash, g_str_equal);
	vhffsfs.cachekeys = g_ptr_array_sized_new(4096);
	pthread_mutex_init(&vhffsfs.cachelock, NULL);
	vhffsfs.cachethreadstarted = 0;
#endif
#ifdef WITH_CHECKQUOTA_CACHE
	vhffsfs.quotacacheused = g_hash_table_new(g_str_hash, g_str_equal);
	vhffsfs.quotacachekeys = g_ptr_array_sized_new(4096);
	pthread_mutex_init(&vhffsfs.quotacachelock, NULL);
	vhffsfs.quotacachethreadstarted = 0;
#endif
	vhffsfs_readconfig(VHFFSFS_CONFIG);

	// generate dbconninfo
	vhffsfs.dbconninfo = malloc(256);
	snprintf(vhffsfs.dbconninfo, 256, "host='%s' port='%d' user='%s' password='%s' dbname='%s' connect_timeout='%d'", vhffsfs.dbhost, vhffsfs.dbport, vhffsfs.dbuser, vhffsfs.dbpass, vhffsfs.dbname, vhffsfs.dbtimeout);
	vhffsfs.dbconninfo = realloc(vhffsfs.dbconninfo, strlen(vhffsfs.dbconninfo)+1);

	umask(0);
	return fuse_main(argc, argv, &vhffsfs_oper);
}
