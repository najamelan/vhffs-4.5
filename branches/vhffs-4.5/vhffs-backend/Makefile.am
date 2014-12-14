if INSTALL_BACKEND

SUBDIRS=src

# If you add files to this, you've to modify install-data-hook
dist_config_DATA = conf/vhffs.conf.dist
configdir = @CONFDIR@
CONF_FILE = @CONFDIR@/vhffs.conf

do_sed = $(SED) --in-place -e 's!%localedir%!$(localedir)!g'

install-data-hook:
	@$(do_sed) $(DESTDIR)$(configdir)/vhffs.conf.dist; \
	if test -f $(DESTDIR)$(CONF_FILE) ; then \
		echo "$@ will not overwrite existing $(DESTDIR)$(CONF_FILE)" ; \
	else \
		echo "$(INSTALL_DATA) $(dist_config_DATA) $(DESTDIR)$(CONF_FILE)"; \
		$(INSTALL_DATA) $(dist_config_DATA) $(DESTDIR)$(CONF_FILE); \
		$(do_sed)  $(DESTDIR)$(CONF_FILE); \
	fi

endif
