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

use strict;
use utf8;

package Vhffs::Object;

use Vhffs::Constants;
use Vhffs::Acl;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Encode;

=head1 SYNOPSIS

Vhffs::Object - The generic object type in VHFFS

=head1 DESCRIPTION

The Vhffs::Object type is the base of each Vhffs::Services::*, Vhffs::User
or Vhffs::Group objects. So, you never have to create an instance of Vhffs::Object,
this class is only used as a super-class for services (or user or group).

So, the methods of Vhffs::Object can be applied to all classes which inherit of it.
You can have all the history of an object with a method, get the status
of a service, ...

This type store information about state, history, owner group/user.

=cut

=pod
=head1 CLASS METHODS
=cut

=pod

=head2 _new

	Self constructor, almost private, please use get_by_* methods instead.

=cut
sub _new {
	my ($class, $vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, $refuse_reason, $state, $type) = @_;

	my $self = {};

	bless($self, $class);

	return undef unless(defined $vhffs);

	$self->{vhffs} = $vhffs;
	$self->{object_id} = $oid;
	$self->{owner_uid} = $owner_uid;
	$self->{owner_gid} = $owner_gid;
	$self->{date_creation} = $date_creation;
	$self->{description} = $description;
	$self->{refuse_reason} = $refuse_reason;
	$self->{state} = $state;
	$self->{type} = $type;

	return $self;
}

=head2 create

my $object = Vhffs::Object::create($vhffs, [$owner_uid, $owner_gid, $description, $state, $type])

Create (in database) and return a new object.

=over 4

=item C<$vhffs>: C<Vhffs> instance

=item C<$owner_uid>: UID of the owner.

=item C<$description>: Description of the object

=item C<$state>: state of the object. Can be undef, if it is, object will be
waiting for validation or waiting for creation depending on wether
moderation is active or not.

=item C<$type>: Object's type (C<Vhffs::Constants::TYPE_*>)

=back

=cut
sub create {
	my ($vhffs, $owner_uid, $owner_gid, $description, $state, $type) = @_;
	$description = '' unless defined $description;
	$description =~ s/\r\n/\n/g;
	$state = ($vhffs->get_config->get_moderation ? Vhffs::Constants::WAITING_FOR_VALIDATION : Vhffs::Constants::WAITING_FOR_CREATION) unless defined $state;
	my $sth = $vhffs->get_db->prepare('INSERT INTO vhffs_object(owner_uid, owner_gid, date_creation, state, description, type) VALUES ( ?, ?, ?, ?, ?, ?)');
	$sth->execute($owner_uid, $owner_gid, time(), $state, $description, $type) or return undef;
	my $oid = $vhffs->get_db->last_insert_id(undef, undef, 'vhffs_object', undef);

	my $object = get_by_oid($vhffs, $oid);
	$object->get_status == Vhffs::Constants::WAITING_FOR_VALIDATION ? $object->add_history('Object created, waiting for validation') : $object->add_history('Object created');
	return $object;
}

=pod

=head2 get_by_oid

my $obj = Vhffs::Object::get_by_oid($vhffs, $oid);

Fetches an object using its object ID. Returned object is
fully functional.

=cut
sub get_by_oid {
	my ($vhffs, $oid) = @_;
	return undef unless ( defined $oid && $oid =~ /^\d+$/ );

	my $query = 'SELECT owner_uid, owner_gid, date_creation, description, refuse_reason, state, type FROM vhffs_object WHERE object_id =?';
	my $sth = $vhffs->get_db->prepare( $query );
	my $rows = $sth->execute( $oid );

	return undef unless $rows == 1;

	my @result = $sth->fetchrow_array();

	my $object = _new Vhffs::Object($vhffs, $oid, @result);

	return $object;
}

=pod

=head2 getall( Vhffs , $name )

The getall is very important and defined in every service. In Vhffs::Object,
it returns all object if $name is not defined (undef). Return all objects that matches with $name if $name is defined.

If $name is undefined, the functions returns ALL objects.

