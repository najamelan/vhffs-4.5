#!%PERL%
# Copyright (c) vhffs project and its contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
#2. Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in
#   the documentation and/or other materials provided with the
#   distribution.
#3. Neither the name of vhffs nor the names of its contributors
#   may be used to endorse or promote products derived from this
#   software without specific prior written permission.
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
#FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
#COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
#BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
#CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

use strict;
use utf8;

# This is a part of VHFFS platform

# This file is used to generate the admin part of the menu (left in the panel)

package Vhffs::Panel::Admin;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;

=pod

=head1 NAME

Vhffs::Panel::Admin - Handle administration functionnalities of VHFFS panel.

=head1 METHODS

=cut

=pod

=head2 get_modo_category

	Vhffs::Panel::Admin::get_modo_category;

Returns a hashref (name, items) where catname is the name of the
general category for moderation and items the corresponding menu
items.

=cut

sub get_modo_category {
	my $items = [
		{ link => '?do=stats',       label => gettext( 'Get Statistics' ) },
		{ link => '?do=moderation',  label => gettext( 'Moderation' ) }
	];
	return { name => gettext( 'General' ),   items => $items, type => 'general' };
}

=head2 get_admin_category

	Vhffs::Panel::Admin::get_admin_category;

Returns a hashref (name, items) containing general administration
items.

=cut

sub get_admin_category {
	my $items = [
		{ link => '?do=stats',               label => gettext( 'Get Statistics' ) },
		{ link => '?do=su',                  label => gettext( 'Change user-id' ) },
		{ link => '?do=moderation',          label => gettext( 'Moderation' ) },
		{ link => '?do=objectsearch;name=',  label => gettext( 'List all objects' ) },
		{ link => '?do=objectsearch',        label => gettext( 'Search for an object' ) },
		{ link => '?do=broadcastcreate',     label => gettext( 'Mail to all hosted people' ) },
		{ link => '?do=broadcastlist',       label => gettext( 'Manage mailings' ) }
	];
	return { name => gettext( 'General' ),   items => $items, type => 'general' };
}


=head2 get_bazaar_category

	Vhffs::Panel::Admin::get_bazaar_category;

Returns a hashref (name, ITEM) containing bazaar's administration
items.

=cut

sub get_bazaar_category {
	my $items = [
		{ link => '?do=bazaarsearch;name=',  label => gettext( 'List all Bazaar repos' ) },
		{ link => '?do=bazaarsearch',        label => gettext( 'Search for a Bazaar repository' ) }
	];
	return { name => gettext( 'Bazaar Admin' ),    items => $items, type => 'bazaar'  };
}

=head2 get_user_category

	Vhffs::Panel::Admin::get_user_category;

Returns a hashref (name, ITEM) containing users' administration
items.

=cut

sub get_user_category {
	my $items = [
		{ link => '?do=usersearch;name=',   label => gettext( 'List all users' ) },
		{ link => '?do=usersearch',         label => gettext( 'Search for an user' ) }
	];
	return { name => gettext( 'User Admin' ),    items => $items, type => 'user'  };
}

=head2 get_user_category

	Vhffs::Panel::Admin::get_group_category;

Returns a hashref (name, ITEM) containing groups' administration
items.

=cut

sub get_group_category {
	my $items = [
		{ link => '?do=groupsearch;name=',  label => gettext( 'List all groups' ) },
		{ link => '?do=groupsearch',        label => gettext( 'Search for a group' ) }
	];
	return { name => gettext( 'Group Admin' ),    items => $items, type => 'group'  };
}


=head2 get_tag_category

	Vhffs::Panel::Admin::get_tag_cagtegory

Returns a hashref (name, ITEM, type) containing tags'
administration items

=cut

sub get_tag_category {
	my $items = [
		{ link => '?do=tagcreate',			label => gettext( 'Create new tag' ) },
		{ link => '?do=taglist',			label => gettext( 'Manage existing tags' )},
		{ link => '?do=tagcategorycreate',		label => gettext( 'Create new category' )},
		{ link => '?do=tagcategorylist',		label => gettext( 'Manage existing categories' )},
		{ link => '?do=tagrequestlist',			label => gettext( 'Manage requests' )}
	];
	return { name => gettext( 'Tags Admin'),		items => $items, type => 'tags' };
}

=head2 get_web_category

	Vhffs::Panel::Admin::get_web_category;

Returns a hashref (name, ITEM) containing webareas' administration
items.

=cut

sub get_web_category {
	my $items = [
		{ link => '?do=websearch;name=',  label => gettext( 'List all webareas' ) },
		{ link => '?do=websearch',        label => gettext( 'Search for a webarea' ) }
	];
	return { name => gettext( 'Web Admin' ),    items => $items, type => 'web'  };
}

=head2 get_svn_category

	Vhffs::Panel::Admin::get_svn_category;

