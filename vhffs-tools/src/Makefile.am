toolsdir = @TOOLSDIR@
dist_tools_SCRIPTS = \
	vhffs-box-add \
	vhffs-dumpmysql \
	vhffs-groupadd \
	vhffs-groupdel \
	vhffs-groupinfo \
	vhffs-makeadmin \
	vhffs-managedns \
	vhffs-managemail \
	vhffs-moderate \
	vhffs-passwd \
	vhffs-quota \
	vhffs-useradd \
	vhffs-userdel \
	vhffs-userinfo \
	vhffs-usermod \
	vhffs-webdir \
	vhffs-webstats
	
# Define the substitution we need to point perl script at correct location
do_sed = $(SED) --in-place \
	-e 's,%PERL%,$(PERL),g' \
	-e 's,'%VHFFS_LIB_DIR%',$(APIDIR),g'

# Because automake, exec-hook is executed before install-scripts
# so install-data is after. Here we use a data-hook
install-data-hook :
	for f in $(dist_tools_SCRIPTS) ; do \
		$(do_sed) $(DESTDIR)$(toolsdir)/$$f; \
	done
