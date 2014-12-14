AC_REVISION($Revision: 101 $)dnl
AC_INIT([VHFFS], [4.5.0], [support@vhffs.org])
AC_CONFIG_AUX_DIR([.])
AC_CONFIG_MACRO_DIR([m4])

AC_PROG_CC
AC_PROG_INSTALL
AC_PROG_SED
AC_PREFIX_DEFAULT([/usr])

PKG_PROG_PKG_CONFIG

# Ugly but will remain until we do some cleanup in directories handling
test "x$prefix" = "xNONE" && prefix="/usr"

AC_PATH_PROG([PERL], [perl], [not found])
if test "$PERL" = 'not found'; then
	AC_MSG_ERROR([perl is needed to run $PACKAGE_NAME])
fi

AC_PATH_PROG([BASH], [bash], [not found])
if test "$BASH" = 'not found'; then
    AC_MSG_ERROR([bash is needed to run $PACKAGE_NAME])
fi

AM_INIT_AUTOMAKE([no-define no-define dist-bzip2 tar-ustar])


# --- Specific path
AC_ARG_WITH(conf-path,
	AC_HELP_STRING([--with-conf-path=path],
		[Complete path for configuration files (/etc/vhffs)]),
	CONFDIR=$withval,
	if test "x$prefix" = "x/usr"; then
		CONFDIR=/etc/vhffs
	else
		CONFDIR=${prefix}/etc/vhffs
	fi
)
AC_SUBST(CONFDIR)

AC_ARG_WITH(shell-path,
	AC_HELP_STRING([--with-shell-path=path],
		[Complete path for tux shell and falseshell(/bin)]),
	SHELLDIR=$withval,
	if test "x$prefix" = "x/usr"; then
		SHELLDIR=/bin
	else
		SHELLDIR=${prefix}/bin
	fi
)
AC_SUBST(SHELLDIR)

dnl Where to store tools
AC_ARG_WITH(tools-path,
	AC_HELP_STRING([--with-tools-path=path],
		[Complete path for tools (executables) (/usr/bin)]),
	TOOLSDIR=$withval,
	TOOLSDIR=${prefix}/bin
)
AC_SUBST(TOOLSDIR)

dnl Documentation
AC_ARG_WITH(doc-path,
	AC_HELP_STRING([--with-doc-path=path],
		[Complete path for documentation files (/usr/share/doc/vhffs)]),
	DOCDIR=$withval,
	DOCDIR=${prefix}/share/doc/vhffs
)
AC_SUBST(DOCDIR)

dnl perl modules
AC_ARG_WITH(api-path,
    AC_HELP_STRING([--with-api-path=path],
        [Path for perl modules (API) (/usr/share/vhffs/api)]),
    APIDIR=$withval,
    APIDIR=${prefix}/share/vhffs/api
)
AC_SUBST(APIDIR)

dnl panel path
AC_ARG_WITH(panel-path,
	AC_HELP_STRING([--with-panel-path=path],
		[Complete path for panel interface (/usr/share/vhffs/panel)]),
	PANELDIR=$withval,
	PANELDIR=${prefix}/share/vhffs/panel
)
AC_SUBST(PANELDIR)

dnl public path
AC_ARG_WITH(public-path,
	AC_HELP_STRING([--with-public-path=path],
		[Complete path for public interface (/usr/share/vhffs/public)]),
	PUBLICDIR=$withval,
	PUBLICDIR=${prefix}/share/vhffs/public
)
AC_SUBST(PUBLICDIR)

dnl templates
AC_ARG_WITH(template-path,
	AC_HELP_STRING([--with-template-path=path],
		[Complete path for web templates (/usr/share/vhffs/templates)]),
	TEMPLATESDIR=$withval,
	TEMPLATESDIR=${prefix}/share/vhffs/templates
)
AC_SUBST(TEMPLATESDIR)

AC_ARG_WITH(backend-path,
	AC_HELP_STRING([--with-backend-path=path],
		[Complete path for backend (/usr/share/vhffs/backend)]),
	BACKENDDIR=$withval,
	BACKENDDIR=${prefix}/share/vhffs/backend
)
AC_SUBST(BACKENDDIR)

dnl Bots path
AC_ARG_WITH(robot-path,
	AC_HELP_STRING([--with-robot-path=path],
		[Complete path for robots file (/usr/lib/vhffs/bots)]),
	BOTSDIR=$withval,
	BOTSDIR=${prefix}/lib/vhffs/bots
)
AC_SUBST(BOTSDIR)

dnl jabber pipe
AC_ARG_WITH(jabber-path,
	AC_HELP_STRING([--with-jabber-path=path],
		[Complete path for jabber pipe (/usr/share/vhffs/jabber)]),
	JABBERDIR=$withval,
	JABBERDIR=${prefix}/lib/vhffs/jabber
)
AC_SUBST(JABBERDIR)

