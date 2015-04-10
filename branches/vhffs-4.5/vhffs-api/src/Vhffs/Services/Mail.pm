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

=head1 SYNOPSYS

Vhffs::Services::Mail - Handle mail domains in VHFFS.

=head2 METHODS

=cut

use strict;
use utf8;

use DBI;
use Vhffs::Functions;
use Vhffs::Services::MailingList;

package Vhffs::Services::Mail;

use constant {
	CATCHALL_ALLOW_NONE => 1,
	CATCHALL_ALLOW_DOMAIN => 2,
	CATCHALL_ALLOW_OPEN => 3,
};


package Vhffs::Services::Mail::Localpart;

=head2 _new

	Self constructor, almost private.

=cut
sub _new {
	my ($class, $mail, $localpart_id, $localpart, $password, $nospam, $novirus ) = @_;
	my $self = {};
	bless( $self, $class );
	$self->{mail} = $mail; # a C<Vhffs::Services::Mail>
	$self->{localpart_id} = $localpart_id;
	$self->{localpart} = $localpart;
	$self->{password} = $password;
	$self->{nospam} = $nospam;
	$self->{novirus} = $novirus;
	return $self;
}

=head2 create

	Create a C<Vhffs::Services::Mail::Localpart> in database.

	Returns a C<Vhffs::Services::Mail::Localpart> which is not yet attached to C<Vhffs::Services::Mail> to allow using SQL transactions.

=cut
sub create {
	my $mail = shift; # a C<Vhffs::Services::Mail>
	my $localpart = shift;

	return undef unless defined $localpart and $localpart =~ Vhffs::Constants::MAIL_VALID_LOCAL_PART;

	my $query = 'INSERT INTO vhffs_mx_localpart (localpart_id, mx_id, localpart, password, nospam, novirus) VALUES(DEFAULT, ?, ?, DEFAULT, DEFAULT, DEFAULT) RETURNING localpart_id,localpart,password,nospam,novirus';
	my $request = $mail->get_db->prepare( $query );
	$request->execute( $mail->{mx_id}, $localpart ) or return;

	my @returning = $request->fetchrow_array;
	return _new Vhffs::Services::Mail::Localpart( $mail, @returning );
}

=head2 commit

	$box->commit or die();

Commit all changes of the current localpart in the database

=cut
sub commit {
	my $self = shift;

	my $query = 'UPDATE vhffs_mx_localpart SET password=?,nospam=?,novirus=? WHERE localpart_id=?';
	return $self->{mail}->get_db->do($query, undef, $self->{password}, $self->{nospam}, $self->{novirus}, $self->{localpart_id});
}

=head2 get_mail

	my $mail = $box->get_mail

Returns the C<Vhffs::Services::Mail>.

=cut
sub get_mail {
	my $self = shift;
	return $self->{mail};
}

=head2 get_localpart

	my $localpart = $lp->get_localpart;

Returns the localpart name.

=cut
sub get_localpart {
	my $self = shift;
	return $self->{localpart};
}

=head2 get_redirects

	my $redirects = $lp->get_redirects;

Returns a hashref of all redirects of a localpart.

=cut
sub get_redirects {
	my $self = shift;
	return $self->{redirects};
}

=head2 get_redirect

	my $redirect = $lp->get_redirect( $remote );

Returns a C<Vhffs::Services::Mail::Redirect> from $remote name.

=cut
sub get_redirect {
	my $self = shift;
	my $remote = shift;
	return undef unless defined $remote and defined $self->get_redirects;
	return $self->get_redirects->{$remote};
}

=head2 get_box

	my $box = $lp->get_box;

Returns the localpart's box.

=cut
sub get_box {
	my $self = shift;
	return $self->{box};
}

=head2 get_ml

	my $ml = $lp->get_ml;

Returns the mailing list embryo.

=cut
sub get_ml {
	my $self = shift;
	return $self->{ml};
}

=head2 get_nospam

	my $nospam = $lp->get_nospam;

Returns whether spam filtering is enabled or not.

=cut
sub get_nospam {
	my $self = shift;
	return $self->{nospam};
}

=head2 set_nospam

	$lp->set_nospam( $enable );

Unset or set the spam filtering.

=cut
sub set_nospam {
	my $self = shift;
	my $on = shift;
	$self->{nospam} = $on ? 1 : 0;
}

=head2 toggle_nospam

	$lp->toggle_nospam;

Toggle nospam flag.

=cut
sub toggle_nospam {
	my $self = shift;
	$self->{nospam} = ($self->{nospam}+1)%2;
}

=head2 get_novirus

	my $novirus = $lp->get_novirus;

Returns whether virus filtering is enabled or not.

=cut
sub get_novirus {
	my $self = shift;
	return $self->{novirus};
}

=head2 set_novirus

	$lp->set_novirus( $enable );

Unset or set the virus filtering.

=cut
sub set_novirus {
	my $self = shift;
	my $on = shift;
	$self->{novirus} = $on ? 1 : 0;
}

=head2 toggle_novirus

	$lp->toggle_novirus;

Toggle novirus flag.

=cut
sub toggle_novirus {
	my $self = shift;
	$self->{novirus} = ($self->{novirus}+1)%2;
}

=head2 set_password

	$lp->set_password( $password );

Set the localpart password. Undef or a likely-null value clear the password.

