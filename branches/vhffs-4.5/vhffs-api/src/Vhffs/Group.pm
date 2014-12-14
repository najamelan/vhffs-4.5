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

package Vhffs::Group;

use base qw(Vhffs::Object);

use strict;
use utf8;
use DBI;
use Vhffs::Constants;

=pod

=head1 NAME

Vhffs::Group - Vhffs Interface to handle *NIX groups

=head1 SYNOPSIS

	use Vhffs;
	my $vhffs = new Vhffs or die();
	my $group = Vhffs::Group::get_by_groupname( $vhffs , 'mygroup' );
	defined $group ? print "Group exists\n" : print "Group does not exist\n";
	...
	my $group = Vhffs::Group::create( $vhffs, 'mygroup', 'Group Human Name', $uid, $gid, $description );
	defined $group ? print "Group created" : print "Group error\n";
	...
	print "Groupname: $group->get_groupname";
	...
	print "Successfully updated group preferences\n" if $group->commit > 0;
=cut

=pod
=head1 CLASS METHODS
=cut

=pod

=head2 check_groupname

	print 'Groupname valid' if Vhffs::Group::check_groupname($groupname));

returns false if groupname is not valid (length not between 3 and 12, name not
composed of alphanumeric chars)

=cut
sub check_groupname($) {
	my $groupname = shift;
	return ( defined $groupname and $groupname =~ /^[a-z0-9]{3,12}$/ );
}

=pod

=head2 _new

	Self constructor, almost private, please use get_by_* methods instead.

=cut
sub _new {
	no strict 'refs';
	my ($class, $vhffs, $gid, $oid, $owner_uid, $groupname, $realname, $passwd, $quota, $quota_used, $date_creation, $description, $state) = @_;
	my $self = $class->SUPER::_new($vhffs, $oid, $owner_uid, $gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_GROUP);
	return undef unless defined $self;

	$self->{gid} = $gid;
	$self->{groupname} = $groupname;
	$self->{realname} = $realname;
	$self->{passwd} = $passwd;
	$self->{quota} = $quota;
	$self->{quota_used} = $quota_used;

	return $self;
}

=pod

=head2 create

	my $group = Vhffs::Group::create($vhffs, $groupname, $realname, $owner_uid, $gid, $description)

Create in DB and return a fully functional group.

=cut
sub create {
	my ($vhffs, $groupname, $realname, $owner_uid, $gid, $description) = @_;
	return undef unless check_groupname($groupname);
	return undef unless defined($owner_uid);

	my $groupconf = $vhffs->get_config->get_groups;
	my $group;

	open(my $badgroups, '<', $groupconf->{'bad_groupname_file'} );
	if( defined $badgroups ) {
		while( <$badgroups> ) {
			chomp;
			if ( $_ eq $groupname ) {
				close $badgroups;
				return undef;
			}
		}
		close $badgroups;
	}

	$realname = $groupname unless defined $realname;

	my $dbh = $vhffs->get_db;
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;

	# Avoid an error if we're already in a transaction
	# (eg. when creating user).
	my $transaction_started;
	if($dbh->{AutoCommit}) {
		# AutoCommit is on => we're not yet in a
		# transaction, let's start one
		$dbh->begin_work;
		$transaction_started = 1;
	} else {
		# We're already in a transaction, ensure that
		# we don't corrupt it.
		$transaction_started = 0;
	}

	eval {
		# Special case : sometimes, gid can't be passed to create
		# to avoid updates (cf Vhffs::User::create)
		($gid) = $dbh->selectrow_array('SELECT nextval(\'vhffs_groups_gid_seq\')') unless defined $gid;

		my $parent = Vhffs::Object::create($vhffs, $owner_uid, $gid, $description, undef, Vhffs::Constants::TYPE_GROUP);
		die('Unable to create parent object') unless(defined $parent);

		my $quota = $groupconf->{default_quota} || 10;

		my $query = 'INSERT INTO vhffs_groups(gid, groupname, realname, passwd, quota, quota_used, object_id) VALUES(?, ?, ?, NULL, ?, 0, ?)';
		my $sth = $dbh->prepare( $query );
		$sth->execute($gid, $groupname, $realname, $quota, $parent->get_oid);

		$dbh->commit if($transaction_started);
		$group = get_by_gid($vhffs, $gid);
	};

	if($transaction_started && $@) {
		warn "Unable to create group $groupname: $@\n";
		$dbh->rollback;
	}

	return $group;
}

