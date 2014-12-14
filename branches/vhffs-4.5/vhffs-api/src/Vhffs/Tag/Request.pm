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

=head1 Vhffs::Tag::Request
=head2 SYNOPSIS

Manages requests for tags.

=cut

use strict;
use utf8;

package Vhffs::Tag::Request;

use Vhffs::ObjectFactory;

sub create {
	my ($vhffs, $category, $tag, $requester, $tagged) = @_;

	my $dbh = $vhffs->get_db();

	my $sql = q{INSERT INTO vhffs_tag_request(category_label, tag_label, created, requester_id, tagged_id) VALUES (?, ?, ?, ?, ?)};
	$dbh->do($sql, undef, $category, $tag, time(), $requester->get_uid, $tagged->get_oid);

	my $request_id = $dbh->last_insert_id(undef, undef, 'vhffs_tag_request', undef);

	return get_by_request_id($vhffs, $request_id);
}

sub _new {
	my($class, $vhffs, $request_id, $category_label, $tag_label, $created, $requester_id, $tagged_id) = @_;

	my $self = {};

	bless($self, $class);

	$self->{vhffs} = $vhffs;
	$self->{request_id} = $request_id;
	$self->{category_label} = $category_label;
	$self->{tag_label} = $tag_label;
	$self->{created} = $created;
	$self->{requester_id} = $requester_id;
	$self->{tagged_id} = $tagged_id;

	return $self;
}

sub get_by_request_id {
	my ($vhffs, $request_id) = @_;

	my $dbh = $vhffs->get_db();

	my $sql = q{SELECT tag_request_id, category_label, tag_label, created, requester_id, tagged_id
		FROM vhffs_tag_request WHERE tag_request_id = ?};

	my $sth = $dbh->prepare($sql);
	$sth->execute($request_id) or return undef;
	my @results = $sth->fetchrow_array();
	return undef unless @results;

	my $request = _new Vhffs::Tag::Request($vhffs, @results);

	return $request;
}

sub get_all {
	my ($vhffs) = @_;

	my $requests = [];

	my $sql = q{SELECT tag_request_id, category_label, tag_label, created, requester_id, tagged_id
		FROM vhffs_tag_request ORDER BY created};

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare($sql);
	$sth->execute() or return undef;

	while(my $c = $sth->fetchrow_arrayref()) {
		push @$requests, _new Vhffs::Tag::Request($vhffs, @$c);
	}

	return $requests;
}

sub get_requester {
	my ($self) = @_;

	unless( defined $self->{requester} ) {
		$self->{requester} = Vhffs::User::get_by_uid($self->{vhffs}, $self->{requester_id});
	}
	return $self->{requester};
}

sub get_tagged {
	my ($self) = @_;

	unless( defined $self->{tagged} ) {
		$self->{tagged} = Vhffs::ObjectFactory::fetch_object($self->{vhffs}, $self->{tagged_id});
	}
	return $self->{tagged};
}

sub delete {
	my ($self) = @_;

	my $sql = q{DELETE FROM vhffs_tag_request WHERE tag_request_id = ?};
	my $dbh = $self->{vhffs}->get_db;
	return $dbh->do($sql, undef, $self->{request_id});
}

package Vhffs::Object;

sub get_tag_requests {
	my ($self) = @_;

	my $requests = [];

	my $dbh = $self->get_db();
	my $sql = q{SELECT tag_request_id, category_label, tag_label, created, requester_id, tagged_id
		FROM vhffs_tag_request WHERE tagged_id = ? ORDER BY created};

	my $sth = $dbh->prepare($sql);

	$sth->execute($self->get_oid()) or return undef;

	while(my $c = $sth->fetchrow_arrayref()) {
		push @$requests, _new Vhffs::Tag::Request($self->get_vhffs(), @$c);
	}

	return $requests;
}

1;