=cut
sub set_password {
	my $self = shift;
	my $password = shift;
	unless( defined $password and $password !~ /^\s*$/ ) {
		$self->{password} = undef;
		return;
	}
	$self->{password} = Vhffs::Services::Mail::password_encrypt( $password );
	return 1;
}

=head2 check_password

	$lp->check_password( $clearpassword );

Check the localpart password, return true or false.

=cut
sub check_password {
	my $self = shift;
	my $clearpw = shift;
	return ( $self->{password} eq crypt( $clearpw, $self->{password} ) );
}

=head2 nb_ref

	my $ref = $lp->nb_ref;

Returns the number of referenced stuff on this localpart. (box + redirects + ml)

=cut
sub nb_ref {
	my $self = shift;
	my $ref = 0;
	$ref++ if $self->get_box;
	$ref++ if $self->get_box and $self->get_box->get_status != Vhffs::Constants::WAITING_FOR_DELETION; # a created box count twice!
	$ref++ if $self->get_ml;
	$ref+= scalar( keys %{$self->get_redirects} ) if $self->get_redirects;
	return $ref;
}

=head2 delete

	Remove a C<Vhffs::Services::Mail::Localpart> from database, and much more.

	Actually calling the C<Vhffs::Services::Mail> delete_localpart method.

=cut
sub delete {
	my $self = shift;
	my $force = shift;
	return $self->{mail}->delete_localpart( $self, $force );
}

=head2 destroy

	Remove a C<Vhffs::Services::Mail::Localpart> from database.

	You should call delete instead of destroy, destroy remove the localpart without checking anything.

=cut
sub destroy {
	my $self = shift;

	my $sql = 'DELETE FROM vhffs_mx_localpart WHERE localpart_id=?';
	return $self->{mail}->get_db->do($sql, undef, $self->{localpart_id});
}


package Vhffs::Services::Mail::Box;

=head2 _new

	Self constructor, almost private.

=cut
sub _new {
	my ($class, $localpart, $box_id, $allowpop, $allowimap, $state ) = @_;
	my $self = {};
	bless( $self, $class );
	$self->{localpart} = $localpart; # a C<Vhffs::Services::Mail::Localpart>
	$self->{box_id} = $box_id;
	$self->{allowpop} = $allowpop;
	$self->{allowimap} = $allowimap;
	$self->{state} = $state;
	return $self;
}

=head2 create

	Create a C<Vhffs::Services::Mail::Box> in database.

	Returns a C<Vhffs::Services::Mail::Box> which is not yet attached to C<Vhffs::Services::Mail::Localpart> to allow using SQL transactions.

=cut
sub create {
	my $lp = shift; # a C<Vhffs::Services::Mail::Localpart>

	my $query = 'INSERT INTO vhffs_mx_box (box_id, localpart_id, allowpop, allowimap, state) VALUES(DEFAULT, ?, DEFAULT, DEFAULT, ?) RETURNING box_id,allowpop,allowimap,state';
	my $request = $lp->{mail}->get_db->prepare( $query );
	$request->execute( $lp->{localpart_id}, Vhffs::Constants::WAITING_FOR_CREATION ) or return;

	my @returning = $request->fetchrow_array;
	return _new Vhffs::Services::Mail::Box( $lp, @returning );
}

=head2 commit

	$box->commit or die();

Commit all changes of the current box in the database

=cut
sub commit {
	my $self = shift;

	my $query = 'UPDATE vhffs_mx_box SET allowpop=?,allowimap=?,state=? WHERE box_id=?';
	return $self->{localpart}->{mail}->get_db->do($query, undef, $self->{allowpop}, $self->{allowimap}, $self->{state}, $self->{box_id});
}

=head2 get_mail

	my $mail = $box->get_mail

Returns the C<Vhffs::Services::Mail>.

=cut
sub get_mail {
	my $self = shift;
	return $self->{localpart}->{mail};
}

=head2 get_localpart

	my $localpart = $box->get_localpart;

Returns the C<Vhffs::Services::Mail::Localpart>.

=cut
sub get_localpart {
	my $self = shift;
	return $self->{localpart};
}

=head2 get_boxname

	my $boxname = $box->get_boxname;

Returns the box' full email.

=cut
sub get_boxname {
	my $self = shift;
	return $self->{localpart}->get_localpart.'@'.$self->{localpart}->{mail}->get_domain;
}

=head2 get_status

	my $state = $box->get_status;

Returns the box' status.

=cut
sub get_status {
	my $self = shift;
	return $self->{state};
}

=head2 set_status

	$box->set_status( $status );

Set the box' status.

=cut
sub set_status {
	my $self = shift;
	my $state = shift;
	$self->{state} = $state;
}

=head2 get_allowpop

	my $allowpop = $box->get_allowpop;

Returns whether POP is allowed.

=cut
sub get_allowpop {
	my $self = shift;
	return $self->{allowpop};
}

=head2 set_allowpop

	$box->set_allowpop( $allow );

Set whether POP is allowed.

=cut
sub set_allowpop {
	my $self = shift;
	my $allow = shift;
	$self->{allowpop} = $allow ? 1 : 0;
}

=head2 get_allowimap

	my $allowimap = $box->get_allowimap;

Returns whether IMAP is allowed.

=cut
sub get_allowimap {
	my $self = shift;
	return $self->{allowimap};
}

=head2 set_allowimap

	$box->set_allowimap( $allow );

