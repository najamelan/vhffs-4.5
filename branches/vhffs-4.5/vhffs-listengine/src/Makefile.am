ledir = @LEDIR@
dist_le_SCRIPTS = listengine.pl

# Define the substitution we need to point perl script at correct location
do_sed = $(SED) --in-place \
	-e 's,%PERL%,$(PERL),g' \
	-e 's,%localedir%,$(localedir),g' \
	-e 's,'%VHFFS_LIB_DIR%',$(APIDIR),g'

# Because automake, exec-hook is executed before install-scripts
# so install-data is after. Here we use a data-hook
install-data-hook :
	for f in $(dist_le_SCRIPTS) ; do \
		$(do_sed) $(DESTDIR)$(ledir)/$$f; \
	done
