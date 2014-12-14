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


# This file is a part of VHFFS4 software, a hosting platform suite
# Please respect the licence of this file and whole program

=pod

=head1 NAME

Vhffs::Services::MailingList - Handle mailing lists in VHFFS.

=head1 SYNOPSIS

TODO

=head1 METHODS

=cut

use strict;
use utf8;
use Vhffs::Services::Mail;

package Vhffs::Services::MailingList;

use base qw(Vhffs::Object);
use DBI;

sub _new {
	my ($class, $vhffs, $ml_id, $domain, $localpart, $prefix, $owner_gid, $open_archive, $reply_to, $sub_ctrl, $post_ctrl, $signature, $oid, $owner_uid, $date_creation, $state, $description) = @_;

	my $self = $class->SUPER::_new($vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_ML);
	return undef unless defined($self);

	$self->{ml_id} = $ml_id;
	$self->{localpart} = $localpart;
	$self->{domain} = $domain,
	$self->{prefix} = $prefix;
	$self->{open_archive} = $open_archive;
	$self->{reply_to} = $reply_to;
	$self->{sub_ctrl} = $sub_ctrl;
	$self->{post_ctrl} = $post_ctrl;
	$self->{signature} = $signature;
	$self->{subs} = {};

	return $self;
}

=pod

=head2 create

	my $ml = Vhffs::Services::MailingList::create($vhffs, $localpart, $description, $user, $group);
	die('Unable to create list') unless defined $ml;

Creates a new mailing list in database and returns the corresponding fully functional object.
Returns undef if an error occurs (box, forward or mailing list with the same address already
exists, domain not found, ...).

$localpart must be a previously created C<Vhffs::Services::Mail::Localpart>

=cut
sub create {
	my ($vhffs, $mail, $localpart, $description, $user, $group) = @_;
	return unless defined $mail and defined $localpart and defined $user and defined $group;

	my $ml;

	my $dbh = $vhffs->get_db;
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	eval {
		my $parent = Vhffs::Object::create($vhffs, $user->get_uid, $group->get_gid, $description, undef, Vhffs::Constants::TYPE_ML);
		die('Unable to create parent object') unless defined $parent;

		# Create a new mail localpart if required
		my $lp = $mail->fetch_localpart( $localpart );
		$lp = Vhffs::Services::Mail::Localpart::create( $mail, $localpart ) unless defined $lp;
		die('Unable to create mail localpart object') unless defined $lp;

		# open sub, post members only
		my $sql = 'INSERT INTO vhffs_mx_ml(localpart_id, prefix, object_id, open_archive, reply_to, sub_ctrl, post_ctrl) VALUES (?, ?, ?, FALSE, TRUE, ?, ? )';
		my $sth = $dbh->prepare($sql);
		$sth->execute($lp->{localpart_id}, $lp->get_localpart, $parent->get_oid, Vhffs::Constants::ML_SUBSCRIBE_NO_APPROVAL_REQUIRED, Vhffs::Constants::ML_POSTING_MEMBERS_ONLY);
		$dbh->commit;
		$ml = get_by_mladdress($vhffs, $localpart, $mail->get_domain);
	};

	if($@) {
		warn 'Unable to create mailing list '.$localpart.'@'.$mail->get_domain.': '.$@."\n";
		$dbh->rollback;
	}

	return $ml;
}

=head2 fill_object

See C<Vhffs::Object::fill_object>.

=cut
sub fill_object {
	my ($class, $obj) = @_;
	my $sql = q{SELECT ml.ml_id, mx.domain, mlp.localpart, ml.prefix, o.owner_gid, ml.open_archive, ml.reply_to, ml.sub_ctrl, ml.post_ctrl, ml.signature, o.object_id, o.owner_uid, o.date_creation, o.state, o.description FROM vhffs_mx_ml ml
		INNER JOIN vhffs_object o ON o.object_id = ml.object_id
		INNER JOIN vhffs_mx_localpart mlp ON mlp.localpart_id=ml.localpart_id
		INNER JOIN vhffs_mx mx ON mx.mx_id=mlp.mx_id
		WHERE ml.object_id = ?};
	$obj = $class->SUPER::_fill_object($obj, $sql);
	return $obj;
}

