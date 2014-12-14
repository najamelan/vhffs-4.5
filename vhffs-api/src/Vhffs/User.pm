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

package Vhffs::User;

use base qw(Vhffs::Object);
use strict;
use utf8;
use DBI;
use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Group;
use Vhffs::Functions;

=pod

=head1 NAME

Vhffs::User - Vhffs Interface to handle *NIX users

=head1 SYNOPSIS

	use Vhffs;
	my $vhffs = new Vhffs or die();
	my $user = Vhffs::User::get_by_username( $vhffs , 'myuser' );
	defined $user ? print "User exists\n" : print "User does not exist\n";
	...
	my $user = Vhffs::User::create( $vhffs, 'myuser', 'apassword', 0, 'myuser@vhffs.org');
	defined $user ? print "User created" : print "User error\n";
	...
	print "Username: $user->get_username";
	...
	print "Successfully updated user preferences\n" if $user->commit > 0;
=cut

=pod
=head1 CLASS METHODS
=cut

=pod

=head2 check_username

	print 'Username valid' if Vhffs::User::check_username($username);

returns false if username is not valid (length not between 3 and 12, name not
composed of alphanumeric chars)

=cut
sub check_username($) {
	my $username = shift;
	return ( defined $username and $username =~ /^[a-z0-9]{3,12}$/ );
}

=pod

=head2 password_encrypt

my $encryptedpass = Vhffs::User::password_encrypt( $pass );

Returns a sha512 crypt password from plain text password. Salt is randomized.

=cut
sub password_encrypt {
	my $password = shift;
	return crypt($password, '$6$'.join( '', ('.', '/', 0..9, 'A'..'Z', 'a'..'z')[map {rand 64} (1..16)]) );
}

=pod

=head2 _new

	Self constructor, almost private, please use get_by_* methods instead.

=cut
sub _new {
	my ($class, $vhffs, $uid, $gid, $oid, $username, $passwd, $homedir, $shell, $admin, $firstname, $lastname, $address, $zipcode, $city, $country, $mail, $gpg_key, $note, $language, $theme, $lastloginpanel, $ircnick, $validated, $date_creation, $description, $state) = @_;
	my $self = $class->SUPER::_new($vhffs, $oid, $uid, $gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_USER);
	return undef unless(defined $self);
	$self->{uid} = $uid;
	$self->{gid} = $gid;
	$self->{username} = $username;
	$self->{passwd} = $passwd;
	$self->{homedir} = $homedir;
	$self->{shell} = $shell;
	$self->{admin} = $admin;
	$self->{firstname} = $firstname;
	$self->{lastname} = $lastname;
	$self->{address} = $address;
	$self->{zipcode} = $zipcode;
	$self->{city} = $city;
	$self->{country} = $country;
	$self->{mail} = $mail;
	$self->{gpg_key} = $gpg_key;
	$self->{note} = $note;
	$self->{language} = $language;
	$self->{theme} = $theme;
	$self->{lastloginpanel} = $lastloginpanel;
	$self->{ircnick} = $ircnick;
	$self->{validated} = $validated;
	return $self;
}

=pod

=head2 create

	my $user = Vhffs::User::create($vhffs, $username, $password, $admin,
		$mail, $firstname, $lastname, $city, $zipcode,
		$country, $address, $gpg_key, $language);

Create in DB and return a fully functional user.

