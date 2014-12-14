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
use Fcntl ':mode';
use IO::Handle;
use IO::Select;
use BSD::Resource;
use English;
use Cwd 'chdir';
#use Data::Dumper;

use constant
{
	STATUS_CREATED => 0,
	STATUS_RUNNING => 1,
	STATUS_KILLED => 2,

	FAIL_TO_RUN_PROCESS_EXIT_CODE => 136,
};

use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::Services::Cron;
use Vhffs::Robots::Cron;
use Vhffs::Functions;

#select(STDOUT);
#$| = 1;

my $vhffs = new Vhffs( { backend => 0 } );
exit 1 unless defined $vhffs;

$vhffs->connect;

my $cronconf = $vhffs->get_config->get_service('cron');
unless( defined $cronconf ) {
	print 'Please add VHFFS configuration for this module'."\n";
	exit 1;
}

# daemonize if there is an argument
if( $#ARGV >= 0 ) {
	close STDOUT;
	close STDIN;
	close STDERR;
	exit 0 if defined fork();
}

my $chroot = $cronconf->{'chroot'};
my $limits = $cronconf->{'limits'};
my $rlimits = BSD::Resource::get_rlimits();
my $mailcronfrom = $cronconf->{'mail_from'};
my $maxexectime = $cronconf->{'max_execution_time'};
my $nice = $cronconf->{'nice'};

my %jobs;
my %fd2jobs;
my $read_set = new IO::Select();
my $prevrun = 0;

while(1)  {

	# Reconnect to backend if necessary, do nothing if backend is down
	unless( $vhffs->reconnect ) {
		sleep 60;
		next;
	}

	if( time() - $prevrun > int(rand 10)+5 )  {

		# new jobs ?
		my $crons = Vhffs::Robots::Cron::get_runnable_jobs( $vhffs );
		foreach my $c ( @{$crons} )  {
			if( exists $jobs{ $c->get_cron_id } )  {
				print scalar localtime().'    ! '.$c->get_cron_id.' '.$c->get_cronpath."\n";
			}
			else {
				new_job( $c );
			}
		}

		# stalled jobs ?
		$crons = Vhffs::Robots::Cron::get_stalled_jobs( $vhffs , $maxexectime + 60 );
		foreach my $c ( @{$crons} )  {
			$c->quick_reset();
			print scalar localtime().'    * '.$c->get_cron_id.' '.$c->get_cronpath."\n";
		}

		$prevrun = time();
	}

	foreach ( keys %jobs )  {
		my $job = $jobs{$_};

		if( $job->{'status'} == STATUS_CREATED )  {
			run_job( $job ) if( time() > $job->{'runat'} );
			next;
		}

		if ( $job->{'status'} == STATUS_RUNNING )  {
			if( defined $maxexectime  &&  $maxexectime > 0  &&  time() - $job->{'startedat'} > $maxexectime ) {
				kill 9, $job->{'pid'};
				$job->{'status'} = STATUS_KILLED;
				next;
			}
		}

		next if defined $job->{'pipe'};

		my $pid = waitpid( $job->{'pid'}, POSIX::WNOHANG );
		my $returnvalue = $? >> 8;
		next if $pid != $job->{'pid'};

		my $cron = $job->{'cron'};
	
		$job->{'output'} .= "\n------KILLED------\n" if( $job->{'status'} == STATUS_KILLED );
		
		if( defined $job->{'output'}  &&  $job->{'output'} ne '' )  {
		
			my $body = 'Exit value: '. $returnvalue."\n\n";
			$body .= 'WARNING: This process was killed because it were still running after more than '.$maxexectime.' seconds'."\n\n" if( $job->{'status'} == STATUS_KILLED );
			$body .= "\n--- Environment ---\n\n".$job->{'env'}."\n\n--- Stdout and stderr output ---\n\n".$job->{'output'}."\n";
			sendmail_cron( $cron , $body );
		}

		my $nextinterval = $cron->get_interval;
		$nextinterval = 600 if $returnvalue == FAIL_TO_RUN_PROCESS_EXIT_CODE;
		$cron->quick_set_nextrundate( time() + $nextinterval );
		$cron->quick_set_lastrun( $job->{'createdat'} , $returnvalue );
		$cron->quick_dec_running();
		destroy_job( $job );
	}

	my ($rh_set) = IO::Select->select($read_set, undef, undef, 1);
	foreach my $rh (@$rh_set) {
		my $job = $fd2jobs{$rh->fileno};
		my $cron = $job->{'cron'};
		my $buf = <$rh>;
		if($buf) {
			if( $job->{'inheaders'} )  {
				if( (my $data) = ( $buf =~ /^ENV:(.*)$/ ) ) {
					$job->{'env'} .= $data."\n";
				}
				elsif( $buf =~ /^$/ )  {
					$job->{'inheaders'} = 0;
				}
			}
			else  {
				$job->{'output'} .= $buf;
			}
		}
		else {
			delete $fd2jobs{ $rh->fileno };
			$read_set->remove( $rh );
			close( $rh );
			$job->{'pipe'} = undef;
		}
	}

	#print 'Jobs: '.join(' ', sort { $a <=> $b } keys %jobs)."\n";
	#print 'Fd2Jobs: '.join(' ', sort { $a <=> $b } keys %fd2jobs)."\n";
}