Set whether IMAP is allowed.

=cut
sub set_allowimap {
	my $self = shift;
	my $allow = shift;
	$self->{allowimap} = $allow ? 1 : 0;
}

=head2 get_dir

Returns mail box dir.

=cut
sub get_dir {
	my $self = shift;
	my $lp = $self->{localpart};
	return( $lp->{mail}->get_dir().'/'.substr( $lp->get_localpart, 0, 1 ).'/'.$lp->get_localpart );
}

=head2 delete

	Remove a C<Vhffs::Services::Mail::Box> from database, and much more.

	Actually calling the C<Vhffs::Services::Mail> delete_box method.

=cut
sub delete {
	my $self = shift;
	return $self->{localpart}->{mail}->delete_box( $self );
}

=head2 destroy

	Remove a C<Vhffs::Services::Mail::Box> from database.

	You should call delete instead of destroy, destroy only remove the box without deleting the localpart if necessary.

=cut
sub destroy {
	my $self = shift;

	my $sql = 'DELETE FROM vhffs_mx_box WHERE box_id=?';
	return $self->{localpart}->{mail}->get_db->do($sql, undef, $self->{box_id});
}


package Vhffs::Services::Mail::Redirect;

=head2 _new

	Self constructor, almost private.

=cut
sub _new {
	my ($class, $localpart, $redirect_id, $redirect ) = @_;
	my $self = {};
	bless( $self, $class );
	$self->{localpart} = $localpart; # a C<Vhffs::Services::Mail::Localpart>
	$self->{redirect_id} = $redirect_id;
	$self->{redirect} = $redirect;
	return $self;
}

=head2 create

	Create a C<Vhffs::Services::Mail::Redirect> in database.

	Returns a C<Vhffs::Services::Mail::Redirect> which is not yet attached to C<Vhffs::Services::Mail::Localpart> to allow using SQL transactions.

=cut
sub create {
	my $lp = shift; # a C<Vhffs::Services::Mail::Localpart>
	my $remote = shift;

	return undef unless defined $remote and Vhffs::Functions::valid_mail( $remote );

	my $query = 'INSERT INTO vhffs_mx_redirect (redirect_id, localpart_id, redirect) VALUES(DEFAULT, ?, ?) RETURNING redirect_id,redirect';
	my $request = $lp->{mail}->get_db->prepare( $query );
	$request->execute( $lp->{localpart_id}, $remote ) or return;

	my @returning = $request->fetchrow_array;
	return _new Vhffs::Services::Mail::Redirect( $lp, @returning );
}

=head2 commit

	$redirect->commit or die();

Commit all changes of the current redirect in the database

=cut
sub commit {
	my $self = shift;

	my $query = 'UPDATE vhffs_mx_redirect SET redirect=? WHERE redirect_id=?';
	return $self->{localpart}->{mail}->get_db->do($query, undef, $self->{redirect}, $self->{redirect_id});
}

=head2 get_mail

	my $mail = $box->get_mail

Returns the C<Vhffs::Services::Mail>.

=cut
sub get_mail {
	my $self = shift;
	return $self->{localpart}->{mail};
}

=head2 get_localpart

	my $localpart = $box->get_localpart;

Returns the C<Vhffs::Services::Mail::Localpart>.

=cut
sub get_localpart {
	my $self = shift;
	return $self->{localpart};
}

=head2 delete

	Remove a C<Vhffs::Services::Mail::Redirect> from database, and much more.

	Actually calling the C<Vhffs::Services::Mail> delete_redirect method.

=cut
sub delete {
	my $self = shift;
	return $self->{localpart}->{mail}->delete_redirect( $self );
}

=head2 destroy

	Remove a C<Vhffs::Services::Mail::Redirect> from database.

	You should call delete instead of destroy, destroy only remove the redirect without deleting the localpart if necessary.

=cut
sub destroy {
	my $self = shift;

	my $sql = 'DELETE FROM vhffs_mx_redirect WHERE redirect_id=?';
	return $self->{localpart}->{mail}->get_db->do($sql, undef, $self->{redirect_id});
}

=head2 get_redirect

	my $remote = $redirect->get_redirect;

Returns the redirect destination (remote).

=cut
sub get_redirect {
	my $self = shift;
	return $self->{redirect};
}

=head2 set_redirect

	$redirect->set_redirect( $remote );

Set the redirect remote address.

=cut
sub set_redirect {
	my $self = shift;
	my $remote = shift;
	return undef unless defined $remote and Vhffs::Functions::valid_mail( $remote );
	$self->{redirect} = $remote;
	return 1;
}


package Vhffs::Services::Mail::Ml;

=head2 _new

	Self constructor, almost private.

=cut
sub _new {
	my ( $class, $localpart, $ml_id ) = @_;
	my $self = {};
	bless( $self, $class );
	$self->{localpart} = $localpart; # a C<Vhffs::Services::Mail::Localpart>
	$self->{ml_id} = $ml_id;
	return $self;
}

=head2 get_mail

	my $mail = $ml->get_mail

Returns the C<Vhffs::Services::Mail>.

=cut
sub get_mail {
	my $self = shift;
	return $self->{localpart}->{mail};
}

=head2 get_localpart

	my $localpart = $ml->get_localpart;

Returns the C<Vhffs::Services::Mail::Localpart>.

