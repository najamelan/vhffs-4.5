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

use strict;
use utf8;

package Vhffs::Robots::User;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Quota;
use File::Path;
use File::Basename;

use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::Robots;
use Vhffs::User;

sub create {
	my $user = shift;
	return undef unless defined $user and $user->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $user->get_vhffs;
	my $dir = $user->get_home;

	if( -e $dir ) {
		$user->set_status( Vhffs::Constants::CREATION_ERROR );
		$user->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating home dir for user '.$user->get_username.' to the filesystem' );
		return undef;
	}

	File::Path::make_path( $dir, { error => \my $errors });
	if(@$errors) {
		$user->set_status( Vhffs::Constants::CREATION_ERROR );
		$user->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating home dir for user '.$user->get_username.' to the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	chown $user->get_uid, $user->get_gid, $dir;
	chmod 0700, $dir;

	# TODO: write a beautiful module for INTL
	bindtextdomain('vhffs', '%localedir%');
	textdomain('vhffs');

	my $prevlocale = setlocale( LC_ALL );
	setlocale( LC_ALL, $user->get_lang );

	my $subject = sprintf( gettext('Account created on %s'), $vhffs->get_config->get_host_name );
	my $content = sprintf( gettext("Hello %s %s,\n\nWe are pleased to announce that your account is now fully created on\n%s.\nYou can now login on the panel.\n\n%s Administrators\n"),
		$user->get_firstname, $user->get_lastname, $vhffs->get_config->get_host_name, $vhffs->get_config->get_host_name );
	$user->send_mail_user( $subject, $content );

	setlocale( LC_ALL, $prevlocale );

	Vhffs::Robots::vhffs_log( $vhffs, 'Created home dir for user '.$user->get_username );
	$user->set_status( Vhffs::Constants::ACTIVATED );
	$user->commit;
	quota($user);

	return 1;
}

sub delete {
	my $user = shift;
	return undef unless defined $user and $user->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $user->get_vhffs;
	my $dir = $user->get_home;

	if( @{$user->get_groups} ) {
		$user->set_status( Vhffs::Constants::DELETION_ERROR );
		$user->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'Deletion required for user '.$user->get_username.', but this user was still in one or more groups' );
		return undef;
	}

	Vhffs::Robots::archive_targz( $user, $dir );

	File::Path::remove_tree( $dir, { error => \my $errors });
	my $parent = File::Basename::dirname($dir);
	rmdir $parent;
	$parent = File::Basename::dirname($parent);
	rmdir $parent;

	if(@$errors) {
		$user->set_status( Vhffs::Constants::DELETION_ERROR );
		$user->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing home dir for user '.$user->get_username.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	if( $user->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted home dir for user '.$user->get_username );
	} else {
		$user->set_status( Vhffs::Constants::DELETION_ERROR );
		$user->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting user '.$user->get_username.' object' );
		return undef;
	}

	return 1;
}

sub modify {
	my $user = shift;
	return undef unless defined $user and $user->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;
	$user->set_status( Vhffs::Constants::ACTIVATED );
	$user->commit;
	return 1;
}

sub quota {
	my $user = shift;
	return undef unless defined $user;

	my $vhffs = $user->get_vhffs;

	my $dev = Quota::getqcarg($vhffs->get_config->get_datadir);

	my $group = $user->get_group;
	return undef unless defined $group;

	my $setblocks = POSIX::ceil( ($group->get_quota*1000000)/1024 );  # Filesystem quota block = 1024B
	my $setinodes = POSIX::ceil( ($group->get_quota*1000000)/4096 );  # Filesystem block = 4096B

	my ($blocks,$softblocks,$hardblocks,undef,undef,$softinodes,$hardinodes,undef) = Quota::query($dev, $group->get_gid, 1);

	# Set quota - only if database and filesystem are out of sync
	unless( defined $softblocks and defined $hardblocks and defined $softinodes and defined $hardinodes
	  and $softblocks == $hardblocks and $softinodes == $hardinodes
	  and $hardblocks == $setblocks and $hardinodes == $setinodes) {

		unless( Quota::setqlim($dev, $group->get_gid, $setblocks, $setblocks, $setinodes, $setinodes, 0, 1) ) {
			Vhffs::Robots::vhffs_log( $vhffs, 'Set quota for user '.$user->get_username.' (gid '.$group->get_gid.') to '.$group->get_quota.' MB');
			$user->add_history( 'Disk quota set to '.$group->get_quota.' MB' );
		} else {
			Vhffs::Robots::vhffs_log( $vhffs, 'Cannot set quota for user '.$user->get_username.' (gid '.$group->get_gid.'), reason: '.Quota::strerr() );
		}
	}

	# Get quota - only push changes if filesystem and database have different values
	return undef unless defined $blocks;
	my $used = POSIX::ceil( ($blocks*1024)/1000000 );
	return 1 if $used == $group->get_quota_used;
	$group->set_quota_used( $used );
	$group->commit;
	Vhffs::Robots::vhffs_log( $vhffs, 'Updated quota used for user '.$user->get_username.' (gid '.$group->get_gid.') to '.$used.' MB');

	return 1;
}

# Use a different quota system, when the linux quota system is not available, as in openBSD
#
# Currently will check du /data/../user
#
sub quotaDuUpdate {

	my $user = shift;
	return undef unless defined $user;

	my $vhffs = $user->get_vhffs;
	return undef unless defined $vhffs;

	my $group = $user->get_group;
	return undef unless defined $group;

	my $home    = $user->get_home;
	my $result  = `du --summarize "$home"`;
	my ($size)  = split /\t/, $result, 2;

	# Get quota - only push changes if filesystem and database have different values
	#
	my $used = POSIX::floor $size/1000 + 0.5;
	return 1 if $used == $group->get_quota_used;

	$group->set_quota_used( $used );
	$group->commit;

	Vhffs::Robots::vhffs_log( $vhffs, 'Updated quota used for user '.$user->get_username.' (gid '.$group->get_gid.') to '.$used.' MB');

	return 1;
}


sub quota_zero {
	my $user = shift;
	my $path = shift;
	return undef unless defined $user and defined $path and -d $path;

	my $vhffs = $user->get_vhffs;

	my $dev = Quota::getqcarg($path);

	# Only set quota if filesystem quota is not currently set
	my (undef,$softblocks,$hardblocks,undef,undef,$softinodes,$hardinodes,undef) = Quota::query($dev, $user->get_gid, 1);
	return 1 if defined $softblocks and defined $hardblocks and defined $softinodes and defined $hardinodes
	  and $softblocks == 1 and $hardblocks == 0
	  and $softinodes == 1 and $hardinodes == 0;

	if( Quota::setqlim($dev, $user->get_gid, 1, 0, 1, 0, 0, 1) ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Cannot set quota to zero for user '.$user->get_username.' (gid '.$user->get_gid.'), on '.$path.', reason: '.Quota::strerr() );
		return undef;
	}

	return 1;
}

1;
