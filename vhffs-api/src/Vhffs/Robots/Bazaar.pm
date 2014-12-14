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
use Cwd;
use File::Path;
use File::Basename;

use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::Robots;
use Vhffs::Services::Bazaar;

package Vhffs::Robots::Bazaar;

sub create {
	my $bazaar = shift;
	return undef unless defined $bazaar and $bazaar->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $bazaar->get_vhffs;
	my $dir = $bazaar->get_dir;

	if( -e $dir ) {
		$bazaar->set_status( Vhffs::Constants::CREATION_ERROR );
		$bazaar->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating bazaar repository '.$bazaar->get_reponame.' to the filesystem' );
		return undef;
	}

	File::Path::make_path( $dir, { error => \my $errors });
	if(@$errors) {
		$bazaar->set_status( Vhffs::Constants::CREATION_ERROR );
		$bazaar->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating bazaar repository '.$bazaar->get_reponame.' to the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	my $oldcwd = Cwd::getcwd();
	if( chdir($dir) ) {
		my $childpid = open( my $output, '-|', 'bzr', 'init' );
		if($childpid) {
			# read process output then discard
			while(<$output>) {}

			# wait for the child to finish
			waitpid( $childpid, 0 );

			# we don't care whether bzr succedded, we are going to check that ourself
		}
	}
	chdir($oldcwd);

	unless( -d $dir.'/.bzr' ) {
		$bazaar->set_status( Vhffs::Constants::CREATION_ERROR );
		$bazaar->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating bazaar repository '.$bazaar->get_reponame.' to the filesystem' );
		return undef;
	}

	Vhffs::Robots::chmod_recur( $dir, 0664, 02775 );
	Vhffs::Robots::chown_recur( $dir, $bazaar->get_owner_uid, $bazaar->get_owner_gid );

	Vhffs::Robots::vhffs_log( $vhffs, 'Created bazaar repository '.$bazaar->get_reponame );
	return undef unless modify( $bazaar );

	$bazaar->send_created_mail;
	return 1;
}

sub delete {
	my $bazaar = shift;
	return undef unless defined $bazaar and $bazaar->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $bazaar->get_vhffs;
	my $dir = $bazaar->get_dir;

	Vhffs::Robots::archive_targz( $bazaar, $dir );

	File::Path::remove_tree( $dir, { error => \my $errors });
	my $groupdir = File::Basename::dirname($dir);
	rmdir($groupdir);

	if(@$errors) {
		$bazaar->set_status( Vhffs::Constants::DELETION_ERROR );
		$bazaar->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing bazaar repository '.$bazaar->get_reponame.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	if( $bazaar->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted bazaar repository '.$bazaar->get_reponame );
	} else {
		$bazaar->set_status( Vhffs::Constants::DELETION_ERROR );
		$bazaar->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting bazaar repository '.$bazaar->get_reponame.' object' );
		return undef;
	}

	return 1;
}

sub modify {
	my $bazaar = shift;
	return undef unless defined $bazaar and ( $bazaar->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION or $bazaar->get_status == Vhffs::Constants::WAITING_FOR_CREATION );

	my $vhffs = $bazaar->get_vhffs;
	my $dir = $bazaar->get_dir;
	my $mail_from = $bazaar->get_config->{notify_from};

	if( $bazaar->get_ml_name !~ /^\s*$/ ) {
		# TODO: Bazaar mail on commit
	}

	if( $bazaar->is_public ) {
		chmod 02775, $bazaar->get_dir;
		Vhffs::Robots::vhffs_log( $vhffs, 'Bazaar repository '.$bazaar->get_reponame.' is now public' );
		$bazaar->add_history( 'Is now public');
	} else {
		chmod 02770, $bazaar->get_dir;
		Vhffs::Robots::vhffs_log( $vhffs, 'Bazaar repository '.$bazaar->get_reponame.' is now private' );
		$bazaar->add_history( 'Is now private');
	}

	$bazaar->set_status( Vhffs::Constants::ACTIVATED );
	$bazaar->commit;

	return 1;
}

1;
