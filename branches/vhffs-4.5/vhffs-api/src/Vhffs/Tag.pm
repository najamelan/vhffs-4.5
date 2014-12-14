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

=head1 NAME

Vhffs::Tag - Class allowing tags manipulation

=head1 SYNOPSIS



=head1 CLASS METHODS

=cut

use strict;
use utf8;

use Vhffs::User;
use Vhffs::Tag::Category;

package Vhffs::Tag;

=pod

=head2 _new

	Self constructor, almost private, please use get_by_* methods instead.

=cut
sub _new {
	my ($class, $vhffs, $tag_id, $label, $description, $updated, $updater_id, $category_id) = @_;

	my $self = {};

	bless($self, $class);

	$self->{vhffs} = $vhffs;
	$self->{tag_id} = $tag_id;
	$self->{label} = $label;
	$self->{description} = $description;
	$self->{updated} = $updated;
	$self->{updater_id} = $updater_id;
	$self->{category_id} = $category_id;

	return $self;
}

=head2 create

my $tag = Vhffs::Tag::create($vhffs, $label, $description, $creator, $category, $created)

Create (in database) and return a new object.

=over 4

=item C<$vhffs>: C<Vhffs> instance

=item C<$label>: Tag label.

=item C<$description>: Tag description.

=item C<$creator>: C<Vhffs::User> instance of the user who is creating this tag.

=item C<$category>: C<Vhffs::Tag::Category> instance of the tag category.

=time C<$created>: Unix timestamp.

=back

=cut
sub create {
	my ($vhffs, $label, $description, $creator, $category, $created) = @_;
	$created = time() unless(defined $created);

	my $dbh = $vhffs->get_db();

	my $sql = q{INSERT INTO vhffs_tag(label, description, updated, category_id, updater_id) VALUES(?, ?, ?, ?, ?)};
	my $sth = $dbh->prepare($sql);
	$sth->execute($label, $description, $created, $category->{category_id}, $creator->get_uid);

	my $tag_id = $dbh->last_insert_id(undef, undef, 'vhffs_tag', undef);
	return get_by_tag_id($vhffs, $tag_id);
}

=cut

=head2 Vhffs::Tag::get_by_tag_id

my $tag = Vhffs::Tag::get_by_tag_id( $vhffs, $tag_id );

Fetches a tag by tag ID.

=cut
sub get_by_tag_id {
	my($vhffs, $tag_id) = @_;

	my $sql = q{SELECT tag_id, label, description, updated, updater_id, category_id FROM vhffs_tag WHERE tag_id = ?};
	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare($sql);
	$sth->execute($tag_id) or return undef;
	my @results = $sth->fetchrow_array();
	return undef unless @results;

	my $tag = _new Vhffs::Tag($vhffs, @results);

	return $tag;
}

=cut

=head2 Vhffs::Tag::get_all

my $tags = Vhffs::Tag::get_all( $vhffs );

Fetches all tags.

=cut
sub get_all {
	my ($vhffs) = @_;

	return _fetch_tags($vhffs, q{SELECT tag_id, label, description, updated, updater_id, category_id
		FROM vhffs_tag ORDER BY label});
}

=cut

=head2 Vhffs::Tag::get_by_category_id

my $tags = Vhffs::Tag::get_all( $vhffs, $category_id );

Fetches all tags from a category.

=cut
sub get_by_category_id {
	my ($vhffs, $category_id) = @_;

	return _fetch_tags($vhffs, q{SELECT tag_id, label, description, updated, updater_id, category_id
		FROM vhffs_tag WHERE category_id = ? ORDER BY label}, $category_id);
}

=cut

=head2 Vhffs::Tag::get_most_popular_tags

my $tags = Vhffs::Tag::get_most_popular_tags( $vhffs, $visibility );

Fetches popular tags.

=over 4

=item C<$vhffs>: C<Vhffs> instance

=item C<$visibility>: C<Vhffs::Constants> TAG_VISIBILITY_* value.

=back

