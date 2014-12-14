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
use Vhffs::Services::Svn;

package Vhffs::Robots::Svn;

sub create {
	my $svn = shift;
	return undef unless defined $svn and $svn->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $svn->get_vhffs;
	my $dir = $svn->get_dir;

	if( -e $dir ) {
		$svn->set_status( Vhffs::Constants::CREATION_ERROR );
		$svn->commit();
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating svn repository '.$svn->get_reponame.' to the filesystem' );
		return undef;
	}

	File::Path::make_path( $dir, { error => \my $errors });
	if(@$errors) {
		$svn->set_status( Vhffs::Constants::CREATION_ERROR );
		$svn->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating svn repository '.$svn->get_reponame.' to the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	my $childpid = open( my $output, '-|', 'svnadmin', 'create', '--fs-type', 'fsfs', $dir );
	if($childpid) {
		# read process output then discard
		while(<$output>) {}

		# wait for the child to finish
		waitpid( $childpid, 0 );

		# we don't care whether svn succedded, we are going to check that ourself
	}

	unless( -f $dir.'/format' ) {
		$svn->set_status( Vhffs::Constants::CREATION_ERROR );
		$svn->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating svn repository '.$svn->get_reponame.' to the filesystem' );
		return undef;
	}

	Vhffs::Robots::chmod_recur( $dir, 0664, 02775 );
	Vhffs::Robots::chown_recur( $dir, $svn->get_owner_uid, $svn->get_owner_gid );

	# './hooks' directory must be owned by root to prevent abuse of servers
	Vhffs::Robots::chmod_recur( $dir.'/hooks', 0644, 0755 );
	Vhffs::Robots::chown_recur( $dir.'/hooks', 0, 0 );

	Vhffs::Robots::vhffs_log( $vhffs, 'Created svn repository '.$svn->get_reponame );
	return undef unless modify( $svn );

	$svn->send_created_mail;
	return 1;
}

sub delete {
	my $svn = shift;
	return undef unless defined $svn and $svn->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $svn->get_vhffs;
	my $dir = $svn->get_dir;

	Vhffs::Robots::archive_targz( $svn, $dir );

	File::Path::remove_tree( $dir, { error => \my $errors });
	my $groupdir = File::Basename::dirname($dir);
	rmdir($groupdir);

	if(@$errors) {
		$svn->set_status( Vhffs::Constants::DELETION_ERROR );
		$svn->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing svn repository '.$svn->get_reponame.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	if( $svn->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted svn repository '.$svn->get_reponame );
	} else {
		$svn->set_status( Vhffs::Constants::DELETION_ERROR );
		$svn->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting svn repository '.$svn->get_reponame.' object' );
		return undef;
	}

	viewvc_conf( $vhffs );
	websvn_conf( $vhffs );
	return 1;
}