dnl Listengine
AC_ARG_WITH(listengine-path,
	AC_HELP_STRING([--with-listengine-path=path],
		[Complete path for listengine bouncer (/usr/lib/vhffs/listengine)]),
	LEDIR=$withval,
	LEDIR=${prefix}/lib/vhffs/listengine
)
AC_SUBST(LEDIR)

dnl Cron
AC_ARG_WITH(cron-path,
	AC_HELP_STRING([--with-cron-path=path],
		[Complete path for cron daemon (/usr/lib/vhffs/cron)]),
	CRONDIR=$withval,
	CRONDIR=${prefix}/lib/vhffs/cron
)
AC_SUBST(CRONDIR)

dnl IRC bot
AC_ARG_WITH(irc-bot-path,
	AC_HELP_STRING([--with-irc-bot-path=path],
		[Complete path for moderation bot (/usr/lib/vhffs/irc)]),
	IRCDIR=$withval,
	IRCDIR=${prefix}/lib/vhffs/irc
)
AC_SUBST(IRCDIR)


dnl documentation
AC_ARG_WITH(doc-path,
	AC_HELP_STRING([--with-doc-path=path],
		[Complete path for documentation files (/usr/share/doc/vhffs)]),
	DOCSDIR=$withval,
	DOCSDIR=${prefix}/share/doc/vhffs
)
AC_SUBST(DOCSDIR)

dnl Compatibility stuff

AC_ARG_WITH(compat-path,
    AC_HELP_STRING([--with-compat-path=path],
        [Complete path for compatibility scripts (/usr/share/doc/vhffs/compat)]),
    COMPATDIR=$withval,
    COMPATDIR=${prefix}/share/doc/vhffs/compat
)
AC_SUBST(COMPATDIR)

dnl Extra misc tools

AC_ARG_WITH(extra-path,
    AC_HELP_STRING([--with-extra-path=path],
        [Complete path for misc extra tools (/usr/lib/vhffs/extra)]),
    EXTRADIR=$withval,
    EXTRADIR=${prefix}/lib/vhffs/extra
)
AC_SUBST(EXTRADIR)


dnl setup min uid and gid
AC_ARG_WITH(min-uid,
	AC_HELP_STRING([--with-min-uid=uid],
		[What is the minimal UID for VHFFS users (10000)]),
	MINUID=$withval,
	MINUID=10000
)
AC_SUBST(MINUID)

AC_ARG_WITH(min-gid,
	AC_HELP_STRING([--with-min-gid=gid],
		[What is the minimal GID for VHFFS groups (10000)]),
	MINGID=$withval,
	MINGID=10000
)
AC_SUBST(MINGID)

dnl Modular build (if someone wants to improve...)

dnl Install panel or not ?
AC_ARG_ENABLE(panel,
    AC_HELP_STRING([--enable-panel],
        [Enable panel and templates installation [default=yes]]),
        enable_panel=$enableval,enable_panel=yes)

AM_CONDITIONAL(INSTALL_PANEL, test "$enable_panel" = yes)

dnl Install public or not ?
AC_ARG_ENABLE(public,
    AC_HELP_STRING([--enable-public],
        [Enable public and templates installation [default=yes]]),
        enable_public=$enableval,enable_public=yes)

AM_CONDITIONAL(INSTALL_PUBLIC, test "$enable_public" = yes)

dnl Install listengine or not ?
AC_ARG_ENABLE(listengine,
    AC_HELP_STRING([--enable-listengine],
        [Enable listengine installation [default=yes]]),
        enable_listengine=$enableval, enable_listengine=yes)

AM_CONDITIONAL(INSTALL_LISTENGINE, test "$enable_listengine" = yes)

dnl Install cron daemon or not ?
AC_ARG_ENABLE(cron,
    AC_HELP_STRING([--enable-cron],
        [Enable cron daemon installation [default=yes]]),
        enable_cron=$enableval, enable_cron=yes)

AM_CONDITIONAL(INSTALL_CRON, test "$enable_cron" = yes)

dnl Install robots or not ?
AC_ARG_ENABLE(robots,
    AC_HELP_STRING([--enable-robots],
        [Enable robots installation [default=yes]]),
        enable_robots=$enableval, enable_robots=yes)

AM_CONDITIONAL(INSTALL_ROBOTS, test "$enable_robots" = yes)

dnl Install backend or not ?
AC_ARG_ENABLE(backend,
    AC_HELP_STRING([--enable-backend],
        [Enable backend installation [default=yes]]),
        enable_backend=$enableval, enable_backend=yes)
        
AM_CONDITIONAL(INSTALL_BACKEND, test "$enable_backend" = yes)

dnl Install migration scripts or not ?
AC_ARG_ENABLE(compat,
    AC_HELP_STRING([--enable-compat],
        [Enable migration scripts installation [default=yes]]),
        enable_compat=$enableval, enable_compat=yes)

AM_CONDITIONAL(INSTALL_COMPAT, test "$enable_compat" = yes)

dnl Install jabber or not ?
AC_ARG_ENABLE(jabber,
    AC_HELP_STRING([--enable-jabber],
        [Enable jabber bridge installation [default=yes]]),
        enable_jabber=$enableval, enable_jabber=yes)