=cut
sub getall {
	my $vhffs = shift;
	my $name = shift;
	my $state = shift;
	my $age = shift; #seconds late

	my $query = 'SELECT o.object_id, o.owner_uid, o.owner_gid, o.date_creation , o.description, o.refuse_reason, o.state, o.type FROM vhffs_object o';
	my @params;

	if( defined $name ) {
		$query .= ' INNER JOIN vhffs_users u ON o.owner_uid = u.uid INNER JOIN vhffs_groups g ON o.owner_gid = g.gid WHERE ( o.description LIKE ? ) OR ( o.object_id LIKE ? ) OR ( o.owner_uid LIKE ? ) OR ( state LIKE ? ) OR ( u.username LIKE ? ) OR ( g.groupname LIKE ? )';
		push(@params, '%'.$name.'%');
		push(@params, '%'.$name.'%');
		push(@params, '%'.$name.'%');
		push(@params, '%'.$name.'%');
		push(@params, '%'.$name.'%');
		push(@params, '%'.$name.'%');
	}
	if( defined $state ) {
		if( $query =~ /WHERE/ ) {
			$query .= ' AND o.state = ?';
		}
		else {
			$query .= ' WHERE o.state = ?';
		}
		push(@params, $state);
	}
	if( defined $age ) {
		my $ts = time() - $age;

		if( $query =~ /WHERE/ ) {
			$query .= ' AND date_creation < ? ';
		}
		else {
			$query .= ' WHERE date_creation < ? ';
		}
		push(@params, $ts);
	}

	$query .= ' ORDER BY object_id';

	my $request = $vhffs->get_db->prepare( $query ) or return -1;
	return undef unless $request->execute(@params);

	my $result;
	my $rows = $request->fetchall_arrayref();
	foreach(@$rows) {
		push(@$result, _new Vhffs::Object($vhffs, @$_));
	}
	return $result;
}

=pod

=head2 fill_object

my $svc = Vhffs::Service::XXX::fill_object($obj);

This method should be overloaded in every subclasses.
Its goal is to transform a given object into a more
specialized subclass.

=cut
sub fill_object {
	my ($class, $obj) = @_;
	warn 'Unimplemented fill_object method'."\n";
	return $obj;
}

=pod

=head2 _fill_object

my $svc = $class->SUPER::_fill_object($obj, $sql);

Convenience method to implement fill_object in subclasses.

Adds fields returned by C<$sql> query to object $obj and, if the query succeed,
bless the object with C<$class>.

C<$sql> must contain a placeholder (?) which will be filled with the object
OID. See subclasses implementation of C<fill_object> for more details.

=cut
sub _fill_object {
	my ($class, $obj, $sql) = @_;
	my $dbh = $obj->get_db();
	my $res = $dbh->selectrow_hashref($sql, undef, $obj->get_oid);
	return $obj unless(defined $res);
	foreach(keys %$res) {
		$obj->{$_} = $res->{$_};
	}
	return bless($obj, $class);
}

=pod
=head1 INSTANCE METHODS
=cut

=pod

=head2 commit

Apply all changes that were made on this object. Returns undef value if failed, true if success.

=cut
sub commit {
	my $self = shift;

	my $request = 'UPDATE vhffs_object SET state=?, description=?, refuse_reason=?, owner_uid=?, owner_gid=? WHERE object_id=?';
	my $result = $self->get_db->prepare($request);
	$result->execute( $self->{'state'} , $self->{'description'} , $self->{'refuse_reason'}, $self->{'owner_uid'} , $self->{'owner_gid'} , $self->{'object_id'} ) or return undef;
	return 1;
}

=pod

=head2 get_vhffs

This method returns the Vhffs object contained in this object.
This method can be useful if you have an object and you need a Vhffs instance.

=cut
sub get_vhffs {
	my $self = shift;
	return $self->{'vhffs'};
}

=pod

=head2 get_db

Return DBH object to backend.

=cut
sub get_db {
	my $self = shift;
	return $self->get_vhffs->get_db;
}

=pod

=head1 get_config

Returns the configuration for this object. Should be redefined in every subclasses
(for example, Web returns the web configuration).

=cut
sub get_config {
	return;
}

=pod

=head2 delete

Delete the object. This method is called from inherited class or directly if
the sub class does not need a delete method.

Note that it destroy the object-part (history, ...), but not the inherited class.

Returns undef value if fails, true if success.

