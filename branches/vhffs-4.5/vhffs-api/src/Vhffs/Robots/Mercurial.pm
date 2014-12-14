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
use Vhffs::Services::Mercurial;

package Vhffs::Robots::Mercurial;

sub create {
	my $mercurial = shift;
	return undef unless defined $mercurial and $mercurial->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $mercurial->get_vhffs;
	my $dir = $mercurial->get_dir;

	if( -e $dir ) {
		$mercurial->set_status( Vhffs::Constants::CREATION_ERROR );
		$mercurial->commit();
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating mercurial repository '.$mercurial->get_reponame.' to the filesystem' );
		return undef;
	}

	File::Path::make_path( $dir, { error => \my $errors });
	if(@$errors) {
		$mercurial->set_status( Vhffs::Constants::CREATION_ERROR );
		$mercurial->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating mercurial repository '.$mercurial->get_reponame.' to the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	my $oldcwd = Cwd::getcwd();
	if( chdir($dir) ) {
		my $childpid = open( my $output, '-|', 'hg', 'init' );
		if($childpid) {
			# read process output then discard
			while(<$output>) {}

			# wait for the child to finish
			waitpid( $childpid, 0 );

			# we don't care whether hg succedded, we are going to check that ourself
		}
	}
	chdir($oldcwd);

	unless( -d $dir.'/.hg' ) {
		$mercurial->set_status( Vhffs::Constants::CREATION_ERROR );
		$mercurial->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating mercurial repository '.$mercurial->get_reponame.' to the filesystem' );
		return undef;
	}

	Vhffs::Robots::chmod_recur( $dir, 0664, 02775 );
	Vhffs::Robots::chown_recur( $dir, $mercurial->get_owner_uid, $mercurial->get_owner_gid );

	Vhffs::Robots::vhffs_log( $vhffs, 'Created mercurial repository '.$mercurial->get_reponame );
	return undef unless modify( $mercurial );

	$mercurial->send_created_mail;
	return 1;
}

sub delete {
	my $mercurial = shift;
	return undef unless defined $mercurial and $mercurial->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $mercurial->get_vhffs;
	my $dir = $mercurial->get_dir;

	Vhffs::Robots::archive_targz( $mercurial, $dir );

	File::Path::remove_tree( $dir, { error => \my $errors });
	my $groupdir = File::Basename::dirname($dir);
	rmdir($groupdir);

	if(@$errors) {
		$mercurial->set_status( Vhffs::Constants::DELETION_ERROR );
		$mercurial->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing mercurial repository '.$mercurial->get_reponame.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	if( $mercurial->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted mercurial repository '.$mercurial->get_reponame );
	} else {
		$mercurial->set_status( Vhffs::Constants::DELETION_ERROR );
		$mercurial->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting mercurial repository '.$mercurial->get_reponame.' object' );
		return undef;
	}

	return 1;
}

sub modify {
	my $mercurial = shift;
	return undef unless defined $mercurial and ( $mercurial->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION or $mercurial->get_status == Vhffs::Constants::WAITING_FOR_CREATION );

	my $vhffs = $mercurial->get_vhffs;
	my $dir = $mercurial->get_dir;

	if( $mercurial->is_public ) {
		chmod 02775, $dir;

		Vhffs::Robots::vhffs_log( $vhffs, 'Mercurial repository '.$mercurial->get_reponame.' is now public' );
		$mercurial->add_history( 'Is now public');
	}
	else {
		chmod 02770, $dir;

		Vhffs::Robots::vhffs_log( $vhffs, 'Mercurial repository '.$mercurial->get_reponame.' is now private' );
		$mercurial->add_history( 'Is now private');
	}

	my $mail_from = $mercurial->get_config->{notify_from};
	my $mladdress = $mercurial->{ml_name};

	my $rcfileoutpath = $dir.'/.hg/hgrc';
	open( my $rcfileout, '>', $rcfileoutpath ) or Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while modifying mercurial repository, cannot open '.$rcfileoutpath );
	unless (defined $rcfileout) {
		$mercurial->set_status( Vhffs::Constants::MODIFICATION_ERROR );
		$mercurial->commit;
		return undef;
	}

	my $description = $mercurial->get_description;
	$description =~ s/\r\n/\n/g; # change CRLF to LF
	$description =~ s/\n\s*\n/\n/g; # remove empty lines (mercurial does not handle description with empty lines because .hgrc discard empty lines)
	$description =~ s/^\n//; # remove first LF
	$description =~ s/\n$//; # remove latest LF
	$description =~ s/\n/\n  /g; # multi line values should be indented

	print $rcfileout '[web]'."\n";
	print $rcfileout 'description ='."\n".'  '.$description."\n";
	require Vhffs::Services::MailGroup;
	my $mg = new Vhffs::Services::MailGroup( $vhffs, $mercurial->get_group );
	print $rcfileout 'contact = '.$mg->get_localpart->get_localpart.'@'.$mg->get_domain."\n" if defined $mg and defined $mg->get_localpart;
	print $rcfileout "\n";

	if( $mladdress !~ /^\s*$/ ) {
		my $rcfileinpath = '%VHFFS_BOTS_DIR%/misc/mercurial_notify.rc';

		# Create the rc file
		open( my $rcfilein, '<', $rcfileinpath ) or Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while modifying mercurial repository, cannot open '.$rcfileinpath );
		unless (defined $rcfilein) {
			$mercurial->set_status( Vhffs::Constants::MODIFICATION_ERROR );
			$mercurial->commit;
			return undef;
		}

		while( <$rcfilein> ) {
			$_ =~ s/MY_MLADDRESS/$mladdress/g;
			$_ =~ s/MY_FROMADDRESS/$mail_from/g;

			print $rcfileout $_;
		}

		close( $rcfilein );

		Vhffs::Robots::vhffs_log( $vhffs, 'Mercurial repository '.$mercurial->get_reponame.' commit mail set to '.$mladdress );
		$mercurial->add_history( 'Commit mail set to '.$mladdress );
	}

	close( $rcfileout );
	chmod 0644, $rcfileoutpath;

	$mercurial->set_status( Vhffs::Constants::ACTIVATED );
	$mercurial->commit;

	return 1;
}

1;
