PERL = @PERL@

SITE_CONFIG_FILE = @CONFDIR@/vhffs.conf

DISTCHECK_CONFIGURE_FLAGS = --enable-extra --enable-panel \
	--enable-public --enable-listengine --enable-cron --enable-robots \
	--enable-backend --enable-compat --enable-jabber --enable-tools \
	--enable-vhffs-fs

if INSTALL_VHFFS_FS 
  SUB_VHFFS_FS=vhffs-fs
endif

SUBDIRS = $(SUB_VHFFS_FS) vhffs-api vhffs-patches vhffs-backend vhffs-doc vhffs-compat vhffs-intl vhffs-jabber vhffs-listengine \
	vhffs-cron vhffs-panel vhffs-public vhffs-robots vhffs-shells vhffs-themes vhffs-tools vhffs-irc vhffs-autokill \
	vhffs-syslogger vhffs-forum vhffs-fssync vhffs-mw vhffs-stsmon

EXTRA_DIST = config.rpath m4/ChangeLog

help:
	@echo "Help for VHFFS makefile"
	@echo " help           display this help"
	@echo " install        install VHFFS on this host"
	@echo " test-deps      Verify all dependecies"

post-inst:
	@echo "Congratulations ! VHFFS is now installed."
	@echo ""
	@echo ""
	@echo "You must now configure vhffs by editing $(SITE_CONFIG_FILE)."
	@echo ""
	@echo "Make sure you setup database information, hostname and services"

test-deps:
	$(PERL) ./vhffs-test-dependencies --verbose --verify=all
	
dist-hook:
	rm -rf `find $(distdir)/ -name '.svn'`

ACLOCAL_AMFLAGS = -I m4
