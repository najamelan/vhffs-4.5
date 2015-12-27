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
use POSIX;
use Quota;
use File::Path;
use File::Basename;

use Vhffs::Group;
use Vhffs::User;
use Vhffs::Functions;
use Vhffs::Constants;
use Vhffs::Robots;
use Vhffs::UserGroup;
use Vhffs::Robots::UserGroup;

package Vhffs::Robots::Group;

sub create {
	my $group = shift;
	return undef unless defined $group and $group->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $group->get_vhffs;
	my $dir = $group->get_dir;

	if( -e $dir ) {
		$group->set_status( Vhffs::Constants::CREATION_ERROR );
		$group->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating group '.$group->get_groupname.' to the filesystem' );
		return undef;
	}

	File::Path::make_path( $dir, { error => \my $errors });
	if(@$errors) {
		$group->set_status( Vhffs::Constants::CREATION_ERROR );
		$group->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating group '.$group->get_groupname.' to the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	chown $group->get_owner->get_uid, $group->get_gid, $dir;
	chmod 02770, $dir;

	Vhffs::Robots::vhffs_log( $vhffs, 'Created group '.$group->get_groupname );
	$group->set_status( Vhffs::Constants::ACTIVATED );
	$group->commit;

	my $usergroup = $group->add_user( $group->get_owner );
	Vhffs::Robots::UserGroup::create( $usergroup );

	quota($group);

	$group->send_created_mail;
	return 1;
}

sub delete {
	my $group = shift;
	return undef unless defined $group and $group->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $group->get_vhffs;
	my $dir = $group->get_dir;

	# Remove users from group
	foreach( @{$group->get_users} ) {
		my $usergroup = Vhffs::UserGroup::get_by_user_group( $_, $group );
		$usergroup->set_status( Vhffs::Constants::WAITING_FOR_DELETION );
		unless( Vhffs::Robots::UserGroup::delete( $usergroup ) ) {
			$group->set_status( Vhffs::Constants::DELETION_ERROR );
			$group->commit;
			return undef;
		}
	}

	# Recursively delete group objects, do not delete the group until this is done
	unless( $group->is_empty )  {
		foreach( @{$group->getall_objects} ) {
			next if $group->get_oid == $_->get_oid;
			next if $_->get_status == Vhffs::Constants::WAITING_FOR_DELETION;
			$_->set_status( Vhffs::Constants::WAITING_FOR_DELETION );
			$_->commit;
		}

		Vhffs::Robots::vhffs_log( $vhffs, 'Cannot delete group '.$group->get_groupname.' because it is not empty yet, delete status have been set to group items' );
		return 1;
	}

	Vhffs::Robots::archive_targz( $group, $dir );

	File::Path::remove_tree( $dir, { error => \my $errors });
	# Group directories are hashed on two levels, so we've potentially two empty directories to delete
	my $parent = File::Basename::dirname($dir);
	rmdir $parent;
	$parent = File::Basename::dirname($parent);
	rmdir $parent;

	if(@$errors) {
		$group->set_status( Vhffs::Constants::DELETION_ERROR );
		$group->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing group '.$group->get_groupname.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	if( $group->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted group '.$group->get_groupname );
	} else {
		$group->set_status( Vhffs::Constants::DELETION_ERROR );
		$group->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting group '.$group->get_groupname.' object' );
		return undef;
	}

	return 1;
}

sub modify {
	my $group = shift;
	return undef unless defined $group and $group->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;
	$group->set_status( Vhffs::Constants::ACTIVATED );
	$group->commit;
	return 1;
}

sub quota {
	my $group = shift;
	return undef unless defined $group;

	my $vhffs = $group->get_vhffs;

	my $dev = Quota::getqcarg($vhffs->get_config->get_datadir);

	my $setblocks = POSIX::ceil( ($group->get_quota*1000000)/1024 );  # Filesystem quota block = 1024B
	my $setinodes = POSIX::ceil( ($group->get_quota*1000000)/4096 );  # Filesystem block = 4096B

	my ($blocks,$softblocks,$hardblocks,undef,undef,$softinodes,$hardinodes,undef) = Quota::query($dev, $group->get_gid, 1);

	# Set quota - only if database and filesystem are out of sync
	unless( defined $softblocks and defined $hardblocks and defined $softinodes and defined $hardinodes
	  and $softblocks == $hardblocks and $softinodes == $hardinodes
	  and $hardblocks == $setblocks and $hardinodes == $setinodes) {

		unless( Quota::setqlim($dev, $group->get_gid, $setblocks, $setblocks, $setinodes, $setinodes, 0, 1) ) {
			Vhffs::Robots::vhffs_log( $vhffs, 'Set quota for group '.$group->get_groupname.' (gid '.$group->get_gid.') to '.$group->get_quota.' MB');
			$group->add_history( 'Disk quota set to '.$group->get_quota.' MB' );
		} else {
			Vhffs::Robots::vhffs_log( $vhffs, 'Cannot set quota for group '.$group->get_groupname.' (gid '.$group->get_gid.'), reason: '.Quota::strerr() );
		}
	}

	# Get quota - only push changes if filesystem and database have different values
	return undef unless defined $blocks;
	my $used = POSIX::ceil( ($blocks*1024)/1000000 );
	return 1 if $used == $group->get_quota_used;
	$group->set_quota_used( $used );
	$group->commit;
	Vhffs::Robots::vhffs_log( $vhffs, 'Updated quota used for group '.$group->get_groupname.' (gid '.$group->get_gid.') to '.$used.' MB');
}


# Use a different quota system, when the linux quota system is not available, as in openBSD
#
# Currently will check du /data/../user
# Updates the database
#
sub quotaDuUpdate
{
	my $group = shift;
	return undef unless defined $group;

	my $vhffs = $group->get_vhffs;
	return undef unless defined $group;

	# A project group has symlinks to website directories, so dereference
	#
	my $dir     = $group->get_dir;
	my $result  = `du --dereference --summarize "$dir"`;
	my ($size)  = split /\t/, $result, 2;

	# Get quota - only push changes if filesystem and database have different values
	#
	my $used = POSIX::floor $size/1000 + 0.5;
	return 1 if $used == $group->get_quota_used;

	$group->set_quota_used( $used );
	$group->commit;

	Vhffs::Robots::vhffs_log( $vhffs, 'Updated quota used for group '.$group->get_groupname.' (gid '.$group->get_gid.') to '.$used.' MB');

	return 1;
}


sub quota_zero {
	my $group = shift;
	my $path = shift;
	return undef unless defined $group and defined $path and -d $path;

	my $vhffs = $group->get_vhffs;

	my $dev = Quota::getqcarg($path);

	# Only set quota if filesystem quota is not currently set
	my (undef,$softblocks,$hardblocks,undef,undef,$softinodes,$hardinodes,undef) = Quota::query($dev, $group->get_gid, 1);
	return 1 if defined $softblocks and defined $hardblocks and defined $softinodes and defined $hardinodes
	  and $softblocks == 1 and $hardblocks == 0
	  and $softinodes == 1 and $hardinodes == 0;

	if( Quota::setqlim($dev, $group->get_gid, 1, 0, 1, 0, 0, 1) ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Cannot set quota to zero for group '.$group->get_groupname.' (gid '.$group->get_gid.'), on '.$path.', reason: '.Quota::strerr() );
		return undef;
	}

	return 1;
}

1;