sub getall {
	my ($vhffs, $state, $name, $group, $domain) = @_;

	my $mls = [];
	my @params;

	my $sql = 'SELECT mlp.localpart, mx.domain
		FROM vhffs_mx_ml ml INNER JOIN vhffs_object o ON ml.object_id = o.object_id INNER JOIN vhffs_mx_localpart mlp ON mlp.localpart_id=ml.localpart_id INNER JOIN vhffs_mx mx ON mx.mx_id=mlp.mx_id';
	if(defined $state) {
		$sql .= ' AND o.state = ?';
		push @params, $state;
	}
	if(defined $group) {
		$sql .= ' AND o.owner_gid = ?';
		push @params, $group->get_gid;
	}
	if(defined $name) {
		$sql .= ' AND ( mlp.localpart LIKE ? OR mx.domain LIKE ?)';
		push @params, '%'.$name.'%', '%'.$name.'%';
	}
	if(defined $domain) {
		$sql .= ' AND mx.domain = ?';
		push @params, $domain;
	}
	$sql .= ' ORDER BY mlp.localpart, mx.domain';

	my $dbh = $vhffs->get_db;
	my $sth = $dbh->prepare($sql);
	$sth->execute(@params) or return undef;

	while(my @ml = $sth->fetchrow_array) {
		push @$mls, get_by_mladdress($vhffs, @ml);
	}
	return $mls;
}

=pod

=head2 get_by_mladdress

	my $ml = Vhffs::Services::MailingList::get_by_mladdress($vhffs, $localpart, $domain);
	die("Mailing list $localpart\@$domain not found\n") unless(defined $ml);

Fetches the mailing list $localpart@$domain.

=cut
sub get_by_mladdress {
	my ($vhffs, $local, $domain) = @_;

	my $dbh = $vhffs->get_db();
	my $sql = 'SELECT ml.ml_id, mx.domain, mlp.localpart, ml.prefix, o.owner_gid, ml.open_archive, ml.reply_to, ml.sub_ctrl, ml.post_ctrl, ml.signature, o.object_id, o.owner_uid, o.date_creation, o.state, o.description FROM vhffs_mx_ml ml INNER JOIN vhffs_object o ON o.object_id = ml.object_id INNER JOIN vhffs_mx_localpart mlp ON mlp.localpart_id=ml.localpart_id INNER JOIN vhffs_mx mx ON mx.mx_id=mlp.mx_id WHERE mx.domain = ? and mlp.localpart = ?';
	my $sth = $dbh->prepare($sql);
	return undef unless ($sth->execute($domain, $local) > 0);
	my @params = $sth->fetchrow_array;
	return _new Vhffs::Services::MailingList($vhffs, @params);
}

=pod

=head2 get_by_id

	my $ml = Vhffs::Services::MailingList::get_by_id($vhffs, $mlid);
	die("Mailing list not found\n") unless(defined $ml);

Fetches the mailing list $mlid.

=cut
sub get_by_id {
	my ($vhffs, $id) = @_;

	my $dbh = $vhffs->get_db();
	my $sql = 'SELECT ml.ml_id, mx.domain, mlp.localpart, ml.prefix, o.owner_gid, ml.open_archive, ml.reply_to, ml.sub_ctrl, ml.post_ctrl, ml.signature, o.object_id, o.owner_uid, o.date_creation, o.state, o.description FROM vhffs_mx_ml ml INNER JOIN vhffs_object o ON o.object_id = ml.object_id INNER JOIN vhffs_mx_localpart mlp ON mlp.localpart_id=ml.localpart_id INNER JOIN vhffs_mx mx ON mx.mx_id=mlp.mx_id WHERE ml.ml_id = ?';
	my $sth = $dbh->prepare($sql);
	return undef unless ($sth->execute($id) > 0);
	my @params = $sth->fetchrow_array;
	return _new Vhffs::Services::MailingList($vhffs, @params);
}

=head2 fetch_subs

	my $subs = $ml->fetch_subs;

Returns an hashref of hashrefs containing all subscribers indexed on their
mail addresses.

=cut
sub fetch_subs {
	my $self = shift;

	my $sql = q{SELECT sub_id, member, perm, hash, ml_id, language FROM vhffs_mx_ml_subscribers WHERE ml_id = ?};
	$self->{subs} = $self->get_db->selectall_hashref($sql, 'member', undef, $self->{ml_id});
	return $self->{subs};
}

=head2 fetch_sub

	my $sub = $ml->fetch_sub($mail);

Returns a hashref containing a subscribers.

=cut
sub fetch_sub {
	my $self = shift;
	my $mail = shift;

	my $sql = q{SELECT sub_id, member, perm, hash, ml_id, language FROM vhffs_mx_ml_subscribers WHERE ml_id = ? AND member = ?};
	my $sth = $self->get_db->prepare($sql);
	$sth->execute( $self->{ml_id}, $mail );
	my $sub = $sth->fetchrow_hashref;
	return unless $sub;
	$self->{subs}->{$mail} = $sub;
	return $sub;
}

