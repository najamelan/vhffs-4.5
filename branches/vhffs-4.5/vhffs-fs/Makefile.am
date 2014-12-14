vhffsfsdir=@VHFFSFSDIR@
vhffsfs_SOURCES=rquota_xdr.c rquota_clnt.c rquota.h md5.h rquota.x md5c.c vhffsfs.c
vhffsfs_PROGRAMS=vhffsfs
dist_vhffsfs_SCRIPTS=

vhffsfsconfdir=@CONFDIR@
dist_vhffsfsconf_DATA=vhffsfs.conf.dist

CONF_FILE=@CONFDIR@/vhffsfs.conf


# TODO REMOVE THE UGLY elif and use sysconf_DATA
install-data-hook:
	@if test -f $(DESTDIR)$(CONF_FILE) ; then \
		echo "$@ will not overwrite existing $(DESTDIR)$(CONF_FILE)" ; \
	elif test -f $(dist_vhffsfsconf_DATA) ; then \
		echo "$(INSTALL_DATA) $(dist_vhffsfsconf_DATA) $(DESTDIR)$(CONF_FILE)"; \
   	    $(INSTALL_DATA) $(dist_vhffsfsconf_DATA) $(DESTDIR)$(CONF_FILE); \
    fi


rquota_xdr.c: rquota.x rquota.h
	rpcgen -c -o rquota_xdr.c rquota.x

rquota_clnt.c: rquota.x rquota.h
	rpcgen -l -o rquota_clnt.c rquota.x

rquota.h: rquota.x
	rpcgen -h -o rquota.h rquota.x

CLEANFILES=rquota_xdr.c rquota_clnt.c rquota.h
