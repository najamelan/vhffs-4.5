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

package Vhffs::Panel::Mercurial;

use DBI;
use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Services::Mercurial;
use Vhffs::Constants;
use Vhffs::Functions;


=pod

=head2 getall_per_group

	$mercurial = Vhffs::Panel::Mercurial::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all mercurial repos owned by
a given group.

=cut
sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT s.object_id AS oid, s.reponame AS displayname, o.state FROM vhffs_mercurial s INNER JOIN vhffs_object o ON s.object_id = o.object_id WHERE o.owner_gid = ? ORDER BY s.reponame';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $mercurial = [];
	while(my $s = $sth->fetchrow_hashref) {
		$s->{active} = ($s->{state} == Vhffs::Constants::ACTIVATED);
		$s->{refused} = ($s->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$s->{state} = Vhffs::Functions::status_string_from_status_id($s->{state});
		push @$mercurial, $s;
	}
	return $mercurial;
}

sub get_repos_per_group {
	my ($vhffs, $gid, $public_only) = @_;
	$public_only = 1 unless(defined $public_only);

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT g.reponame, o.description FROM vhffs_mercurial g INNER JOIN vhffs_object o ON o.object_id = g.object_id '.
	  'WHERE '.($public_only ? 'public = 1 AND ' : '').'o.owner_gid = ? AND o.state = ?';
	return $dbh->selectall_arrayref($sql, { Slice => {} }, $gid, Vhffs::Constants::ACTIVATED);
}


sub search_mercurial {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT m.reponame as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_mercurial m '.
	  'INNER JOIN vhffs_object o ON (o.object_id = m.object_id) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) ';

	if( defined $name ) {
		$sql .= 'WHERE m.reponame LIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY m.reponame';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}



sub create_mercurial {
	my ($vhffs, $repo, $description, $user, $group) = @_;
	return -1 unless defined $user;
	return -2 unless defined $group;

	my $mercurial = Vhffs::Services::Mercurial::create( $vhffs, $repo, $description, $user, $group );
	return -1 unless defined $mercurial;


	return $mercurial;
}

sub create {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group and $user->can_modify( $group ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}
	$panel->set_group( $group );

	my $submitted = $cgi->param('mercurial_submit');
	my $reponame = '';
	my $description = '';
	my $vars = {};

	if( $submitted ) {
		$reponame = $cgi->param('reponame');
		my $fullreponame = $group->get_groupname.'/'.$reponame;
		$description = Encode::decode_utf8( scalar $cgi->param('description') );
		unless( defined $reponame and defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
		} else {
			$panel->add_error( gettext('Invalid repository name. It must contain between 3 and 64 characters, only lowercase letters and numbers') ) unless Vhffs::Services::Mercurial::check_name($fullreponame);
			$panel->add_error( gettext('You must enter a description') ) unless $description !~ /^\s*$/;
		}

		unless( $panel->has_errors() ) {
			my $mercurial = Vhffs::Panel::Mercurial::create_mercurial( $vhffs, $fullreponame, $description, $user, $group );
			if(defined $mercurial) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The Mercurial object was successfully created !');
				$panel->redirect($url);
				return;
			}

			$panel->add_error( gettext('An error occured while creating the mercurial repository') );
		}

		$vars->{reponame} = $reponame;
		$vars->{description} = $description;
	}

	$vars->{group} = $group;
	$panel->render('mercurial/create.tt', $vars);
}


sub prefs {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $repo_name = $cgi->param('name');
	unless( defined $repo_name ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		return;
	}

	my $mercurial = Vhffs::Services::Mercurial::get_by_reponame( $vhffs , $repo_name );
	unless( defined $mercurial ) {
		$panel->render('misc/message.tt', { message => gettext( 'Cannot get informations on this object' ) } );
		return;
	}
	$panel->set_group( $mercurial->get_group );

	unless( $user->can_view( $mercurial ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	save_prefs($panel, $mercurial) if defined $cgi->param('save_prefs_submit');

	$panel->set_title( gettext("Modify Mercurial repository") );
	my $vars = {};
	$vars->{repository} = $mercurial;
	$vars->{notify_from} = $mercurial->get_config->{notify_from};
	$vars->{type} = 'mercurial';
	$panel->render( 'scm/prefs.tt', $vars );
}

sub save_prefs {
	my $panel = shift;
	my $mercurial = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	my $public = $cgi->param('public');
	my $ml_name = $cgi->param('ml_name');

	unless( $user->can_modify($mercurial) ) {
		$panel->add_error( gettext('You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights') );
		return 0;
	}

	unless( defined $public and defined $ml_name ) {
		$panel->add_error( gettext('CGI error !') );
		return 0;
	}

	if($public != $mercurial->is_public) {
		if($public == 1) {
			$mercurial->set_public();
		} else {
			$mercurial->set_private();
		}
		$mercurial->set_status(Vhffs::Constants::WAITING_FOR_MODIFICATION);
	}

	if( $ml_name =~ /^\s*$/ or Vhffs::Functions::valid_mail($ml_name) ) {
		if($ml_name ne $mercurial->get_ml_name) {
			$mercurial->set_ml_name($ml_name);
			$mercurial->set_status( Vhffs::Constants::WAITING_FOR_MODIFICATION );
		}
	} else {
		$panel->add_error( gettext('Invalid mailing list address') );
		return 0;
	}

	if($mercurial->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION) {
		if($mercurial->commit > 0) {
			my $url = '?do=groupview;group='.$mercurial->get_group->get_groupname.';msg='.gettext('Modifications applied. Please wait while your repository is being updated');
			$panel->redirect($url);
			return 1;
		}

		$panel->add_error( gettext('Unable to apply modifications') );
		return 0;
	}

	return 0;
}

sub index {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group ) {
		$panel->render_template('misc/message.tt', { message => gettext('You have to select a group first') } );
		return;
	}

	unless($group->get_status == Vhffs::Constants::ACTIVATED) {
		$panel->render( 'misc/message.tt', { message => gettext('This group is not activated yet') } );
		return;
	}

	unless( $user->can_view( $group ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}

	$panel->set_group( $group );
	$panel->set_title( sprintf(gettext('Mercurial repositories for %s'), $group->get_groupname) );
	my $mercurial = Vhffs::Panel::Mercurial::getall_per_group( $vhffs, $group->get_gid );
	if($mercurial < 0) {
		$panel->render( 'misc/message.tt', { message => gettext('Unable to get Mercurial repositories') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'Mercurial repositories',
	  group => $group,
	  list => $mercurial,
	  help_url => $vhffs->get_config->get_service('mercurial')->{url_doc},
	  type => 'mercurial'
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
		  search_title => gettext('Mercurial search'),
		  type => 'mercurial'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all mercurial repositories');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_mercurial( $vhffs , $name );
	$vars->{type} = 'mercurial';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Mercurial repositories administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_mercurial_category() ] } );
}

1;
