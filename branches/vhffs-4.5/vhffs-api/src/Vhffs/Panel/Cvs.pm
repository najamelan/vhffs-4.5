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

package Vhffs::Panel::Cvs;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Services::Cvs;
use Vhffs::Constants;

sub search_cvs {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT cvs.cvsroot as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_cvs cvs '.
	  'INNER JOIN vhffs_object o ON (o.object_id = cvs.object_id) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) ';

	if( defined $name ) {
		$sql .= 'WHERE cvs.cvsroot LIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY cvs.cvsroot';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}


sub create_cvs {
	my( $vhffs, $cvsroot, $description, $user, $group ) = @_;
	return undef unless defined $user;
	return undef unless defined $group;

	my $cvs = Vhffs::Services::Cvs::create($vhffs, $cvsroot, $description, $user, $group);
	return undef unless defined $cvs;


	return $cvs;
}

=pod

=head2 getall_per_group

	$cvs = Vhffs::Panel::Cvs::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all CVS repos owned by
a given group.

=cut


sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT c.object_id AS oid, c.cvsroot AS displayname, o.state FROM vhffs_cvs c INNER JOIN vhffs_object o ON c.object_id = o.object_id WHERE o.owner_gid = ? ORDER BY c.cvsroot';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $cvs = [];
	while(my $c = $sth->fetchrow_hashref) {
		$c->{active} = ($c->{state} == Vhffs::Constants::ACTIVATED);
		$c->{refused} = ($c->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$c->{state} = Vhffs::Functions::status_string_from_status_id($c->{state});
		push @$cvs, $c;
	}
	return $cvs;
}

sub get_repos_per_group {
	my ($vhffs, $gid, $public_only) = @_;
	$public_only = 1 unless(defined $public_only);

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT c.cvsroot, o.description FROM vhffs_cvs c INNER JOIN vhffs_object o ON o.object_id = c.object_id '.
	  'WHERE '.($public_only ? 'c.public = true AND ' : '').'o.owner_gid = ? AND o.state = ?';
	return $dbh->selectall_arrayref($sql, { Slice => {} }, $gid, Vhffs::Constants::ACTIVATED);
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

	my $submitted = defined($cgi->param('cvs_submit'));
	my $reponame = '';
	my $description = '';
	my $vars = {};

	if($submitted) {
		$reponame = $cgi->param('reponame');
		my $fullreponame = $group->get_groupname.'/'.$reponame;
		$description = Encode::decode_utf8( scalar $cgi->param('description') );

		unless( defined $reponame and defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
		} else {
			$panel->add_error( gettext('Invalid reponame. It must contain between 3 and 64 characters, only lowercase letters and numbers') ) unless Vhffs::Services::Cvs::check_name($fullreponame);
			$panel->add_error( gettext('You must enter a description') ) unless $description !~ /^\s*$/;
		}

		unless( $panel->has_errors() ) {
			#Create CVS
			my $cvs = Vhffs::Panel::Cvs::create_cvs( $vhffs, $fullreponame, $description, $user , $group );
			if( defined $cvs ) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The CVS object was successfully created !');
				$panel->redirect($url);
				return;
			} else {
				$panel->add_error( gettext( 'An error occured while creating the object.It probably already exists' ) );
			}
		}
		$vars->{reponame} = $reponame;
		$vars->{description} = $description;
	}

	$vars->{group} = $group;

	$panel->set_title( gettext('Create a CVS Repository') );
	$panel->render('cvs/create.tt', $vars);
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

	my $cvs = Vhffs::Services::Cvs::get_by_reponame($vhffs, $repo_name);
	unless( defined $cvs ) {
		$panel->render('misc/message.tt', { message => gettext( 'Cannot get informations on this object' ) } );
		return;
	}
	$panel->set_group( $cvs->get_group );

	unless( $user->can_view($cvs) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	if( defined $cgi->param('save_prefs_submit') ) {
		unless( $user->can_modify($cvs) ) {
			$panel->add_error( gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) );
		} elsif( not defined($cgi->param('public')) ) {
			$panel->add_error( gettext("CGI Error !") );
		} else {
			my $public = $cgi->param('public');
			if($public == 1 and not $cvs->is_public) {
				$cvs->set_public;
				$cvs->set_status( Vhffs::Constants::WAITING_FOR_MODIFICATION );
			} elsif($public == 0 and $cvs->is_public) {
				$cvs->set_private;
				$cvs->set_status( Vhffs::Constants::WAITING_FOR_MODIFICATION );
			}

			if($cvs->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION) {
				if($cvs->commit > 0) {
					my $url = '?do=groupview;group='.$cvs->get_group->get_groupname.';msg='.gettext('Modifications applied. Please wait while your repository is being updated');
					$panel->redirect($url);
					return;
				}

				$panel->add_error(gettext('An error occured during CVS repository update'));
			}
		}
	}

	my $vars = {};
	$vars->{repository} = $cvs;
	$vars->{type} = 'cvs';
	$panel->render( 'scm/prefs.tt', $vars );
}

sub index {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group ) {
		$panel->render('misc/message.tt', { message => gettext('You have to select a group first') });
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
	$panel->set_title( sprintf(gettext('CVS repositories for %s'), $group->get_groupname) );
	my $cvs = Vhffs::Panel::Cvs::getall_per_group( $vhffs, $group->get_gid );
	if($cvs < 0) {
		$panel->render('misc/message.tt', { message => gettext('Unable to get CVS repositories') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'CVS repositories',
	  group => $group,
	  list => $cvs,
	  help_url => $vhffs->get_config->get_service('cvs')->{url_doc},
	  type => 'cvs'
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
		  search_title => gettext('CVS search'),
		  type => 'cvs'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all CVS repositories');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_cvs( $vhffs , $name );
	$vars->{type} = 'cvs';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('CVS repositories administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_cvs_category() ] } );
}

1;
