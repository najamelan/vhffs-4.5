if INSTALL_PUBLIC
SUBDIRS = templates

publicdir = @PUBLICDIR@
nobase_dist_public_SCRIPTS = index.pl

# Define the substitution we need to point perl script at correct location
do_sed = $(SED) --in-place \
	-e 's,%PERL%,$(PERL),g' \
	-e 's,'%VHFFS_LIB_DIR%',$(APIDIR),g'

# Because automake, exec-hook is executed before install-scripts
# so install-data is after. Here we use a data-hook
install-data-hook :
	for f in $(nobase_dist_public_SCRIPTS) ; do \
		$(do_sed) $(DESTDIR)$(publicdir)/$$f; \
	done

endif # Install public