=cut
sub create {
	my ( $vhffs, $username, $password, $admin, $mail, $firstname, $lastname, $city, $zipcode, $country, $address, $gpg_key, $language ) = @_;
	return undef unless check_username($username);

	my $userconf = $vhffs->get_config->get_users;
	my $user;

	open(my $badusers, '<', $userconf->{'bad_username_file'} );
	if(defined $badusers) {
		while( <$badusers> ) {
			chomp;
			if ( $_ eq $username ) {
				close $badusers;
				return undef;
			}
		}
		close $badusers;
	}

	my $dbh = $vhffs->get_db;
	# Localize RaiseError so it get restored after we finish
	# With this enabled, DBI automagically call die if a
	# query goes wrong.
	local $dbh->{RaiseError} = 1;
	$dbh->begin_work;
	eval {
		# object(owner_uid) references user(uid) and user(object_id) object(object_id)
		# so we have to tell pg that constraints shouldn't be checked before the end
		# of transaction
		$dbh->do('SET CONSTRAINTS ALL DEFERRED');

		my ($uid) = $dbh->selectrow_array('SELECT nextval(\'vhffs_users_uid_seq\')');
		my ($gid) = $dbh->selectrow_array('SELECT nextval(\'vhffs_groups_gid_seq\')');

		# Create corresponding object
		# -- TODO, user moderation (easy to do now)
		my $parent = Vhffs::Object::create($vhffs, $uid, $gid, '', Vhffs::Constants::WAITING_FOR_CREATION, Vhffs::Constants::TYPE_USER);
		die('Error creating parent') unless (defined $parent);

		# Insert base information
		$admin = 0 unless (defined $admin);
		$password = Vhffs::Functions::generate_random_password() unless defined $password and $password !~ /^\s+$/;
		$language = $vhffs->get_config->get_default_language unless defined $language and grep { $_ eq $language } $vhffs->get_config->get_available_languages;
		my $homedir = $vhffs->get_config->get_datadir.'/home/'.substr( $username, 0, 1 ).'/'.substr( $username, 1, 1 ).'/'.$username;

		my $sth = $dbh->prepare('INSERT INTO vhffs_users (uid, gid, username, shell, passwd, homedir, admin, firstname, lastname, address, zipcode, city, country, mail, gpg_key, note, language, theme, lastloginpanel, object_id) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, NULL, NULL, ?)');
		$sth->execute($uid, $gid, $username, $userconf->{'default_shell'}, password_encrypt($password), $homedir, $admin, $firstname, $lastname, $address, $zipcode, $city, $country, $mail, $gpg_key, $language, $parent->get_oid);

		my $group = Vhffs::Group::create($vhffs, $username, undef, $uid, $gid);
		die('Error creating group') unless (defined $group);
		$group->set_status(Vhffs::Constants::ACTIVATED);
		$group->set_quota( $userconf->{'default_quota'} || 1 );
		$group->commit;

		$dbh->commit;
		$user = get_by_uid($vhffs, $uid);
	};

	if($@) {
		warn "Error creating user : $@\n";
		$dbh->rollback;
		undef $user;
	}
	else {
		my $subject = sprintf( gettext('Welcome on %s'), $vhffs->get_config->get_host_name );
		my $content = sprintf( gettext("Hello %s %s, Welcome on %s\n\nHere are your login information :\nUser: %s\nPassword: %s\n\nYour account is NOT created yet, you cannot login on the panel now, you\nare going to receive another mail in a few minutes upon account creation.\n\n%s Administrators\n"), $user->get_firstname, $user->get_lastname, $vhffs->get_config->get_host_name, $user->get_username, $password , $vhffs->get_config->get_host_name );
		$user->send_mail_user( $subject, $content );
	}

	return $user;
}

=pod

=head2 fill_object

See C<Vhffs::Object::fill_object>.

=cut
sub fill_object {
# We just add some specific fields
	my ($class, $obj) = @_;
	my $sql = q{SELECT uid, gid, username, shell, passwd, homedir, admin,
		firstname, lastname, address, zipcode, city, country, mail, gpg_key,
		note, language, theme FROM vhffs_users WHERE object_id = ?};
	return $class->SUPER::_fill_object($obj, $sql);
}

=pod

=head2 getall

	my @users = Vhffs::User::getall( $vhffs, $state, $name );

Returns an array of users who matched $state and $name.

=cut
sub getall {
	my $vhffs = shift;
	my $state = shift;
	my $name = shift;
	my @users;
	my @params;
	return unless defined $vhffs;

	my $query = 'SELECT username FROM vhffs_users vu INNER JOIN vhffs_object o ON o.object_id=vu.object_id WHERE o.object_id=vu.object_id ';

	if(defined $name) {
		$name = '%'.$name.'%';
		$query .= ' AND ( vu.username LIKE ? OR vu.firstname LIKE ? OR vu.lastname LIKE ? )';
		push @params, $name, $name, $name;
	}
	(push(@params, $state), $query.= ' AND o.state=?') if( defined $state );

	$query .= 'ORDER BY username';

	my $request = $vhffs->get_db->prepare( $query );
	$request->execute(@params);
	while( my ($name) = $request->fetchrow_array ) {
		my $user = Vhffs::User::get_by_username( $vhffs , $name );
		push( @users , $user ) if( defined $user );
	}

	return \@users;
}

