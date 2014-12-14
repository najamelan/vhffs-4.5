#!%PERL%
# Copyright (c) vhffs project and its contributors
# Copyright (c) 2007 Julien Danjou <julien@danjou.info>
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
use File::Copy;

use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::Robots;
use Vhffs::Services::Git;

package Vhffs::Robots::Git;

sub create {
	my $git = shift;
	return undef unless defined $git and $git->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $git->get_vhffs;
	my $dir = $git->get_dir;

	if( -e $dir ) {
		$git->set_status( Vhffs::Constants::CREATION_ERROR );
		$git->commit();
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating git repository '.$git->get_reponame.' to the filesystem' );
		return undef;
	}

	File::Path::make_path( $dir, { error => \my $errors });
	if(@$errors) {
		$git->set_status( Vhffs::Constants::CREATION_ERROR );
		$git->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating git repository '.$git->get_reponame.' to the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	my $oldcwd = Cwd::getcwd();
	if( chdir($dir) ) {
		my $childpid = open( my $output, '-|', 'git', 'init', '--shared=all', '--bare' );
		if($childpid) {
			# read process output then discard
			while(<$output>) {}

			# wait for the child to finish
			waitpid( $childpid, 0 );

			# we don't care whether git succedded, we are going to check that ourself
		}
	}
	chdir($oldcwd);

	unless( -f $dir.'/config' ) {
		$git->set_status( Vhffs::Constants::CREATION_ERROR );
		$git->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating git repository '.$git->get_reponame.' to the filesystem' );
		return undef;
	}

	Vhffs::Robots::chmod_recur( $dir, 0664, 02775 );
	Vhffs::Robots::chown_recur( $dir, $git->get_owner_uid, $git->get_owner_gid );

	# './hooks' directory must be owned by root to prevent abuse of servers
	Vhffs::Robots::chmod_recur( $dir.'/hooks', 0644, 0755 );
	Vhffs::Robots::chown_recur( $dir.'/hooks', 0, 0 );

	Vhffs::Robots::vhffs_log( $vhffs, 'Created git repository '.$git->get_reponame );
	return undef unless modify( $git );

	$git->send_created_mail;
	return 1;
}

sub delete {
	my $git = shift;
	return undef unless defined $git and $git->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $git->get_vhffs;
	my $dir = $git->get_dir;

	Vhffs::Robots::archive_targz( $git, $dir );

	File::Path::remove_tree( $dir, { error => \my $errors });
	my $groupdir = File::Basename::dirname($dir);
	rmdir($groupdir);

	if(@$errors) {
		$git->set_status( Vhffs::Constants::DELETION_ERROR );
		$git->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing git repository '.$git->get_reponame.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	if( $git->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted git repository '.$git->get_reponame );
	} else {
		$git->set_status( Vhffs::Constants::DELETION_ERROR );
		$git->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting git repository '.$git->get_reponame.' object' );
		return undef;
	}

	return 1;
}

sub modify {
	my $git = shift;
	return undef unless defined $git and ( $git->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION or $git->get_status == Vhffs::Constants::WAITING_FOR_CREATION );

	my $vhffs = $git->get_vhffs;
	my $dir = $git->get_dir;

	if( $git->is_public ) {
		chmod 02775, $dir;

		Vhffs::Robots::vhffs_log( $vhffs, 'Svn repository '.$git->get_reponame.' is now public' );
		$git->add_history( 'Is now public');
	}
	else {
		chmod 02770, $dir;

		Vhffs::Robots::vhffs_log( $vhffs, 'Svn repository '.$git->get_reponame.' is now private' );
		$git->add_history( 'Is now private');
	}

	my $mail_from = $git->get_config->{'notify_from'};

	# Always unlink since git init create a dummy post-receive
	unlink $dir.'/hooks/post-receive';

	if( $git->get_ml_name !~ /^\s*$/ ) {
		File::Copy::copy( '%VHFFS_BOTS_DIR%/misc/git_post-receive', $dir.'/hooks/post-receive' );

		{
			my $childpid = open( my $output, '-|', 'git', 'config', '-f', $dir.'/config', 'hooks.mailinglist', $git->{ml_name} );
			if($childpid) {
				# read process output then discard
				while(<$output>) {}

				# wait for the child to finish
				waitpid( $childpid, 0 );

				if( $? ) {
					$git->set_status( Vhffs::Constants::MODIFICATION_ERROR );
					$git->commit;
					return undef;
				}
			}
		}

		{
			my $childpid = open( my $output, '-|', 'git', 'config', '-f', $dir.'/config', 'hooks.envelopesender', $mail_from );
			if($childpid) {
				# read process output then discard
				while(<$output>) {}

				# wait for the child to finish
				waitpid( $childpid, 0 );

				if( $? ) {
					$git->set_status( Vhffs::Constants::MODIFICATION_ERROR );
					$git->commit;
					return undef;
				}
			}
		}
		chmod 0755, $dir.'/hooks/post-receive';

		Vhffs::Robots::vhffs_log( $vhffs, 'Git repository '.$git->get_reponame.' commit mail set to '.$git->{ml_name} );
		$git->add_history( 'Commit mail set to '.$git->{ml_name} );
	}

	# Write a description to enhance pushed mails.
	open( my $description, '>', $dir.'/description' );
	unless( defined $description ) {
		$git->set_status( Vhffs::Constants::MODIFICATION_ERROR );
		$git->commit;
		return undef;
	}

	print $description $git->get_reponame."\n";
	close( $description );
	chmod 0664, $dir.'/description';

	$git->set_status( Vhffs::Constants::ACTIVATED );
	$git->commit;

	return 1;
}

1;