Returns a hashref (name, ITEM) containing svn's administration
items.

=cut

sub get_svn_category {
	my $items = [
		{ link => '?do=svnsearch;name=',  label => gettext( 'List all SVN repos' ) },
		{ link => '?do=svnsearch',        label => gettext( 'Search for a SVN repository' ) }
	];
	return { name => gettext( 'SVN Admin' ),    items => $items, type => 'svn'  };
}


=head2 get_cvs_category

	Vhffs::Panel::Admin::get_cvs_category;

Returns a hashref (name, ITEM) containing cvs' administration
items.

=cut

sub get_cvs_category {
	my $items = [
		{ link => '?do=cvssearch;name=',   label => gettext( 'List all CVS repos' ) },
		{ link => '?do=cvssearch',         label => gettext( 'Search for a CVS repository' ) }
	];
	return { name => gettext( 'CVS Admin' ),    items => $items, type => 'cvs'  };
}


=head2 get_git_category

	Vhffs::Panel::Admin::get_git_category;

Returns a hashref (name, ITEM) containing git's administration
items.

=cut

sub get_git_category {
	my $items = [
		{ link => '?do=gitsearch;name=',  label => gettext( 'List all Git repos' ) },
		{ link => '?do=gitsearch',        label => gettext( 'Search for a Git repository' ) }
	];
	return { name => gettext( 'Git Admin' ),    items => $items, type => 'git'  };
}


=head2 get_mercurial_category

	Vhffs::Panel::Admin::get_mercurial_category;

Returns a hashref (name, ITEM) containing mercurial's administration
items.

=cut

sub get_mercurial_category {
	my $items = [
		{ link => '?do=mercurialsearch;name=',  label => gettext( 'List all Mercurial repos' ) },
		{ link => '?do=mercurialsearch',        label => gettext( 'Search for a Mercurial repository' ) }
	];
	return { name => gettext( 'Mercurial Admin' ),    items => $items, type => 'mercurial'  };
}

=head2 get_mysql_category

	Vhffs::Panel::Admin::get_mysql_category;

Returns a hashref (name, ITEM) containing mysql's administration
items.

=cut

sub get_mysql_category {
	my $items = [
		{ link => '?do=mysqlsearch;name=',  label => gettext( 'List all MySQL databases' ) },
		{ link => '?do=mysqlsearch',        label => gettext( 'Search for a MySQL database' ) }
	];
	return { name => gettext( 'MySQL Admin' ),    items => $items, type => 'mysql'  };
}

=head2 get_pgsql_category

	Vhffs::Panel::Admin::get_pgsql_category;

Returns a hashref (name, ITEM) containing PostgreSQL's administration
items.

=cut

sub get_pgsql_category {
	my $items = [
		{ link => '?do=pgsqlsearch;name=',  label => gettext( 'List all Pg databases' ) },
		{ link => '?do=pgsqlsearch',        label => gettext( 'Search for a Pg database' ) }
	];
	return { name => gettext( 'PostgreSQL Admin' ),    items => $items, type => 'pgsql'  };
}

=head2 get_mail_category

	Vhffs::Panel::Admin::get_mail_category;

Returns a hashref (name, ITEM) containing mail domains' administration
items.

=cut

sub get_mail_category {
	my $items = [
		{ link => '?do=mailsearch;name=',  label => gettext( 'List all mail domains' ) },
		{ link => '?do=mailsearch',        label => gettext( 'Search for a mail domain' ) }
	];
	return { name => gettext( 'Mail domains Admin' ),    items => $items, type => 'mail'  };
}


=head2 get_mailing_category

	Vhffs::Panel::Admin::get_mailing_category;

Returns a hashref (name, ITEM) containing mailing lists' administration
items.

=cut

sub get_mailing_category {
	my $items = [
		{ link => '?do=mailinglistsearch;name=',  label => gettext( 'List all mailing lists' ) },
		{ link => '?do=mailinglistsearch',        label => gettext( 'Search for a mailing list' ) }
	];
	return { name => gettext( 'Mailing lists Admin' ),    items => $items, type => 'mailing'  };
}


=head2 get_dns_category

	Vhffs::Panel::Admin::get_dns_category;

Returns a hashref (name, ITEM) containing DNS' administration
items.

=cut

sub get_dns_category {
	my $items = [
		{ link => '?do=dnssearch;name=',  label => gettext( 'List all domain names' ) },
		{ link => '?do=dnssearch',        label => gettext( 'Search for a domain name' ) }
	];
	return { name => gettext( 'DNS Admin' ),    items => $items, type => 'dns'  };
}


=head2 get_repo_category

	Vhffs::Panel::Admin::get_repo_category;

Returns a hashref (name, ITEM) containing download repositories' administration
items.

=cut

