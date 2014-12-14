if INSTALL_IRC

ircdir = @IRCDIR@
dist_irc_SCRIPTS = modobot.pl

# Define the substitution we need to point perl script at correct location
do_sed = $(SED) --in-place \
        -e 's,%PERL%,$(PERL),g' \
        -e 's,'%VHFFS_LIB_DIR%',$(APIDIR),g'

# Because automake, exec-hook is executed before install-scripts
# so install-data is after. Here we use a data-hook
install-data-hook :
	for f in $(dist_irc_SCRIPTS) ; do \
		$(do_sed) $(DESTDIR)$(ircdir)/$$f; \
	done


endif