=cut
sub delete {
	my $self = shift;

	# Foreign key constraints are in 'ON DELETE CASCADE' mode
	# we don't have to bother with foreign tables deletion.
	my $query = 'DELETE FROM vhffs_object WHERE object_id=?';
	my $request = $self->get_db->prepare($query);
	$request->execute( $self->{'object_id'} ) or return undef;

	return 1;
}

=pod

=head2 set_owner_uid

Change the uid of the owner of this object.

=cut
sub set_owner_uid {
	my ( $self , $value ) = @_;
	$self->{'owner_uid'} = $value;
}

=pod

=head2 get_owner_uid

Returns the uid that owns this Object.

=cut
sub get_owner_uid {
	my $self = shift;
	return $self->{'owner_uid'};
}

=pod

=head2 set_owner_gid

Change the gid of the group of this object.

=cut
sub set_owner_gid {
	my ( $self , $value ) = @_;
	$self->{'owner_gid'} = $value;
}

=pod

=head2 get_owner_gid

Returns the gid that owns this Object.

=cut
sub get_owner_gid {
	my $self = shift;
	return $self->{'owner_gid'};
}

=pod

=head2 get_type

Returns the object type. See C<Vhffs::Constants>

=cut
sub get_type {
	my $self = shift;
	return $self->{type};
}

=pod

=head2 get_date

Returns the date of the creation for this object.

=cut
sub get_date {
	my $self = shift;
	return $self->{'date_creation'};
}

=pod

=head2 get_oid

Returns the object_id of this Object.

=cut
sub get_oid {
	my $self = shift;
	return $self->{'object_id'};
}

=pod

=head2 get_description

Returns the description of this object.

=cut
sub get_description {
	my $self = shift;
	return $self->{'description'};
}

=pod

=head2 get_status

Get the status of this object. The status are given in the Vhffs::Constants class.

=cut
sub get_status {
	my $self = shift;
	return $self->{'state'};
}

=head2 get_label

Returns a label for this object that can be used to display information.
Should be redefined in every subclasses (for example, Web returns the
servername).

=cut
sub get_label {
	return '????';
}

=pod

=head2 set_status

Change the status of an object. The status are available as constants in Vhffs::Constants class. When you change the status of an object, a message is added in its history.

=cut
sub set_status {
	my ($self, $value) = @_;
	return if $self->{'state'} == $value;
	$self->{'state'} = $value;

	if( $value == Vhffs::Constants::WAITING_FOR_VALIDATION ) {
		$self->add_history( 'Waiting for validation' );
	}
	elsif( $value == Vhffs::Constants::VALIDATION_REFUSED ) {
		$self->add_history( 'Validation refused' );
	}
	elsif( $value == Vhffs::Constants::WAITING_FOR_CREATION ) {
		$self->add_history( 'Validation accepted. Will be created' );
	}
	elsif( $value == Vhffs::Constants::CREATION_ERROR ) {
		$self->add_history( 'An error occured while creating this object' );
	}
	elsif( $value == Vhffs::Constants::WAITING_FOR_ACTIVATION ) {
		$self->add_history( 'Waiting for activation' );
	}
	elsif( $value == Vhffs::Constants::ACTIVATED ) {
		$self->add_history( 'Is now active for production' );
	}
	elsif( $value == Vhffs::Constants::ACTIVATION_ERROR ) {
		$self->add_history( 'An error occured while activating this object' );
	}
	elsif( $value == Vhffs::Constants::WAITING_FOR_SUSPENSION ) {
		$self->add_history( 'Waiting for suspension' );
	}
	elsif( $value == Vhffs::Constants::SUSPENDED ) {
		$self->add_history( 'Suspended' );
	}
	elsif( $value == Vhffs::Constants::SUSPENSION_ERROR ) {
		$self->add_history( 'An error occured while suspending this object' );
	}
	elsif( $value == Vhffs::Constants::WAITING_FOR_MODIFICATION ) {
		$self->add_history( 'Waiting for modification' );
	}
	elsif( $value == Vhffs::Constants::MODIFICATION_ERROR ) {
		$self->add_history( 'An error occured while modifying this object' );
	}
	elsif( $value == Vhffs::Constants::WAITING_FOR_DELETION ) {
		$self->add_history( 'Will be deleted' );
	}
	elsif( $value == Vhffs::Constants::DELETION_ERROR ) {
		$self->add_history( 'An error occured while deleting this objet' );
	}
}

