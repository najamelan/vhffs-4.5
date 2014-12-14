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

=head1 Vhffs::Tag::Category
=head2 SYNOPSIS

Object allowing tags categories manipulation

=cut

use strict;
use utf8;

use Vhffs::Constants;

package Vhffs::Tag::Category;

my @VISIBILITY_STRING;
$VISIBILITY_STRING[Vhffs::Constants::TAG_VISIBILITY_GROUP_CREATION] = 'Public (available on group creation)';
$VISIBILITY_STRING[Vhffs::Constants::TAG_VISIBILITY_PUBLIC] = 'Public';
$VISIBILITY_STRING[Vhffs::Constants::TAG_VISIBILITY_MODERATORS] = 'Moderators';
$VISIBILITY_STRING[Vhffs::Constants::TAG_VISIBILITY_ADMINS] = 'Administrators';

sub create {
	my ($vhffs, $label, $description, $visibility, $creator, $updated) = @_;
	$updated = time() unless(defined $updated);

	my $dbh = $vhffs->get_db();

	my $sql = q{INSERT INTO vhffs_tag_category(label, description, visibility, updated, updater_id) VALUES (?, ?, ?, ?, ?)};
	$dbh->do($sql, undef, $label, $description, $visibility, $updated, $creator->get_uid);

	my $category_id = $dbh->last_insert_id(undef, undef, 'vhffs_tag_category', undef);
	return get_by_category_id($vhffs, $category_id);
}

sub get_by_category_id {
	my ($vhffs, $category_id) = @_;

	my $dbh = $vhffs->get_db();

	my $sql = q{SELECT tag_category_id, label, description, visibility, updated, updater_id
		FROM vhffs_tag_category WHERE tag_category_id = ?};

	my $sth = $dbh->prepare($sql);
	$sth->execute($category_id) or return undef;
	my @results = $sth->fetchrow_array();
	return undef unless @results;

	my $category = _new Vhffs::Tag::Category($vhffs, @results);

	return $category;
}

sub get_by_label {
	my ($vhffs, $label) = @_;

	my $dbh = $vhffs->get_db();

	my $sql = q{SELECT tag_category_id, label, description, visibility, updated, updater_id
		FROM vhffs_tag_category WHERE label = ?};

	my $sth = $dbh->prepare($sql);
	$sth->execute($label) or return undef;
	my @results = $sth->fetchrow_array();
	return undef unless @results;

	my $category = _new Vhffs::Tag::Category($vhffs, @results);

	return $category;
}

sub get_all {
	my ($vhffs, $visibility) = @_;

	my @params = ();
	my $cats = [];

	my $sql = q{SELECT tag_category_id, label, description, visibility, updated, updater_id
		FROM vhffs_tag_category};
	if(defined $visibility) {
		$sql .= q{ WHERE visibility <= ?};
		push  @params, $visibility;
	}
	$sql .= q{ ORDER BY label};

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare($sql);
	$sth->execute(@params) or return undef;

	while(my $c = $sth->fetchrow_arrayref()) {
		push @$cats, _new Vhffs::Tag::Category($vhffs, @$c);
	}

	return $cats;
}

sub _new {
	my($class, $vhffs, $category_id, $label, $description, $visibility, $updated, $updater_id) = @_;

	my $self = {};

	bless($self, $class);

	$self->{vhffs} = $vhffs;
	$self->{category_id} = $category_id;
	$self->{label} = $label;
	$self->{description} = $description;
	$self->{visibility} = $visibility;
	$self->{updated} = $updated;
	$self->{updater_id} = $updater_id;

	return $self;
}

sub save {
	my ($self) = @_;
	my $sql = q{UPDATE vhffs_tag_category SET label = ?, description = ?, visibility = ?, updated = ?, updater_id = ? WHERE tag_category_id = ?};
	my $dbh = $self->{vhffs}->get_db();
	return $dbh->do($sql, undef, $self->{label}, $self->{description}, $self->{visibility}, $self->{updated}, $self->{updater_id}, $self->{category_id});
}

sub delete {
	my ($self) = @_;
	my $sql = q{DELETE FROM vhffs_tag_category WHERE tag_category_id = ?};
	my $dbh = $self->{vhffs}->get_db();
	return $dbh->do($sql, undef, $self->{category_id});
}

sub get_updater {
	my ($self) = @_;

	unless( defined $self->{updater} ) {
		$self->{updater} = Vhffs::User::get_by_uid($self->{vhffs}, $self->{updater_id});
	}
	return $self->{updater};
}

sub get_visibility_string {
	my($self) = @_;
	return $VISIBILITY_STRING[$self->{visibility}];
}

1;