=cut
sub get_most_popular_tags {
	use POSIX;	# ceil

	my ($vhffs, $visibility) = @_;
	$visibility = Vhffs::Constants::TAG_VISIBILITY_PUBLIC unless(defined $visibility);
	my $tags = [];

	my $dbh = $vhffs->get_db();

	my $sql = q{SELECT MAX(c) AS max_count FROM
		(SELECT COUNT(*) AS c
		FROM vhffs_object_tag ot
		INNER JOIN vhffs_tag t ON t.tag_id = ot.tag_id
		INNER JOIN vhffs_tag_category c ON c.tag_category_id = t.category_id
		WHERE c.visibility <= ?
		GROUP BY t.tag_id) AS counts};
	my $sth = $dbh->prepare($sql);
	return undef unless($sth->execute($visibility));
	my $max_count = $sth->fetchrow_hashref()->{max_count};

	$sql = q{SELECT c.tag_category_id AS category_id, c.label AS category_label, c.description AS category_description,
		t.tag_id AS tag_id, t.label AS tag_label, t.description AS tag_description, COUNT(*) AS object_count
		FROM vhffs_tag t
		INNER JOIN vhffs_tag_category c ON c.tag_category_id = t.category_id
		INNER JOIN vhffs_object_tag ot ON ot.tag_id = t.tag_id
		WHERE c.visibility <= ?
		GROUP BY t.tag_id, t.label, t.description, c.tag_category_id, c.label, c.description
		ORDER BY object_count DESC
		LIMIT 10};
	$sth = $vhffs->get_db->prepare($sql);
	$sth->execute($visibility) or return undef;
	while( (my $t = $sth->fetchrow_hashref() )  ) {
		$t->{weight} = ceil($t->{object_count} * 10 / $max_count);
		push @$tags, $t;
	}
	return $tags;
}

=cut

=head2 Vhffs::Tag::get_random_tags

my $tags = Vhffs::Tag::get_random_tags( $vhffs, $visibility );

Fetches ten random tags.

=over 4

=item C<$vhffs>: C<Vhffs> instance

=item C<$visibility>: C<Vhffs::Constants> TAG_VISIBILITY_* value.

=back

=cut
sub get_random_tags {
	use POSIX;	# ceil

	my ($vhffs, $visibility) = @_;
	$visibility = Vhffs::Constants::TAG_VISIBILITY_PUBLIC unless(defined $visibility);
	my $tags = [];

	my $dbh = $vhffs->get_db();

	my $sql = q{SELECT MAX(c) AS max_count FROM
		(SELECT COUNT(*) AS c
		FROM vhffs_object_tag ot
		INNER JOIN vhffs_tag t ON t.tag_id = ot.tag_id
		INNER JOIN vhffs_tag_category c ON c.tag_category_id = t.category_id
		WHERE c.visibility <= ?
		GROUP BY t.tag_id) AS counts};
	my $sth = $dbh->prepare($sql);
	return undef unless($sth->execute($visibility));
	my $max_count = $sth->fetchrow_hashref()->{max_count};

	$sql = q{SELECT c.tag_category_id AS category_id, c.label AS category_label, c.description AS category_description,
		t.tag_id AS tag_id, t.label AS tag_label, t.description AS tag_description, COUNT(*) AS object_count
		FROM vhffs_tag t
		INNER JOIN vhffs_tag_category c ON c.tag_category_id = t.category_id
		INNER JOIN vhffs_object_tag ot ON ot.tag_id = t.tag_id
		WHERE c.visibility <= ?
		GROUP BY t.tag_id, t.label, t.description, c.tag_category_id, c.label, c.description
		ORDER BY RANDOM()
		LIMIT 10};
	$sth = $vhffs->get_db->prepare($sql);
	$sth->execute($visibility) or return undef;
	while( (my $t = $sth->fetchrow_hashref() )  ) {
		$t->{weight} = ceil($t->{object_count} * 10 / $max_count);
		push @$tags, $t;
	}
	return $tags;
}

=cut

=head2
	Vhffs::Tag::_fetch_tags($vhffs, $sql, @params)

Fetches a tag list using C<$sql> and C<@params>.
C<$sql> is a query having the following format
	SELECT tag_id, label, description, updated, updater_id, category_id FROM vhffs_tag...

=cut
sub _fetch_tags {
	my ($vhffs, $sql, @params) = @_;

	my $tags = [];

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare($sql);
	$sth->execute(@params) or return undef;

	while(my $t = $sth->fetchrow_arrayref()) {
		push @$tags, _new Vhffs::Tag($vhffs, @$t);
	}

	return $tags;
}

=pod
=head1 INSTANCE METHODS
=cut

