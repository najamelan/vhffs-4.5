#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

AC_PREREQ(2.61)
AC_INIT([VHFFS-FS], [4.5.0], [bugs@vhffs.org])
AC_CONFIG_AUX_DIR([.])
AC_CONFIG_SRCDIR([vhffsfs.c])
AC_CONFIG_HEADER([config.h])

AM_INIT_AUTOMAKE
PKG_PROG_PKG_CONFIG

test "x$prefix" = "xNONE" && prefix=/usr

# Checks for programs.
AC_PROG_CC

# Cache stuff
AC_ARG_ENABLE(cache-query,
    AC_HELP_STRING([--enable-cache-query],
        [Enable caching of SQL queries (see --with-cache-query-timeout , --with-cache-query-flush and --enable-cache-query-debug)
            [default=yes]]), enable_cache_query=$enableval, enable_cache_query=yes)

AC_ARG_ENABLE(cache-query-debug,
    AC_HELP_STRING([--enable-cache-query-debug],
        [Enable debug of queries cache
            [default=no]]), enable_cache_query_debug=$enableval, enable_cache_query_debug=no)

if test "$enable_cache_query" = yes ; then
    AC_DEFINE([WITH_CACHE], [1], [Enable queries cache facility])
    if test "$enable_cache_query_debug" = yes ; then
        AC_DEFINE([WITH_CACHE_DEBUG], [1], [Enable queries cache facility debugging])
    fi
    AC_ARG_WITH([--with-cache-query-timeout],
        AC_HELP_STRING([--with-cache-query-timeout],
            [???? [default=600]]), 
        AC_DEFINE([VHFFSFS_CACHE_QUERY_TIMEOUT], $withval, [???]),
        AC_DEFINE([VHFFSFS_CACHE_QUERY_TIMEOUT], 600, [???]))
    AC_ARG_WITH([cache-query-flush],
        AC_HELP_STRING([--with-cache-query-flush],
            [???? [default=1800]]),
        AC_DEFINE([VHFFSFS_CACHE_QUERY_FLUSH_EVERY], $withval, [???]),
        AC_DEFINE([VHFFSFS_CACHE_QUERY_FLUSH_EVERY], 1800, [???]))
fi


# Check quota stuff
AC_ARG_ENABLE(check-quota,
    AC_HELP_STRING([--enable-check-quota],
        [Enable check of quota (see --enable-check-quota-rpc and --enable-check-quota-cache)
            [default=yes]]), enable_checkquota=$enableval, enable_checkquota=yes)

AC_ARG_ENABLE(check-quota-rpc,
    AC_HELP_STRING([--enable-check-quota-rpc],
        [Enable check of quota through RPC
            [default=yes]]), enable_checkquota_rpc=$enableval, enable_checkquota_rpc=yes)

AC_ARG_ENABLE(check-quota-cache,
    AC_HELP_STRING([--enable-check-quota-cache],
        [Enable quota cache (see --enable-check-quota-cache-debug , --with-check-quota-cache-timeout , --with-check-quota-cache-flush )
            [default=yes]]), enable_checkquota_cache=$enableval, enable_checkquota_cache=yes)

AC_ARG_ENABLE(check-quota-cache-debug,
    AC_HELP_STRING([--enable-check-quota-cache-debug],
        [Enable quota cache debugging
            [default=no]]), enable_checkquota_cache_debug=$enableval, enable_checkquota_cache_debug=no)

if test "$enable_checkquota" = yes ; then
    AC_DEFINE([WITH_CHECKQUOTA], [1], [Enable quota check])
    if test "$enable_checkquota_rpc" = yes ; then
        AC_DEFINE([WITH_CHECKQUOTA_RPC], [1], [Enable quota through RPC])
    fi
    if test "$enable_checkquota_cache" = yes ; then
       AC_DEFINE([WITH_CHECKQUOTA_CACHE], [1], [Enable quota cache])
       if test "$enable_checkquota_cache_debug" = yes ; then
           AC_DEFINE([WITH_CHECKQUOTA_CACHE_DEBUG], [1], [Enable quota cache debugging])
       fi
       AC_ARG_WITH([check-quota-cache-timeout],
           AC_HELP_STRING([--with-check-quota-cache-timeout],
               [???? [default=60]]), 
           AC_DEFINE([VHFFSFS_CHECKQUOTA_CACHE_TIMEOUT], $withval, [???]),
           AC_DEFINE([VHFFSFS_CHECKQUOTA_CACHE_TIMEOUT], 60, [???]))
       AC_ARG_WITH([check-quota-cache-flush],
           AC_HELP_STRING([--with-check-quota-cache-flush],
               [???? [default=1800]]),
           AC_DEFINE([VHFFSFS_CHECKQUOTA_CACHE_REFRESH], $withval, [???]),
           AC_DEFINE([VHFFSFS_CHECKQUOTA_CACHE_REFRESH], 1800, [???]))
    fi