=pod

=head2 set_description( $string )

Change the description of an object. As all accessors, you need to call commit() method after.

=cut
sub set_description {
	my ($self , $value) = @_;
	$value =~ s/\r\n/\n/g;
	$self->{'description'} = $value ;
}

=pod

=head2 add_history( $string )

Add a message in the object's history. Don't forget to set current user through $vhffs->set_current_user before.

=cut
sub add_history {
	my $self = shift;
	my $message = shift;
	my $user = $self->get_vhffs->get_current_user->get_uid if defined $self->get_vhffs->get_current_user;

	my $query = 'INSERT INTO vhffs_history(object_id, date, message, source_uid) VALUES(?, ?, ?, ?)';
	my $request = $self->get_db->prepare( $query );
	$request->execute( $self->{'object_id'}, time(), $message, $user ) or return -2;

	return $self->get_db->last_insert_id(undef, undef, 'vhffs_history', undef);;
}

=pod

=head2 get_history( )

Returns an hashref that represent the history of this object. This object has as key the date of each history message. For exemple :

$history = $object->get_history();

if( defined $history ) {
	foreach $key ( keys %{$history} ) {

		print "At date " . $key . " message: " . $history->{$key}{'message'};
	}
}

=cut
sub get_history {
	my $self = shift;

	my $dbh = $self->get_db;
	my $sql = 'SELECT history_id, message, date, source.username as source FROM vhffs_history h LEFT JOIN vhffs_users source ON source.uid = h.source_uid WHERE h.object_id = ? ORDER BY h.date DESC, h.history_id DESC';
	return $dbh->selectall_arrayref($sql, {Slice => {}}, $self->{object_id});
}

=pod

=head2 set_refuse_reason( $reason )

Set refuse reason for this object, with reason $reason.

=cut
sub set_refuse_reason {
	my ($self , $value) = @_;
	$self->{'refuse_reason'} = $value;
}

=pod

=head2 get_refuse_reason()

Get refusal reason of this object.

=cut
sub get_refuse_reason {
	my $self = shift;
	return gettext('no reason given') unless defined $self->{'refuse_reason'} and length $self->{'refuse_reason'} > 0;
	return $self->{'refuse_reason'};
}

=pod

=head2 moderate_accept( $comment )

Accept this object, with optional comment $comment.

=cut
sub moderate_accept {
	my $self = shift;
	my $comments = shift;

	my $vhffs = $self->get_vhffs;
	my $user = $self->get_owner;

	$self->set_status( Vhffs::Constants::WAITING_FOR_CREATION );
	$self->set_refuse_reason( '' );

	# TODO: write a beautiful module for INTL
	bindtextdomain('vhffs', '%localedir%');
	textdomain('vhffs');

	my $prevlocale = setlocale( LC_ALL );
	setlocale( LC_ALL , $user->get_lang );

	my $mail;

	my $docstr = '';
	$docstr = sprintf( gettext("Related documentation is available at:\n  %s\n\n"), $self->get_config->{'url_doc'} ) if $self->get_config->{'url_doc'};

	if(defined $comments and $comments =~ /\S/) {
		$mail = sprintf(
			gettext( "Hello %s %s,\n\nYour request for a %s (%s) on %s was accepted, however, moderators wanted to add some precision:\n%s.\n\n%sPlease wait while we are creating your object.\n\nCheers,\nThe moderator team\n\n---------\n%s\n%s\n" ) ,
		$user->get_firstname,
		$user->get_lastname,
		Vhffs::Functions::type_string_from_type_id( $self->get_type ),
		$self->get_label,
		$vhffs->get_config->get_host_name,
		$comments,
		$docstr,
		$vhffs->get_config->get_host_name,
		$vhffs->get_config->get_panel->{url}
		);
	} else {
		$mail = sprintf(
			gettext( "Hello %s %s,\n\nYour request for a %s (%s) on %s was accepted.\n\n%sPlease wait while we are creating your object.\n\nCheers,\nThe moderator team\n\n---------\n%s\n%s\n" ) ,
		$user->get_firstname,
		$user->get_lastname,
		Vhffs::Functions::type_string_from_type_id( $self->get_type ),
		$self->get_label,
		$vhffs->get_config->get_host_name,
		$docstr,
		$vhffs->get_config->get_host_name,
		$vhffs->get_config->get_panel->{url}
		);
	}
	my $subject = sprintf(
		gettext('Your request for a %s (%s) on %s was accepted'),
		Vhffs::Functions::type_string_from_type_id( $self->get_type ),
		$self->get_label,
		$vhffs->get_config->get_host_name
		);

	Vhffs::Functions::send_mail( $vhffs , $vhffs->get_config->get_moderator_mail , $user->get_mail , $vhffs->get_config->get_mailtag , $subject , $mail );

	setlocale( LC_ALL , $prevlocale );

	$user->set_note( $user->get_note +1 );
	$user->set_validated( 1 );
	$user->commit;

	return $self->commit;
}

