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

=pod

=head1 NAME

Vhffs::Services::Cvs - Handle CVS service in VHFFS

=head1 SYNOPSIS

TODO

=head1 METHODS

=cut

use strict;
use utf8;

package Vhffs::Services::Cvs;

use base qw(Vhffs::Object);
use Vhffs::Group;
use DBI;

=pod

=head2 check_name

	die("Invalid CVS root\n") unless(Vhffs::Services::Cvs::check_name($cvsroot));

Checks whether a cvsroot is valid or not.

=cut
sub check_name($) {
	my $name = shift;
	return ($name =~ /^[a-z0-9]+\/[a-z0-9\-_]{3,64}$/);
}

sub supports_notifications {
	return 0;
}

sub _new {
	my ($class, $vhffs, $cvs_id, $cvsroot, $owner_uid, $owner_gid, $public, $oid, $date_creation, $description, $state) = @_;

	my $self = $class->SUPER::_new($vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_CVS);
	return undef unless(defined $self);

	$self->{cvsroot} = $cvsroot;
	$self->{cvs_id} = $cvs_id;
	$self->{public} = $public;
	return $self;
}

=pod

=head2 create

	my $cvs = Vhffs::Services::Cvs::create($vhffs, $cvsroot, $description, $user, $group);
	die("Unable to create cvs\n") unless($cvs);

Creates a new CVS service in database and returns the corresponding fully functional object.

=cut
sub create {
	my ($vhffs, $cvsroot, $description, $user, $group) = @_;
	return undef unless(defined($user) && defined($group));
	return undef unless(check_name($cvsroot));

	my $cvs;
	my $dbh = $vhffs->get_db();
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;
	eval {

		my $parent = Vhffs::Object::create($vhffs, $user->get_uid, $group->get_gid, $description, undef, Vhffs::Constants::TYPE_CVS);

		die('Unable to create parent object') unless(defined($parent));

		my $sql = 'INSERT INTO vhffs_cvs(cvsroot, public, object_id) VALUES (?, TRUE, ?)';
		my $sth = $dbh->prepare($sql);
		$sth->execute($cvsroot, $parent->get_oid);

		$dbh->commit;
		$cvs = get_by_reponame($vhffs, $cvsroot);
	};

	if($@) {
		warn 'Error creating cvs service: '.$@."\n";
		$dbh->rollback;
	}
	return $cvs;

}

=head2 fill_object

See C<Vhffs::Object::fill_object>.

=cut
sub fill_object {
	my ($class, $obj) = @_;
	my $sql = q{SELECT cvsroot, cvs_id, public FROM vhffs_cvs WHERE object_id = ?};
	return $class->SUPER::_fill_object($obj, $sql);
}

sub getall {
	my ($vhffs, $state, $name, $group) = @_;

	my $cvs = [];
	my @params;

	my $sql = 'SELECT c.cvs_id, c.cvsroot, o.owner_uid, o.owner_gid, c.public, o.object_id, o.date_creation, o.description, o.state
		FROM vhffs_cvs c INNER JOIN vhffs_object o ON c.object_id = o.object_id';

	if(defined $state) {
		$sql .= ' AND o.state=?';
		push(@params, $state);
	}
	if(defined $name) {
		$sql .= ' AND c.cvsroot LIKE ?';
		push(@params, '%'.$name.'%');
	}
	if(defined $group) {
		$sql .= ' AND o.owner_gid=?';
		push(@params, $group->get_gid);
	}
	$sql .= ' ORDER BY c.cvsroot';

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare( $sql );
	$sth->execute(@params) or return undef;

	while(my $s = $sth->fetchrow_arrayref()) {
		push(@$cvs, _new Vhffs::Services::Cvs($vhffs, @$s));
	}
	return $cvs;
}

sub get_by_reponame {
	my($vhffs, $cvsroot) = @_;
	my $sql = 'SELECT c.cvs_id, c.cvsroot, o.owner_uid, o.owner_gid, c.public, c.object_id, o.date_creation, o.description, o.state FROM vhffs_cvs c
		INNER JOIN vhffs_object o ON c.object_id = o.object_id WHERE c.cvsroot = ?';
	my $dbh = $vhffs->get_db();
	my @params;
	return undef unless(@params = $dbh->selectrow_array($sql, undef, $cvsroot));

	return _new Vhffs::Services::Cvs($vhffs, @params);
}

sub commit {
	my $self = shift;

	my $sql = 'UPDATE vhffs_cvs SET cvsroot = ?, public = ? WHERE cvs_id = ?';
	$self->get_db()->do($sql, undef, $self->{'cvsroot'},
		                                $self->{'public'}, $self->{'cvs_id'})
		                                    or return -1;

	return -2 if( $self->SUPER::commit < 0 );
	return 1;
}

=head2 set_public

	$cvs->set_public;

Set a CVS repository public.

=cut
sub set_public {
	my $self = shift;
	$self->{'public'} = 1;
}

=head2 set_private

	$cvs->set_private;

Set a CVS repository private.

=cut
sub set_private {
	my $self = shift;
	$self->{'public'} = 0;
}

sub is_public {
	my $self = shift;
	return $self->{'public'};
}

sub get_label {
	my $self = shift;
	return $self->{cvsroot};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_service('cvs');
}

sub get_reponame {
	my ($self) = @_;
	return $self->{'cvsroot'};
}

sub get_dir {
	my $self = shift;
	return $self->get_base_dir.'/'.$self->get_reponame;
}

=head2 get_base_dir

	my $basedir = $cvs->get_base_dir();

Returns the directory containing all the repositories.

=cut
sub get_base_dir {
	my $self = shift;
	return $self->get_vhffs->get_config->get_datadir.'/cvs/cvsroot';
}

1;
__END__
=head1 AUTHORS

soda < dieu at gunnm dot org>

Sebastien Le Ray < beuss at tuxfamily dot org >
