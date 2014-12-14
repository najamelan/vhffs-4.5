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

use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::Robots;
use Vhffs::Services::Repository;

package Vhffs::Robots::Repository;

sub create {
	my $repository = shift;
	return undef unless defined $repository and $repository->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $repository->get_vhffs;
	my $dir = $repository->get_dir;

	if( -e $dir ) {
		$repository->set_status( Vhffs::Constants::CREATION_ERROR );
		$repository->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating downloads repository '.$repository->get_name.' to the filesystem' );
		return undef;
	}

	File::Path::make_path( $dir, { error => \my $errors });
	if(@$errors) {
		$repository->set_status( Vhffs::Constants::CREATION_ERROR );
		$repository->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating downloads repository '.$repository->get_name.' to the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	chown( $repository->get_owner_uid, $repository->get_owner_gid, $dir );
	chmod( 02775, $dir );

	unless( Vhffs::Robots::link_to_group( $repository, $repository->get_name.'-repository', $dir ) ) {
		$repository->set_status( Vhffs::Constants::CREATION_ERROR );
		$repository->commit;
		return undef;
	}

	Vhffs::Robots::vhffs_log( $vhffs, 'Created downloads repository '.$repository->get_name );
	$repository->set_status( Vhffs::Constants::ACTIVATED );
	$repository->commit;
	quota($repository);

	$repository->send_created_mail;
	return 1;
}

sub delete {
	my $repository = shift;
	return undef unless defined $repository and $repository->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $repository->get_vhffs;
	my $dir = $repository->get_dir;

	unless( Vhffs::Robots::unlink_from_group( $repository, $repository->get_name.'-repository' ) ) {
		$repository->set_status( Vhffs::Constants::DELETION_ERROR );
		$repository->commit;
		return undef;
	}

	Vhffs::Robots::archive_targz( $repository, $dir );

	File::Path::remove_tree( $dir, { error => \my $errors });
	if(@$errors) {
		$repository->set_status( Vhffs::Constants::DELETION_ERROR );
		$repository->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing downloads repository '.$repository->get_name.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	if( $repository->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted downloads repository '.$repository->get_name );
	} else {
		$repository->set_status( Vhffs::Constants::DELETION_ERROR );
		$repository->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting downloads repository '.$repository->get_name.' object' );
		return undef;
	}

	return 1;
}

sub modify {
	my $repository = shift;
	return undef unless defined $repository and $repository->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;
	$repository->set_status( Vhffs::Constants::ACTIVATED );
	$repository->commit;
	return 1;
}

sub quota {
	my $repository = shift;
	return undef unless defined $repository;

	my $vhffs = $repository->get_vhffs;

	my $dev = Quota::getqcarg($vhffs->get_config->get_datadir.'/repository');

	my $setblocks = POSIX::ceil( ($repository->get_quota*1000000)/1024 );  # Filesystem quota block = 1024B
	my $setinodes = POSIX::ceil( ($repository->get_quota*1000000)/4096 );  # Filesystem block = 4096B

	my ($blocks,$softblocks,$hardblocks,undef,undef,$softinodes,$hardinodes,undef) = Quota::query($dev, $repository->get_owner_gid, 1);

	# Set quota - only if database and filesystem are out of sync
	unless( defined $softblocks and defined $hardblocks and defined $softinodes and defined $hardinodes
	  and $softblocks == $hardblocks and $softinodes == $hardinodes
	  and $hardblocks == $setblocks and $hardinodes == $setinodes) {

		unless( Quota::setqlim($dev, $repository->get_owner_gid, $setblocks, $setblocks, $setinodes, $setinodes, 0, 1) ) {
			Vhffs::Robots::vhffs_log( $vhffs, 'Set quota for repository '.$repository->get_name.' (gid '.$repository->get_owner_gid.') to '.$repository->get_quota.' MB');
			$repository->add_history( 'Disk quota set to '.$repository->get_quota.' MB' );
		} else {
			Vhffs::Robots::vhffs_log( $vhffs, 'Cannot set quota for repository '.$repository->get_name.' (gid '.$repository->get_owner_gid.'), reason: '.Quota::strerr() );
		}
	}

	# Get quota - only push changes if filesystem and database have different values
	return undef unless defined $blocks;
	my $used = POSIX::ceil( ($blocks*1024)/1000000 );
	return 1 if $used == $repository->get_quota_used;
	$repository->set_quota_used( $used );
	$repository->commit;
	Vhffs::Robots::vhffs_log( $vhffs, 'Updated quota used for repository '.$repository->get_name.' (gid '.$repository->get_owner_gid.') to '.$used.' MB');
}

