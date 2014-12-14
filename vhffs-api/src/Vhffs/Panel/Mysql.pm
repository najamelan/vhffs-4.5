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

package Vhffs::Panel::Mysql;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Services::Mysql;
use Vhffs::Constants;

=pod

=head1 NAME

Vhffs::Panel::Mysql - Lightweight objects for MySQL DBs handling in VHFFS panel.

=head1 METHODS

=cut


sub search_mysql {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT m.dbname as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_mysql m '.
	  'INNER JOIN vhffs_object o ON (o.object_id = m.object_id) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) ';

	if( defined $name ) {
		$sql .= 'WHERE m.dbname LIKE ? ';
		push(@params, '%'.lc($name).'%' );
	}

	$sql .= 'ORDER BY label';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

sub create_mysql($$$$$$$) {
	my( $vhffs , $dbname , $user , $group , $dbuser, $dbpass, $description ) = @_;
	return undef unless defined $user and defined $group;

	my $mysql = Vhffs::Services::Mysql::create($vhffs, $dbname, $dbuser, $dbpass, $description, $user, $group);
	return undef unless defined $mysql;


	return $mysql;
}

=pod

=head2 getall_per_group

	$mysql = Vhffs::Panel::Mysql::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all MySQL DBs owned by
a given group.

=cut


sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT m.object_id AS oid, m.dbname AS displayname, o.state FROM vhffs_mysql m INNER JOIN vhffs_object o ON m.object_id = o.object_id WHERE o.owner_gid = ? ORDER BY m.dbname';
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

	my $submitted = defined($cgi->param('mysql_submit'));
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
			$panel->add_error( gettext('Invalid database name, it must contain only numbers, lowercase letters and underscore (the latter isn\'t allowed in first or last position) and be between 3 and 32 characters.') ) unless Vhffs::Services::Mysql::check_dbname($dbname);
			$panel->add_error( gettext('Invalid password. It must contain at least 3 characters') ) unless Vhffs::Services::Mysql::check_dbpass($dbpass);
		}

		unless( $panel->has_errors() ) {
			if(defined Vhffs::Panel::Mysql::create_mysql($vhffs, $dbname, $user, $group, $dbuser, $dbpass, $description)) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The MySQL DB was successfully created !');
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
	$panel->render('mysql/create.tt', $vars);
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

	my $mysql = Vhffs::Services::Mysql::get_by_dbname( $vhffs , $dbname );
	unless( defined $mysql ) {
		$panel->render('misc/message.tt', { message => gettext('Cannot get informations on this object') } );
		return;
	}
	$panel->set_group( $mysql->get_group );

	unless( $user->can_view( $mysql ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	if(defined $cgi->param('save_prefs_submit')) {
		return if save_prefs($panel, $mysql);
	}

	my $vars = { db => $mysql, type => 'mysql' };

	$panel->set_title( gettext('MySQL Administration') );
	$panel->render('database/prefs.tt', $vars);
}

sub save_prefs {
	my $panel = shift;
	my $mysql = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $user = $panel->{'user'};

	unless( $user->can_modify($mysql) ) {
		$panel->add_error( gettext('You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights') );
		return 0;
	}

	my $new_passwd = $cgi->param('newpassword');
	unless(defined $new_passwd) {
		$panel->add_error( gettext('CGI Error !') );
		return 0;
	}

	if($mysql->set_dbpassword($new_passwd) < 0) {
		$panel->add_error( gettext('Bad password, should be at least 3 chars') );
		return 0;
	}

	$mysql->set_status( Vhffs::Constants::WAITING_FOR_MODIFICATION );
	if($mysql->commit < 0) {
		$panel->add_error( gettext('Unable to apply changes') );
		$mysql->blank_password;
		return 0;
	}

	my $url = '?do=groupview;group='.$mysql->get_group->get_groupname.';msg='.gettext('Password change request taken in account, please wait for processing');
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
	$panel->set_title( sprintf(gettext('MySQL DBs for %s'), $group->get_groupname) );
	my $mysql = Vhffs::Panel::Mysql::getall_per_group( $vhffs, $group->get_gid );
	if($mysql < 0) {
		$panel->render('misc/message.tt', { message => gettext('Unable to get MySQL databases.') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'MySQL databases',
	  group => $group,
	  list => $mysql,
	  help_url => $vhffs->get_config->get_service('mysql')->{url_doc},
	  type => 'mysql'
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
		  search_title => gettext('MySQL search'),
		  type => 'mysql'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all MySQL databases');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_mysql( $vhffs , $name );
	$vars->{type} = 'mysql';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('MySQL databases administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_mysql_category() ] } );
}

1;
