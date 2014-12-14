if INSTALL_JABBER

jabberdir = @JABBERDIR@
dist_jabber_SCRIPTS = vhffspipe.pl

# Define the substitution we need to point perl script at correct location
do_sed = $(SED) --in-place \
	-e 's,%PERL%,$(PERL),g' \
	-e 's,'%VHFFS_LIB_DIR%',$(APIDIR),g'

# Because automake, exec-hook is executed before install-scripts
# so install-data is after. Here we use a data-hook
install-data-hook :
	for f in $(dist_jabber_SCRIPTS) ; do \
		$(do_sed) $(DESTDIR)$(jabberdir)/$$f; \
	done

endif
