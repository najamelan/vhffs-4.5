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

package Vhffs::UserGroup;

use strict;
use utf8;
use DBI;
use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::User;
use Vhffs::Group;
use Vhffs::Functions;

=pod

=head1 NAME

Vhffs::UserGroup - Vhffs Interface to handle user-group relations

=head1 SYNOPSIS

	use Vhffs::UserGroup;
	my $vhffs = new Vhffs or die();
	my $usergroups = Vhffs::UserGroup::getall( $vhffs, Vhffs::Constants::WAITING_FOR_CREATION );
	foreach ( @{$usergroups} ) {
		my $user = $usergroup->get_user;
		my $group = $usergroup->get_group;
		...
	}
=cut

=pod
=head1 CLASS METHODS
=cut

=pod

=head2 _new

	Self constructor, almost private, please use getall methods instead.

=cut
sub _new {
	my ($class, $vhffs, $user, $group, $state) = @_;

	return undef unless defined $vhffs;

	my $self = {};
	bless($self, $class);

	$self->{vhffs} = $vhffs;
	$self->{group} = $group;
	$self->{user} = $user;
	$self->{state} = $state;

	return $self;
}

=pod

=head2 create

	my $usergroup = Vhffs::UserGroup::create($vhffs, $group, $user)

Create in DB and return a C<Vhffs::UserGroup>.

=cut
sub create {
	my ( $user, $group ) = @_;
	return undef unless defined $user and defined $group;

	my $sql = 'INSERT INTO vhffs_user_group(uid, gid, state) VALUES(?, ?, ?)';
	my $res = $group->get_db->do( $sql, {}, $user->get_uid, $group->get_gid, Vhffs::Constants::WAITING_FOR_CREATION ) or return undef;
	my $self = _new Vhffs::UserGroup( $group->get_vhffs, $user, $group, Vhffs::Constants::WAITING_FOR_CREATION );
	if( defined $self ) {
		$user->set_validated( 1 );
		$user->commit;
	}
	return $self;
}

=pod

=head2 getall

	my $usergroups = Vhffs::UserGroup::getall( $vhffs, $state ;

Returns an array of usergroups who matched $state.

=cut
sub getall {
	my $vhffs = shift;
	my $state = shift;
	my @usergroups;
	my @params;
	return unless defined $vhffs;

	my $query = 'SELECT uid, gid, state FROM vhffs_user_group';

	if( defined $state ) {
		$query.= ' WHERE state=?';
		push(@params, $state);
	}

	my $request = $vhffs->get_db->prepare( $query );
	$request->execute(@params);
	while( my ($uid, $gid, $state) = $request->fetchrow_array ) {
		my $user = Vhffs::User::get_by_uid( $vhffs, $uid );
		my $group = Vhffs::Group::get_by_gid( $vhffs, $gid );
		push( @usergroups, _new Vhffs::UserGroup($vhffs, $user, $group, $state) ) if defined $user and defined $group;
	}

	return \@usergroups;
}

=pod

=head2 get_by_user_group

	my $usergroup = Vhffs::Group::get_by_user_group( $user, $group );
	die('UserGroup not found') unless(defined $usergroup);

Fetches the user group whose group is a C:<Vhffs::Group> and user is a C<Vhffs::User>

=cut
sub get_by_user_group {
	my ($user, $group) = @_;
	return undef unless defined $user and defined $group;
	my $query = 'SELECT state FROM vhffs_user_group WHERE uid=? and gid=?';

	my @params = $user->get_db->selectrow_array($query, undef, $user->get_uid, $group->get_gid);
	return undef unless(@params);
	my $usergroup = _new Vhffs::UserGroup( $group->get_vhffs, $user, $group, @params);
	return $usergroup;
}

=pod
=head1 INSTANCE METHODS
=cut

=pod

=head2 get_vhffs

This method returns the Vhffs object.

=cut
sub get_vhffs {
	my $self = shift;
	return $self->{'vhffs'};
}

=pod

=head2 get_status

Get the status of this user-group relation. The status are given in the Vhffs::Constants class.

=cut
sub get_status {
	my $self = shift;
	return $self->{'state'};
}

=pod

=head2 set_status

Change the status. The status are available as constants in Vhffs::Constants class.

=cut
sub set_status {
	my ($self, $value) = @_;
	$self->{'state'} = $value;
}

=pod

=head2 get_user

Returns the C<Vhffs::User> of this user-group relation.

=cut
sub get_user {
	my $self = shift;
	return $self->{'user'};
}

=pod

=head2 get_group

Returns the C<Vhffs::Group> of this user-group relation.

=cut
sub get_group {
	my $self = shift;
	return $self->{'group'};
}

=pod

=head2 commit

Apply all changes that were made on this user-group relation. Returns undef value if failed, true if success.

=cut
sub commit {
	my $self = shift;

	my $query = 'UPDATE vhffs_user_group SET state=? WHERE uid=? AND gid=?';
	my $dbh = $self->get_vhffs->get_db;
	my $result = $dbh->prepare($query);
	$result->execute( $self->{'state'}, $self->{'user'}->get_uid, $self->{'group'}->get_gid ) or return undef;
	return 1;
}

=pod

=head2 delete

Delete the user-group relation from the database.

=cut
sub delete {
	my $self = shift;

	# Foreign key constraints are in 'ON DELETE CASCADE' mode
	# we don't have to bother with foreign tables deletion.
	my $query = 'DELETE FROM vhffs_user_group WHERE uid=? AND gid=?';
	my $dbh = $self->get_vhffs->get_db;
	my $request = $dbh->prepare($query);
	$request->execute( $self->{'user'}->get_uid, $self->{'group'}->get_gid ) or return undef;

	return 1;
}

1;
