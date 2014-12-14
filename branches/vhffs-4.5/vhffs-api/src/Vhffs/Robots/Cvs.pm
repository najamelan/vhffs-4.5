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
use Vhffs::Services::Cvs;

package Vhffs::Robots::Cvs;

sub create {
	my $cvs = shift;
	return undef unless defined $cvs and $cvs->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $cvs->get_vhffs;
	my $dir = $cvs->get_dir;

	if( -e $dir ) {
		$cvs->set_status( Vhffs::Constants::CREATION_ERROR );
		$cvs->commit();
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating cvs repository '.$cvs->get_reponame.' to the filesystem' );
		return undef;
	}

	File::Path::make_path( $dir, { error => \my $errors });
	if(@$errors) {
		$cvs->set_status( Vhffs::Constants::CREATION_ERROR );
		$cvs->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating cvs repository '.$cvs->get_reponame.' to the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	my $childpid = open( my $output, '-|', 'cvs', '-d', $dir, 'init' );
	if($childpid) {
		# read process output then discard
		while(<$output>) {}

		# wait for the child to finish
		waitpid( $childpid, 0 );

		# we don't care whether cvs succedded, we are going to check that ourself
	}

	unless( -d $dir.'/CVSROOT' ) {
		$cvs->set_status( Vhffs::Constants::CREATION_ERROR );
		$cvs->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating cvs repository '.$cvs->get_reponame.' to the filesystem' );
		return undef;
	}

	Vhffs::Robots::chmod_recur( $dir, 0664, 02775 );
	Vhffs::Robots::chown_recur( $dir, $cvs->get_owner_uid, $cvs->get_owner_gid );

	Vhffs::Robots::vhffs_log( $vhffs, 'Created cvs repository '.$cvs->get_reponame );
	return undef unless modify( $cvs );

	$cvs->send_created_mail;
	return 1;
}

sub delete {
	my $cvs = shift;
	return undef unless defined $cvs and $cvs->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $cvs->get_vhffs;
	my $dir = $cvs->get_dir;

	Vhffs::Robots::archive_targz( $cvs, $dir );

	File::Path::remove_tree( $dir, { error => \my $errors });
	my $groupdir = File::Basename::dirname($dir);
	rmdir($groupdir);

	if(@$errors) {
		$cvs->set_status( Vhffs::Constants::DELETION_ERROR );
		$cvs->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing cvs repository '.$cvs->get_reponame.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	if( $cvs->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted cvs repository '.$cvs->get_reponame );
	} else {
		$cvs->set_status( Vhffs::Constants::DELETION_ERROR );
		$cvs->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting cvs repository '.$cvs->get_reponame.' object' );
		return undef;
	}

	viewvc_conf( $vhffs );
	return 1;
}

sub modify {
	my $cvs = shift;
	return undef unless defined $cvs and ( $cvs->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION or $cvs->get_status == Vhffs::Constants::WAITING_FOR_CREATION );

	my $vhffs = $cvs->get_vhffs;
	my $dir = $cvs->get_dir;
	my $readers_file = $dir.'/CVSROOT/readers';
	my $passwd_file = $dir.'/CVSROOT/passwd';

	if( $cvs->is_public ) {
		chmod 02775, $dir;

		open( my $readers, '>', $readers_file ) or Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while modifying cvs repository, cannot open '.$readers_file );
		open( my $passwd, '>', $passwd_file ) or Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while modifying cvs repository, cannot open '.$passwd_file );
		unless( defined $readers and defined $passwd ) {
			$cvs->set_status( Vhffs::Constants::MODIFICATION_ERROR );
			$cvs->commit;
			return undef;
		}

		# Write readers file
		print $readers 'anonymous'."\n";
		close( $readers );
		chown $cvs->get_owner_uid, $cvs->get_owner_gid, $readers_file;
		chmod 0664, $readers_file;

		# Write passwd file
		print $passwd 'anonymous::'.$cvs->get_owner->get_username."\n";
		close( $passwd );
		chown $cvs->get_owner_uid, $cvs->get_owner_gid, $passwd_file;
		chmod 0664, $passwd_file;

		Vhffs::Robots::vhffs_log( $vhffs, 'Cvs repository '.$cvs->get_reponame.' is now public' );
		$cvs->add_history( 'Is now public');
	}
	else {
		chmod 02770, $dir;
		unlink $readers_file;

		Vhffs::Robots::vhffs_log( $vhffs, 'Cvs repository '.$cvs->get_reponame.' is now private' );
		$cvs->add_history( 'Is now private');
	}

	$cvs->set_status( Vhffs::Constants::ACTIVATED );
	$cvs->commit;

	viewvc_conf( $vhffs );
	return 1;
}

sub viewvc_conf {
	require Template;
	require File::Copy;

	my $vhffs = shift;

	my $confdir = $vhffs->get_config->get_datadir.'/cvs/conf';
	unless( -d $confdir ) {
		mkdir( $confdir ) or Vhffs::Robots::vhffs_log( $vhffs, 'Unable to create cvs confdir '.$confdir.': '.$! );
	}

	my $cvsroots = [];
	my $cvss = Vhffs::Services::Cvs::getall( $vhffs, Vhffs::Constants::ACTIVATED );
	foreach ( @{$cvss} ) {
		next unless $_->is_public;
		my $cvspath = $_->get_reponame;
		$cvspath =~ s/\//_/;
		push @$cvsroots, $cvspath.': '.$_->get_dir;
	}

	return undef unless $cvsroots;

	my ( $tmpfile, $tmppath ) = Vhffs::Robots::tmpfile( $vhffs );
	return undef unless defined $tmpfile;
	close( $tmpfile );

	# TODO: remove hardcoded path
	my $template = new Template( { INCLUDE_PATH => '/usr/lib/vhffs/bots/misc/' } );
	$template->process( 'cvs_viewvc.conf.tt', { cvsroots => $cvsroots }, $tmppath );

	chmod 0644, $tmppath;
	File::Copy::move( $tmppath, $confdir.'/viewvc.conf' );

	return 1;
}

1;
