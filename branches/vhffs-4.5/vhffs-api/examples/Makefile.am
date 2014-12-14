dist_examples_SCRIPTS = \
	add_acl_dns.pl \
	add_acl.pl \
	create_box.pl \
	create_cvs_panel.pl \
	create_cvs.pl \
	create_dns.pl \
	create_forward.pl \
	create_group_by_panel.pl \
	create_group.pl \
	create_list.pl \
	create_mail.pl \
	create_mysql_panel.pl \
	create_mysql.pl \
	create_panel_mail.pl \
	create_postgres.pl \
	create_repository.pl \
	create_user.pl \
	create_web_panel.pl \
	create_web.pl \
	delbox.pl \
	delete_acl.pl \
	generate_password.pl \
	get_list.pl \
	join_group.pl \
	mailuser_add_box.pl \
	mailuser.pl \
	modify_acl.pl \
	modify_user.pl \
	perm_for_user.pl \
	print_domain.pl \
	show_acl_per_object.pl \
	show_dns_per_group.pl \
	show_dns_per_user.pl \
	show_dumper_cvs.pl \
	show_dumper_group.pl \
	show_dumper_object.pl \
	show_dumper_user.pl \
	show_groups_per_user.pl \
	show_last_users.pl \
	show_mail_conf.pl \
	show_mail_per_group.pl \
	show_members_from_list.pl \
	stats.pl

# Define the substitution we need to point perl script at correct location
do_sed = $(SED) --in-place \
	-e 's,%PERL%,$(PERL),g' \
	-e 's,'%VHFFS_LIB_DIR%',$(APIDIR),g'

install-data-hook:
	for f in $(dist_examples_DATA) ; do \
		$(do_sed) $$f; \
	done
