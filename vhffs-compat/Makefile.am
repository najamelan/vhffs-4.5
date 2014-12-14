if INSTALL_COMPAT

compatdir = @COMPATDIR@
dist_compat_DATA = \
	from-4.1-to-4.2.sql \
	from-4.2-to-4.3.sql \
	from-4.3-to-4.4.sql \
	from-4.4-to-4.5.sql

dist_compat_SCRIPTS = \
	updatedb.pl

# Define the substitution we need to point perl script at correct location
do_sed = $(SED) --in-place \
	-e 's,%PERL%,$(PERL),g' \
	-e 's,'%VHFFS_LIB_DIR%',$(APIDIR),g' \
	-e 's,'%VHFFS_BACKEND_DIR%',$(BACKENDDIR),g' \
	-e 's,'%VHFFS_COMPAT_DIR%',$(compatdir),g' \
	-e 's,'%VHFFS_BOTS_DIR%',$(BOTSDIR),g' \
	-e 's,'%BASH%',$(BASH),g'

# Because automake, exec-hook is executed before install-scripts
# so install-data is after. Here we use a data-hook
install-data-hook :
	for f in $(dist_compat_DATA) ; do \
		$(do_sed) $(DESTDIR)$(compatdir)/$$f; \
	done
	for f in $(dist_compat_SCRIPTS) ; do \
		$(do_sed) $(DESTDIR)$(compatdir)/$$f; \
	done

endif # INSTALL_COMPAT
