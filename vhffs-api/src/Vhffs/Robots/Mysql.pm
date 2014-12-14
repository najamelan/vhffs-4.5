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
use Vhffs::Services::Mysql;

package Vhffs::Robots::Mysql;

sub mysql_admin_db_connect {
	use DBI;
	my $vhffs = shift;
	my $mysqlconfig = $vhffs->get_config->get_service('mysql');

	return DBI->connect( 'DBI:mysql:'.$mysqlconfig->{'datasource'}, $mysqlconfig->{'username'}, $mysqlconfig->{'password'} );
}

sub create {
	my $mysql = shift;
	return undef unless defined $mysql and $mysql->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $mysql->get_vhffs;

	my $dbi = mysql_admin_db_connect( $vhffs );
	return unless $dbi;

	# create the database
	unless( $dbi->do( 'CREATE DATABASE '.$mysql->get_dbname ) ) {
		$mysql->set_status( Vhffs::Constants::CREATION_ERROR );
		$mysql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating mysql database '.$mysql->get_dbname );
		return undef;
	}

	# grant privileges to user
	my $query = 'GRANT ALL ON '.$mysql->get_dbname.'.* TO '.$mysql->get_dbname.' IDENTIFIED BY ?';
	unless( $dbi->do( $query, undef, $mysql->get_dbpassword ) ) {
		$mysql->set_status( Vhffs::Constants::CREATION_ERROR );
		$mysql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while granting privileges to mysql database '.$mysql->get_dbname.' to '.$mysql->get_dbname );
		$dbi->do( 'DROP DATABASE '.$mysql->get_dbname );
		return undef;
	}

	$dbi->do( 'FLUSH PRIVILEGES' );
	$dbi->disconnect;

	Vhffs::Robots::vhffs_log( $vhffs, 'Created mysql database '.$mysql->get_dbname );
	$mysql->blank_password;
	$mysql->set_status( Vhffs::Constants::ACTIVATED );
	$mysql->commit;

	$mysql->send_created_mail;
	return 1;
}

sub delete {
	my $mysql = shift;
	return undef unless defined $mysql and $mysql->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $mysql->get_vhffs;

	my $dbi = mysql_admin_db_connect( $vhffs );
	return unless $dbi;

	my $fail = 0;
	$dbi->do( 'DELETE FROM user WHERE User = ?', undef, $mysql->get_dbname ) or $fail=1;
	$dbi->do( 'DELETE FROM db WHERE User = ?', undef, $mysql->get_dbname ) or $fail=1;
	$dbi->do( 'DELETE FROM tables_priv WHERE User = ?', undef, $mysql->get_dbname ) or $fail=1;
	$dbi->do( 'DELETE FROM columns_priv WHERE User = ?', undef, $mysql->get_dbname ) or $fail=1;

	if( $fail ) {
		$mysql->set_status( Vhffs::Constants::DELETION_ERROR );
		$mysql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while revoking privileges from mysql database '.$mysql->get_dbname.' for '.$mysql->get_dbname );
		return undef;
	}

	$dbi->do( 'FLUSH PRIVILEGES' );

	# Dump the database after access are removed (thus setting the database read-only) and just before dropping it
	my $tmpfile = _dump( $mysql );
	if( defined $tmpfile ) {
		my $file = $vhffs->get_config->get_robots->{'archive_deleted_path'}.'/'.time().'_'.$mysql->get_group->get_groupname.'_mysql_'.$mysql->get_dbname.'.dump';
		File::Copy::move( $tmpfile, $file );
	}

	unless( $dbi->do( 'DROP DATABASE '.$mysql->get_dbname ) ) {
		$mysql->set_status( Vhffs::Constants::DELETION_ERROR );
		$mysql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing mysql database '.$mysql->get_dbname );
		return undef;
	}

	$dbi->disconnect;

	if( $mysql->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted mysql database '.$mysql->get_dbname );
	} else {
		$mysql->set_status( Vhffs::Constants::DELETION_ERROR );
		$mysql->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting mysql database '.$mysql->get_dbname.' object' );
		return undef;
	}

	return 1;
}

sub modify {
	my $mysql = shift;
	return undef unless defined $mysql and $mysql->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;

	my $vhffs = $mysql->get_vhffs;

	my $dbi = mysql_admin_db_connect( $vhffs );
	return unless $dbi;

	if( $mysql->get_dbpassword ) {
		unless( $dbi->do( 'UPDATE user SET PASSWORD=PASSWORD(?) WHERE user = ?', undef, $mysql->get_dbpassword, $mysql->get_dbname) ) {
			$mysql->set_status( Vhffs::Constants::MODIFICATION_ERROR );
			$mysql->commit;
			Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while modifying mysql database '.$mysql->get_dbname );
			return undef;
		}
		$mysql->blank_password;
		$mysql->add_history( 'Password changed' );
		Vhffs::Robots::vhffs_log( $vhffs, 'Password changed for mysql database '.$mysql->get_dbname );
	}

	$dbi->do( 'FLUSH PRIVILEGES' );
	$dbi->disconnect;

	$mysql->set_status( Vhffs::Constants::ACTIVATED );
	$mysql->commit;
	return 1;
}

sub _dump {
	my $mysql = shift;
	my $mysqlconf = $mysql->get_config;
	return undef unless defined $mysqlconf;

	my $dbconf = {};
	foreach( split /;/, $mysqlconf->{'datasource'} ) {
		my ( $key, $value ) = split /=/;
		$dbconf->{$key} = $value;
	}

	my ( $tmpfile, $tmppath ) = Vhffs::Robots::tmpfile( $mysql->get_vhffs );
	return undef unless defined $tmpfile;

	my @params;
	push @params, '-h', $dbconf->{'host'} if defined $dbconf->{'host'};
	push @params, '-P', $dbconf->{'port'} if defined $dbconf->{'port'};

	my $ret;
	my $childpid = open( my $output, '-|', $mysqlconf->{'mysqldump_path'}, '-c', '-R', '--hex-blob', @params, '-u', $mysqlconf->{'username'}, '-p'.$mysqlconf->{'password'}, $mysql->get_dbname );
	if ($childpid) {
		# Ensure output is in binary mode
		binmode($output);

		# read process output, write output to $tmpfile
		while(<$output>) { print $tmpfile $_; }

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

	close( $tmpfile );

	# Something went wrong, output is available in stderr
	unless( $childpid and not defined $ret and -s $tmppath ) {
		unlink $tmppath;	
		return undef;
	}

	return $tmppath;
}

sub dump_night {
	my $mysql = shift;

	my $dir = $mysql->get_group->get_dir;
	return undef unless -d $dir;
	my $file = $dir.'/'.$mysql->get_dbname.'.mysql.dump';

	my $tmpfile = _dump($mysql);
	return undef unless defined $tmpfile;

	chmod( 0440, $tmpfile );
	chown( $mysql->get_owner_uid , $mysql->get_owner_gid , $tmpfile );
	require File::Copy;
	File::Copy::move( $tmpfile , $file );

	return 1;
}

1;
