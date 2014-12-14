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
use File::Path;
use File::Basename;

use Vhffs::Functions;
use Vhffs::Constants;
use Vhffs::Robots;
use Vhffs::UserGroup;

package Vhffs::Robots::UserGroup;

sub create {
	my $usergroup = shift;
	return undef unless defined $usergroup and $usergroup->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $user = $usergroup->get_user;
	my $group = $usergroup->get_group;
	my $vhffs = $usergroup->get_vhffs;

	unless( $vhffs->get_config->use_vhffsfs )  {
		my $groupdir = $group->get_dir;
		my $path = $user->get_home.'/'.$group->get_groupname;
		unless( symlink( $groupdir, $path ) ) {
			$usergroup->set_status( Vhffs::Constants::CREATION_ERROR );
			$usergroup->commit;
			Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while adding user '.$user->get_username.' to group '.$group->get_groupname.' to the filesystem' );
			return undef;
		}
	}

	$usergroup->set_status( Vhffs::Constants::ACTIVATED );
	$usergroup->commit;
	$user->add_history( 'Joined group '.$group->get_groupname );
	$group->add_history( $user->get_username.' user joined' );
	Vhffs::Robots::vhffs_log( $vhffs, 'Added user '.$user->get_username.' to group '.$group->get_groupname );
	return 1;
}

sub delete {
	my $usergroup = shift;
	return undef unless defined $usergroup and $usergroup->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $user = $usergroup->get_user;
	my $group = $usergroup->get_group;
	my $vhffs = $usergroup->get_vhffs;

	unless( $vhffs->get_config->use_vhffsfs )  {
		my $path = $user->get_home.'/'.$group->get_groupname;
		unless( unlink( $path ) ) {
			$usergroup->set_status( Vhffs::Constants::DELETION_ERROR );
			$usergroup->commit;
			Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing user '.$user->get_username.' from group '.$group->get_groupname.' from the filesystem' );
			return undef;
		}
	}

	unless( $usergroup->delete ) {
		$usergroup->set_status( Vhffs::Constants::DELETION_ERROR );
		$usergroup->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing user '.$user->get_username.' from group '.$group->get_groupname.' object' );
		return undef;
	}

	$user->add_history( 'Left group '.$group->get_groupname );
	$group->add_history( $user->get_username.' user left' );
	Vhffs::Robots::vhffs_log( $vhffs, 'Removed user '.$user->get_username.' from group '.$group->get_groupname );
	return 1;
}

sub modify {
	my $usergroup = shift;
	return undef unless defined $usergroup and $usergroup->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;
	$usergroup->set_status( Vhffs::Constants::ACTIVATED );
	$usergroup->commit;
	return 1;
}

1;