exit 0;


sub new_job
{
	my $cron = shift;
	my $cron_id = $cron->get_cron_id;

	$jobs{$cron_id}{'cron'} = $cron;
	$jobs{$cron_id}{'pid'} = undef;
	$jobs{$cron_id}{'pipe'} = undef;
	$jobs{$cron_id}{'output'} = undef;
	$jobs{$cron_id}{'env'} = '';
	$jobs{$cron_id}{'inheaders'} = 1;
	$jobs{$cron_id}{'createdat'} = time();
	$jobs{$cron_id}{'runat'} = $jobs{$cron_id}{'createdat'} + int(rand 4) +2;
	$jobs{$cron_id}{'startedat'} = undef;
	$jobs{$cron_id}{'status'} = STATUS_CREATED;
	$cron->quick_set_nextrundate( $jobs{$cron_id}{'runat'} );  # so that we know when the process will/has be/been started in nextrundate
	$cron->quick_inc_running();

	print scalar localtime().'    + '.$cron_id.' '.$cron->get_cronpath."\n";
	return $jobs{$cron_id};
}


sub run_job
{
	my $job = shift;
	my $cron = $job->{'cron'};
	my $cron_id = $cron->get_cron_id;

	my $running = $cron->quick_get_running();
	return 1 unless defined $running;
	if( $running > 1 )  {
		print scalar localtime().'    x '.$cron_id.' '.$cron->get_cronpath."\n";
		$cron->quick_dec_running();
		destroy_job( $job );
		return 1;
	}
	elsif( $running < 0 )  {
		#this should not happen, set running to 0 and abort
		$cron->quick_set_running( 0 );
		destroy_job( $job );
		return 1;
	}
	print scalar localtime().'    > '.$cron_id.' '.$cron->get_cronpath."\n";

	my $par = new IO::Handle->new();
	my $son = new IO::Handle->new();

	unless( pipe( $par, $son ) )  {
		print "pipe() failed\n";
		destroy_job( $job );
		return 1;
	}

	my $pid = fork();
	unless( defined $pid )  {
		print "fork() failed\n";
		close $par;
		close $son;
		destroy_job( $job );
		return 1;
	}

	if ($pid) {

		# I am the parent
		close $son;

		$jobs{$cron_id}{'pid'} = $pid;
		$jobs{$cron_id}{'pipe'} = $par;
		$jobs{$cron_id}{'startedat'} = time();
		$jobs{$cron_id}{'status'} = STATUS_RUNNING;
		$fd2jobs{$par->fileno} = $jobs{$cron_id};
		$read_set->add($par);
		return 0;

	}
	elsif($pid == 0)  {

		# I am the child
		close $par;
		$son->autoflush(1);

		close STDOUT;
		open STDOUT, '>&'.$son->fileno;
		STDOUT->autoflush(1);

		close STDERR;
		open STDERR, '>&'.$son->fileno;
		STDERR->autoflush(1);

		foreach my $resource ( keys %{$limits} )  {
			my ( $soft , $hard ) = ( $limits->{$resource} =~ /^\s*([\d\w]+)\s+([\d\w]+)\s*$/ );

			$resource = $rlimits->{uc $resource};
			$soft = eval $soft;   # we get a string, we have to convert it to the
			$hard = eval $hard;   # integer constant if needed ( RLIM_INFINITY and such )

			BSD::Resource::setrlimit( $resource , $soft, $hard ) if defined $resource and defined $soft and defined $hard;
		}

		POSIX::nice $nice;
		%ENV = ();

		chroot $chroot if defined $chroot;

		$GID = $EGID = $cron->get_owner_gid.' '.$cron->get_owner_gid;
		$UID = $EUID = $cron->get_owner_uid;
		unless( POSIX::getuid() == $cron->get_owner_uid && POSIX::getgid() == $cron->get_owner_gid ) {
			print $son "CRITICAL: Error while setting UID and GID\n";
			_exit(FAIL_TO_RUN_PROCESS_EXIT_CODE);
		}

		my ($username,undef,undef,undef,undef,undef,undef,$homedir,undef,undef) = getpwuid( $cron->get_owner_uid );
		if( $username and $homedir ) {
			$ENV{'PATH'} = '/usr/bin:/bin';
			$ENV{'HOME'} = $homedir;
			$ENV{'LOGNAME'} = $username;
			chdir $homedir;
		}

		unless( $username and $homedir and $ENV{'PWD'} eq $homedir ) {
			print $son "CRITICAL: Cannot chdir() to home directory\n";
			_exit(FAIL_TO_RUN_PROCESS_EXIT_CODE);
		}

		foreach (sort keys(%ENV)) {
			print $son 'ENV:'.$_.'='.$ENV{$_}."\n";
		}
		print $son "\n";

		my $cronpath = $cron->get_cronpath;

		unless( -f $cronpath && -x $cronpath )  {
			print $son "CRITICAL: The path must be a regular file with executable rights (+x)\n";
			_exit(FAIL_TO_RUN_PROCESS_EXIT_CODE);
		}

		my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($cronpath);

		unless( $gid == $cron->get_owner_gid )  {
			print $son "CRITICAL: GID of file don't match the owner GID of this object in the VHFFS database\n";
			_exit(FAIL_TO_RUN_PROCESS_EXIT_CODE);
		}

		unless( $uid == $cron->get_owner_uid )  {
			print $son "CRITICAL: UID of file don't match the owner UID of this object in the VHFFS database\n";
			_exit(FAIL_TO_RUN_PROCESS_EXIT_CODE);
		}

		if( $mode & S_IWOTH )  {
			print $son "CRITICAL: File is writeable by others, I am not going to execute that\n";
			_exit(FAIL_TO_RUN_PROCESS_EXIT_CODE);
		}	

		exec $cron->get_cronpath;	
		exit 1;
	}
}


sub destroy_job
{
	my $job = shift;
	my $cron = $job->{'cron'};
	my $cron_id = $cron->get_cron_id;

	print scalar localtime().'    - '.$cron->get_cron_id.' '.$cron->get_cronpath."\n";
	delete $jobs{$cron_id};

	my $pipe = $job->{'pipe'};
	if( defined $pipe )  {
		delete $fd2jobs{ $pipe->fileno };
		$read_set->remove($pipe);
		close($pipe);
	}
}


sub sendmail_cron
{
	my $cron = shift;
	my $body = shift;
	return undef unless( defined $cron->get_reportmail  &&  $cron->get_reportmail ne '' );
	my $subject = 'VHFFS Cron '.$cron->get_cronpath;
	Vhffs::Functions::send_mail( $vhffs , $mailcronfrom , $cron->get_reportmail , $vhffs->get_config->get_mailtag , $subject , $body );
}
