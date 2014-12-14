#!%PERL%
# Copyright (c) vhffs project and its contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name of vhffs nor the names of its contributors
#    may be used to endorse or promote products derived from this
#    software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# This file is a part of VHFFS4 Hosting Platform
# Please respect the licence of this file and the whole software


=pod

=head1 NAME

Vhffs::Services::Repository - Handle download repositories in VHFFS

=head1 SYNOPSIS

TODO

=head1 METHODS

=cut

use strict;
use utf8;

package Vhffs::Services::Repository;

use base qw(Vhffs::Object);
use DBI;

sub check_name($) {
	my $name = shift;
	return ($name =~ /^[a-z0-9]+$/);
}

sub _new {
	my ($class, $vhffs, $repository_id, $name, $owner_uid, $owner_gid, $quota, $quota_used, $oid, $date_creation, $description, $state) = @_;

	my $self = $class->SUPER::_new($vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_REPOSITORY);
	return undef unless defined $self;

	$self->{repository_id} = $repository_id;
	$self->{name} = $name;
	$self->{quota} = $quota;
	$self->{quota_used} = $quota_used;

	return $self;
}

=pod

=head2 create

	my $repo = Vhffs::Services::Repository::create($vhffs, $rname, $description, $user, $group);
	die('Unable to create repository) unless(defined $repo);

Creates a new download repository in database and return the corresponding
fully functional object.

=cut
sub create {
	my ($vhffs, $rname, $description, $user, $group) = @_;
	return undef unless defined $user and defined $group;
	return undef unless check_name($rname);

	my $repo;
	my $dbh = $vhffs->get_db();
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	eval {
		my $parent = Vhffs::Object::create($vhffs, $user->get_uid, $group->get_gid, $description, undef, Vhffs::Constants::TYPE_REPOSITORY);
		die('Unable to create parent object') unless(defined $parent);

		my $sql = 'INSERT INTO vhffs_repository(name, quota, quota_used, object_id) VALUES(?, ?, 0, ?)';

		#Quota
		my $config = $vhffs->get_config->get_service('repository');
		my $quota = $config->{'default_quota'} if defined($config);
		$quota = 100 unless defined $quota;

		my $sth = $dbh->prepare($sql);
		$sth->execute($rname, $quota, $parent->get_oid);

		$dbh->commit;
		$repo = get_by_reponame($vhffs, $rname);
	};

	if($@) {
		warn 'Unable to create repository '.$rname.': '.$@."\n";
		$dbh->rollback;
	}

	return $repo;
}

=head2 fill_object

See C<Vhffs::Object::fill_object

=cut
sub fill_object {
	my ($class, $obj) = @_;
	my $sql = q{SELECT repository_id, name, quota, quota_used
		FROM vhffs_repository WHERE object_id = ?};
	return $class->SUPER::_fill_object($obj, $sql);
}

sub getall {
	my ($vhffs, $state, $name, $group) = @_;

	my $repos = [];
	my @params;

	my $sql = 'SELECT r.repository_id, r.name, o.owner_uid, o.owner_gid, r.quota, r.quota_used, o.object_id, o.date_creation, o.description, o.state
		FROM vhffs_repository r INNER JOIN vhffs_object o ON o.object_id = r.object_id';
	if(defined $state) {
		$sql .= ' AND o.state = ?';
		push(@params, $state);
	}
	if(defined $name) {
		$sql .= ' AND r.name LIKE ?';
		push(@params, '%'.$name.'%');
	}
	if(defined $group) {
		$sql .= ' AND o.owner_gid = ?';
		push(@params, $group->get_gid);
	}
	$sql .= ' ORDER BY r.name';

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare($sql);
	$sth->execute(@params) or return undef;

	while(my $r = $sth->fetchrow_arrayref()) {
		push(@$repos, _new Vhffs::Services::Repository($vhffs, @$r));
	}
	return $repos;
}

=pod

=head2 get_by_reponame

	my $repo = Vhffs::Services::Repository::get_by_reponame($vhffs, $name);
	die('Repository not found') unless(defined $repo);

Fetches an existing repository.

=cut
sub get_by_reponame($$) {
	my ($vhffs, $name) = @_;

	my @params;

	my $sql = 'SELECT r.repository_id, r.name, o.owner_uid, o.owner_gid, r.quota, r.quota_used, o.object_id, o.date_creation, o.description, o.state FROM vhffs_repository r INNER JOIN vhffs_object o ON o.object_id = r.object_id WHERE r.name = ?';

	my $dbh = $vhffs->get_db();
	return undef unless(@params = $dbh->selectrow_array($sql, undef, $name));

	return _new Vhffs::Services::Repository($vhffs, @params);
}

sub commit {
	my $self = shift;

	my $query = 'UPDATE vhffs_repository SET name=?, quota=?, quota_used=? WHERE repository_id=?';
	my $request = $self->get_db->prepare($query);
	$request->execute( $self->{'name'}, $self->{'quota'}, $self->{'quota_used'}, $self->{'repository_id'} ) or return -1;

	return $self->SUPER::commit;
}

sub get_label {
	my $self = shift;
	return $self->{name};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_service('repository');
}

sub get_name {
	my $self = shift;
	return $self->{'name'};
}

sub get_quota {
	my $self = shift;
	return $self->{'quota'};
}

sub set_quota {
	my ($self, $value) = @_;
	$self->{'quota'} = $value;
}

sub get_quota_used {
	my $self = shift;
	return $self->{'quota_used'};
}

sub set_quota_used {
	my ($self, $value) = @_;
	$self->{'quota_used'} = $value;
}

sub get_dir {
	my $self = shift;
	return $self->get_vhffs->get_config->get_datadir.'/repository/'.$self->get_name;
}

1;

__END__

=head1 AUTHORS

Sylvain Rochet < gradator at gradator dot net >

Sebastien Le Ray < beuss at tuxfamily dot net >