=pod

=head2 fill_object

See C<Vhffs::Object::fill_object>.

=cut
sub fill_object {
	my ($class, $obj) = @_;
	my $sql = q{SELECT gid, groupname, realname, passwd, quota, quota_used FROM
		vhffs_groups WHERE object_id = ?};
	return $class->SUPER::_fill_object($obj, $sql);
}

=pod

=head2 getall

	my @groups = Vhffs::User::getall( $vhffs, $state, $name );

Returns an array of groups which matched $state and $name.

=cut
sub getall {
	my $vhffs = shift;
	my $state = shift;
	my $name = shift;

	my $groups = [];
	my @params;
	my $sql = 'SELECT groupname FROM vhffs_groups g INNER JOIN vhffs_object o ON g.object_id=o.object_id LEFT OUTER JOIN vhffs_users u ON u.username = g.groupname WHERE u.username IS NULL ';

	if(defined $state) {
		$sql .= ' AND o.state = ?';
		push @params, $state;
	}
	if(defined $name) {
		$sql .= ' AND g.groupname LIKE ?';
		push @params, '%'.$name.'%';
	}
	$sql .= ' ORDER BY g.groupname';

	my $dbh = $vhffs->get_db();
	my $sth = $dbh->prepare($sql);
	$sth->execute(@params);
	while(my @d = $sth->fetchrow_array) {
		push @$groups, get_by_groupname($vhffs, $d[0]);
	}

	return $groups;
}

=pod

=head2 getall_by_letter

	my @groups = Vhffs::User::getall_by_letter( $vhffs, $letter, $state );

Returns an array of all groups which starts by letter $letter and are having state $state.

=cut
sub getall_by_letter {
	my $vhffs = shift;
	my $letter = shift;
	my $state = shift;

	return getall($vhffs, $state) if(! defined $letter );
	$letter .= '%';

	my $db = $vhffs->get_db;
	my @result;
	my $query = 'SELECT groupname FROM vhffs_groups g INNER JOIN vhffs_object o ON g.object_id=o.object_id LEFT OUTER JOIN vhffs_users u ON u.username = g.groupname WHERE u.username IS NULL AND g.groupname LIKE ?';
	$query .= "AND o.state=$state " if( defined $state );

	my $request = $db->prepare( $query );
	return undef if( ! $request->execute( $letter ) );

	my $names = $request->fetchall_arrayref;

	my $group;
	foreach my $name ( @{$names} ) {

		$group = Vhffs::Group::get_by_groupname( $vhffs , $name->[0] );
		push( @result , $group) if( defined $group );
	}
	return \@result;
}

=pod

=head2 getall_quotalimit

	my @groups = Vhffs::User::getall_quotalimit( $vhffs, $limit );

Returns an array of groups which are using more than 90% of the disk quota applied

Maximum number of returned group is set by $limit, default value is 10.

=cut
sub getall_quotalimit {
	my ($vhffs, $limit) = @_;
	$limit = 10 unless(defined $limit);
	my $sql = q{SELECT g.gid, o.object_id, o.owner_uid, g.groupname, g.realname, g.passwd, g.quota,
		g.quota_used, o.date_creation, o.description, o.state
		FROM vhffs_groups g INNER JOIN vhffs_object o ON o.object_id = g.object_id
		WHERE (g.quota_used / g.quota) >= 0.9 ORDER BY g.quota_used DESC LIMIT ?};

	my $dbh = $vhffs->get_db;
	my $sth = $dbh->prepare($sql);
	$sth->execute($limit) or return undef;
	my $groups = [];
	while(my @r = $sth->fetchrow_array) {
		push @{$groups}, _new Vhffs::Group($vhffs, @r);
	}
	return $groups;
}

=pod