#Your logs must be in format : "%V %h %l %u %t \"%r\" %>s %b"
#So, add in your httpd.conf following lines :
#LogFormat "%V %h %l %u %t \"%r\" %>s %b" vhffs
#CustomLog /var/log/apache2/http.log vhffs
sub awstats_stats {
	my $vhffs = shift;
	return undef unless defined $vhffs;

	my $repoconf = $vhffs->get_config->get_service('repository');
	return undef unless defined $repoconf;

	my $log_incoming_root = $repoconf->{'log_incoming_root'};
	my $log_parsed_root = $repoconf->{'log_parsed_root'};

	unless( -d $log_incoming_root ) {
		print 'ERROR: '.$log_incoming_root.' is not a directory'."\n";
		return undef;
	}
	unless( -d $log_parsed_root ) {
		print 'ERROR: '.$log_parsed_root.' is not a directory'."\n";
		return undef;
	}
	unless( -x $repoconf->{'log_awstats'} ) {
		print 'ERROR: '.$repoconf->{'log_awstats'}.' does no exist'."\n";
		return undef;
	}
	unless( -f $repoconf->{'log_awstats_sample'} ) {
		print 'ERROR: cannot find the awstat sample at '.$repoconf->{'log_awstats_sample'}."\n";
		return undef;
	}

	my $repos = Vhffs::Services::Repository::getall( $vhffs, Vhffs::Constants::ACTIVATED );
	return undef unless defined $repos;

	# Build a hash of all repositories names
	my %repositorys;
	foreach ( @{$repos} )  {
		$repositorys{$_->get_name} = $_;
	}

	# Build downloads servers list
	my @downloadservers;
	opendir( my $dirfd, $log_incoming_root );
	foreach( readdir( $dirfd ) )  {
		next if /^\./;
		my $path = $log_incoming_root.'/'.$_;
		next unless -d $path;
		push @downloadservers, { name => $_, path => $path };
	}
	closedir( $dirfd );

	# Rotate downloads servers logs
	#
	# All *.log files, I know that the suffix is hardcoded but I don't bother to add a configuration
	# entry for that, it's already too complicated, and, who would like anything other than .log ?
	foreach my $downloadserver ( @downloadservers ) {

		opendir( my $dirfd, $downloadserver->{path} );
		foreach( readdir( $dirfd ) )  {
			next unless /\.log$/;
			Vhffs::Robots::rotate_log( $downloadserver->{path}.'/'.$_, $repoconf->{'log_incoming_rotations'}, $repoconf->{'log_incoming_compress'} );
		}
		closedir( $dirfd );
	}

	# Run the post rotate command
	if( $repoconf->{'log_postrotate'} ) {
		my $ret;

		my $childpid = open( my $output, '-|', split( /\s+/, $repoconf->{'log_postrotate'} ) );
		if($childpid) {
			# read process output and discard
			while(<$output>) {}

			# wait for the child to finish
			waitpid( $childpid, 0 );

			# $? contains the return value, The high byte is the exit value of the process. The low 7 bits represent
			# the number of the signal that killed the process, with the 8th bit indicating whether a core dump occurred.
			# -- signal is 0 if no signal were sent to kill the process
			# -- exit value is 0 if the process success
			# -- core dump bit is 0 if no core dump were written to disk
			# ---- so, $? contains 0 if everything went fine
			$ret = $?;
		}

		unless( defined $ret and $ret == 0 ) {
			print 'ERROR: failed to run the postrotate command line, aborting: '.$repoconf->{'log_postrotate'}."\n";
			return;
		}
	}

	# Deleting previous logs
	unlink $log_incoming_root.'/mergedlog';
	unlink $log_incoming_root.'/rejectlog';

	# Merge all logs
	open( my $mergedoutput, '>', $log_incoming_root.'/mergedlog' );
	my $childpid = open( my $output, '-|', 'mergelog', ( map { $_->{path}.'/http.log.0' } @downloadservers ), ( map { $_->{path}.'/ftp.log.0' } @downloadservers ) );
	if($childpid) {
		# read process output and print to destination
		while(<$output>) { print $mergedoutput $_; }

		# wait for the child to finish
		waitpid( $childpid, 0 );
	}
	close( $mergedoutput );

	# Parse http logs
	my $prev = '';
	my $fileout;
	my $ddir = $vhffs->get_config->get_datadir.'/repository/';
	$ddir =~ s%[/]{2,}%/%g;

	open( my $mergedin, '<', $log_incoming_root.'/mergedlog' );
	open( my $rejectout, '>', $log_incoming_root.'/rejectlog' );

	while( <$mergedin> ) {

		my ( $remotehost, $rfc931, $authuser, $date, $request, $status, $size, $referer, $useragent ) = ( $_ =~ /^([^\s]*)\s+([^\s]*)\s+([^\s]*)\s+\[([^\]]*)\]\s+\"([^\"]*)\"\s+([^\s]*)\s+([^\s]*)(?:\s+\"([^\"]*)\")?(?:\s+\"([^\"]*)\")?$/ );
		next unless defined $remotehost and defined $rfc931 and defined $authuser and defined $date and defined $request and defined $status and defined $size;

		# define referer and useragent (convert common to combined log)
		$referer = '-' unless defined $referer;
		$useragent = '-' unless defined $useragent;

		# remove the "/data/repository/" part of the query
		$request =~ s%$ddir/*%/%;

		# remove the http:// part of the query if it exists
		$request =~ s%http://[^/]+/*%/%;

		# add HTTP/1.0 at the end of the query if needed
		$request .= ' HTTP/1.0' if( $request && $request !~ /\ HTTP\/1.[01]$/ );

		# fetch the group
		my ( $area ) = ( $request =~ /^[^\/]*\/([^\/]+)/ );

		# rebuild
		my $log = $remotehost.' '.$rfc931.' '.$authuser.' ['.$date.'] "'.$request.'" '.$status.' '.$size.' "'.$referer.'" "'.$useragent.'"';

		# append log line to the concerned download area
		next unless defined $area and defined $log;

		my $repository = $repositorys{$area};

		# We are _NOT_ hosting this repository
		unless( $repository )  {
			print $rejectout $area.' '.$log."\n";
			next;
		}

		# the repository changed
		if ( $prev ne $area )  {
			my $repodir = $log_parsed_root.'/'.$area.'/logs';
			unless( -d $repodir ) {
				File::Path::make_path( $repodir );
				#chown( $repository->get_owner_uid, $repository->get_owner_gid, $repodir );
				#chmod( 0770, $repodir );
			}
			unless( -d $repodir ) {
				close( $fileout ) if defined $fileout;
				undef $fileout;
				$prev = '';
				next;
			}

			close( $fileout ) if defined $fileout;
			open( $fileout, '>>', $repodir.'/access.log');

			$prev = $area;
		}

		print $fileout $log."\n";
	}

	close( $mergedin );
	close( $rejectout );
	close( $fileout ) if defined $fileout;

	# Create a configuration file and generate statistic for each website
	foreach ( @{$repos} ) {
		my $reponame = $_->get_name;

		my $weblogdir = $log_parsed_root.'/'.$reponame;
		my $logpath = $weblogdir.'/logs/access.log';
		my $datadir = $weblogdir.'/awstats';
		my $conffile = $datadir.'/awstats.'.$reponame.'.conf';

		next unless -f $logpath;
		unless( -d $datadir ) {
			File::Path::make_path( $datadir );
		}
		unless( -d $datadir ) {
			next;
		}

		# Create the config file
		open( my $awfilein, '<', $repoconf->{'log_awstats_sample'} );
		open( my $awfileout, '>', $conffile );

		while( <$awfilein> ) {
			s/MY_DOMAINNAME/$reponame/g;
			s/MY_LOGPATH/$logpath/g;
			s/MY_DATADIR/$datadir/g;
			print $awfileout $_;
		}

		close( $awfileout );
		close( $awfilein );

		# Generate statistics
		my $childpid = open( my $output, '-|', $repoconf->{'log_awstats'}, '-config='.$reponame, '-update' );
		if($childpid) {
			# read process output and discard
			while(<$output>) {}

			# wait for the child to finish
			waitpid( $childpid, 0 );
		}

		# Rotate logs for this website
		Vhffs::Robots::rotate_log( $logpath, $repoconf->{'log_parsed_rotation'}, $repoconf->{'log_parsed_compress'} );
	}

	return 1;
}

1;