AM_CONDITIONAL(INSTALL_JABBER, test "$enable_jabber" = yes)

dnl Install tools or not ?
AC_ARG_ENABLE(tools,
    AC_HELP_STRING([--enable-tools],
        [Enable VHFFS tools installation [default=yes]]),
        enable_tools=$enableval, enable_tools=yes)

AM_CONDITIONAL(INSTALL_TOOLS, test "$enable_tools" = yes)

dnl Install vhffs-fs or not ?
AC_ARG_ENABLE(vhffs-fs,
    AC_HELP_STRING([--enable-vhffs-fs],
        [Enable VHFFS filesystem (on the fly homedirs using VHFFS DB) 
            [default=no]]),
        enable_vhffs_fs=$enableval, enable_vhffs_fs=no)

AM_CONDITIONAL(INSTALL_VHFFS_FS, test "$enable_vhffs_fs" = yes)

dnl Install IRC moderation bot or not ?
AC_ARG_ENABLE(irc,
    AC_HELP_STRING([--enable-irc],
        [Enable IRC moderation bot 
            [default=no]]),
        enable_irc=$enableval, enable_irc=no)

AM_CONDITIONAL(INSTALL_IRC, test "$enable_irc" = yes)

dnl Install extra tools or not ?
AC_ARG_ENABLE(extra,
    AC_HELP_STRING([--enable-extra],
        [Enable extra tools (autokill, syslogger, stsmon, etc.)
            [default=no]]),
        enable_extra=$enableval, enable_extra=no)

AM_CONDITIONAL(INSTALL_EXTRA, test "$enable_extra" = yes)

dnl Install vhffs-fssync or not ?
AC_ARG_ENABLE(fssync,
    AC_HELP_STRING([--enable-fssync],
        [Enable fssync (useful for download reporisitories.)
            [default=no]]),
        enable_fssync=$enableval, enable_fssync=no)

AM_CONDITIONAL(INSTALL_FSSYNC, test "$enable_fssync" = yes)

# -- Starting system checks
AC_CHECK_HEADERS([stdlib.h string.h sys/time.h syslog.h unistd.h])

# Needed for tuxshell
AC_CONFIG_SRCDIR([vhffs-shells/tuxshell.c])

# Checks for typedefs, structures, and compiler characteristics.
AC_HEADER_TIME
AC_HEADER_STDBOOL
AC_TYPE_UID_T

# Checks for library functions.
AC_FUNC_CLOSEDIR_VOID
AC_FUNC_FORK
AC_CHECK_FUNCS([gettimeofday])

AM_GNU_GETTEXT([external])

# -- Files to generate

# Configures vhffs-fs if needed
if test "$enable_vhffs_fs" = yes ; then
    AC_CONFIG_SUBDIRS([vhffs-fs])
fi

if test "$enable_extra" = yes ; then
    AM_PROG_CC_C_O
#    AM_PATH_GLIB_2_0( 2.0.0, [], [AC_MSG_FAILURE([Glib not found (needed for extra packages)])])
fi

if test "$enable_fssync" = yes ; then
    PKG_CHECK_MODULES(GLIB2, [glib-2.0 >= 2.16.0])
    AC_SUBST(GLIB2_CFLAGS)
    AC_SUBST(GLIB2_LIBS)
    AC_CHECK_HEADERS([sys/inotify.h],,[AC_MSG_ERROR([Cannot find inotify headers])])
    AC_CHECK_FUNCS([inotify_init inotify_add_watch inotify_rm_watch])
fi

AC_CONFIG_FILES([ vhffs-intl/Makefile.in
	vhffs-test-dependencies],
	[chmod ug+x $ac_file]
)

AC_CONFIG_FILES([
	vhffs-backend/src/pgsql/initdb.sql
	vhffs-backend/conf/vhffs.conf.dist])

AC_CONFIG_FILES([
	Makefile
	vhffs-api/Makefile
	vhffs-api/src/Makefile
	vhffs-autokill/Makefile
	vhffs-backend/Makefile
	vhffs-backend/src/Makefile
	vhffs-compat/Makefile
	vhffs-doc/Makefile
	vhffs-forum/Makefile
	vhffs-fssync/Makefile
	vhffs-jabber/Makefile
	vhffs-listengine/Makefile
	vhffs-listengine/src/Makefile
	vhffs-cron/Makefile
	vhffs-cron/src/Makefile
	vhffs-mw/Makefile
	vhffs-patches/Makefile
	vhffs-panel/Makefile
	vhffs-panel/templates/Makefile
	vhffs-public/Makefile
	vhffs-public/templates/Makefile
	vhffs-robots/Makefile
	vhffs-shells/Makefile
	vhffs-stsmon/Makefile
	vhffs-syslogger/Makefile
	vhffs-themes/Makefile
	vhffs-tools/Makefile
	vhffs-tools/src/Makefile
	vhffs-irc/Makefile
	vhffs-tools/mans/Makefile
	],
)

AC_OUTPUT