=pod

=head2 moderate_refuse( $reason )

Refuse this object, with reason $reason.

=cut
sub moderate_refuse {
	my $self = shift;
	my $reason = shift;

	my $vhffs = $self->get_vhffs;
	my $user = $self->get_owner;

	$self->set_status( Vhffs::Constants::VALIDATION_REFUSED );
	$self->set_refuse_reason( $reason );

	# TODO: write a beautiful module for INTL
	bindtextdomain('vhffs', '%localedir%');
	textdomain('vhffs');

	my $prevlocale = setlocale( LC_ALL );
	setlocale( LC_ALL , $user->get_lang );

	my $docstr = '';
	$docstr = sprintf( gettext("Related documentation is available at:\n  %s\n\n"), $self->get_config->{'url_doc'} ) if $self->get_config->{'url_doc'};

	my $mail = sprintf(
		gettext( "Hello %s %s,\n\nYour request for a %s (%s) on %s was refused.\n\nThe reason of refusal given by moderators is:\n%s\n\nYou can change the description and submit it again for moderation on the\npanel. You can delete this object on the panel if you have made\na mistake. Don't be upset, if you don't understand why your request has\nbeen refused, just reply to this email !\n\n%sCheers,\nThe moderator team\n\n---------\n%s\n%s\n" ) ,

		$user->get_firstname,
		$user->get_lastname,
		Vhffs::Functions::type_string_from_type_id( $self->get_type ),
		$self->get_label,
		$vhffs->get_config->get_host_name,
		$self->get_refuse_reason,
		$docstr,
		$vhffs->get_config->get_host_name,
		$vhffs->get_config->get_panel->{url}
		);

	my $subject = sprintf(
		gettext('Your request for a %s (%s) on %s was refused'),
		Vhffs::Functions::type_string_from_type_id( $self->get_type ),
		$self->get_label,
		$vhffs->get_config->get_host_name
		);

	Vhffs::Functions::send_mail( $vhffs , $vhffs->get_config->get_moderator_mail , $user->get_mail , $vhffs->get_config->get_mailtag , $subject , $mail );

	setlocale( LC_ALL , $prevlocale );

	$user->set_note( $user->get_note -1 );
	$user->commit;

	return $self->commit;
}

=pod

=head2 send_created_mail

Send an email to the owner of the object indicating that the object has been created

=cut
sub send_created_mail {
	my $self = shift;

	my $vhffs = $self->get_vhffs;
	my $user = $self->get_owner;

	# TODO: write a beautiful module for INTL
	bindtextdomain('vhffs', '%localedir%');
	textdomain('vhffs');

	my $prevlocale = setlocale( LC_ALL );
	setlocale( LC_ALL , $user->get_lang );

	my $docstr = '';
	$docstr = sprintf( gettext("Related documentation is available at:\n  %s\n\n"), $self->get_config->{'url_doc'} ) if $self->get_config->{'url_doc'};

	my $mail = sprintf(
		gettext( "Hello %s %s,\n\nYour %s (%s) on %s was successfully created.\n\n%sEnjoy!\n\nCheers,\nThe moderator team\n\n---------\n%s\n%s\n" ) ,
		$user->get_firstname,
		$user->get_lastname,
		Vhffs::Functions::type_string_from_type_id( $self->get_type ),
		$self->get_label,
		$vhffs->get_config->get_host_name,
		$docstr,
		$vhffs->get_config->get_host_name,
		$vhffs->get_config->get_panel->{url}
		);
	my $subject = sprintf(
		gettext('Your %s (%s) on %s was successfully created'),
		Vhffs::Functions::type_string_from_type_id( $self->get_type ),
		$self->get_label,
		$vhffs->get_config->get_host_name
		);

	Vhffs::Functions::send_mail( $vhffs , $vhffs->get_config->get_moderator_mail , $user->get_mail , $vhffs->get_config->get_mailtag , $subject , $mail );

	setlocale( LC_ALL , $prevlocale );
}

