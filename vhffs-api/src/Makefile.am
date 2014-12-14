apidir = @APIDIR@

revision=`svnversion . | perl -e '$$_ = <STDIN>; /^(?:.*?:)?(\d+)\w*\$$/; print \$$1;'`
botsdir = @BOTSDIR@

files_do_sed = \
	Vhffs.pm \
	Vhffs/Acl.pm \
	Vhffs/Broadcast.pm \
	Vhffs/Conf.pm \
	Vhffs/Constants.pm \
	Vhffs/Functions.pm \
	Vhffs/Group.pm \
	Vhffs/Listengine.pm \
	Vhffs/Panel.pm \
	Vhffs/ObjectFactory.pm \
	Vhffs/Object.pm \
	Vhffs/Robots.pm \
	Vhffs/Services.pm \
	Vhffs/Stats.pm \
	Vhffs/Tag.pm \
	Vhffs/User.pm \
	Vhffs/UserGroup.pm \
	Vhffs/Panel/Acl.pm \
	Vhffs/Panel/Admin.pm \
	Vhffs/Panel/Auth.pm \
	Vhffs/Panel/Avatar.pm \
	Vhffs/Panel/Bazaar.pm \
	Vhffs/Panel/Commons.pm \
	Vhffs/Panel/Contact.pm \
	Vhffs/Panel/Cvs.pm \
	Vhffs/Panel/DNS.pm \
	Vhffs/Panel/Group.pm \
	Vhffs/Panel/Mail.pm \
	Vhffs/Panel/MailingList.pm \
	Vhffs/Panel/Broadcast.pm \
	Vhffs/Panel/Mercurial.pm \
	Vhffs/Panel/Moderation.pm \
	Vhffs/Panel/Mysql.pm \
	Vhffs/Panel/Object.pm \
	Vhffs/Panel/Pgsql.pm \
	Vhffs/Panel/Public.pm \
	Vhffs/Panel/Repository.pm \
	Vhffs/Panel/Subscribe.pm \
	Vhffs/Panel/Svn.pm \
	Vhffs/Panel/Stats.pm \
	Vhffs/Panel/Tag.pm \
	Vhffs/Panel/Git.pm \
	Vhffs/Panel/User.pm \
	Vhffs/Panel/Web.pm \
	Vhffs/Panel/Cron.pm \
	Vhffs/Robots/Bazaar.pm \
	Vhffs/Robots/Broadcast.pm \
	Vhffs/Robots/Cvs.pm \
	Vhffs/Robots/DNS.pm \
	Vhffs/Robots/Group.pm \
	Vhffs/Robots/Mail.pm \
	Vhffs/Robots/MailingList.pm \
	Vhffs/Robots/Mercurial.pm \
	Vhffs/Robots/Mysql.pm \
	Vhffs/Robots/Pgsql.pm \
	Vhffs/Robots/Repository.pm \
	Vhffs/Robots/Svn.pm \
	Vhffs/Robots/Git.pm \
	Vhffs/Robots/User.pm \
	Vhffs/Robots/UserGroup.pm \
	Vhffs/Robots/Web.pm \
	Vhffs/Robots/Cron.pm \
	Vhffs/Services/Bazaar.pm \
	Vhffs/Services/Cvs.pm \
	Vhffs/Services/DNS.pm \
	Vhffs/Services/Web.pm \
	Vhffs/Services/Mail.pm \
	Vhffs/Services/MailingList.pm \
	Vhffs/Services/Newsletter.pm \
	Vhffs/Services/MailUser.pm \
	Vhffs/Services/MailGroup.pm \
	Vhffs/Services/Mercurial.pm \
	Vhffs/Services/Mysql.pm \
	Vhffs/Services/Pgsql.pm \
	Vhffs/Services/Repository.pm \
	Vhffs/Services/Svn.pm \
	Vhffs/Services/Git.pm \
	Vhffs/Services/Cron.pm \
	Vhffs/Tag/Category.pm \
	Vhffs/Tag/Request.pm

files_no_sed = 

nobase_dist_api_DATA = \
	$(files_do_sed) \
	$(files_no_sed)

# Define the substitution we need to point perl script at correct location
do_sed = $(SED) --in-place \
	-e 's,%PERL%,$(PERL),g' \
	-e 's,'%VHFFS_LIB_DIR%',$(APIDIR),g' \
	-e 's,'%VHFFS_REVISION%",$(revision),g" \
	-e 's,'%VHFFS_BOTS_DIR%',$(botsdir),g' \
	-e 's,'%localedir%',$(localedir),g'

install-data-hook:
	for f in $(files_do_sed) ; do \
		$(do_sed) $(DESTDIR)$(apidir)/$$f; \
	done