=cut
sub get_localpart {
	my $self = shift;
	return $self->{localpart};
}

=head2 get_ml_object

	my $ml = $ml->get_ml_object;

Returns the full C<Vhffs::Services::MailingList> object.

=cut
sub get_ml_object {
	my $self = shift;
	require Vhffs::Services::MailingList;
	return Vhffs::Services::MailingList::get_by_id( $self->get_mail->get_vhffs, $self->{ml_id} );
}

package Vhffs::Services::Mail::Catchall;

=head2 _new

	Self constructor, almost private.

=cut
sub _new {
	my ($class, $mail, $catchall_id, $box_id, $boxname ) = @_;
	my $self = {};
	bless( $self, $class );
	$self->{mail} = $mail; # a C<Vhffs::Services::Mail>
	$self->{catchall_id} = $catchall_id;
	$self->{box_id} = $box_id;
	$self->{boxname} = $boxname;
	return $self;
}

=head2 create

	Create a C<Vhffs::Services::Mail::Catchall> in database.

	Returns a C<Vhffs::Services::Mail::Catchall> which is not yet attached to C<Vhffs::Services::Mail> to allow using SQL transactions.

=cut
sub create {
	my $mail = shift; # a C<Vhffs::Services::Mail>
	my $box = shift; # a C<Vhffs::Services::Mail::Box>

	my $query = 'INSERT INTO vhffs_mx_catchall (catchall_id, mx_id, box_id) VALUES(DEFAULT, ?, ?) RETURNING catchall_id';
	my $request = $mail->get_db->prepare( $query );
	$request->execute( $mail->{mx_id}, $box->{box_id} ) or return;

	my @returning = $request->fetchrow_array;
	return _new Vhffs::Services::Mail::Catchall( $mail, @returning, $box->{box_id}, $box->get_boxname );
}

=head2 get_catchall

	my $boxname = $catchall->get_catchall;

Returns the catchcall boxname

=cut
sub get_catchall {
	my $self = shift;
	return $self->{boxname};
}

=head2 get_mail

	my $mail = $box->get_mail

Returns the C<Vhffs::Services::Mail>.

=cut
sub get_mail {
	my $self = shift;
	return $self->{mail};
}

=head2 delete

	Remove a C<Vhffs::Services::Mail::Catchall> from database, and much more.

	Actually calling the C<Vhffs::Services::Mail> delete_catchall method.

=cut
sub delete {
	my $self = shift;
	return $self->{mail}->delete_catchall( $self );
}

=head2 destroy

	Remove a C<Vhffs::Services::Mail::Catchall> from database.

	You should call delete instead of destroy, destroy remove the catchall without checking anything.

=cut
sub destroy {
	my $self = shift;

	my $sql = 'DELETE FROM vhffs_mx_catchall WHERE catchall_id=?';
	return $self->{mail}->get_db->do($sql, undef, $self->{catchall_id});
}


package Vhffs::Services::Mail;
use base qw(Vhffs::Object);

=pod

=head2 password_encrypt

my $encryptedpass = Vhffs::Services::Mail::password_encrypt( $pass );

Returns a sha512 crypt password from plain text password. Salt is randomized.