sub get_repo_category {
	my $items = [
		{ link => '?do=repositorysearch;name=',  label => gettext( 'List all download repositories' ) },
		{ link => '?do=repositorysearch',        label => gettext( 'Search for a download repository' ) }
	];
	return { name => gettext( 'Download repositories Admin' ),    items => $items, type => 'repository'  };
}

=head2 get_cron_category

	Vhffs::Panel::Admin::get_cron_category;

Returns a hashref (name, ITEM) containing cron jobs administration
items.

=cut

sub get_cron_category {
	my $items = [
		{ link => '?do=cronsearch;name=',  label => gettext( 'List all cron jobs' ) },
		{ link => '?do=cronsearch',        label => gettext( 'Search for a cron job' ) }
	];
	return { name => gettext( 'Crons Admin' ),    items => $items, type => 'cron'  };
}

=head2 get_all_admin_categories

	Vhffs::Panel::Admin::get_all_admin_categories($vhffs);

Return an arrayref of hashrefs (name, ITEM) containing all administration
categories and items based on configuration of $vhffs.

=cut

sub get_all_admin_categories($) {
	my $vhffs = shift;
	my $config = $vhffs->get_config;
	my $categories = [];

	push @$categories, get_admin_category;
	push @$categories, get_user_category;
	push @$categories, get_group_category;
	push @$categories, get_web_category       if($config->get_service_availability('web'));
	push @$categories, get_mysql_category     if($config->get_service_availability('mysql'));
	push @$categories, get_pgsql_category     if($config->get_service_availability('pgsql'));
	push @$categories, get_cvs_category       if($config->get_service_availability('cvs'));
	push @$categories, get_svn_category       if($config->get_service_availability('svn'));
	push @$categories, get_dns_category       if($config->get_service_availability('dns'));
	push @$categories, get_git_category       if($config->get_service_availability('git'));
	push @$categories, get_mercurial_category if($config->get_service_availability('mercurial'));
	push @$categories, get_bazaar_category    if($config->get_service_availability('bazaar'));
	push @$categories, get_mail_category      if($config->get_service_availability('mail'));
	push @$categories, get_mailing_category   if($config->get_service_availability('mailinglist'));
	push @$categories, get_repo_category      if($config->get_service_availability('repository'));
	push @$categories, get_cron_category      if($config->get_service_availability('cron'));
	push @$categories, get_tag_category;

	return $categories;
}


=head2 get_all_modo_categories

	Vhffs::Panel::Admin::get_all_modo_categories($vhffs);

Return an arrayref of hashrefs (name, ITEM) containing all administration
categories and items based on configuration of $vhffs.

=cut

sub get_all_modo_categories($) {
	my $vhffs = shift;
	my $config = $vhffs->get_config;
	my $categories = [];

	push @$categories, get_modo_category;
	push @$categories, get_user_category;
	push @$categories, get_group_category;
	push @$categories, get_web_category       if($config->get_service_availability('web'));
	push @$categories, get_mysql_category     if($config->get_service_availability('mysql'));
	push @$categories, get_pgsql_category     if($config->get_service_availability('pgsql'));
	push @$categories, get_cvs_category       if($config->get_service_availability('cvs'));
	push @$categories, get_svn_category       if($config->get_service_availability('svn'));
	push @$categories, get_git_category       if($config->get_service_availability('git'));
	push @$categories, get_mercurial_category if($config->get_service_availability('mercurial'));
	push @$categories, get_bazaar_category    if($config->get_service_availability('bazaar'));
	push @$categories, get_dns_category       if($config->get_service_availability('dns'));
	push @$categories, get_mail_category      if($config->get_service_availability('mail'));
	push @$categories, get_mailing_category   if($config->get_service_availability('mailinglist'));
	push @$categories, get_repo_category      if($config->get_service_availability('repository'));
	push @$categories, get_cron_category      if($config->get_service_availability('cron'));
	push @$categories, get_tag_category;

	return $categories;
}

sub main {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Administration'));

	my $categories = [];
	if( $user->is_moderator ) {
		$categories = Vhffs::Panel::Admin::get_all_modo_categories($panel->{vhffs});
	} else {
		$categories = Vhffs::Panel::Admin::get_all_admin_categories($panel->{vhffs});
	}

	$panel->render('admin/index.tt', {
	  categories => $categories
	  });
}

sub su {
	my $panel = shift;
	return unless $panel->check_admin();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $username = $cgi->param('user');
	if( defined $username ) {
		require Vhffs::User;
		my $user = Vhffs::User::get_by_username( $vhffs, $username );
		if(defined $user) {
			$session->param('uid', $user->get_uid);
			$session->flush();
			$panel->{user} = $user;
			$vhffs->set_current_user( $user );

			require Vhffs::Panel::Group;
			return Vhffs::Panel::Group::index( $panel );
		}

		$panel->add_error( gettext( sprintf( 'User %s does not exist' , $username) ) );
	}

	$panel->render('admin/misc/su.tt');
}

1;
