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

package Vhffs::Panel::Pgsql;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Constants;
use Vhffs::Services::Pgsql;


sub search_pgsql {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT p.dbname as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_pgsql p '.
	  'INNER JOIN vhffs_object o ON (o.object_id = p.object_id) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) ';

	if( defined $name ) {
		$sql .= 'WHERE p.dbname LIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY label';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref( $sql, { Slice => {} }, @params);
}


=pod

=head2 getall_per_group

	$pgsql = Vhffs::Panel::Postgres::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all PgSQL DBs owned by
a given group.

=cut


sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT p.object_id AS oid, p.dbname AS displayname, o.state FROM vhffs_pgsql p INNER JOIN vhffs_object o ON p.object_id = o.object_id WHERE o.owner_gid = ? ORDER BY p.dbname';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $pgsql = [];
	while(my $p = $sth->fetchrow_hashref) {
		$p->{active} = ($p->{state} == Vhffs::Constants::ACTIVATED);
		$p->{refused} = ($p->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$p->{state} = Vhffs::Functions::status_string_from_status_id($p->{state});
		push @$pgsql, $p;
	}
	return $pgsql;
}

sub create_pgsql {
	my( $vhffs , $dbname , $user , $group , $dbuser , $dbpass, $description ) = @_;
	return -1 unless defined $user;
	return -2 unless defined $group;

	my $pgsql = Vhffs::Services::Pgsql::create($vhffs, $dbname, $dbuser, $dbpass, $description, $user, $group);
	return undef unless defined $pgsql;

	return $pgsql;
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

	my $submitted = defined($cgi->param('pgsql_submit'));
	my $dbsuffix = '';
	my $description = '';
	my $dbpass = '';
	my $vars = {};

	if( $submitted ) {
		$dbsuffix = $cgi->param('db_suffix');
		my $dbname = $group->get_groupname.'_'.$dbsuffix;
		my $dbuser = $dbname;
		$dbpass = $cgi->param('db_pass');
		$description = Encode::decode_utf8( scalar $cgi->param('description') );

		unless( defined $dbpass and defined $dbsuffix and defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
		} else {
			$panel->add_error( gettext('You must enter a description') ) unless $description !~ /^\s*$/;
			$panel->add_error( gettext('Invalid database name, it must contain only numbers, lowercase letters and underscore (the latter isn\'t allowed in first or last position) and be between 3 and 32 characters.') ) unless Vhffs::Services::Pgsql::check_dbname($dbname);
			$panel->add_error( gettext('Invalid password. It must contain at least 3 characters') ) unless Vhffs::Services::Pgsql::check_dbpass($dbpass);
		}

		unless( $panel->has_errors() ) {
			if(defined Vhffs::Panel::Pgsql::create_pgsql($vhffs, $dbname, $user, $group, $dbuser, $dbpass, $description)) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The PostgreSQL DB was successfully created !');
				$panel->redirect($url);
				return;
			} else {
				$panel->add_error( 'An error occured while creating the object.' );
			}
		}

		$vars->{db_suffix} = $dbsuffix;
		$vars->{description} = $description;
	}

	$vars->{group} = $group;
	$panel->render('pgsql/create.tt', $vars);
}

sub prefs {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $dbname = $cgi->param('name');
	unless( defined $dbname ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		return;
	}

	my $pgsql = Vhffs::Services::Pgsql::get_by_dbname( $vhffs , $dbname );
	unless( defined $pgsql ) {
		$panel->render('misc/message.tt', { message => gettext('Cannot get informations on this object') } );
		return;
	}
	$panel->set_group( $pgsql->get_group );

	unless( $user->can_view( $pgsql ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	if(defined $cgi->param('save_prefs_submit')) {
		return if save_prefs($panel, $pgsql);
	}

	my $vars = { db => $pgsql, type => 'pgsql' };

	$panel->set_title( gettext('PostgreSQL Administration') );
	$panel->render('database/prefs.tt', $vars);
}

sub save_prefs {
	my $panel = shift;
	my $pgsql = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	unless( $user->can_modify($pgsql) ) {
		$panel->add_error( gettext('You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights') );
		return 0;
	}

	my $new_passwd = $cgi->param('newpassword');
	unless(defined $new_passwd) {
		$panel->add_error( gettext('CGI Error !') );
		return 0;
	}

	if($pgsql->set_dbpassword($new_passwd) < 0) {
		$panel->add_error( gettext('Bad password, should be at least 3 chars') );
		return 0;
	}

	$pgsql->set_status( Vhffs::Constants::WAITING_FOR_MODIFICATION );
	if($pgsql->commit < 0) {
		$panel->add_error( gettext('Unable to apply changes') );
		$pgsql->blank_password;
		return 0;
	}

	my $url = '?do=groupview;group='.$pgsql->get_group->get_groupname.';msg='.gettext('Password change request taken in account, please wait for processing');
	$panel->redirect($url);
	return 1;
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

	unless( $group->get_status == Vhffs::Constants::ACTIVATED ) {
		$panel->render( 'misc/message.tt', { message => gettext('This group is not activated yet') } );
		return;
	}

	unless( $user->can_view($group) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}

	$panel->set_group( $group );
	$panel->set_title( sprintf(gettext('PostgreSQL DBs for %s'), $group->get_groupname) );
	my $pgsql = Vhffs::Panel::Pgsql::getall_per_group( $vhffs, $group->get_gid );
	if($pgsql < 0) {
		$panel->render('misc/message.tt', { message => gettext('Unable to get PostgreSQL databases.') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'PostgreSQL databases',
	  group => $group,
	  list => $pgsql,
	  help_url => $vhffs->get_config->get_service('pgsql')->{url_doc},
	  type => 'pgsql'
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
		  search_title => gettext('PostgreSQL search'),
		  type => 'pgsql'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all PostgreSQL databases');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_pgsql( $vhffs , $name );
	$vars->{type} = 'pgsql';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('PostgreSQL databases administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_pgsql_category() ] } );
}

1;
