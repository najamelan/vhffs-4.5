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

#Vhffs::ACL written by sod` <dieu AT gunnm DOT org>

# This software is free software, please read LICENCE file

use Vhffs::Constants;

use strict;
use utf8;
use diagnostics;

# Since perl allows us to do such things, let's have an unobstrusive approach
package Vhffs::Object;

=pod

=head1 NAME

Vhffs::Acl - Handle Access Control Lists in VHFFS.

=head1 METHODS

=cut

=pod

=head2 add_acl

	die("Unable to add ACL\n") unless $object->add_acl( $grantedo, $perm );

Grant permission C<$perm> to user or group C<$grantedd> on service C<$object>.

An ACL where C<$object> is a group object is the default access for users of the group.

Returns 1 if success, undef otherwise.

=cut
sub add_acl {
	my $self = shift; # -target- a C<Vhffs::User>, C<Vhffs::Group>, or a C<Vhffs::Services>
	my $object = shift; # -granted- a C<Vhffs::User> or a C<Vhffs::Group>
	my $perm = shift;

	return undef unless defined $object and defined $perm;
	return undef unless( $object->get_type == Vhffs::Constants::TYPE_USER or $object->get_type == Vhffs::Constants::TYPE_GROUP );

	# Refuse to create an ACL if the granted user is the owner of the target
	return undef if $object->get_type == Vhffs::Constants::TYPE_USER and $object->get_owner_uid == $self->get_owner_uid;

	my $dbh = $self->get_db;

	my $sql = 'INSERT INTO vhffs_acl(granted_oid, perm, target_oid) VALUES(?, ?, ?)';
	return undef unless( $dbh->do($sql, undef, $object->get_oid, $perm, $self->get_oid) );
	return 1;
}

=pod

=head2 update_acl

	my $ret = $object->update_acl( $grantedo, $perm );

Update the ACL between $object and $grantedo.

Returns 1 if success, undef otherwise.

=cut
sub update_acl {
	my $self = shift; # -target- a C<Vhffs::User>, C<Vhffs::Group>, or a C<Vhffs::Services>
	my $object = shift; # -granted- a C<Vhffs::User> or a C<Vhffs::Group>
	my $perm = shift;

	return undef unless defined $object and defined $perm;

	my $dbh = $self->get_db;

	# If no line was updated, ACL doesn't exists => error
	return undef unless $dbh->do( 'UPDATE vhffs_acl SET perm = ? WHERE target_oid=? AND granted_oid=?', undef, $perm, $self->get_oid, $object->get_oid) > 0;
	return 1;
}

=pod

=head2 del_acl

	my $ret = $object->del_acl( $grantedo );

Delete the ACL between $objectand $grantedo.

Returns 1 if success, undef otherwise.

=cut
sub del_acl {
	my $self = shift; # -target- a C<Vhffs::User>, C<Vhffs::Group>, or a C<Vhffs::Services>
	my $object = shift; # -granted- a C<Vhffs::User> or a C<Vhffs::Group>

	return undef unless defined $object;

	my $dbh = $self->get_db;

	return undef unless $dbh->do( 'DELETE FROM vhffs_acl WHERE granted_oid=? AND target_oid=?', undef, $object->get_oid, $self->get_oid) > 0;
	return 1;
}

=pod

=head2 add_update_or_del_acl

	my $ret = $object->add_update_or_del_acl( $grantedo, $perm );

This is the magic function. It deletes the ACL entry if $perm equals Vhffs::Constants::ACL_UNDEFINED or
creates the ACL entry if necessary or update the ACL entry if the ACL entry already exists.

Returns 1 if acl has been added, 2 if acl has been updated, 3 if acl has been deleted, undef is something went wrong.

=cut
sub add_update_or_del_acl {
	my $self = shift; # -target- a C<Vhffs::User>, C<Vhffs::Group>, or a C<Vhffs::Services>
	my $object = shift; # -granted- a C<Vhffs::User> or a C<Vhffs::Group>
	my $perm = shift;

	return undef unless defined $object and defined $perm;

	if( $perm == Vhffs::Constants::ACL_UNDEFINED ) {
		return 3 if $self->del_acl( $object );
		return undef;
	}

	return 2 if $self->update_acl( $object, $perm );
	return 1 if $self->add_acl( $object, $perm );
	return undef;
}

=pod

=head2 get_acl

	my $rights = $object->get_acl();

Returns an array of hashref with keys 'granted_oid, name, perm'.
A NULL perm is a non existing ACL.
A NULL name is the default ACL.

Also add implicit ACL in case of undefined ACL (owner, default access for users of the group);

Example:
	 granted_oid |   name   |   uid    | perm
	-------------+----------+----------+-----
	           3 | (nul)    | (nul)    |    0   <== default ACL
	           1 | user1    | 10000    |    2
	          25 | user2    | 10010    |   10
	          72 | user3    | 10020    |   -1   <== user without ACL
	(4 rows)

