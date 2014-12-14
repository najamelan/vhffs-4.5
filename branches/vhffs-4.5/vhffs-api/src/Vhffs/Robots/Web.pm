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
use Vhffs::Services::Web;

package Vhffs::Robots::Web;

sub create {
	my $web = shift;
	return undef unless defined $web and $web->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $web->get_vhffs;
	my $dir = $web->get_dir;

	if( -e $dir ) {
		$web->set_status( Vhffs::Constants::CREATION_ERROR );
		$web->commit();
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating web area '.$web->get_servername.' to the filesystem' );
		return undef;
	}

	my @dirs = ( $dir.'/htdocs', $dir.'/php-include', $dir.'/tmp' );

	File::Path::make_path( @dirs, { error => \my $errors });
	if(@$errors) {
		$web->set_status( Vhffs::Constants::CREATION_ERROR );
		$web->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating web area '.$web->get_servername.' to the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	foreach( @dirs ) {
		chown( $web->get_owner_uid, $web->get_owner_gid, $_ );
		chmod( 02775, $_ );
	}

	unless( Vhffs::Robots::link_to_group( $web, $web->get_servername.'-web', $dir ) ) {
		$web->set_status( Vhffs::Constants::CREATION_ERROR );
		$web->commit;
		return undef;
	}

	Vhffs::Robots::vhffs_log( $vhffs, 'Created web area '.$web->get_servername );
	$web->set_status( Vhffs::Constants::ACTIVATED );
	$web->commit;

	$web->send_created_mail;
	return 1;
}

sub delete {
	my $web = shift;
	return undef unless defined $web and $web->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $web->get_vhffs;
	my $dir = $web->get_dir;

	unless( Vhffs::Robots::unlink_from_group( $web, $web->get_servername.'-web' ) ) {
		$web->set_status( Vhffs::Constants::DELETION_ERROR );
		$web->commit;
		return undef;
	}

	Vhffs::Robots::archive_targz( $web, $dir );

	File::Path::remove_tree( $dir, { error => \my $errors });
	my $parent = File::Basename::dirname($dir);
	rmdir $parent;
	$parent = File::Basename::dirname($parent);
	rmdir $parent;
	$parent = File::Basename::dirname($parent);
	rmdir $parent;

	if(@$errors) {
		$web->set_status( Vhffs::Constants::DELETION_ERROR );
		$web->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing web area '.$web->get_servername.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	if( $web->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted web area '.$web->get_servername );
	} else {
		$web->set_status( Vhffs::Constants::DELETION_ERROR );
		$web->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting web area '.$web->get_servername.' object' );
		return undef;
	}

	return 1;
}

sub modify {
	my $web = shift;
	return undef unless defined $web and $web->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;
	$web->set_status( Vhffs::Constants::ACTIVATED );
	$web->commit;
	return 1;
}

sub disable {
	my $web = shift;
	return undef unless defined $web and $web->get_status == Vhffs::Constants::WAITING_FOR_SUSPENSION;

	my $vhffs = $web->get_vhffs;
	my $template = '%VHFFS_BOTS_DIR%/misc/disabled_webarea.htaccess';
	my $htaccess = $web->get_dir.'/.htaccess';

	unless ( File::Copy::copy( $template, $htaccess ) ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while disabling web area '.$web->get_servername.' : '.$! );
		$web->set_status( Vhffs::Constants::SUSPENSION_ERROR );
		$web->commit;
		return undef;
	}
	Vhffs::Robots::vhffs_log( $vhffs, 'Disabled web area '.$web->get_servername );
	$web->set_status( Vhffs::Constants::SUSPENDED );
	$web->commit;
	return 1;
}

sub enable {
	my $web = shift;
	return undef unless defined $web and $web->get_status == Vhffs::Constants::WAITING_FOR_ACTIVATION;

	my $vhffs = $web->get_vhffs;

	my $htaccess = $web->get_dir."/.htaccess";

	unless( unlink $htaccess ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while enabling web area '.$web->get_servername );
		$web->set_status( Vhffs::Constants::ACTIVATION_ERROR );
		$web->commit;
		return undef;
	}
	Vhffs::Robots::vhffs_log( $vhffs, 'Enabled web area '.$web->get_servername );
	$web->set_status( Vhffs::Constants::ACTIVATED );
	$web->commit;
	return 1;
}