=head2 get_by_gid

	my $group = Vhffs::Group::get_by_gid($vhffs, $gid);
	die('Group not found') unless(defined $group);

Fetches the group whose gid is $gid.

=cut
sub get_by_gid {
	my ($vhffs, $gid) = @_;
	my $query = 'SELECT g.gid, o.object_id, o.owner_uid, g.groupname, g.realname, g.passwd, g.quota, g.quota_used, o.date_creation, o.description, o.state FROM vhffs_groups g INNER JOIN vhffs_object o ON o.object_id = g.object_id WHERE g.gid = ?';

	my $dbh = $vhffs->get_db;
	my @params = $dbh->selectrow_array($query, undef, $gid);
	return undef unless(@params);
	my $group = _new Vhffs::Group($vhffs, @params);
	return $group;
}

=pod

=head2 get_by_groupname

	my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
	die('Group not found') unless(defined $group);

Fetches the group whose name is $groupname.

=cut
sub get_by_groupname {
	my ($vhffs, $groupname) = @_;
	my $query = 'SELECT g.gid, o.object_id, o.owner_uid, g.groupname, g.realname, g.passwd, g.quota, g.quota_used, o.date_creation, o.description, o.state FROM vhffs_groups g INNER JOIN vhffs_object o ON o.object_id = g.object_id WHERE g.groupname = ?';

	my $dbh = $vhffs->get_db;
	my @params = $dbh->selectrow_array($query, undef, $groupname);
	return undef unless(@params);
	my $group = _new Vhffs::Group($vhffs, @params);
	return $group;
}

=pod
=head1 INSTANCE METHODS
=cut

=pod

=head2 commit

	my $ret = $group->commit;

Commit all changes to the database, returns 1 if success, otherwise returns a negative value.

=cut
sub commit {
	my $self = shift;

	return -1 if $self->SUPER::commit < 0;

	my $sql = 'UPDATE vhffs_groups SET realname = ?, quota = ?, quota_used = ? WHERE gid = ?';
	my $sth = $self->get_db->prepare($sql);
	$sth->execute( $self->{'realname'}, $self->{'quota'}, $self->{'quota_used'}, $self->{'gid'}) or return -1;

	return 1;
}

=head2 add_user

	$group->add_user($user);

Adds a C<Vhffs::User> to a C<Vhffs::Group>.
Returns a C<Vhffs::UserGroup> on success, otherwise returns false.

=cut
sub add_user {
	my( $self, $user ) = @_;
	use Vhffs::UserGroup;
	return Vhffs::UserGroup::create( $user, $self );
}

=pod

=head2 remove_user

	$group->remove_user($user);

Remove a C<Vhffs::User> from a C<Vhffs::Group>.
Return false if an error occurs or if the user wasn't in the group.

=cut
sub remove_user {
	my( $self, $user ) = @_;
	use Vhffs::UserGroup;
	my $usergroup = Vhffs::UserGroup::get_by_user_group( $user, $self );
	return undef unless $usergroup;
	$usergroup->set_status( Vhffs::Constants::WAITING_FOR_DELETION );
	return $usergroup->commit;
}

=pod

=head2 is_empty

	print "Group is empty !\n" if $group->is_empty;

Return true if the group is empty, otherwise retourn false.

=cut
sub is_empty {
	my $self = shift;
	return 0 unless defined $self;

	my $query = 'SELECT COUNT(*) FROM vhffs_object WHERE owner_gid=? AND object_id!=?';
	my $request = $self->get_db->prepare( $query );
	$request->execute( $self->get_gid, $self->get_oid );
	my ( $rows ) = $request->fetchrow();

	return $rows ? 0 : 1;
}

=pod

=head2 delete

	my $ret = $group->delete;

Delete a group from the database. Should be called after group have been cleaned up from the filesystem.

=cut
sub delete {
	my $self = shift;

	require Vhffs::Services::MailGroup;
	my $mg = new Vhffs::Services::MailGroup( $self->get_vhffs, $self );
	$mg->delete if defined $mg;

	# User references corresponding object with an ON DELETE cascade foreign key
	# so we don't even need to delete group
	# rows that reference this group will be deleted by foreign keys constraints
	return $self->SUPER::delete;
}