=pod

=head2 get_updater

my $updater = $tag->get_updater;

Returns a C<Vhffs::User> object of the user who last modified this tag.

=cut
sub get_updater {
	my ($self) = @_;

	unless( defined $self->{updater} ) {
		$self->{updater} = Vhffs::User::get_by_uid($self->{vhffs}, $self->{updater_id});
	}
	return $self->{updater};
}

=pod

=head2 get_category

my $category = $tag->get_category;

Returns a C<Vhffs::Tag::Category> object of the tag category.

=cut
sub get_category {
	my ($self) = @_;

	unless( defined $self->{category} ) {
		$self->{category} = Vhffs::Tag::Category::get_by_category_id($self->{vhffs}, $self->{category_id});
	}

	return $self->{category}
}

=pod

=head2 delete

$tag->delete;

Delete a tag.

=cut
sub delete {
	my ($self) = @_;

	my $sql = q{DELETE FROM vhffs_tag WHERE tag_id = ?};
	my $dbh = $self->{vhffs}->get_db;
	return $dbh->do($sql, undef, $self->{tag_id});
}

=pod

=head2 save

$tag->save;

Commit changes of a tag to the database.

=cut
sub save {
	my ($self) = @_;

	my $sql = q{UPDATE vhffs_tag SET category_id = ?,  label = ?, description = ?, updated = ?, updater_id = ? WHERE tag_id = ?};
	my $dbh = $self->{vhffs}->get_db;
	return $dbh->do($sql, undef, $self->{category_id}, $self->{label}, $self->{description}, $self->{updated}, $self->{updater_id}, $self->{tag_id});
}

# Since perl allows us to do such things, let's have
# an unobstrusive approach

package Vhffs::Object;

=pod

=head2 get_tags

	my $tags = $o->get_tags($access_level);
Returns an array of all tag categories for an object. Each
element contains {label, tags}, tags is an array containing
all tags of the given category for this object ({tag_id, label}).

=cut
sub get_tags {
	my ($o, $visibility) = @_;

	my $dbh = $o->get_db();
	my $tags = [];

	my $sql = q{SELECT t.tag_id, t.label as tag_label, c.label as cat_label
		FROM vhffs_tag t INNER JOIN vhffs_tag_category c ON c.tag_category_id = t.category_id
		INNER JOIN vhffs_object_tag ot ON ot.tag_id = t.tag_id
		WHERE ot.object_id = ? AND visibility <= ? ORDER BY c.label, t.label};

	my $sth = $dbh->prepare($sql);
	$sth->execute($o->get_oid(), $visibility) or return undef;

	my $cat = undef;

	while(my $t = $sth->fetchrow_hashref()) {
		if( (!defined $cat) || ($cat->{label} ne $t->{cat_label}) ) {
			$cat = {
				label => $t->{cat_label},
				tags => []
			};
			push @$tags, $cat;
		}
		my $tag = {
			tag_id => $t->{tag_id},
			label => $t->{tag_label}
		};
		push @{$cat->{tags}}, $tag;
	}

	return $tags;
}

=pod

=head2 add_tag

$object->add_tag( $tag, $updater, $updated );

=over 4

=item C<$tag>: C<Vhffs::Tag> instance

=item C<$updater>: C<Vhffs::User> instance of the user who is adding this tag.

=time C<$updated>: Unix timestamp.

=back

=cut
sub add_tag {
	my ($o, $tag, $updater, $updated) = @_;

	my $dbh = $o->get_db();
	$updated = time() unless($updated);

	# Don't fill error log with useless error messages.
	local $dbh->{PrintError} = 0;

	return $dbh->do(q{INSERT INTO vhffs_object_tag(object_id, tag_id, updated, updater_id) VALUES(?, ?, ?, ?)},
		undef, $o->get_oid(), $tag->{tag_id}, $updated, $updater->get_uid());
}

=pod

=head2 deleted_tag

$object->delete_tag( $tag );

=over 4

=item C<$tag>: C<Vhffs::Tag> instance

=back

=cut
sub delete_tag {
	my ($o, $tag) = @_;

	my $dbh = $o->get_db();

	return $dbh->do(q{DELETE FROM vhffs_object_tag WHERE object_id = ? AND tag_id = ?}, undef,
		$o->get_oid(), $tag->{tag_id});
}

1;
