if INSTALL_ROBOTS

botsdir = @BOTSDIR@
nobase_dist_bots_DATA = \
	misc/awstats_6.95_vhffs.patch \
	misc/awstats_7.0_vhffs.patch \
	misc/awstats_htaccess_example \
	misc/awstats.sample \
	misc/disabled_webarea.htaccess \
	misc/repository.awstats_6.95_vhffs.patch \
	misc/repository.awstats_7.0_vhffs.patch \
	misc/repository.awstats_htaccess_example \
	misc/repository.awstats.sample \
	misc/cvs_viewvc.conf.tt \
	misc/svn_viewvc.conf.tt \
	misc/mhonarc.config \
	misc/mhonarc.indexmain.tt \
	misc/mercurial_notify.rc

nobase_dist_bots_SCRIPTS = \
	misc/svn_post-commit.pl \
	misc/git_post-receive

dist_bots_SCRIPTS = \
	src/broadcast.pl \
	src/dns.pl \
	src/group.pl \
	src/group_quota.pl \
	src/mail.pl \
	src/mailinglist.pl \
	src/mailinglist_mhonarc.pl \
	src/mysql.pl \
	src/mysql_dump.pl \
	src/object_cleanup.pl \
	src/pgsql.pl \
	src/pgsql_dump.pl \
	src/repository.pl \
	src/repository_quota.pl \
	src/repository_stats.pl \
	src/cvs.pl \
	src/svn.pl \
	src/git.pl \
	src/mercurial.pl \
	src/bazaar.pl \
	src/user.pl \
	src/user_quota.pl \
	src/user_cleanup.pl \
	src/usergroup.pl \
	src/web.pl \
	src/web_stats.pl \
	src/cron.pl

# Define the substitution we need to point perl script at correct location
do_sed = $(SED) --in-place \
	-e 's,%PERL%,$(PERL),g' \
	-e 's,'%VHFFS_LIB_DIR%',$(APIDIR),g' \
	-e 's,'%VHFFS_BOTS_DIR%',$(botsdir),g'

# Because automake, exec-hook is executed before install-scripts
# so install-data is after. Here we use a data-hook
install-data-hook :
	for f in $(nobase_dist_bots_DATA) ; do \
		$(do_sed) $(DESTDIR)$(botsdir)/$$f; \
	done
	for f in $(dist_bots_SCRIPTS) ; do \
		nf=`echo $$f | sed 's,^.*/,,'`; \
		$(do_sed) $(DESTDIR)$(botsdir)/$$nf; \
	done
	for f in $(nobase_dist_bots_SCRIPTS) ; do \
		$(do_sed) $(DESTDIR)$(botsdir)/$$f; \
	done

endif # INSTALL_ROBOTS