=pod

=head2 get_unused_accounts

	my @users = Vhffs::User::get_unused_accounts( $vhffs, $age );

Returns an array of users who seem to be left unused for at least $age seconds long.

Unused = no active group and last login panel over $age seconds long.

=cut
sub get_unused_accounts {
	my $vhffs = shift;
	my $age = shift;
	my @users;
	return unless defined $vhffs;

	my $ts = time() - $age;

	my $query = 'SELECT u.uid FROM vhffs_users u INNER JOIN vhffs_object o ON o.object_id=u.object_id WHERE u.admin=? AND u.validated=false AND o.state=? AND o.date_creation<? AND ( u.lastloginpanel IS NULL OR u.lastloginpanel<? ) AND u.uid NOT IN (SELECT u.uid FROM vhffs_users u INNER JOIN vhffs_user_group ug ON u.uid=ug.uid)';

	my $request = $vhffs->get_db->prepare( $query );
	$request->execute( Vhffs::Constants::USER_NORMAL , Vhffs::Constants::ACTIVATED , $ts , $ts );
	while( my $uid = $request->fetchrow_array ) {
		my $user = Vhffs::User::get_by_uid( $vhffs , $uid );
		push( @users , $user ) if( defined $user );
	}

	return \@users;
}

=pod

=head2 get_by_uid

	my $user = Vhffs::User::get_by_uid($vhffs, $uid);
	die('User not found') unless defined($user);

Fetches an user using its UID. Returned user is fully functional.

=cut
sub get_by_uid {
	my ($vhffs, $uid) = @_;
	my $query = 'SELECT u.uid, u.gid, u.object_id, u.username, u.passwd, u.homedir, u.shell, u.admin, u.firstname, u.lastname, u.address, u.zipcode, u.city, u.country, u.mail, u.gpg_key, u.note, u.language, u.theme, u.lastloginpanel, u.ircnick, u.validated, o.date_creation, o.description, o.state FROM vhffs_users u INNER JOIN vhffs_object o ON o.object_id = u.object_id WHERE u.uid = ?';
	my $dbh = $vhffs->get_db;
	my @params = $dbh->selectrow_array($query, undef, $uid);
	return undef unless(@params);
	return _new Vhffs::User($vhffs, @params);
}

=pod

=head2 get_by_username

	my $user = Vhffs::User::get_by_username($vhffs, $username);
	die('User not found') unless defined($user);

Fetches an user using its username. Returned user is fully functional.

=cut
sub get_by_username {
	my ($vhffs, $username) = @_;
	my $query = 'SELECT u.uid, u.gid, u.object_id, u.username, u.passwd, u.homedir, u.shell, u.admin, u.firstname, u.lastname, u.address, u.zipcode, u.city, u.country, u.mail, u.gpg_key, u.note, u.language, u.theme, u.lastloginpanel, u.ircnick, u.validated, o.date_creation, o.description, o.state FROM vhffs_users u INNER JOIN vhffs_object o ON o.object_id = u.object_id WHERE u.username = ?';
	my $dbh = $vhffs->get_db;
	my @params = $dbh->selectrow_array($query, undef, $username);
	return undef unless(@params);
	return _new Vhffs::User($vhffs, @params);
}

=head2 get_by_ircnick

	my $user = Vhffs::User::get_by_ircnick($vhffs, $ircnick);
	die('User not found') unless defined($user);

Fetches an user using its IRC nick. Returned user is fully functional.