sub modify {
	my $svn = shift;
	return undef unless defined $svn and ( $svn->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION or $svn->get_status == Vhffs::Constants::WAITING_FOR_CREATION );

	my $vhffs = $svn->get_vhffs;
	my $dir = $svn->get_dir;

	my $confpath = $dir.'/conf/svnserve.conf';

	# Read configuration file
	open( my $conffile, '<', $confpath ) or Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while modifying svn repository, cannot open '.$confpath );
	unless( defined $conffile ) {
		$svn->set_status( Vhffs::Constants::MODIFICATION_ERROR );
		$svn->commit;
		return undef;
	}

	my @lines;
	while( <$conffile> ) {
		push( @lines, $_ );
	}
	close( $conffile );

	# Write configuration file
	open( $conffile, '>', $confpath ) or Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while modifying svn repository, cannot open '.$confpath );
	unless( defined $conffile ) {
		$svn->set_status( Vhffs::Constants::MODIFICATION_ERROR );
		$svn->commit;
		return undef;
	}

	foreach( @lines ) {
		if( $_ =~ /.*anon\-access.*/ ) {
			if( $svn->is_public == 1 ) {
				$_ = 'anon-access = read'."\n";
			} else{
				$_ = 'anon-access = none'."\n";
			}
		}
		if( $_ =~ /.*\[general\].*/ ) {
			$_ = '[general]'."\n";
		}
		print $conffile $_;
	}
	close( $conffile );
	chmod 0664, $conffile;

	if( $svn->is_public ) {
		chmod 02775, $dir;

		Vhffs::Robots::vhffs_log( $vhffs, 'Svn repository '.$svn->get_reponame.' is now public' );
		$svn->add_history( 'Is now public');
	}
	else {
		chmod 02770, $dir;

		Vhffs::Robots::vhffs_log( $vhffs, 'Svn repository '.$svn->get_reponame.' is now private' );
		$svn->add_history( 'Is now private');
	}

	# Commit mail
	my $svnconf = $svn->get_config;
	my $mailfrom = $svnconf->{'notify_from'};
	my $mailto = $svn->{ml_name};
	if( defined $mailfrom and defined $mailto )  {

		# read template file
		open( my $postcommit, '<', '%VHFFS_BOTS_DIR%/misc/svn_post-commit.pl' ) or Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while modifying svn repository, cannot open %VHFFS_BOTS_DIR%/misc/svn_post-commit.pl' );
		unless( defined $postcommit ) {
			$svn->set_status( Vhffs::Constants::MODIFICATION_ERROR );
			$svn->commit;
			return undef;
		}

		my @lines;
		while( <$postcommit> ) {
			push( @lines, $_ );
		}
		close( $postcommit );

		# write hook
		my $postcommitpath = $dir.'/hooks/post-commit';

		unlink $postcommitpath;

		open( $postcommit, '>', $postcommitpath ) or Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while modifying svn repository, cannot open '.$postcommitpath );
		unless( defined $postcommit ) {
			$svn->set_status( Vhffs::Constants::MODIFICATION_ERROR );
			$svn->commit;
			return undef;
		}

		foreach( @lines )  {
			# replace some parameters
			$_ =~ s/%MAILNOTIFYFROM%/$mailfrom/g;
			$_ =~ s/%MAILNOTIFYTO%/$mailto/g;

			print $postcommit $_;
		}
		close( $postcommit );
		chmod 0755, $postcommitpath;

		Vhffs::Robots::vhffs_log( $vhffs, 'Svn repository '.$svn->get_reponame.' commit mail set to '.$mailto );
		$svn->add_history( 'Commit mail set to '.$mailto );
	}

	$svn->set_status( Vhffs::Constants::ACTIVATED );
	$svn->commit;

	viewvc_conf( $vhffs );
	websvn_conf( $vhffs );
	return 1;
}

sub viewvc_conf {
	require Template;
	require File::Copy;

	my $vhffs = shift;

	my $confdir = $vhffs->get_config->get_datadir.'/svn/conf';
	unless( -d $confdir ) {
		mkdir( $confdir ) or Vhffs::Robots::vhffs_log( $vhffs, 'Unable to create svn confdir '.$confdir.': '.$! );
	}

	my $svnroots = [];
	my $svns = Vhffs::Services::Svn::getall( $vhffs, Vhffs::Constants::ACTIVATED );
	foreach ( @{$svns} ) {
		next unless $_->is_public;
		my $svnpath = $_->get_reponame;
		$svnpath =~ s/\//_/;
		push @$svnroots, $svnpath.': '.$_->get_dir;
	}

	return undef unless $svnroots;

	my ( $tmpfile, $tmppath ) = Vhffs::Robots::tmpfile( $vhffs );
	return undef unless defined $tmpfile;
	close( $tmpfile );

	# TODO: remove hardcoded path
	my $template = new Template( { INCLUDE_PATH => '/usr/lib/vhffs/bots/misc/' } );
	$template->process( 'svn_viewvc.conf.tt', { svnroots => $svnroots }, $tmppath );

	chmod 0644, $tmppath;
	File::Copy::move( $tmppath, $confdir.'/viewvc.conf' );

	return 1;
}

sub websvn_conf {
	require File::Copy;

	my $vhffs = shift;

	my $confdir = $vhffs->get_config->get_datadir.'/svn/conf';
	unless( -d $confdir ) {
		mkdir( $confdir ) or Vhffs::Robots::vhffs_log( $vhffs, 'Unable to create svn confdir '.$confdir.': '.$! );
	}

	my ( $tmpfile, $tmppath ) = Vhffs::Robots::tmpfile( $vhffs );
	return undef unless defined $tmpfile;
	print $tmpfile '<?php'."\n";

	my $svns = Vhffs::Services::Svn::getall( $vhffs, Vhffs::Constants::ACTIVATED );
	foreach ( @{$svns} )  {
		print $tmpfile '  $config->addRepository("'.$_->get_reponame.'","file://'.$_->get_dir.'");'."\n" if $_->is_public;
	}

	print $tmpfile '?>'."\n";
	close( $tmpfile );

	chmod 0644, $tmppath;
	File::Copy::move( $tmppath, $confdir.'/websvn.inc' );
	return 1;
}

1;