=cut
sub password_encrypt {
	my $password = shift;
	return crypt($password, '$6$'.join( '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[map {rand 64} (1..16)]) );
}

=head2 _new

	Self constructor, almost private.

=cut
sub _new {
	my ($class, $vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, $state, $mx_id, $domain, $localparts) = @_;
	my $self = $class->SUPER::_new($vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_MAIL);
	return undef unless defined $self;

	$self->{mx_id} = $mx_id;
	$self->{domain} = $domain;
	$self->{nb_localparts} = 0;
	$self->{nb_boxes} = 0;
	$self->{nb_redirects} = 0;
	$self->{nb_mls} = 0;
	$self->{nb_catchalls} = 0;
	$self->{localpart} = {};
	$self->{catchall} = {};

	my $mail_config = $self->get_config;
	my $allowed_catchall = CATCHALL_ALLOW_DOMAIN;
	$allowed_catchall = CATCHALL_ALLOW_NONE if $mail_config->{allowed_catchall} =~ /^none$/i;
	$allowed_catchall = CATCHALL_ALLOW_OPEN if $mail_config->{allowed_catchall} =~ /^open$/i;
	$self->{conf_allowed_catchall} = $allowed_catchall;

	return $self;
}

=pod

=head2 create

	my $mail = Vhffs::Services::Mail::create($vhffs, $domain, $description, $user, $group);

Create a new domain mail in database and return corresponding object.

=cut
sub create {
	my ($vhffs, $domain, $description, $user, $group) = @_;
	return undef unless(defined($user) && defined($group));
	return undef unless(Vhffs::Functions::check_domain_name($domain));

	my $mail;
	my $dbh = $vhffs->get_db;
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	eval {
		my $parent = Vhffs::Object::create($vhffs, $user->get_uid, $group->get_gid, $description, undef, Vhffs::Constants::TYPE_MAIL);

		die('Unable to create parent object') unless(defined $parent);

		my $sql = 'INSERT INTO vhffs_mx(domain, object_id) VALUES(?, ?)';
		my $sth = $dbh->prepare($sql);
		$sth->execute($domain, $parent->get_oid);

		$dbh->commit;
		$mail = get_by_mxdomain($vhffs, $domain);
	};

	if($@) {
		warn 'Unable to create mail domain '.$domain.': '.$@."\n";
		$dbh->rollback;
	}

	return $mail;
}

=head2 fill_object

See C<Vhffs::Object::fill_object>.

=cut
sub fill_object {
	my ($class, $obj) = @_;
	my $sql = q{SELECT mx_id, domain FROM vhffs_mx WHERE object_id = ?};
	$obj = $class->SUPER::_fill_object($obj, $sql);
	return $obj;
}

=head2 getall

	my @mails = Vhffs::Services::Mail::getall( $vhffs, $state, $name, $group );

Returns C<Vhffs::Services::Mail> objects based on $state and/or part of $name and/or owned by a C<Vhffs::Group>.

=cut
sub getall {
	my ($vhffs, $state, $name, $group) = @_;

	my $mail = [];
	my @params;

	my $sql = 'SELECT m.domain
		FROM vhffs_mx m INNER JOIN vhffs_object o ON m.object_id=o.object_id';
	if(defined $state) {
		$sql .= ' AND o.state=?';
		push(@params, $state);
	}
	if(defined $name) {
		$sql .= ' AND m.domain LIKE ?';
		push(@params, '%'.$name.'%');
	}
	if(defined $group) {
		$sql .= ' AND o.owner_gid= ?';
		push(@params, $group->get_gid);
	}
	$sql .= ' ORDER BY m.domain';

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare( $sql );
	$sth->execute(@params) or return undef;

	while( my $s = $sth->fetchrow_hashref() ) {
		push( @$mail, get_by_mxdomain( $vhffs, $s->{domain} ) );
	}
	return $mail;
}

=pod

=head2 get_by_mxdomain

	my $mail = Vhffs::Services::get_by_mxdomain($vhffs, $domain);
	die("Mail domain $domain not found\n") unless(defined $mail);

Fetches the mail services whose domainname is $domain.

=cut
sub get_by_mxdomain {
	my ($vhffs, $domain) = @_;

	my $sql = 'SELECT o.object_id, o.owner_uid, o.owner_gid, o.date_creation, o.description, o.state, m.mx_id, m.domain FROM vhffs_mx m INNER JOIN vhffs_object o ON o.object_id=m.object_id WHERE m.domain=?';
	my $dbh = $vhffs->get_db;
	my @params;
	return undef unless(@params = $dbh->selectrow_array($sql, undef, $domain));

	return _new Vhffs::Services::Mail( $vhffs, @params );
}

=head2 fetch_localparts

	my $lps = $mail->fetch_localparts;

Fill $mail->{localpart} with a hashref of hashrefs containing all this domain's boxes,
redirects, mailing lists embryo, indexed on localpart.

Also fetch catchall entries.

Returns the $mail->{localpart}, but should only be called once.

=cut
sub fetch_localparts {
	my $mail = shift;
	my $localparts = {};
	my $catchalls = {};
	$mail->{nb_localparts} = 0;
	$mail->{nb_catchalls} = 0;
	$mail->{nb_boxes} = 0;
	$mail->{nb_redirects} = 0;
	$mail->{nb_mls} = 0;

	# Localparts
	my $sql = 'SELECT mxl.localpart_id,mxl.localpart,mxl.password,mxl.nospam,mxl.novirus FROM vhffs_mx_localpart mxl WHERE mxl.mx_id=?';
	my $sth = $mail->get_db->prepare($sql);
	$sth->execute($mail->{mx_id});
	while ( my @lp = $sth->fetchrow_array ) {
		my $o = _new Vhffs::Services::Mail::Localpart( $mail, @lp );
		$localparts->{$o->{localpart}} = $o;
		$mail->{nb_localparts}++;
	}

	# Catchall
	$sql = 'SELECT mxc.catchall_id,mb.box_id,mxl.localpart||\'@\'||mx.domain AS boxname FROM vhffs_mx_catchall mxc INNER JOIN vhffs_mx_box mb ON mb.box_id=mxc.box_id INNER JOIN vhffs_mx_localpart mxl ON mxl.localpart_id=mb.localpart_id INNER JOIN vhffs_mx mx ON mx.mx_id=mxl.mx_id WHERE mxc.mx_id=?';
	$sth = $mail->get_db->prepare($sql);
	$sth->execute($mail->{mx_id});
	while ( my @catchall = $sth->fetchrow_array ) {
		my $o = _new Vhffs::Services::Mail::Catchall( $mail, @catchall );
		$catchalls->{$o->{boxname}} = $o;
		$mail->{nb_catchalls}++;
	}

	# Boxes
	$sql = 'SELECT mxl.localpart,mb.box_id,mb.allowpop,mb.allowimap,mb.state FROM vhffs_mx_box mb INNER JOIN vhffs_mx_localpart mxl ON mb.localpart_id=mxl.localpart_id WHERE mxl.mx_id=?';
	$sth = $mail->get_db->prepare($sql);
	$sth->execute($mail->{mx_id});
	while ( my @box = $sth->fetchrow_array ) {
		my $lp = $localparts->{ shift @box };
		$lp->{box} = _new Vhffs::Services::Mail::Box( $lp, @box );
		$mail->{nb_boxes}++;
	}

	# Redirects
	$sql = 'SELECT mxl.localpart,mr.redirect_id,mr.redirect FROM vhffs_mx_redirect mr INNER JOIN vhffs_mx_localpart mxl ON mr.localpart_id=mxl.localpart_id WHERE mxl.mx_id=?';
	$sth = $mail->get_db->prepare($sql);
	$sth->execute($mail->{mx_id});
	while ( my @redirect = $sth->fetchrow_array ) {
		my $lp = $localparts->{ shift @redirect };
		my $o = _new Vhffs::Services::Mail::Redirect( $lp, @redirect );
		$lp->{redirects}->{$o->{redirect}} = $o;
		$mail->{nb_redirects}++;
	}

	# Embryos of ML (embryos because we are Vhffs::Services::Mail, not Vhffs::Services::MailingList, but we need to have a way to know which localparts are actually a mailing list)
	$sql = 'SELECT mxl.localpart,ml.ml_id FROM vhffs_mx_ml ml INNER JOIN vhffs_mx_localpart mxl ON ml.localpart_id=mxl.localpart_id WHERE mxl.mx_id=?';
	$sth = $mail->get_db->prepare($sql);
	$sth->execute($mail->{mx_id});
	while ( my @ml = $sth->fetchrow_array ) {
		my $lp = $localparts->{ shift @ml };
		$lp->{ml} = _new Vhffs::Services::Mail::Ml( $lp, @ml );
		$mail->{nb_mls}++;
	}

	$mail->{catchall} = $catchalls;
	$mail->{localpart} = $localparts;
	return $localparts;
}

=head2 fetch_localpart

	my $lp = $mail->fetch_localpart( $localpart );

Fill $mail->{localpart} with a new hashref entry containing one localpart.

Useful for mailing lists, MailGroup and MailUser modules, so that we don't fetch all localparts.

=cut
sub fetch_localpart {
	my $mail = shift;
	my $localpart_name = shift;

	# Localpart
	my $sql = 'SELECT mxl.localpart_id,mxl.localpart,mxl.password,mxl.nospam,mxl.novirus FROM vhffs_mx_localpart mxl WHERE mxl.mx_id=? AND mxl.localpart=?';
	my $sth = $mail->get_db->prepare($sql);
	$sth->execute($mail->{mx_id}, $localpart_name);
	my @lp = $sth->fetchrow_array;
	return unless @lp;
	my $localpart = _new Vhffs::Services::Mail::Localpart( $mail, @lp );

	# Box
	$sql = 'SELECT mb.box_id,mb.allowpop,mb.allowimap,mb.state FROM vhffs_mx_box mb INNER JOIN vhffs_mx_localpart mxl ON mb.localpart_id=mxl.localpart_id WHERE mxl.localpart_id=?';
	$sth = $mail->get_db->prepare($sql);
	$sth->execute($localpart->{localpart_id});
	my @box = $sth->fetchrow_array;
	$localpart->{box} = _new Vhffs::Services::Mail::Box( $localpart, @box ) if @box;

	# Redirects
	$sql = 'SELECT mr.redirect_id,mr.redirect FROM vhffs_mx_redirect mr INNER JOIN vhffs_mx_localpart mxl ON mr.localpart_id=mxl.localpart_id WHERE mxl.localpart_id=?';
	$sth = $mail->get_db->prepare($sql);
	$sth->execute($localpart->{localpart_id});
	while ( my @redirect = $sth->fetchrow_array ) {
		my $o = _new Vhffs::Services::Mail::Redirect( $localpart, @redirect );
		$localpart->{redirects}->{$o->{redirect}} = $o;
	}

	# Embryos of ML (embryos because we are Vhffs::Services::Mail, not Vhffs::Services::MailingList, but we need to have a way to know which localparts are actually a mailing list)
	$sql = 'SELECT ml.ml_id FROM vhffs_mx_ml ml INNER JOIN vhffs_mx_localpart mxl ON ml.localpart_id=mxl.localpart_id WHERE mxl.localpart_id=?';
	$sth = $mail->get_db->prepare($sql);
	$sth->execute($localpart->{localpart_id});
	my @ml = $sth->fetchrow_array;
	$localpart->{ml} = _new Vhffs::Services::Mail::Ml( $localpart, @ml ) if @ml;

	$mail->{localpart}->{$localpart->{localpart}} = $localpart;
	return $localpart;
}

=head2 commit

	$mail->commit or die();

Commit all changes of the current instance in the database

=cut
sub commit {
	my $self = shift;
	return $self->SUPER::commit;
}

=head2 get_label

See C<Vhffs::Object::get_label>.

=cut
sub get_label {
	my $self = shift;
	return $self->{domain};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_service('mail');
}

=head2 get_domain

	my $domain = $mail->get_domain;

Returns domain name.

=cut
sub get_domain {
	my $self = shift;
	return $self->{domain};
}

=head2 get_dir

Returns mail domain root dir.

=cut
sub get_dir {
	my $self = shift;
	return( $self->get_vhffs->get_config->get_datadir.'/mail/boxes/'.substr( $self->{domain}, 0, 1 ).'/'.substr( $self->{domain}, 1, 1 ).'/'.$self->{domain} );
}

=head2 nb_localparts

Returns the number of localparts on this domain.

=cut
sub nb_localparts {
	my $self = shift;
	return $self->{nb_localparts};
}

=head2 nb_boxes

Returns the number of boxes on this domain.

=cut
sub nb_boxes {
	my $self = shift;
	return $self->{nb_boxes};
}

=head2 nb_redirects

Returns the number of redirects on this domain.

=cut
sub nb_redirects {
	my $self = shift;
	return $self->{nb_redirects};
}

=head2 nb_mls

Returns the number of mailing lists on this domain.

=cut
sub nb_mls {
	my $self = shift;
	return $self->{nb_mls};
}

=head2 nb_catchalls

Returns the number of catchalls on this domain.

=cut
sub nb_catchalls {
	my $self = shift;
	return $self->{nb_catchalls};
}

=head2 get_localparts

	my $localparts = $mail->get_localparts;

Returns a hashref with all localparts
The key of this hash is the local part for the forward

=cut
sub get_localparts {
	my $self = shift;
	return $self->{localpart};
}

=head2 get_localpart

	my $localpart = $mail->get_localpart( $localname );

Returns a C<Vhffs::Services::Mail::Localpart> from $localname.

=cut
sub get_localpart {
	my $self = shift;
	my $localpart = shift;
	return undef unless defined $localpart and defined $self->get_localparts;
	return $self->get_localparts->{$localpart};
}

=pod

=head2 delete_localpart

	die("Unable to delete localpart $localpart\n") unless $mail->delete_localpart($localpart);

Delete a localpart from $localpart@$mail->get_domain.

=cut
sub delete_localpart {
	my $self = shift;
	my $localpart = shift; # a C<Vhffs::Services::Mail::Localpart> object
	my $force = shift;
	return undef unless defined $localpart and $localpart->{mail} == $self; # Do not be cheated

	# FIXME: Should we recursively delete all objects referencing this localpart ?
	# That would be a lovely feature but quite hard to implement
	# at least it requires to redesign fetch_localparts sub

	# Count references, only delete localpart if references are below 1
	my $ref = $force ? 0 : $localpart->nb_ref;

	return undef if $ref > 1;
	return $localpart->destroy;
}

=pod

=head2 add_redirect

	die("Unable to add redirect $localpart to $remote\n") unless $mail->add_redirect($localpart, $remote);

Add a redirect from $localpart@$mail->get_domain to $remote.

=cut
sub add_redirect {
	my $self = shift;
	my $localpart = shift;
	my $remote = shift;

	# $localpart is checked by Localpart class
	# $remote is checked by Redirect class

	my $lp = $self->get_localpart($localpart);
	return undef if defined $lp and defined $lp->{redirects}->{$remote};
	my $redirect;

	my $dbh = $self->get_db;
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	eval {
		# create localpart if necessary
		unless( defined $lp ) {
			$lp = Vhffs::Services::Mail::Localpart::create( $self, $localpart );
			die unless defined $lp;
		}

		# create redirect
		$redirect = Vhffs::Services::Mail::Redirect::create( $lp, $remote );
		die unless defined $redirect;

		$dbh->commit;
	};

	if($@) {
		$dbh->rollback;
		return undef;
	}

	# Attach localpart and box
	unless( defined $self->get_localparts->{$localpart} ) {
		$self->get_localparts->{$localpart} = $lp;
		$self->{nb_localparts}++;
	}
	$lp->{redirects}->{$remote} = $redirect;
	$self->{nb_redirects}++;

	$self->add_history( $localpart.'@'.$self->get_domain.' forward added to '.$remote );
	return $redirect;
}

=pod

=head2 get_redirects

	$redirects = $mail->get_redirects( $localpart );

Returns a hashref of C<Vhffs::Services::Mail::Redirect> from $localpart.

=cut
sub get_redirects {
	my $self = shift;
	my $localpart = shift;
	return undef unless defined $localpart;
	my $lp = $self->get_localpart($localpart);
	return undef unless defined $lp;
	return $lp->get_redirects;
}

=pod

=head2 get_redirect

	$redirect = $mail->get_redirect( $localpart, $remote );

Returns a C<Vhffs::Services::Mail::Redirect> from $localpart and $remote.

=cut
sub get_redirect {
	my $self = shift;
	my $localpart = shift;
	my $remote = shift;
	return undef unless defined $localpart and defined $remote;
	my $lp = $self->get_localpart($localpart);
	return undef unless defined $lp;
	return $lp->get_redirect($remote);
}

=pod

=head2 delete_redirect

	die("Unable to delete redirect $localpart to $redirect->get_redirect\n") unless $mail->delete_redirect($localpart, $redirect);

Delete a redirect from $localpart@$mail->get_domain to $redirect->get_redirect.

=cut
sub delete_redirect {
	my $self = shift;
	my $redirect = shift; # a C<Vhffs::Services::Mail::Redirect> object
	return undef unless defined $redirect;

	my $lp = $redirect->{localpart};
	return undef unless defined $lp and $lp->{mail} == $self; # Do not be cheated

	my $dbh = $self->get_db;
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	my $lpdestroyed;
	eval {
		# delete redirect
		die unless $redirect->destroy;
		$lpdestroyed = $lp->delete;

		$dbh->commit;
	};

	if($@) {
		$dbh->rollback;
		return undef;
	}

	# Detach localpart and redirect
	delete $lp->{redirects}->{$redirect->get_redirect};
	$self->{nb_redirects}--;
	if( $lpdestroyed ) {
		delete $self->get_localparts->{$lp->get_localpart};
		$self->{nb_localparts}--;
	}

	$self->add_history( $lp->get_localpart.'@'.$self->get_domain.' to '.$redirect->get_redirect.' forward deleted' );
	return 1;
}

=pod

=head2 add_box

	die("Unable to create box\n") unless($mail->add_box($localpart, $password);

Add a new mailbox to the mail domain.

=cut
sub add_box {
	my $self = shift;
	my $localpart = shift;
	my $password = shift;
	my $ishashed = shift;

	# $localpart is checked by Localpart class

	return undef unless defined $password;

	my $lp = $self->get_localpart($localpart);
	return undef if defined $lp and defined $lp->{box};
	my $box;

	my $dbh = $self->get_db;
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	eval {
		# create localpart if necessary
		unless( defined $lp ) {
			$lp = Vhffs::Services::Mail::Localpart::create( $self, $localpart );
			die unless defined $lp;
		}
		# update the password
		unless( $ishashed ) {
			$lp->set_password( $password );
		} else {
			$lp->{password} = $password;
		}
		$lp->commit;

		# create box
		$box = Vhffs::Services::Mail::Box::create( $lp );
		die unless defined $box;

		$dbh->commit;
	};

	if($@) {
		$dbh->rollback;
		return undef;
	}

	# Attach localpart and box
	unless( defined $self->get_localparts->{$localpart} ) {
		$self->get_localparts->{$localpart} = $lp;
		$self->{nb_localparts}++;
	}
	$lp->{box} = $box;
	$self->{nb_boxes}++;

	$self->add_history( $localpart.'@'.$self->get_domain.' mail box added' );
	return $box;
}

=pod

=head2 get_box

	my $box = $mail->get_box( $localpart );

Returns the C<Vhffs::Services::Mail::Box> from $localpart.

=cut
sub get_box {
	my $self = shift;
	my $localpart = shift;
	return undef unless defined $localpart;
	my $lp = $self->get_localpart($localpart);
	return undef unless defined $lp;
	return $lp->get_box;
}

=pod

=head2 delete_box

	die("Unable to delete box $localpart\n") unless $mail->delete_box($localpart);

Delete a box from $localpart@$mail->get_domain.

=cut
sub delete_box {
	my $self = shift;
	my $box = shift; # a C<Vhffs::Services::Mail::Box> object
	return undef unless defined $box and $box->get_status == Vhffs::Constants::WAITING_FOR_DELETION; 

	my $lp = $box->{localpart};
	return undef unless defined $lp and $lp->{mail} == $self; # Do not be cheated

	my $dbh = $self->get_db;
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	my $lpdestroyed;
	eval {
		# delete box
		die unless $box->destroy;
		$lpdestroyed = $lp->delete;

		$dbh->commit;
	};

	if($@) {
		$dbh->rollback;
		return undef;
	}

	# Detach localpart and box
	delete $lp->{box};
	$self->{nb_boxes}--;
	if( $lpdestroyed ) {
		delete $self->get_localparts->{$lp->get_localpart};
		$self->{nb_localparts}--;
	}

	$self->add_history( $lp->get_localpart.'@'.$self->get_domain.' mail box deleted' );
	return 1;
}

=pod

=head2 add_catchall

	die("Unable to create catchall\n") unless($mail->add_catchall($boxname);

Add a new catchall box to the mail domain.

=cut
sub add_catchall {
	my $self = shift;
	my $box = shift; # a C<Vhffs::Services::Mail::Box> object, belonging to this domain or not

	return unless defined $box;
	return if $self->get_catchall($box);

	# Is catchall allowed ?
	return if $self->{conf_allowed_catchall} == CATCHALL_ALLOW_NONE;
	return if $self->{conf_allowed_catchall} == CATCHALL_ALLOW_DOMAIN and $box->{localpart}->{mail}->get_domain ne $self->get_domain;

	# create catchcall
	my $catchall = Vhffs::Services::Mail::Catchall::create( $self, $box );
	return unless defined $catchall;

	# Attach catchall
	$self->get_catchalls->{$catchall->get_catchall} = $catchall;
	$self->{nb_catchalls}++;

	$self->add_history( $catchall->get_catchall.' catchall box added' );
	return $catchall;
}

=head2 get_catchalls

	my $catchalls = $mail->get_catchalls;

Returns a hashref with all catchalls
The key of this hash is the full catchall boxname local@domaine.

=cut
sub get_catchalls {
	my $self = shift;
	return $self->{catchall};
}

=head2 get_catchall

	my $catchall = $mail->get_catchall( $boxname );

Returns a C<Vhffs::Services::Mail::Localpart> from $localname.

=cut
sub get_catchall {
	my $self = shift;
	my $catchall = shift;
	return undef unless defined $catchall and defined $self->get_catchalls;
	return $self->get_catchalls->{$catchall};
}

=pod

=head2 delete_catchall

	die("Unable to delete catchall $catchall\n") unless $mail->delete_catchall($catchall);

Delete a catchall from $mail->get_domain.

=cut
sub delete_catchall {
	my $self = shift;
	my $catchall = shift; # a C<Vhffs::Services::Mail::Catchall> object
	return undef unless defined $catchall and $catchall->{mail} == $self; # Do not be cheated

	return unless $catchall->destroy;
	delete $self->get_catchalls->{$catchall->get_catchall};
	$self->{nb_catchalls}--;

	$self->add_history( $catchall->get_catchall.' catchall box deleted' );
	return 1;
}

1;