=cut
sub get_by_ircnick {
	my ($vhffs, $ircnick) = @_;
	my $query = 'SELECT u.uid, u.gid, u.object_id, u.username, u.passwd, u.homedir, u.shell, u.admin, u.firstname, u.lastname, u.address, u.zipcode, u.city, u.country, u.mail, u.gpg_key, u.note, u.language, u.theme, u.lastloginpanel, u.ircnick, u.validated, o.date_creation, o.description, o.state FROM vhffs_users u INNER JOIN vhffs_object o ON o.object_id = u.object_id WHERE u.ircnick = ?';
	my $dbh = $vhffs->get_db;
	my @params = $dbh->selectrow_array($query, undef, $ircnick);
	return undef unless(@params);
	return _new Vhffs::User($vhffs, @params);
}

=pod
=head1 INSTANCE METHODS
=cut

=pod

=head2 commit

	my $ret = $user->commit;

Commit all changes to the database, returns 1 if success, otherwise returns a negative value.

=cut
sub commit {
	my $self = shift;

	$self->{'shell'} = $self->get_config->{'default_shell'} unless defined $self->{'shell'};
	$self->{'admin'} = 0 unless defined $self->{'admin'};

	return -1 unless defined $self->{'passwd'} and $self->{'passwd'} ne '';
	return -2 if $self->SUPER::commit < 0;

	my $sql = 'UPDATE vhffs_users SET shell = ?, passwd = ?, admin = ?, firstname = ?, lastname = ?, address = ?, zipcode = ?, country = ?, mail = ?, city = ?, gpg_key = ?, note = ?, language = ?, theme = ?, lastloginpanel = ?, ircnick = ?, validated = ? WHERE uid = ?';
	my $sth = $self->get_db->prepare($sql) or return -1;
	$sth->execute($self->{'shell'}, $self->{'passwd'}, $self->{'admin'},
		$self->{'firstname'}, $self->{'lastname'}, $self->{'address'}, $self->{'zipcode'},
		$self->{'country'}, $self->{'mail'}, $self->{'city'}, $self->{'gpg_key'}, $self->{'note'},
		$self->{'language'}, $self->{'theme'}, $self->{'lastloginpanel'},
		$self->{'ircnick'}, $self->{'validated'}, $self->{'uid'}) or return -3;

	return 1;
}

=pod

=head2 delete

	my $ret = $user->delete;

Delete a user from the database. Should be called after user have been cleaned up from the filesystem.

=cut
sub delete {
	my $request;
	my $self;

	$self = shift;

	unless( $self->get_group->delete ) {
		# TODO: set Vhffs::Constants::DELETION_ERROR
		return undef;
	}

	# delete mail user if mail_user is enabled
	use Vhffs::Services::MailUser;
	my $mu = new Vhffs::Services::MailUser( $self->get_vhffs, $self );
	$mu->delete if defined $mu;

	# remove subscription from newsletter
	use Vhffs::Services::Newsletter;
	my $newsletter = new Vhffs::Services::Newsletter( $self->get_vhffs, $self );
	$newsletter->del if defined $newsletter;

	# User references corresponding object with an ON DELETE cascade foreign key
	# so we don't even need to delete user
	# rows that reference this user will be deleted by foreign keys constraints
	return $self->SUPER::delete;
}

=pod

=head2 delete

	my $ret = $user->pendingdeletion_withmail;

Delete a user with a notice mail.

=cut
sub pendingdeletion_withmail {
	my $self = shift;

	my $vhffs = $self->get_vhffs;

	# TODO: write a beautiful module for INTL
	bindtextdomain('vhffs', '%localedir%');
	textdomain('vhffs');

	my $prevlocale = setlocale( LC_ALL );
	setlocale( LC_ALL , $self->get_lang );

	my $mail = sprintf(
		gettext( "Hello %s %s,\n\nYour account (%s) on %s has been deleted.\n\nThis is because it was left unused for a long time\n\nDon't be upset, create it again and reply to this email to tell us\nwhy you really need to keep your account.\nIf you need further information, just reply to this email !\n\nCheers,\nThe moderator team\n\n---------\n%s\n%s\n" ) ,

		$self->get_firstname,
		$self->get_lastname,
		$self->get_username,
		$vhffs->get_config->get_host_name,
		$vhffs->get_config->get_host_name,
		$vhffs->get_config->get_panel->{url}
		);

	my $subject = sprintf(
		gettext('Your account (%s) on %s has been deleted because it was unused for a long time'),
		$self->get_username,
		$vhffs->get_config->get_host_name
		);

	Vhffs::Functions::send_mail( $vhffs, $vhffs->get_config->get_moderator_mail, $self->get_mail, $vhffs->get_config->get_mailtag, $subject, $mail );

	setlocale( LC_ALL , $prevlocale );

	$self->set_status( Vhffs::Constants::WAITING_FOR_DELETION );
	$self->commit;
}

