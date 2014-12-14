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

package Vhffs::Panel::Bazaar;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Services::Bazaar;
use Vhffs::Constants;
use Vhffs::Functions;


=pod

=head2 getall_per_group

	$bazaar = Vhffs::Panel::Bazaar::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all bazaar repos owned by
a given group.

=cut


sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT s.object_id AS oid, s.reponame AS displayname, o.state FROM vhffs_bazaar s INNER JOIN vhffs_object o ON s.object_id = o.object_id WHERE o.owner_gid = ? ORDER BY s.reponame';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $bazaar = [];
	while(my $s = $sth->fetchrow_hashref) {
		$s->{active} = ($s->{state} == Vhffs::Constants::ACTIVATED);
		$s->{refused} = ($s->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$s->{state} = Vhffs::Functions::status_string_from_status_id($s->{state});
		push @$bazaar, $s;
	}
	return $bazaar;
}

sub get_repos_per_group {
	my ($vhffs, $gid, $public_only) = @_;
	$public_only = 1 unless(defined $public_only);

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT g.reponame, o.description FROM vhffs_bazaar g INNER JOIN vhffs_object o ON o.object_id = g.object_id '.
	  'WHERE '.($public_only ? 'public = 1 AND ' : '').'o.owner_gid = ? AND o.state = ?';
	return $dbh->selectall_arrayref($sql, { Slice => {} }, $gid, Vhffs::Constants::ACTIVATED);
}

sub search_bazaar {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT bazaar.reponame as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_bazaar bazaar '.
	  'INNER JOIN vhffs_object o ON (o.object_id = bazaar.object_id) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) ';

	if( defined $name ) {
		$sql .= 'WHERE bazaar.reponame LIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY bazaar.reponame';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

sub create_bazaar {
	my ($vhffs, $repo, $description, $user, $group) = @_;
	return -1 unless defined $user;
	return -2 unless defined $group;

	my $bazaar = Vhffs::Services::Bazaar::create( $vhffs, $repo, $description, $user, $group );
	return -1 unless defined $bazaar;

	return $bazaar;
}

sub create {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group and $user->can_modify( $group ) ) {
		$panel->render('message/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}
	$panel->set_group( $group );

	my $submitted = $cgi->param('bazaar_submit');
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
			$panel->add_error( gettext('Invalid reponame. It must contain between 3 and 64 characters, only lowercase letters and numbers') ) unless Vhffs::Services::Bazaar::check_name($fullreponame);
			$panel->add_error( gettext('You must enter a description') ) unless $description !~ /^\s*$/;
		}

		unless( $panel->has_errors() ) {
			my $bazaar = Vhffs::Panel::Bazaar::create_bazaar( $vhffs, $fullreponame, $description, $user, $group );
			if( defined $bazaar ) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The Bazaar object was successfully created !');
				$panel->redirect($url);
				return;
			}

			$panel->add_error( gettext('An error occured while creating the bazaar repository') );
		}

		$vars->{reponame} = $reponame;
		$vars->{description} = $description;
	}

	$vars->{group} = $group;
	$panel->render('bazaar/create.tt', $vars);
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

	my $bazaar = Vhffs::Services::Bazaar::get_by_reponame( $vhffs , $repo_name );
	unless( defined $bazaar ) {
		$panel->render('misc/message.tt', { message => gettext( 'Cannot get informations on this object' ) } );
		return;
	}
	$panel->set_group( $bazaar->get_group );

	unless( $user->can_view( $bazaar ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	save_prefs($panel, $bazaar) if defined $cgi->param('save_prefs_submit');

	$panel->set_title( gettext("Modify Bazaar repository") );
	my $vars = {};
	$vars->{repository} = $bazaar;
	$vars->{notify_from} = 'Please finish bazaar implementation'; # $bazaar->get_config->{notify_from};
	$vars->{type} = 'bazaar';
	$panel->render( 'scm/prefs.tt', $vars );
}

sub save_prefs {
	my $panel = shift;
	my $bazaar = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	my $public = $cgi->param('public');
	my $ml_name = $cgi->param('ml_name');

	unless( $user->can_modify($bazaar) ) {
		$panel->add_error( gettext('You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights') );
		return 0;
	}

	unless( defined $public and defined $ml_name ) {
		$panel->add_error( gettext('CGI error !') );
		return 0;
	}

	if($public != $bazaar->is_public) {
		if($public == 1) {
			$bazaar->set_public();
		} else {
			$bazaar->set_private();
		}
		$bazaar->set_status(Vhffs::Constants::WAITING_FOR_MODIFICATION);
	}

	if($ml_name =~ /^\s*$/ or Vhffs::Functions::valid_mail($ml_name)) {
		if($ml_name ne $bazaar->get_ml_name) {
			$bazaar->set_ml_name($ml_name);
			$bazaar->set_status( Vhffs::Constants::WAITING_FOR_MODIFICATION );
		}
	} else {
		$panel->add_error( gettext('Invalid mailing list address') );
		return 0;
	}

	if($bazaar->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION) {
		if($bazaar->commit > 0) {
			my $url = '?do=groupview;group='.$bazaar->get_group->get_groupname.';msg='.gettext('Modifications applied. Please wait while your repository is being updated');
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
	$panel->set_title( sprintf(gettext('Bazaar repositories for %s'), $group->get_groupname) );
	my $bazaar = Vhffs::Panel::Bazaar::getall_per_group( $vhffs, $group->get_gid );
	if($bazaar < 0) {
		$panel->render('misc/message.tt', { message => gettext('Unable to get Bazaar repositories') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'Bazaar repositories',
	  group => $group,
	  list => $bazaar,
	  help_url => 'Finish implementation', # $vhffs->get_config->get_service('bazaar')->{url_doc},
	  type => 'bazaar'
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
		  search_title => gettext('Bazaar search'),
		  type => 'bazaar'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all bazaar repositories');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_bazaar( $vhffs , $name );
	$vars->{type} = 'bazaar';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('Bazaar repositories administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_bazaar_category() ] } );
}

1;
