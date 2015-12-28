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
use File::Path;
use File::Basename;
use File::Copy;

use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::Robots;
use Vhffs::Services::Pgsql;

package Vhffs::Robots::Pgsql;

sub pgsql_admin_db_connect {
	use DBI;
	my $vhffs = shift;
	my $pgsqlconfig = $vhffs->get_config->get_service('pgsql');

	my $conn = DBI->connect( 'DBI:Pg:'.$pgsqlconfig->{'datasource'}, $pgsqlconfig->{'username'}, $pgsqlconfig->{'password'} );

	return  $conn ? $conn : -1;
}

sub create {
	my $pgsql = shift;
	return undef unless defined $pgsql and $pgsql->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $pgsql->get_vhffs;

	my $dbi = pgsql_admin_db_connect( $vhffs );
	return unless $dbi;

	unless( $dbi->do('CREATE USER '.$pgsql->get_dbusername.' WITH PASSWORD ?', undef, $pgsql->get_dbpassword) ) {
		$pgsql->set_status( Vhffs::Constants::CREATION_ERROR );
		$pgsql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating user '.$pgsql->get_dbusername.' for pgsql database '.$pgsql->get_dbname );
		return undef;
	}

	unless( $dbi->do('CREATE DATABASE '.$pgsql->get_dbname.' OWNER '.$pgsql->get_dbusername ) ) {
		$pgsql->set_status( Vhffs::Constants::CREATION_ERROR );
		$pgsql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating pgsql database '.$pgsql->get_dbname );
		return undef;
	}

	$dbi->disconnect;

	Vhffs::Robots::vhffs_log( $vhffs, 'Created pgsql database '.$pgsql->get_dbname );
	$pgsql->blank_password;
	$pgsql->set_status( Vhffs::Constants::ACTIVATED );
	$pgsql->commit;

	$pgsql->send_created_mail;
	return 1;
}

sub delete {
	my $pgsql = shift;
	return undef unless defined $pgsql and $pgsql->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $pgsql->get_vhffs;
	my $pgsqlconfig = $pgsql->get_config;

	my $dbi = pgsql_admin_db_connect( $vhffs );
	return unless $dbi;

	# Replace user password with another password (we don't care which one), to set the database more or less read-only
	unless( $dbi->do('ALTER USER '.$pgsql->get_dbusername.' WITH PASSWORD ?', undef, $pgsqlconfig->{'password'}) ) {
		$pgsql->set_status( Vhffs::Constants::DELETION_ERROR );
		$pgsql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while revoking privileges from pgsql database '.$pgsql->get_dbname.' for '.$pgsql->get_dbusername );
		return undef;
	}

	# Dump the database after access are removed (thus setting the database read-only) and just before dropping it
	my $tmpfile = _dump( $pgsql );
	if( defined $tmpfile ) {
		my $file = $vhffs->get_config->get_robots->{'archive_deleted_path'}.'/'.time().'_'.$pgsql->get_group->get_groupname.'_pgsql_'.$pgsql->get_dbname.'.dump';
		require File::Copy;
		File::Copy::move( $tmpfile , $file );
	}

	unless( $dbi->do( 'DROP DATABASE '.$pgsql->get_dbname ) ) {
		$pgsql->set_status( Vhffs::Constants::DELETION_ERROR );
		$pgsql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing pgsql database '.$pgsql->get_dbname );
		return undef;
	}

	unless( $dbi->do( 'DROP USER '.$pgsql->get_dbusername ) ) {
		$pgsql->set_status( Vhffs::Constants::DELETION_ERROR );
		$pgsql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing pgsql database '.$pgsql->get_dbname );
		return undef;
	}

	$dbi->disconnect;

	if( $pgsql->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted pgsql database '.$pgsql->get_dbname );
	} else {
		$pgsql->set_status( Vhffs::Constants::DELETION_ERROR );
		$pgsql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting pgsql database '.$pgsql->get_dbname.' object' );
		return undef;
	}

	return 1;
}

