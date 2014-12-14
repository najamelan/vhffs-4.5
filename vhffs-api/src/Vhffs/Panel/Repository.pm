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

package Vhffs::Panel::Repository;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Services::Repository;
use Vhffs::Constants;

=pod

=head2 getall_per_group

	$repos = Vhffs::Panel::Repository::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all download
repositories owned by a given group.

=cut

sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT r.object_id AS oid, r.name AS displayname, o.state FROM vhffs_repository r INNER JOIN vhffs_object o ON r.object_id = o.object_id WHERE o.owner_gid = ? ORDER BY r.name';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $mysql = [];
	while(my $m = $sth->fetchrow_hashref) {
		$m->{active} = ($m->{state} == Vhffs::Constants::ACTIVATED);
		$m->{refused} = ($m->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$m->{state} = Vhffs::Functions::status_string_from_status_id($m->{state});
		push @$mysql, $m;
	}
	return $mysql;
}

sub search_repository {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT r.name as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_repository r '.
	  'INNER JOIN vhffs_object o ON (o.object_id = r.object_id) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) ';

	if( defined $name ) {
		$sql .= 'WHERE r.name LIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY label';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}



sub create_repository
{
	my( $vhffs , $name , $user , $group, $description ) = @_;
	return undef unless defined $user and defined $group;

	my $repo = Vhffs::Services::Repository::create( $vhffs , $name , $description, $user , $group );
	return undef unless defined $repo;


	return $repo;
}

sub create {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group and $user->can_modify( $group ) ) {
		$panel->render( 'misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}
	$panel->set_group( $group );

	my $submitted = $cgi->param('repo_submit');
	my $description = '';
	my $vars = {};

	if( $submitted ) {
		$description = Encode::decode_utf8( scalar $cgi->param('description') );

		unless( defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
		} else {
			$panel->add_error( gettext('You must enter a description') ) unless $description !~ /^\s*$/;
		}

		unless( $panel->has_errors() ) {	
			my $repository = Vhffs::Panel::Repository::create_repository( $vhffs, $group->get_groupname, $user, $group , $description );
			if( defined $repository ) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The repository was successfully created !');
				$panel->redirect($url);
				return;
			}

			$panel->add_error( gettext('An error occured while creating the object. Check that this group doesn\'t already have a download repository') );
		}

		$vars->{description} = $description;
	}

	$panel->set_title( gettext('Create a Download Repository') );
	$vars->{group} = $group;
	$panel->render( 'repository/create.tt', $vars );
}

sub prefs {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $repo_name = $cgi->param('name');
	unless( defined $repo_name ) {
		$panel->render('misc/message.tt', { message => gettext('CGI Error !') });
		return;
	}

	my $repo = Vhffs::Services::Repository::get_by_reponame( $vhffs , $repo_name );
	unless( defined $repo ) {
		$panel->render('misc/message.tt', { message => gettext('Cannot get informations on this object') });
		return;
	}
	$panel->set_group( $repo->get_group );

	unless( $user->can_view( $repo ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' )} );
		return;
	}

	update_quota($panel, $repo) if defined $cgi->param('update_quota_submit');

	my $vars = { repository => $repo };
	$panel->set_title( gettext('Admin Download repository') );
	$panel->render('repository/prefs.tt', $vars);
}

sub update_quota {
	my $panel = shift;
	my $repo = shift;
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	unless($user->is_admin()) {
		$panel->add_error( gettext('Only administrators are allowed to do this') );
		return;
	}

	my $quota = $cgi->param('new_quota');
	unless(defined $quota and $quota =~ /^\d+$/) {
		$panel->add_error( gettext('Invalid quota') );
		return;
	}

	$repo->set_quota($quota);

	if($repo->commit < 0) {
		$panel->add_error( gettext('Unable to apply modifications, please try again later') );
		return;
	}

	$panel->add_info( gettext('Repository updated, please wait while quota is updated on filesystem') );
}

sub index {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group ) {
		$panel->render('misc/message.tt', { message => gettext('You have to select a group first') } );
		return;
	}

	unless($group->get_status == Vhffs::Constants::ACTIVATED) {
		$panel->render( 'misc/message.tt', { message => gettext('This group is not activated yet') } );
		return;
	}

	unless( $user->can_modify( $group ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}

	$panel->set_group( $group );
	$panel->set_title( sprintf(gettext('Download repositories for %s'), $group->get_groupname) );

	my $repositories = Vhffs::Panel::Repository::getall_per_group( $vhffs, $group->get_gid );
	if($repositories < 0) {
		$panel->render( 'misc/message.tt', { message => gettext('Unable to get download repositories') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'Download repositories',
	  group => $group,
	  list => $repositories,
	  help_url => $vhffs->get_config->get_service('repository')->{url_doc},
	  type => 'repository'
	  });
}

sub search {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $name = $cgi->param('name');
	my $vars = {};

	unless( defined $name ) {

		$panel->render('admin/misc/search.tt', {
		  search_title => gettext('Download repositories search'),
		  type => 'repository'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all download repositories');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_repository( $vhffs , $name );
	$vars->{type} = 'repository';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Download repositories administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_repo_category() ] } );
}

1;