=cut
sub get_acl {
	my $self = shift; # -target- a C<Vhffs::User>, C<Vhffs::Group>, or a C<Vhffs::Services>

	my $dbh = $self->get_db;

	my $sth = $dbh->prepare('SELECT u.object_id AS granted_oid, u.username AS name, u.uid AS uid, aclu.perm FROM vhffs_users u INNER JOIN vhffs_user_group ug ON ug.uid=u.uid INNER JOIN vhffs_object o ON o.owner_gid=ug.gid LEFT OUTER JOIN (SELECT acl.granted_oid, acl.perm FROM vhffs_acl acl WHERE acl.target_oid=?) AS aclu ON aclu.granted_oid=u.object_id WHERE o.object_id=? UNION SELECT g.object_id AS granted_oid, NULL AS name, NULL AS uid, aclu.perm FROM vhffs_groups g INNER JOIN vhffs_object o ON o.owner_gid=g.gid LEFT OUTER JOIN (SELECT acl.granted_oid, acl.perm FROM vhffs_acl acl WHERE acl.target_oid=?) AS aclu ON aclu.granted_oid=g.object_id WHERE o.object_id=? ORDER BY name ASC');
	return undef unless $sth->execute( $self->get_oid, $self->get_oid, $self->get_oid, $self->get_oid );
	my $acls = $sth->fetchall_arrayref({});

	my $default_acl;
	my $owner_acl;
	my $users_acls = [];
	# If someone find a way to do that using SQL, please do ;-)
	foreach my $acl ( @{$acls} )  {

		# Owner
		if( defined $acl->{uid} and $acl->{uid} == $self->get_owner_uid ) {
			$acl->{perm} = Vhffs::Constants::ACL_DELETE unless defined $acl->{perm};
			$owner_acl = $acl
		}

		# A real ACL
		elsif( defined $acl->{name} ) {
			$acl->{perm} = Vhffs::Constants::ACL_UNDEFINED unless defined $acl->{perm};
			push( @$users_acls, $acl );
		}

		# Default ACL (group ACL)
		else {
			$acl->{perm} = Vhffs::Constants::ACL_VIEW unless defined $acl->{perm};
			$default_acl = $acl;
		}
	}

	return ( $default_acl, $owner_acl, $users_acls );
}

=pod

=head2 get_perm

	my $perm = $object->get_perm( $targetobject );

Returns the permission of C<$object> (actually always a C<Vhffs::User>)
for C<$targetobject> (actually always a C<Vhffs::User>, C<Vhffs::Group>, or a C<Vhffs::Services>)

=cut
sub get_perm {
	my $self = shift; # -granted- a C<Vhffs::User>
	my $object = shift; # -target- a C<Vhffs::User>, C<Vhffs::Group>, or a C<Vhffs::Services>

	# Returns ACL_DENIED if $self is not a C<Vhffs::User>, managing other cases are complicated and totally useless
	# Also, access to objects in states other than ACTIVATED are denied, unless user is an administrator
	return Vhffs::Constants::ACL_DENIED unless defined $object and $self->get_type == Vhffs::Constants::TYPE_USER and ($object->get_status == Vhffs::Constants::ACTIVATED or $self->is_admin);

	# Administrators have full access to objects, whatever the current object state
	# Users have full access to their objets (where object owner_uid equals user uid)
	return Vhffs::Constants::ACL_DELETE if ($self->is_admin or $object->get_owner_uid == $self->get_owner_uid);

	my $dbh = $self->get_db;

	# Fetch user ACL (if any)
	my $perm = $dbh->selectrow_array('SELECT acl.perm FROM vhffs_acl acl WHERE acl.granted_oid=? AND acl.target_oid=?', undef, $self->get_oid, $object->get_oid);

	# User specific ACL is not defined, try to find group ACL, but first, check if user is in the group
	unless( defined $perm ) {
		# Else, which should be the default case, check if user is a member of the object group, otherwise set ACL_DENIED
		my $isusergroup = $dbh->selectrow_array('SELECT COUNT(*) FROM vhffs_user_group ug WHERE ug.uid=? and ug.gid=?', undef, $self->get_owner_uid, $object->get_owner_gid);
		$perm = Vhffs::Constants::ACL_DENIED unless $isusergroup;
	}

	# User is in the group (if user is not, $perm is set to ACL_DENIED)
	unless( defined $perm ) {
		# Fetch default ACL (on group)
		$perm = $dbh->selectrow_array('SELECT acl.perm FROM vhffs_acl acl INNER JOIN vhffs_groups g ON g.object_id=acl.granted_oid WHERE g.gid=? AND acl.target_oid=?', undef, $object->get_owner_gid, $object->get_oid);

		# Default access to group object if user is in the group
		$perm = Vhffs::Constants::ACL_VIEW unless defined $perm;
	}

	# Default perm if perm is undefined
	$perm = Vhffs::Constants::ACL_DENIED unless defined $perm;

	# But moderators have view access to all objects
	$perm = Vhffs::Constants::ACL_VIEW if $self->is_moderator and $perm < Vhffs::Constants::ACL_VIEW;

	return $perm;
}

=head2 can_view

	die("You are not allowed to view this object\n") unless($object->can_view($object));

Returns true if the object on which the method is called can view the given object.

=cut
sub can_view {
	my ($self, $object) = @_;
	return ( $self->get_perm($object) >= Vhffs::Constants::ACL_VIEW );
}

=head2 can_modify

	die("You are not allowed to modify this object\n") unless($object->can_modify($object));

Returns true if the object on which the method is called can modify the given object.

=cut
sub can_modify {
	my ($self, $object) = @_;
	return ( $self->get_perm($object) >= Vhffs::Constants::ACL_MODIFY );
}

=head2 can_manageacl

	die("You are not allowed to manage acl on this object\n") unless($object->can_manageacl($object));

Returns true if the object on which the method is called can modify ACLs on the given object.

=cut
sub can_manageacl {
	my ($self, $object) = @_;
	return ( $self->get_perm($object) >= Vhffs::Constants::ACL_MANAGEACL );
}

=head2 can_delete

	die("You are not allowed to delete this object\n") unless($object->can_delete($object));

Returns true if the object on which the method is called can delete the given object.

=cut
sub can_delete {
	my ($self, $object) = @_;
	return ( $self->get_perm($object) >= Vhffs::Constants::ACL_DELETE );
}

1;
