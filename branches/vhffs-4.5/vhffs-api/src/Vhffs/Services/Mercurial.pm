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

# This file is a part of VHFFS4 Hosting Platform
# Please respect the licence of this file and the whole software

use strict;
use utf8;

package Vhffs::Services::Mercurial;

use base qw(Vhffs::Object);
use Vhffs::Group;
use DBI;

sub check_name($) {
	my $name = shift;
	return ($name =~ /^[a-z0-9]+\/[a-z0-9\-_]{3,64}$/);
}

sub supports_notifications {
	return 1;
}

sub _new {
	my ($class, $vhffs, $mercurial_id, $reponame, $owner_uid, $owner_gid, $public, $ml_name, $oid, $date_creation, $description, $state) = @_;

	my $self = $class->SUPER::_new($vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_MERCURIAL);
	return undef unless(defined $self);

	$self->{mercurial_id} = $mercurial_id;
	$self->{reponame} = $reponame;
	$self->{public} = $public;
	$self->{ml_name} = $ml_name;

	return $self;
}

sub create {
	my ($vhffs, $rname, $description, $user, $group) = @_;

	return undef unless(defined($user) && defined($group));
	return undef unless(check_name($rname));

	my $mercurial;

	my $dbh = $vhffs->get_db();
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	eval {
		my $parent = Vhffs::Object::create($vhffs, $user->get_uid, $group->get_gid, $description, undef, Vhffs::Constants::TYPE_MERCURIAL);

		die('Unable to create parent object') unless(defined $parent);

		my $sql = 'INSERT INTO vhffs_mercurial(reponame, public, ml_name, object_id) VALUES(?, 1, \'\', ?)';
		my $sth = $dbh->prepare($sql);
		$sth->execute($rname, $parent->get_oid) or return undef;

		$dbh->commit;
		$mercurial = get_by_reponame($vhffs, $rname);
	};

	if($@) {
		warn 'Unable to create mercurial repository '.$rname.': '.$@."\n";
		$dbh->rollback;
	}

	return $mercurial;
}

=head2 fill_object

See C<Vhffs::Object::fill_object>.

=cut
sub fill_object {
	my ($class, $obj) = @_;
	my $sql = q{SELECT mercurial_id, reponame, public, ml_name FROM vhffs_mercurial
		WHERE object_id = ?};
	return $class->SUPER::_fill_object($obj, $sql);
}

sub getall {
	my ($vhffs, $state, $name, $group) = @_;

	my $mercurial = [];
	my @params;

	my $sql = 'SELECT m.mercurial_id, m.reponame, o.owner_uid, o.owner_gid, m.public, m.ml_name, o.object_id, o.date_creation, o.description, o.state
		FROM vhffs_mercurial m INNER JOIN vhffs_object o ON m.object_id = o.object_id';

	if(defined $state) {
		$sql .= ' AND o.state = ?';
		push(@params, $state);
	}
	if(defined $name) {
		$sql .= ' AND m.reponame LIKE ?';
		push(@params, '%'.$name.'%');
	}
	if(defined($group)) {
		$sql .= ' AND o.owner_gid = ?';
		push(@params, $group->get_gid);
	}
	$sql .= ' ORDER BY m.reponame';

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare($sql);
	$sth->execute(@params) or return undef;

	while(my $s = $sth->fetchrow_arrayref()) {
		push(@$mercurial, _new Vhffs::Services::Mercurial($vhffs, @$s));
	}
	return $mercurial;
}

sub get_by_reponame($$) {
	my ($vhffs, $reponame) = @_;
	my @params;

	my $sql = 'SELECT m.mercurial_id, m.reponame, o.owner_uid, o.owner_gid, m.public, m.ml_name, o.object_id, o.date_creation, o.description, o.state FROM vhffs_mercurial m
		INNER JOIN vhffs_object o ON o.object_id = m.object_id WHERE m.reponame = ?';

	my $dbh = $vhffs->get_db();

	return undef unless(@params = $dbh->selectrow_array($sql, undef, $reponame));

	return _new Vhffs::Services::Mercurial($vhffs, @params);
}

sub commit {
	my $self = shift;

	my $dbh = $self->get_db;
	my $sql = 'UPDATE vhffs_mercurial SET public = ?, ml_name = ? WHERE mercurial_id = ?';
	$dbh->do($sql, undef, $self->{public}, $self->{ml_name}, $self->{mercurial_id});

	$self->SUPER::commit;
}

sub set_public {
	my $self = shift;
	$self->{'public'} = 1;
}

sub set_private {
	my $self = shift;
	$self->{'public'} = 0;
}

sub set_ml_name {
	my ($self, $ml_name) = @_;
	return -1 unless(Vhffs::Functions::valid_mail($ml_name) || $ml_name =~ /^\s*$/);
	$self->{ml_name} = $ml_name;
}

sub is_public {
	my $self = shift;
	return $self->{'public'};
}

sub get_label {
	my $self = shift;
	return $self->{reponame};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_service('mercurial');
}

sub get_reponame {
	my $self = shift;
	return $self->{'reponame'};
}

sub get_ml_name {
	my $self = shift;
	return $self->{ml_name};
}

sub get_dir {
	my $self = shift;
	return $self->get_base_dir.'/'.$self->get_reponame;
}

=head2 get_base_dir

	my $basedir = $mercurial->get_base_dir();

Returns the directory containing all the repositories.

=cut
sub get_base_dir {
	my $self = shift;
	return $self->get_vhffs->get_config->get_datadir.'/mercurial/mercurialroot';
}

1;