=pod

=head2 delete_withmail()

Delete this object, sending a nice mail to the owner.

=cut
sub delete_withmail {
	my $self = shift;

	my $vhffs = $self->get_vhffs;
	my $user = $self->get_owner;

	# TODO: write a beautiful module for INTL
	bindtextdomain('vhffs', '%localedir%');
	textdomain('vhffs');

	my $prevlocale = setlocale( LC_ALL );
	setlocale( LC_ALL , $user->get_lang );

	my $docstr = '';
	$docstr = sprintf( gettext("Related documentation is available at:\n  %s\n\n"), $self->get_config->{'url_doc'} ) if $self->get_config->{'url_doc'};

	my $mail = sprintf(
		gettext( "Hello %s %s,\n\nYour %s (%s) on %s has been deleted.\n\nThis is because it have been refused a long time ago and you didn't\nsubmit an update since.\n\nFor reminder, the reason of refusal was:\n%s\n\nDon't be upset, submit it again if you forgot to update it in time.\nIf you need further information, just reply to this email !\n\n%sCheers,\nThe moderator team\n\n---------\n%s\n%s\n" ) ,

		$user->get_firstname,
		$user->get_lastname,
		Vhffs::Functions::type_string_from_type_id( $self->get_type ),
		$self->get_label,
		$vhffs->get_config->get_host_name,
		$self->get_refuse_reason,
		$docstr,
		$vhffs->get_config->get_host_name,
		$vhffs->get_config->get_panel->{url}
		);

	my $subject = sprintf(
		gettext('Your %s (%s) on %s has been deleted due to lack of updates'),
		Vhffs::Functions::type_string_from_type_id( $self->get_type ),
		$self->get_label,
		$vhffs->get_config->get_host_name
		);

	Vhffs::Functions::send_mail( $vhffs , $vhffs->get_config->get_moderator_mail , $user->get_mail , $vhffs->get_config->get_mailtag , $subject , $mail );

	setlocale( LC_ALL , $prevlocale );

	$self->delete;
}

=pod

=head2 resubmit_for_moderation( $description )

Put an object back in waiting for moderation state, using the new $description description.

=cut
sub resubmit_for_moderation {
	my $self = shift;
	my $description = shift;

	return -1 unless defined $description;
	return -1 if( $self->get_status != Vhffs::Constants::VALIDATION_REFUSED );

	$self->set_description( $description );
	$self->set_status( Vhffs::Constants::WAITING_FOR_VALIDATION );
	return $self->commit;
}

=pod

=head2 get_group

my $group = $object->get_group;

Returns a Vhffs::Group object of the group of the Vhffs::Object object.

=cut
sub get_group {
	my $self = shift;
	return $self->{'group'} if defined $self->{'group'};
	require Vhffs::Group;
	$self->{'group'} = Vhffs::Group::get_by_gid( $self->get_vhffs, $self->{'owner_gid'} );
	return $self->{'group'};
}

=pod

=head2 get_owner

my $owner = $object->get_owner;

Returns a Vhffs::User object of the owner of the Vhffs::Object object.

=cut
sub get_owner {
	my $self = shift;
	return $self->{'user'} if defined $self->{'user'};
	require Vhffs::User;
	$self->{'user'} = Vhffs::User::get_by_uid( $self->get_vhffs, $self->{'owner_uid'} );
	return $self->{'user'};
}

1;

__END__

=head1 SEE ALSO
Vhffs::Constants Vhffs::User Vhffs::Group

=head1 AUTHOR

	Julien Delange <julien at gunnm dot org>

=head1 COPYRIGHT

	Julien Delange <julien at gunnm dot org>