=pod

=head2 check_password

	my $ret = $user->check_password( $plaintext_password );

Check user password against crypt sha512 password stored in the database.

=cut
sub check_password {
	my $self = shift;
	my $clearpass = shift;

	my $dbpass = $self->get_password;
	return $dbpass eq crypt($clearpass, $dbpass) ? 1 : 0;
}

=pod

=head2 send_mail_user

	$user->send_mail_user( $subject, $content );

Send a mail to the user, this is only a helper for Vhffs::Functions::send_mail() which sets all arguments excepted subject and content.

=cut
sub send_mail_user {
	use Vhffs::Functions;
	my ( $user, $subject, $content ) = @_;
	return undef unless defined $user->get_mail;

	my $vhffs = $user->get_vhffs;

	my $from = $vhffs->get_config->get_master_mail;
	return undef unless defined $from;

	return Vhffs::Functions::send_mail( $vhffs, $from, $user->get_mail, $vhffs->get_config->get_mailtag, $subject, $content );
}

=pod

=head2 get_username

	$user->get_username;

Returns user username.

=cut
sub get_username {
	my $self = shift;
	return $self->{'username'};
}

=pod

=head2 get_firstname

	$user->get_firstname;

Returns user firstname.

=cut
sub get_firstname {
	my $self = shift;
	return $self->{'firstname'};
}

=pod

=head2 get_lastname

	$user->get_lastname;

Returns user lastname.

=cut
sub get_lastname {
	my $self = shift;
	return $self->{'lastname'};
}

=pod

=head2 get_city

	$user->get_city;

Returns user city.

=cut
sub get_city {
	my $self = shift;
	return $self->{'city'};
}

=pod

=head2 get_country

	$user->get_country;

Returns user country.

=cut
sub get_country {
	 my $self = shift;
	 return $self->{'country'};
}

=pod

=head2 get_zipcode

	$user->get_zipcode;

Returns user zipcode.

=cut
sub get_zipcode {
	my $self = shift;
	return $self->{'zipcode'};
}

=pod

=head2 get_home

	$user->get_home;

Returns user home directory.

=cut
sub get_home {
	my $self = shift;
	return $self->{'homedir'}
}

=pod

=head2 get_password

	$user->get_password;

Returns user hashed password (using crypt-sha512).

=cut
sub get_password {
	my $self = shift;
	return $self->{'passwd'}
}

=pod

=head2 get_uid

	$user->get_uid;

Returns user UID.

=cut
sub get_uid {
	my $self = shift;
	return $self->{'uid'};
}

=pod

=head2 get_gid

	$user->get_gid;

Returns user GID.

=cut
sub get_gid {
	my $self = shift;
	return $self->{'gid'};
}

=pod

=head2 get_lang

	$user->get_lang;

Returns user lang (in the locale xx_XX pattern).

=cut
sub get_lang {
	my $self = shift;
	return $self->{language};
}

=pod

=head2 get_mail

	$user->get_mail;

Returns user mail.

=cut
sub get_mail {
	my $self = shift;
	return $self->{'mail'};
}

=pod

=head2 get_theme

	$user->get_theme;

Returns user theme (used in Panel).

=cut
sub get_theme {
	my $self = shift;
	return $self->{theme};
}

=pod

=head2 get_address

	$user->get_address;

Returns user address.

=cut
sub get_address {
	my $self = shift;
	return $self->{'address'};
}

=pod

=head2 get_shell

	$user->get_shell;

Returns user shell.