#Your logs must be in format : "%V %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\""
#So, add in your httpd.conf following lines :
#LogFormat "%V %h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-agent}i\"" vhffs
#CustomLog /var/log/apache2/ServerName/vhffs.log vhffs
sub awstats_stats {
	my $vhffs = shift;
	return undef unless defined $vhffs;

	my $webconf = $vhffs->get_config->get_service('web');
	return undef unless defined $webconf;

	my $log_incoming_root = $webconf->{'log_incoming_root'};
	my $log_parsed_root = $webconf->{'log_parsed_root'};

	unless( -d $log_incoming_root ) {
		print 'ERROR: '.$log_incoming_root.' is not a directory'."\n";
		return undef;
	}
	unless( -d $log_parsed_root ) {
		print 'ERROR: '.$log_parsed_root.' is not a directory'."\n";
		return undef;
	}
	unless( -x $webconf->{'log_awstats'} ) {
		print 'ERROR: '.$webconf->{'log_awstats'}.' does no exist'."\n";
		return undef;
	}
	unless( -f $webconf->{'log_awstats_sample'} ) {
		print 'ERROR: cannot find the awstat sample at '.$webconf->{'log_awstats_sample'}."\n";
		return undef;
	}

	my $webs = Vhffs::Services::Web::getall( $vhffs, Vhffs::Constants::ACTIVATED );
	return undef unless defined $webs;

	# Build a hash of all web sites names
	my %websites;
	foreach ( @{$webs} ) {
		$websites{$_->get_servername} = $_;
	}

	# Build web servers list
	my @webservers;
	opendir( my $dirfd, $log_incoming_root );
	foreach( readdir( $dirfd ) )  {
		next if /^\./;
		my $path = $log_incoming_root.'/'.$_;
		next unless -d $path;
		push @webservers, { name => $_, path => $path };
	}
	closedir( $dirfd );

	# Rotate web servers logs
	#
	# All *.log files, I know that the suffix is hardcoded but I don't bother to add a configuration
	# entry for that, it's already too complicated, and, who would like anything other than .log ?
	foreach my $webserver ( @webservers ) {

		opendir( my $dirfd, $webserver->{path} );
		foreach( readdir( $dirfd ) )  {
			next unless /\.log$/;
			Vhffs::Robots::rotate_log( $webserver->{path}.'/'.$_, $webconf->{'log_incoming_rotations'}, $webconf->{'log_incoming_compress'} );
		}
		closedir( $dirfd );
	}

	# Run the post rotate command
	if( $webconf->{'log_postrotate'} ) {
		my $ret;

		my $childpid = open( my $output, '-|', split( /\s+/, $webconf->{'log_postrotate'} ) );
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
			print 'ERROR: failed to run the postrotate command line, aborting: '.$webconf->{'log_postrotate'}."\n";
			return;
		}
	}

	# Deleting previous logs
	unlink $log_incoming_root.'/mergedlog';
	unlink $log_incoming_root.'/rejectlog';

	# Merge all logs
	open( my $mergedoutput, '>', $log_incoming_root.'/mergedlog' );
	my $childpid = open( my $output, '-|', 'mergelog', ( map { $_->{path}.'/vhffs.log.0' } @webservers ) );
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

	open( my $mergedin, '<', $log_incoming_root.'/mergedlog' );
	open( my $rejectout, '>', $log_incoming_root.'/rejectlog' );

	while( my $line = <$mergedin> ) {
		( my ( $svname , $log ) = ( $line =~ /([a-zA-Z0-9\.\-]+)\s(.+)/g) ) or next;

		# Discard www
		$svname =~ s/^www\.//;

		my $web = $websites{$svname};

		# We are _NOT_ hosting this website
		unless( $web )  {
			print $rejectout $svname.' '.$log."\n";
			next;
		}

		# the website changed
		if ( $prev ne $svname ) {
			my $webdir = $log_parsed_root.'/'.$web->get_hash.'/logs';
			unless( -d $webdir ) {
				File::Path::make_path( $webdir );
				chown( $web->get_owner_uid, $web->get_owner_gid, $webdir );
				chmod( 0770, $webdir );
			}
			unless( -d $webdir ) {
				close( $fileout ) if defined $fileout;
				undef $fileout;
				$prev = '';
				next;
			}

			close( $fileout ) if defined $fileout;
			open( $fileout, '>>', $webdir.'/access.log');

			$prev = $svname;
		}

		print $fileout $log."\n";
	}

	close( $mergedin );
	close( $rejectout );
	close( $fileout ) if defined $fileout;

	# Create a configuration file and generate statistic for each website
	foreach my $web ( @{$webs} ) {
		my $svname = $web->get_servername;

		my $weblogdir = $log_parsed_root.'/'.$web->get_hash;
		my $logpath = $weblogdir.'/logs/access.log';
		my $datadir = $weblogdir.'/awstats';
		my $conffile = $datadir.'/awstats.'.$svname.'.conf';

		next unless -f $logpath;

		unless( -d $datadir ) {
			File::Path::make_path( $datadir );
			chown( $web->get_owner_uid, $web->get_owner_gid, $datadir );
			chmod( 0775, $datadir );
		}
		unless( -d $datadir ) {
			next;
		}

		# Create the config file
		open( my $awfilein, '<', $webconf->{'log_awstats_sample'} );
		open( my $awfileout, '>', $conffile );

		while( <$awfilein> ) {
			s/MY_DOMAINNAME/$svname/g;
			s/MY_LOGPATH/$logpath/g;
			s/MY_DATADIR/$datadir/g;
			print $awfileout $_;
		}

		close( $awfileout );
		close( $awfilein );

		# Generate statistics
		my $childpid = open( my $output, '-|', $webconf->{'log_awstats'}, '-config='.$svname, '-update' );
		if($childpid) {
			# read process output and discard
			while(<$output>) {}

			# wait for the child to finish
			waitpid( $childpid, 0 );
		}

		# Rotate logs for this website
		Vhffs::Robots::rotate_log( $logpath, $webconf->{'log_parsed_rotation'}, $webconf->{'log_parsed_compress'} );
	}

	return 1;
}

1;