# Commit all changes of the current instance in the database
sub commit {
	my $self = shift;

	my $sql = 'UPDATE vhffs_mx_ml SET prefix = ?, open_archive = ?, reply_to = ?, sub_ctrl = ?, post_ctrl = ?, signature = ? WHERE ml_id = ?';
	my $dbh = $self->get_db;
	$dbh->do($sql, undef, $self->{prefix}, $self->{open_archive}, $self->{reply_to}, $self->{sub_ctrl}, $self->{post_ctrl}, $self->{signature}, $self->{ml_id});

	return $self->SUPER::commit;
}

sub change_right_for_sub {
	my ($self, $subscriber, $right) = @_;

	my $sql = 'UPDATE vhffs_mx_ml_subscribers SET perm = ? WHERE ml_id = ? AND member = ?';
	my $dbh = $self->get_db;
	# FIXME compatibility hack, we should return a boolean
	return -1 unless($dbh->do($sql, undef, $right, $self->{ml_id}, $subscriber) > 0);
	$self->{subs}->{$subscriber}->{perm} = $right;
	return 1;
}

sub add_sub {
	my $self = shift;
	my $subscriber = lc shift;
	my $right = shift;

	return -1 unless( Vhffs::Functions::valid_mail( $subscriber ) );
	return -2 if $subscriber =~ /[<>\s]/;
	return -3 unless $right =~ /^[\d]+$/;

	my $sql = 'INSERT INTO vhffs_mx_ml_subscribers (member, perm, hash, ml_id, language) VALUES (?, ?, NULL, ?, NULL)';
	my $dbh = $self->get_db;
	$dbh->do($sql, undef, $subscriber, $right, $self->{ml_id}) or return -4;

	my $id = $dbh->last_insert_id(undef, undef, 'vhffs_mx_ml_subscribers', undef);

	$self->{subs}->{$subscriber} = {
		sub_id => $id,
		member => $subscriber,
		perm => $right,
		hash => undef,
		ml_id => $self->{ml_id},
		language => undef
	};

	return 1;
}

#add a subscriber, return undef if already exists
sub add_sub_with_reply {
	my $self = shift;
	my $subscriber = lc shift;

	return undef unless( Vhffs::Functions::valid_mail( $subscriber ) );
	return undef if( $subscriber =~ /.*<.*/ );
	return undef if( $subscriber =~ /.*>.*/ );
	return undef if( $subscriber =~ /.*\s.*/ );

	my $pass = Vhffs::Functions::generate_random_password();

	my $sql = 'INSERT INTO vhffs_mx_ml_subscribers(member, perm, hash, ml_id, language) VALUES(?, ?, ?, ?, NULL)';
	my $dbh = $self->get_db;
	$dbh->do($sql, undef, $subscriber, Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_REPLY, $pass, $self->{ml_id}) or return undef;

	my $id = $dbh->last_insert_id(undef, undef, 'vhffs_mx_ml_subscribers', undef);

	$self->{subs}->{$subscriber} = {
		sub_id => $id,
		member => $subscriber,
		perm => Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_REPLY,
		hash => $pass,
		ml_id => $self->{ml_id},
		language => undef
	};

	return $pass;
}

sub del_sub {
	my $self = shift;
	my $subscriber = shift;

	my $sql = 'DELETE FROM vhffs_mx_ml_subscribers WHERE ml_id = ? AND member = ?';
	# FIXME we should return a boolean
	return -1 unless($self->get_db->do($sql, undef, $self->{ml_id}, $subscriber) > 0);

	delete $self->{subs}->{$subscriber};
	return 1;
}

sub set_randomhash {
	my $self = shift;
	my $subscriber = shift;
	my $pass = Vhffs::Functions::generate_random_password();

	my $sql = 'UPDATE vhffs_mx_ml_subscribers SET hash = ? WHERE ml_id = ? AND member = ?';
	return undef unless($self->get_db->do($sql, undef, $pass, $self->{ml_id}, $subscriber) > 0);

	$self->{subs}->{$subscriber}->{hash} = $pass;
	return $pass;
}

sub clear_hash {
	my $self = shift;
	my $subscriber = shift;

	my $sql = 'UPDATE vhffs_mx_ml_subscribers SET hash = NULL WHERE ml_id = ? AND member = ?';
	# FIXME we should return a boolean
	return -1 unless($self->get_db->do($sql, undef, $self->{ml_id}, $subscriber) > 0);

	$self->{subs}->{$subscriber}->{hash} = undef;
	return 1;
}

