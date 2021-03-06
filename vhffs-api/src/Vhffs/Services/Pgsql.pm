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


# This file is a part of VHFFS4 platofmrm

=pod

=head1 NAME

Vhffs::Services::Pgsql - Handle PostgreSQL databases in VHFFS.

=head1 SYNOPSIS

TODO

=head1 METHODS

=cut

use strict;
use utf8;

package Vhffs::Services::Pgsql;

use base qw(Vhffs::Object);
use DBI;

=pod

=head2 check_dbname

	die('Bad DB name') unless(Vhffs::Services::Pgsql::check_dbname($dbname));

Indicates wether a DB name is valid or not (3 to 32 alphanumeric chars, underscore
allowed except at begining and end).

=cut
sub check_dbname($) {
	my $dbname = shift;
	return ( $dbname =~ /^[a-z0-9][a-z0-9\_]{1,30}[a-z0-9]$/ );
}

=pod

=head2 check_dbuser

	die('Bad DB username') unless(Vhffs::Services::Pgsql::check_dbuser($user));

Indicates wether a DB user name is valid or not (3 to 32 lowercase alphanumeric chars, underscore
allowed except at begining and end).

=cut
sub check_dbuser($) {
	return check_dbname($_[0]);
}

=pod

=head2 check_dbpass

	die('Bad DB pass') unless(Vhffs::Services::Pgsql::check_dbpass($pass));

Indicates wether a DB password is valid or not (at least three chars).

=cut
sub check_dbpass($) {
	my $dbpass = shift;
	return ( $dbpass =~ /^.{3,}$/);
}

sub _new {
	my ($class, $vhffs, $pgsql_id, $owner_gid, $dbname, $dbuser, $dbpass, $oid, $owner_uid, $date_creation, $state, $description) = @_;
	my $self = $class->SUPER::_new($vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_PGSQL);
	return undef unless(defined $self);

	$self->{pgsql_id} = $pgsql_id;
	$self->{dbname} = $dbname;
	$self->{dbuser} = $dbuser;
	$self->{dbpass} = $dbpass;
	return $self;
}

=pod

=head2 create

	my $psql = Vhffs::Services::Pgsql::create($vhffs, $dbname, $dbuser, $dbpass, $description, $user, $group);
	die("Unable to create Postgre Service\n") unless(defined $psql);

Create a new Postgres services and return the corresponding fully functional object.

=cut
sub create {
	my ($vhffs, $dbname, $dbuser, $dbpass, $description, $user, $group) = @_;
	return undef unless(defined($user) && defined($group));
	return undef unless(check_dbname($dbname) && check_dbpass($dbpass) && check_dbuser($dbuser));

	my $pg;
	my $dbh = $vhffs->get_db();
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	eval {

		my $parent = Vhffs::Object::create($vhffs, $user->get_uid, $group->get_gid, $description, undef, Vhffs::Constants::TYPE_PGSQL);
		die('Unable to create parent object') unless defined ($parent);

		my $sql = 'INSERT INTO vhffs_pgsql(dbname, dbuser, dbpass, object_id) VALUES(?, ?, ?, ?)';
		my $sth = $dbh->prepare($sql);
		$sth->execute($dbname, $dbuser, $dbpass, $parent->get_oid);

		$dbh->commit;
		$pg = get_by_dbname($vhffs, $dbname);
	};

	if($@) {
		warn 'Unable to create PostgreSQL database '.$dbname.': '.$@."\n";
		$dbh->rollback;
	}

	return $pg;
}

=head2 fill_object

See C<Vhffs::Object::fill_object>.

=cut
sub fill_object {
	my ($class, $obj) = @_;
	my $sql = q{SELECT pgsql_id, dbname, dbuser, dbpass FROM vhffs_pgsql
		WHERE object_id = ?};
	return $class->SUPER::_fill_object($obj, $sql);
}

sub getall {
	my ($vhffs, $state, $name, $group) = @_;

	my $postgres = [];
	my @params;

	my $sql = 'SELECT p.pgsql_id, o.owner_gid, p.dbname, p.dbuser, p.dbpass, o.object_id, o.owner_uid, o.date_creation, o.state, o.description
		FROM vhffs_pgsql p INNER JOIN vhffs_object o ON o.object_id = p.object_id';
	if(defined $state) {
		$sql .= ' AND o.state = ?';
		push(@params, $state);
	}
	if(defined $name) {
		$sql .= ' AND p.dbname LIKE ?';
		push(@params, '%'.$name.'%');
	}
	if(defined $group) {
		$sql .= ' AND o.owner_gid = ?';
		push(@params, $group->get_gid);
	}
	$sql .= ' ORDER BY p.dbname';

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare($sql);
	$sth->execute(@params) or return undef;

	while(my $row = $sth->fetchrow_arrayref()) {
		push(@$postgres, _new Vhffs::Services::Pgsql($vhffs, @$row));
	}

	return $postgres;
}

=pod

=head2 get_by_dbname

	my $pg = Vhffs::Services::Pgsql::get_by_dbname($vhffs, $dbname);
	die("No database with this name") unless(defined $pg);

Fetches the pg database whose name is C<$dbname>.

=cut
sub get_by_dbname($$) {
	my ($vhffs, $dbname) = @_;

	my $sql = q{SELECT m.pgsql_id, o.owner_gid, m.dbname, m.dbuser, m.dbpass, o.object_id, o.owner_uid, o.date_creation, o.state, o.description FROM vhffs_pgsql m INNER JOIN vhffs_object o ON o.object_id = m.object_id WHERE m.dbname = ?};
	my $dbh = $vhffs->get_db();
	my @params;
	return undef unless(@params = $dbh->selectrow_array($sql, undef, $dbname));

	return _new Vhffs::Services::Pgsql($vhffs, @params);

}

sub commit {
	my $self = shift;

	my $sql = 'UPDATE vhffs_pgsql SET dbuser = ?, dbpass = ? WHERE pgsql_id = ?';
	my $sth = $self->get_db()->prepare( $sql );
	$sth->execute($self->{dbuser}, $self->{dbpass}, $self->{pgsql_id});

	return $self->SUPER::commit;
}

sub get_dbusername {
	my $self = shift;
	return $self->{'dbuser'};
}

sub get_dbname {
	my $self = shift;
	return $self->{'dbname'};
}

=head2 get_label

See C<Vhffs::Object::get_label>.

=cut
sub get_label {
	my $self = shift;
	return $self->{dbname};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_service('pgsql');
}

sub get_dbpassword {
	my $self = shift;
	return $self->{'dbpass'};
}

sub set_dbpassword {
	my $self = shift;
	my $value = shift;
	return -1 unless check_dbpass( $value );
	$self->{'dbpass'} = $value;
	return 1;
}

sub blank_password {
	my $self = shift;

	my $request = $self->get_db->prepare('UPDATE vhffs_pgsql SET dbpass=\'\' WHERE pgsql_id=?') or return -1;
	$request->execute( $self->{pgsql_id} );

	$self->{'dbpass'} = '';
	return 1;
}

1;