=pod

=head2 set_quota

Set the group disk quota.

=cut
sub set_quota {
	my $self = shift;
	my $value = shift;
	$self->{'quota'} = $value;
}

=pod

=head2 set_realname

Set the group realname.

=cut
sub set_realname {
	my $self = shift;
	my $value = shift;
	$self->{'realname'} = $value;
}

=pod

=head2 set_quota_used

Set the disk space used by this group.

=cut
sub set_quota_used {
	my $self = shift;
	my $value = shift;
	$self->{'quota_used'} = $value;
}

=pod

=head2 get_quota_used

Returns the disk space used by this group.

=cut
sub get_quota_used {
	my $self = shift;
	return $self->{'quota_used'};
}

=pod

=head2 get_realname

Returns the group realname (human name).

=cut
sub get_realname {
	my $self = shift;
	return $self->{'realname'};
}

=head2 get_label

See C<Vhffs::Object::get_label>.

=cut
sub get_label {
	my $self = shift;
	return $self->{groupname};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_groups;
}

=pod

=head2 get_quota

Returns the disk quota set for this group.

=cut
sub get_quota {
	my $self = shift;
	return $self->{'quota'};
}

=pod

=head2 get_groupname

Returns the name of this group.

=cut
sub get_groupname {
	my $self = shift;
	return $self->{'groupname'};
}

=pod

=head2 get_gid

Returns group GID.

=cut
sub get_gid {
	my $self = shift;
	return $self->{'gid'};
}

=pod

=head2 get_dir

Returns group directory. Such as /data/groups/v/h/vhffs4/.

=cut
sub get_dir {
	my $self = shift;
	return $self->get_vhffs->get_config->get_datadir.'/groups/'.substr($self->get_groupname, 0, 1).'/'.substr($self->get_groupname, 1, 1).'/'.$self->get_groupname;
}

=pod

=head2 get_users

Returns an array of all users C<Vhffs::Users> of this group.

=cut
sub get_users {
	use Vhffs::User;
	my $self = shift;

	my @users;
	my $gid = $self->get_gid;
	my $query = 'SELECT ug.uid FROM vhffs_user_group ug WHERE ug.gid = ?';
	my $request = $self->get_db->prepare( $query );
	$request->execute($gid);
	while( my ($uid) = $request->fetchrow_array ) {
		my $user = Vhffs::User::get_by_uid( $self->get_vhffs, $uid );
		push( @users , $user ) if( defined $user );
	}
	return \@users;
}

=pod

=head2 get_full_history

Returns an array containing all history entries for this group and its objects,
descending ordered by date.

=cut
sub get_full_history {
	my $self = shift;

	my $sql = 'SELECT o.object_id,o.type,h.history_id,h.date,h.message,source.username as source FROM vhffs_history h INNER JOIN vhffs_object o ON o.object_id=h.object_id LEFT JOIN vhffs_users source ON source.uid = h.source_uid WHERE o.owner_gid=? ORDER BY h.date DESC, h.history_id DESC';
	my $dbh = $self->get_db;
	return $dbh->selectall_arrayref($sql, {Slice => {}}, $self->{gid});
}

=pod

=head2 getall_objects

Returns an array of all objects C<Vhffs::Object> owned by this group.

Caution: it also returns the group itself.

=cut
sub getall_objects {
	my $self = shift;

	# TODO should be in Vhffs::Object
	my $query = 'SELECT object_id FROM vhffs_object WHERE owner_gid=?';
	my $request = $self->get_db->prepare( $query ) or return -1;
	return undef unless $request->execute( $self->get_gid );

	my @objects;
	my $rows = $request->fetchall_arrayref();

	foreach (@$rows) {
		push @objects , Vhffs::Object::get_by_oid( $self->get_vhffs, @$_ );
	}
	return \@objects;
}

1;

__END__

=head1 AUTHORS

soda <dieu AT gunnm DOT org>

Sebastien Le Ray <beuss at tuxfamily dot org>