=cut
sub get_shell {
	my $self = shift;
	return $self->{'shell'};
}

=pod

=head2 get_gpgkey

	$user->get_gpgkey;

Returns user GPG key.

=cut
sub get_gpgkey {
	my $self = shift;
	return( $self->{'gpg_key'} );
}

=pod

=head2 get_note

	$user->get_note;

Returns user note.

=cut
sub get_note {
	my $self = shift;
	return( $self->{'note'} );
}

=pod

=head2 get_lastloginpanel

	$user->get_lastloginpanel;

Returns last time user logged in to the panel.

=cut
sub get_lastloginpanel {
	my $self = shift;
	return( $self->{'lastloginpanel'} );
}

=pod

=head2 get_ircnick

	$user->get_ircnick;

Returns user IRC nick.

=cut
sub get_ircnick {
	my $self = shift;
	return( $self->{'ircnick'} );
}

=pod

=head2 get_validated

	$user->get_validated;

Returns user validated state. A user get validated when its group got accepted or when it joined a group.

=cut
sub get_validated {
	my $self = shift;
	return( $self->{'validated'} );
}

=pod

=head2 set_shell

	$user->set_shell( $shell );

Set user shell.

=cut
sub set_shell {
	my $self = shift;
	my $value = shift;
	$self->{'shell'} = $value;
}

=pod

=head2 set_firstname

	$user->set_firstname( $firstname );

Set user firstname.

=cut
sub set_firstname {
	my $self = shift;
	my $value = shift;
	$self->{'firstname'} = $value;
}

=pod

=head2 set_lastname

	$user->set_lastname( $lastname );

Set user lastname.

=cut
sub set_lastname {
	my $self = shift;
	my $value = shift;
	$self->{'lastname'} = $value;
}

=pod

=head2 set_city

	$user->set_city( $city );

Set user city.

=cut
sub set_city {
	my $self = shift;
	my $value = shift;
	$self->{'city'} = $value;
}

=pod

=head2 set_zipcode

	$user->set_zipcode( $zipcode );

Set user zipcode.

=cut
sub set_zipcode {
	my $self = shift;
	my $value = shift;
	$self->{'zipcode'} = $value;
}

=pod

=head2 set_country

	$user->set_country( $country );

Set user country.

=cut
sub set_country {
	my $self = shift;
	my $value = shift;
	$self->{'country'} = $value;
}

=pod

=head2 set_address

	$user->set_address( $address );

Set user address.

=cut
sub set_address {
	my $self = shift;
	my $value = shift;
	$self->{'address'} = $value;
}

=pod

=head2 set_mail

	$user->set_mail( $mail );

Set user mail.

=cut
sub set_mail {
	use Vhffs::Functions;
	my $self = shift;
	my $value = shift;

	return -1 unless Vhffs::Functions::valid_mail( $value );
	$self->{'mail'} = $value;
	return 0;
}

=pod

=head2 set_gpgkey

	$user->set_gpgkey( $gpgkey );

Set user GPG key.

=cut
sub set_gpgkey {
	my $self = shift;
	my $value = shift;
	$self->{'gpg_key'} = $value;
}

=pod

=head2 set_note

	$user->set_note( $note );

Set user note.

=cut
sub set_note {
	my $self = shift;
	my $value = shift;
	$self->{'note'} = $value;
}

=pod

=head2 set_password

	$user->set_password( $plaintext_password );

Set user password.

=cut
sub set_password {
	use Vhffs::Functions;

	my $self = shift;
	my $value = shift;
	$self->{'passwd'} = password_encrypt( $value );
}

=pod

=head2 set_lang

	$user->set_lang( $langl );

Set user language.

=cut
sub set_lang {
	my $self = shift;
	my $value = shift;
	$self->{'language'} = $value;
}

=pod

=head2 set_theme

	$user->set_theme( $themel );

Set user themeuage.

=cut
sub set_theme {
	my $self = shift;
	my $value = shift;
	$self->{'theme'} = $value;
}

=pod

=head2 update_lastloginpanel

	$user->update_lastloginpanel;

Set user last time login to panel.

=cut
sub update_lastloginpanel {
	my $self = shift;
	$self->{'lastloginpanel'} = time();
}