sub del_sub_with_reply {
	use Digest::MD5;

	my $self = shift;
	my $subscriber = shift;

	my $hash = Digest::MD5::md5_hex( Vhffs::Functions::generate_random_password() );

	my $sql = 'UPDATE vhffs_mx_ml_subscribers SET perm = ?, hash = ? WHERE ml_id = ? AND member = ? AND perm IN (?, ?)';
	# FIXME we should return a boolean
	return undef unless($self->get_db->do($sql, undef, Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_DEL, $hash, $self->{ml_id}, $subscriber, Vhffs::Constants::ML_RIGHT_SUB, Vhffs::Constants::ML_RIGHT_ADMIN) > 0);

	$self->{subs}->{$subscriber}->{hash} = $hash;
	$self->{subs}->{$subscriber}->{perm} = Vhffs::Constants::ML_RIGHT_SUB_WAITING_FOR_DEL;
	return $hash;
}

sub get_language_for_sub {
	my ($vhffs, $sub) = @_;

	my $sql = 'SELECT language FROM vhffs_mx_ml_subscribers WHERE member = ?';
	my $lang = $vhffs->get_db->selectrow_array($sql, undef, $sub);
	return $lang;
}

sub set_language_for_sub {
	my ($vhffs, $sub, $language) = @_;

	$language = 'en_US' unless( $language =~ /^\w+$/ );
	my $sql = 'UPDATE vhffs_mx_ml_subscribers SET language = ? WHERE member = ?';
	$vhffs->get_db->do($sql, undef, $language, $sub) or return -1;
}

sub get_localpart {
	my $self = shift;
	return $self->{'localpart'};
}

sub get_signature {
	my $self = shift;
	return $self->{signature} if defined $self->{signature} and $self->{signature} !~ /^\s*$/;
	return undef;
}

sub set_signature {
	my ($self, $sig) = @_;
	$sig =~ s/\r\n/\n/;
	$self->{signature} = $sig;
}

sub get_open_archive {
	my $self = shift;
	return $self->{'open_archive'};
}

sub get_sub_ctrl {
	my $self = shift;
	return $self->{'sub_ctrl'};
}

sub get_post_ctrl {
	my $self = shift;
	return $self->{'post_ctrl'};
}

sub get_replyto {
	my $self = shift;
	return $self->{'reply_to'};
}

sub get_domain {
	my $self = shift;
	return $self->{'domain'};
}

sub get_prefix {
	my $self = shift;
	return $self->{'prefix'};
}

sub get_members {
	my $self = shift;
	return $self->{subs};
}

sub set_replyto {
	my( $self, $value ) = @_;
	return -2 unless( $value == 0 or $value == 1);
	$self->{'reply_to'} = $value;
	return 1;
}

sub set_open_archive {
	my( $self, $value ) = @_;
	$self->{'open_archive'} = $value;
}

sub set_sub_ctrl {
	my( $self, $value ) = @_;
	return -1 unless $value =~ /\d+/;
	return -2 if( $value < Vhffs::Constants::ML_SUBSCRIBE_NO_APPROVAL_REQUIRED or $value > Vhffs::Constants::ML_SUBSCRIBE_CLOSED );
	$self->{'sub_ctrl'} = $value;
	return 0;
}

sub set_post_ctrl {
	my( $self, $value ) = @_;
	return -1 unless $value =~ /\d+/;
	return -2 if( $value < Vhffs::Constants::ML_POSTING_OPEN_ALL or $value > Vhffs::Constants::ML_POSTING_ADMINS_ONLY );
	$self->{'post_ctrl'} = $value;
	return 0;
}

sub set_prefix {
	my( $self , $value ) = @_;
	$self->{'prefix'} = $value;
}

sub getall_subs {
	my $self = shift;
	return ( keys %{$self->{subs}} );
}

=head2 get_label

See C<Vhffs::Object::get_label>.

=cut
sub get_label {
	my $self = shift;
	return $self->{localpart}.'@'.$self->{domain};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_service('mailinglist');
}

sub get_listname {
	my $self = shift;
	return $self->get_localpart.'@'.$self->get_domain;
}

sub get_listrequestname {
	my $self = shift;
	return $self->get_localpart.'-request@'.$self->get_domain;
}

1;

__END__

=head1 AUTHORS

Julien Delange < god at gunnm dot org >
Sebastien Le Ray < beuss at tuxfamily dot org >
Sylvain Rochet < gradator at gradator dot net >