sub modify {
	my $pgsql = shift;
	return undef unless defined $pgsql and $pgsql->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;

	my $vhffs = $pgsql->get_vhffs;

	my $dbi = pgsql_admin_db_connect( $vhffs );
	return unless $dbi;

	if( $pgsql->get_dbpassword ) {
		unless( $dbi->do( 'ALTER USER '.$pgsql->get_dbusername.' WITH PASSWORD ?', undef, $pgsql->get_dbpassword ) ) {
			$pgsql->set_status( Vhffs::Constants::MODIFICATION_ERROR );
			$pgsql->commit;
			Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while modifying pgsql database '.$pgsql->get_dbname );
			return undef;
		}
		$pgsql->blank_password;
		$pgsql->add_history( 'Password changed' );
		Vhffs::Robots::vhffs_log( $vhffs, 'Password changed for pgsql database '.$pgsql->get_dbname );
	}

	$dbi->disconnect;

	$pgsql->set_status( Vhffs::Constants::ACTIVATED );
	$pgsql->commit;
	return 1;
}

sub _dump {
	my $pg = shift;
	my $pgsqlconf = $pg->get_config;
	return undef unless defined $pgsqlconf;

	my $dbconf = {};
	foreach( split /;/, $pgsqlconf->{'datasource'} ) {
		my ( $key, $value ) = split /=/;
		$dbconf->{$key} = $value;
	}

	# create the postgres password file
	my ( $pgpassfile, $pgpasspath ) = Vhffs::Robots::tmpfile( $pg->get_vhffs );
	return undef unless defined $pgpassfile;
	chmod( 0400, $pgpasspath );
	print $pgpassfile '*:*:*:*:'.$pgsqlconf->{'password'}."\n";
	close $pgpassfile;

	my ( $tmpfile, $tmppath ) = Vhffs::Robots::tmpfile( $pg->get_vhffs );
	unless( defined $tmpfile ) {
		unlink $pgpasspath;
		return undef;
	}
	close $tmpfile;

	my $ret;
	$ENV{'PGPASSFILE'} = $pgpasspath;

	my @params;
	push @params, '-h', $dbconf->{'host'} if defined $dbconf->{'host'};
	push @params, '-p', $dbconf->{'port'} if defined $dbconf->{'port'};

	my $childpid = open( my $output, '-|', $pgsqlconf->{'pgdump_path'}, '-U', $pgsqlconf->{'username'}, @params, '-b', '-Fc', '-Z0', '-f', $tmppath, $pg->get_dbname );
	if ($childpid) {
		# read process output
		while(<$output>) {}

		# wait for the child to finish
		waitpid( $childpid, 0 );

		# $? contains the return value, The high byte is the exit value of the process. The low 7 bits represent
		# the number of the signal that killed the process, with the 8th bit indicating whether a core dump occurred.
		# -- signal is 0 if no signal were sent to kill the process
		# -- exit value is 0 if the process success
		# -- core dump bit is 0 if no core dump were written to disk
		# ---- so, $? contains 0 if everything went fine
		$ret = $? >> 8 if $?;
	}

	delete $ENV{'PGPASSFILE'};
	unlink $pgpasspath;

	# Something went wrong, output is available in stderr
	unless( $childpid and not defined $ret and -s $tmppath ) {
		unlink $tmppath;
		return undef;
	}

	return $tmppath;
}

sub dump_night {
	my $pg = shift;

	my $dir = $pg->get_group->get_dir;
	return undef unless -d $dir;
	my $file = $dir.'/'.$pg->get_dbname.'.pgsql.dump';

	my $tmpfile = _dump($pg);
	return undef unless defined $tmpfile;

	chmod( 0440, $tmpfile );
	chown( $pg->get_owner_uid , $pg->get_owner_gid , $tmpfile );
	require File::Copy;
	File::Copy::move( $tmpfile , $file );

	return 1;
}

1;
