#!%PERL% -w
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


# This file is a part of the VHFFS plateform
# Please respect the entire licence of VHFFS
#
# Author : Julien Delange < dieu at gunnm dot org >

package Vhffs::Broadcast;

use strict;
use utf8;
use Vhffs::Functions;
use Vhffs::Constants;
use Encode;

=pod

=head1 NAME

Vhffs::Broadcast - Handle broadcast message to all users.

=cut

=pod
=head1 CLASS METHODS
=cut

=pod

=head2 _new

	Self constructor, almost private, please use get_by_* methods instead.

=cut
sub _new {
	my ($class, $vhffs, $mailing_id, $subject, $message, $date, $state) = @_;

	return undef unless defined $vhffs;

	my $self = {};
	bless($self, $class);

	$self->{vhffs} = $vhffs;
	$self->{mailing_id} = $mailing_id;
	$self->{subject} = $subject;
	$self->{message} = $message;
	$self->{date} = $date;
	$self->{state} = $state;

	return $self;
}

=pod

=head2 create

	my $ret = Vhffs::Broadcast::create( $vhffs, $subject, $message );

Add a broadcast message to all users.

Returns 1 on success, otherwise returns undef;

=cut
sub create {
	my $vhffs = shift;
	my $subject = shift;
	my $message = shift;

	return undef unless defined $vhffs;

	$message =~ s/\r\n/\n/g;

	my $query = 'INSERT INTO vhffs_mailings (mailing_id, subject, message, date, state) VALUES(DEFAULT, ?, ?, ?, ? ) RETURNING mailing_id';
	my $dbh = $vhffs->get_db;
	my $request = $dbh->prepare( $query );
	$request->execute($subject, $message, time(), Vhffs::Constants::BROADCAST_WAITING_TO_BE_SENT) or return undef;

	my ( $mailing_id ) = $request->fetchrow_array;
	return get_by_mailing_id( $vhffs, $mailing_id );
}

=pod

=head2 get_by_mailing_id

	my $broadcast = Vhffs::Broadcast::get_by_mailing_id( $vhffs, $id );

Fetch broadcast $id.

=cut
sub get_by_mailing_id {
	my $vhffs = shift;
	my $id = shift;

	return undef unless defined $id;

	my $query = 'SELECT mailing_id, subject, message, date, state FROM vhffs_mailings WHERE mailing_id=?';
	my $dbh = $vhffs->get_db;
	my @params = $dbh->selectrow_array($query, undef, $id);
	return undef unless(@params);
	my $mailing = _new Vhffs::Broadcast($vhffs, @params);
	return $mailing;
}

=pod

=head2 getall

	my $broadcasts = Vhffs::Broadcast::getall( $vhffs, $state );

Returns a hash of all broadcasts. $state can be used to filter the state.

=cut
sub getall {
	my $vhffs = shift;
	my $state = shift;
	return unless defined $vhffs;

	my $mailings = [];
	my @params;

	my $query = 'SELECT mailing_id, subject, message, date, state FROM vhffs_mailings ';
	if( defined $state ) {
		$query .= ' WHERE state=?';
		push @params, $state;
	}

	my $dbh = $vhffs->get_db;

	my $sth = $dbh->prepare($query);
	$sth->execute(@params) or return undef;

	while(my $s = $sth->fetchrow_arrayref) {
		push(@$mailings, _new Vhffs::Broadcast($vhffs, @$s));
	}
	return $mailings;
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

Get the status of this broadcast. The status are given in the Vhffs::Constants class.

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

=head2 commit

Apply all changes that were made on this broadcast. Returns undef value if failed, true if success.

=cut
sub commit {
	my $self = shift;

	my $query = 'UPDATE vhffs_mailings SET state=? WHERE mailing_id=?';
	my $dbh = $self->get_vhffs->get_db;
	my $result = $dbh->prepare($query);
	$result->execute( $self->{'state'}, $self->{'mailing_id'} ) or return undef;
	return 1;
}

=pod

=head2 delete

	my $ret = $mailing->delete;

Delete broadcast $mailing.

Returns 1 on success, otherwise returns undef;

=cut
sub delete {
	my $self = shift;

	my $query = 'DELETE FROM vhffs_mailings WHERE mailing_id=?';
	my $dbh = $self->get_vhffs->get_db;
	my $request = $dbh->prepare( $query );
	$request->execute( $self->{'mailing_id'} ) or return undef;
	return 1;
}

1;