=pod

=head2 set_ircnick

	$user->set_ircnick( $nick );

Set user IRC nick (used by IRC bot to join IRC users to VHFFS users).

=cut
sub set_ircnick {
	my $self = shift;
	my $value = shift;
	$self->{'ircnick'} = $value;
}

=pod

=head2 set_validated

	$user->set_validated( $valid );

Set user validated state.

=cut
sub set_validated {
	my $self = shift;
	my $value = shift;
	$self->{'validated'} = $value;
}

=pod

=head2 set_admin

	$user->set_admin( $level );

Set user access level.

=cut
sub set_admin {
	my ( $self , $value ) = @_;
	$self->{'admin'} = $value;
}

=pod

See C<Vhffs::Object::get_label>.

=cut
sub get_label {
	my $self = shift;
	return $self->{username};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_users;
}

=pod

=head2 is_admin

	my $isadmin = $user->is_admin;

Returns 1 if user is an administrator, otherwise returns 0.

=cut
sub is_admin {
	my $self = shift;
	return 1 if defined $self->{'admin'} and $self->{'admin'} == Vhffs::Constants::USER_ADMIN;
	return 0;
}

=pod

=head2 is_moderator

	my $ismodo = $user->is_moderator;

Returns 1 if user is a moderator, otherwise returns 0.
Caution, it does not return 1 if user is an administrator.

=cut
sub is_moderator {
	my $self = shift;
	return 1 if defined $self->{'admin'} and $self->{'admin'} == Vhffs::Constants::USER_MODERATOR;
	return 0;
}

=pod

=head2 get_admin

	my $perm = $user->get_admin;

Returns user access level.

=cut
sub get_admin {
	my $self = shift;
	return $self->{admin};
}

=head2 have_activegroups

	my $havegroups = $user->have_activegroups;

Returns the number of groups of which the user is contributing. Returns -1 in case of failure.

=cut
sub have_activegroups {
	my $self = shift;

	my $uid = $self->get_uid;

	my $query = 'SELECT COUNT(g.groupname) FROM vhffs_groups g, vhffs_user_group ug, vhffs_object o WHERE ug.uid=? AND g.gid=ug.gid AND o.object_id=g.object_id AND o.state=?';
	my $request = $self->get_db->prepare( $query );
	return -1 unless $request->execute($uid, Vhffs::Constants::ACTIVATED);

	my $row = $request->fetchrow_arrayref;
	return -1 unless defined $row;
	return $row->[0];
}

=head2 get_groups

	my @groups = $user->get_groups;

Returns an array of all of the user groups, except the user primary group.

=cut
sub get_groups {
	my $self = shift;

	my $groupnames = {};

	my $query = 'SELECT g.groupname FROM vhffs_groups g INNER JOIN vhffs_user_group ug ON g.gid=ug.gid WHERE ug.uid=?';
	my $request = $self->get_db->prepare( $query );
	return unless $request->execute($self->get_uid);
	while( my ($groupname) = $request->fetchrow_array ) {
		$groupnames->{$groupname} = 1;
	}

	# owned groups
	$query = 'SELECT g.groupname FROM vhffs_groups g INNER JOIN vhffs_object o ON o.object_id=g.object_id WHERE o.owner_uid=? AND g.gid!=?';
	$request = $self->get_db->prepare( $query );
	return unless $request->execute($self->get_uid, $self->get_gid);
	while( my ($groupname) = $request->fetchrow_array ) {
		$groupnames->{$groupname} = 1;
	}

	my $groups = [];
	foreach( sort keys %{$groupnames} ) {
		my $group = Vhffs::Group::get_by_groupname( $self->get_vhffs, $_ );
		push( @$groups, $group ) if defined $group;
	}
	return $groups;
}

1;

__END__

=head1 SEE ALSO

Vhffs::Group , Vhffs , Vhffs::Constants

=head1 AUTHORS

Julien Delange <julien at tuxfamily dot org>

Sebastien Le Ray <beuss at tuxfamily dot org>

Sylvain Rochet <gradator at tuxfamily dot org>
