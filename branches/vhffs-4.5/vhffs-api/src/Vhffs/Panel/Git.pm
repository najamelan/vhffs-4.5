#!%PERL%
# Copyright (c) vhffs project and its contributors
# Copyright (c) 2007 Julien Danjou <julien@danjou.info>
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

package Vhffs::Panel::Git;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Services::Git;
use Vhffs::Constants;
use Vhffs::Functions;


=pod

=head2 getall_per_group

	$git = Vhffs::Panel::Git::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all git repos owned by
a given group.

=cut


sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT s.object_id AS oid, s.reponame AS displayname, o.state FROM vhffs_git s INNER JOIN vhffs_object o ON s.object_id = o.object_id WHERE o.owner_gid = ? ORDER BY s.reponame';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $git = [];
	while(my $s = $sth->fetchrow_hashref) {
		$s->{active} = ($s->{state} == Vhffs::Constants::ACTIVATED);
		$s->{refused} = ($s->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$s->{state} = Vhffs::Functions::status_string_from_status_id($s->{state});
		push @$git, $s;
	}
	return $git;
}

sub get_repos_per_group {
	my ($vhffs, $gid, $public_only) = @_;
	$public_only = 1 unless(defined $public_only);

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT g.reponame, o.description FROM vhffs_git g INNER JOIN vhffs_object o ON o.object_id = g.object_id '.
	  'WHERE '.($public_only ? 'public = 1 AND ' : '').'o.owner_gid = ? AND o.state = ?';
	return $dbh->selectall_arrayref($sql, { Slice => {} }, $gid, Vhffs::Constants::ACTIVATED);
}

sub search_git {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT git.reponame as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_git git '.
	  'INNER JOIN vhffs_object o ON (o.object_id = git.object_id) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) ';

	if( defined $name ) {
		$sql .= 'WHERE git.reponame LIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY git.reponame';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

sub create_git {
	my ($vhffs, $repo, $description, $user, $group) = @_;
	return -1 unless defined $user;
	return -2 unless defined $group;

	my $git = Vhffs::Services::Git::create( $vhffs, $repo, $description, $user, $group );
	return -1 unless defined $git;


	return $git;
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

	my $submitted = $cgi->param('git_submit');
	my $reponame = '';
	my $description = '';
	my $vars = {};

	if( $submitted ) {
		$reponame = $cgi->param('reponame');
		my $fullreponame = $group->get_groupname.'/'.$reponame.'.git';
		$description = Encode::decode_utf8( scalar $cgi->param('description') );
		unless( defined $reponame && defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
		} else {
			$panel->add_error( gettext('Invalid reponame. It must contain between 3 and 64 characters, only lowercase letters and numbers') ) unless Vhffs::Services::Git::check_name($fullreponame);
			$panel->add_error( gettext('You must enter a description') ) unless $description !~ /^\s*$/;
		}

		unless( $panel->has_errors() ) {
			my $git = Vhffs::Panel::Git::create_git( $vhffs, $fullreponame, $description, $user, $group );
			if( defined $git ) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The GIT object was successfully created !');
				$panel->redirect($url);
				return;
			}

			$panel->add_error( gettext('An error occured while creating the git repository') );
		}

		$vars->{reponame} = $reponame;
		$vars->{description} = $description;
	}

	$vars->{group} = $group;
	$panel->render('git/create.tt', $vars);
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

	my $git = Vhffs::Services::Git::get_by_reponame( $vhffs , $repo_name );
	unless( defined $git ) {
		$panel->render('misc/message.tt', { message => gettext( 'Cannot get informations on this object' ) } );
		return;
	}
	$panel->set_group( $git->get_group );

	unless( $user->can_view( $git ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	save_prefs($panel, $git) if defined $cgi->param('save_prefs_submit');

	$panel->set_title( gettext('Modify Git repository') );
	my $vars = {};
	$vars->{repository} = $git;
	$vars->{notify_from} = $git->get_config->{notify_from};
	$vars->{type} = 'git';
	$panel->render( 'scm/prefs.tt', $vars );
}

sub save_prefs {
	my $panel = shift;
	my $git = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	my $public = $cgi->param('public');
	my $ml_name = $cgi->param('ml_name');

	unless( $user->can_modify($git) ) {
		$panel->add_error( gettext('You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights') );
		return 0;
	}

	unless( defined $public and defined $ml_name ) {
		$panel->add_error( gettext('CGI error !') );
		return 0;
	}

	if($public != $git->is_public) {
		if($public == 1) {
			$git->set_public();
		} else {
			$git->set_private();
		}
		$git->set_status(Vhffs::Constants::WAITING_FOR_MODIFICATION);
	}

	if($ml_name =~ /^\s*$/ or Vhffs::Functions::valid_mail($ml_name)) {
		if($ml_name ne $git->get_ml_name) {
			$git->set_ml_name($ml_name);
			$git->set_status( Vhffs::Constants::WAITING_FOR_MODIFICATION );
		}
	} else {
		$panel->add_error( gettext('Invalid mailing list address') );
		return 0;
	}

	if($git->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION) {
		if($git->commit > 0) {
			my $url = '?do=groupview;group='.$git->get_group->get_groupname.';msg='.gettext('Modifications applied. Please wait while your repository is being updated');
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
	unless( defined($group) ) {
		$panel->render('misc/message.tt', { message => gettext('You have to select a group first') } );
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
	$panel->set_title( sprintf(gettext('Git repositories for %s'), $group->get_groupname) );

	my $git = Vhffs::Panel::Git::getall_per_group( $vhffs, $group->get_gid );
	if($git < 0) {
		$panel->render( 'misc/message.tt', { message => gettext('Unable to get Git repositories') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'Git repositories',
	  group => $group,
	  list => $git,
	  help_url => $vhffs->get_config->get_service('git')->{url_doc},
	  type => 'git'
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
		  search_title => gettext('Git search'),
		  type => 'git'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all git repositories');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_git( $vhffs , $name );
	$vars->{type} = 'git';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Git repositories administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_git_category() ] } );
}

1;