fi


# fuse stuff
AC_ARG_WITH(fuse-version,
    AC_HELP_STRING([--with-fuse-version],
        [Specify fuse version to use [default=25]]),
        AC_DEFINE([FUSE_USE_VERSION], $withval, [Fuse version to use]),
        AC_DEFINE([FUSE_USE_VERSION], [25], [Fuse version to use]))

AC_ARG_WITH(vhffs-fs-path,
    AC_HELP_STRING([--with-vhffs-fs-path],
        [Specify vhffs-fs installation path]),
    VHFFSFSDIR=$withval,
    VHFFSFSDIR=$prefix/sbin)

AC_SUBST(VHFFSFSDIR)

# Use the same switch as root configure.ac. This way, all config files
# are in the same dir
AC_ARG_WITH(conf-path,
    AC_HELP_STRING([--with-conf-path=path],
        [Complete path for configuration files (/etc/vhffs)]),
    CONFDIR=$withval,
	if test "x$prefix" = "x/usr"; then
		CONFDIR=/etc/vhffs
	else
		CONFDIR=$prefix/etc/vhffs
	fi
)
AC_SUBST(CONFDIR)

AC_DEFINE_UNQUOTED(VHFFSFS_CONFIG, ["$CONFDIR/vhffsfs.conf"], [VHFFS-fs config file])

# Needed for fuse
AC_DEFINE([_FILE_OFFSET_BITS], [64], [Required for fuse to works correctly])
AC_DEFINE([_REENTRANT], [1], [Reentrant program])

# Checks for libraries.

AC_CHECK_LIB([pq], [PQconnectdb])
AC_CHECK_LIB([pthread], [pthread_create])
AC_CHECK_LIB([fuse], [fuse_new])
# Checks for header files.
AC_HEADER_DIRENT
AC_HEADER_STDC
AC_HEADER_TIME
AC_CHECK_HEADERS([sys/xattr.h])
AC_CHECK_HEADERS([sys/time.h])
AC_CHECK_HEADERS([fuse.h],,[AC_MSG_ERROR([Cannot find fuse headers])], [#define _FILE_OFFSET_BITS 64])
AC_CHECK_HEADERS([fcntl.h inttypes.h postgresql/libpq-fe.h pthread.h signal.h stdint.h stdio.h unistd.h], 
    [], [AC_MSG_ERROR([Missing headers, bailing out])])
if test "$enable_cache_query" = yes || test "$enable_checkquota_cache" = yes ; then
    PKG_CHECK_MODULES(GLIB2, [glib-2.0 >= 2.16.0])
    CFLAGS="$CFLAGS $GLIB2_CFLAGS"
    LIBS="$LIBS $GLIB2_LIBS"
fi

# Checks for typedefs, structures, and compiler characteristics.
AC_C_CONST
AC_TYPE_UID_T
AC_C_INLINE
AC_TYPE_MODE_T
AC_TYPE_OFF_T
AC_TYPE_SIZE_T
AC_HEADER_TIME
AC_TYPE_UINT32_T

# Checks for library functions.
AC_FUNC_CLOSEDIR_VOID
AC_FUNC_LSTAT
AC_FUNC_LSTAT_FOLLOWS_SLASHED_SYMLINK
AC_FUNC_MALLOC
AC_FUNC_REALLOC
AC_FUNC_STAT
AC_FUNC_UTIME_NULL
AC_CHECK_FUNCS([fdatasync ftruncate gettimeofday lchown memset mkdir rmdir strdup strerror strndup strtoul utime])

AC_CONFIG_FILES([Makefile])

AC_OUTPUT
