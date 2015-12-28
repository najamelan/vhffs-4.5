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

package Vhffs::Robots;

no warnings 'redefine';

use strict;
use utf8;

require Exporter;
my @ISA    = qw(Exporter);
my @EXPORT = qw(vhffs_log lock unlock);

use Cwd;
use File::Basename;

use Vhffs;
use Vhffs::Functions;
use LockFile::Simple;

=pod

=head1 NAME

Vhffs::Robots - common interface for VHFFS Robots

=head1 SYNOPSIS

	use Vhffs::Robots;

	Vhffs::Robots::lock();

	Vhffs::Robots::unlock();

	Vhffs::Robots::vhffs_log( "My log message" );

=head1 DESCRIPTION

This class contains static methods commonly used by VHFFS robots.

=head1 METHODS

=cut

=pod

=head2 lock

Vhffs::Robots::lock( $vhffs, 'lockname' );

Creates a lockfile. Other process that call lock method are stalled until unlock is deleted.

=cut
sub lock {
	my $vhffs = shift;
	my $name = shift;
	return 1 unless defined $vhffs and defined $name;

	my $robotconf = $vhffs->get_config->get_robots;
	return 0 unless $robotconf->{'use_lock'} and defined $robotconf->{'lockfile'};

	LockFile::Simple::lock( $robotconf->{'lockfile'}.'.'.$name ) or exit( 1 );
	return 0;
}

=pod

=head2 unlock

Vhffs::Robots::unlock( $vhffs, 'lockname' );

Delete a lock file. Locked processes can continue.

=cut
sub unlock {
	my $vhffs = shift;
	my $name = shift;
	return 1 unless defined $vhffs and defined $name;

	my $robotconf = $vhffs->get_config->get_robots;
	return 0 unless $robotconf->{'use_lock'} and defined $robotconf->{'lockfile'};

	LockFile::Simple::unlock( $robotconf->{'lockfile'}.'.'.$name );
	return 0;
}

=pod

=head2 vhffs_log

Vhffs::Robots::vhffs_log( $vhffs, 'Message' );

Add a line to the VHFFS logfile.

=cut
sub vhffs_log {
	my $vhffs = shift;
	my $message = shift;
	return 1 unless defined $vhffs and defined $message;

	my $robotconf = $vhffs->get_config->get_robots;
	return 0 unless $robotconf->{'use_logging'} and defined $robotconf->{'logfile'};

	my ($seconds,$minutes,$hours,$day,$month,$year) = localtime(time);
	my $timestamp = sprintf ('[ %.4u/%.2u/%.2u %.2u:%.2u:%.2u ]', $year+1900, $month+1, $day, $hours, $minutes, $seconds);

	open( my $logfile, '>>', $robotconf->{'logfile'} ) or return -1;
	print $logfile $timestamp.' - '.$message."\n";
	close $logfile;

	return 0;
}

=pod

=head2 link_to_group

Vhffs::Robots::link_to_group( $object, $linkname, $dir );

Create a symbolic link in C<$object> group home directory named $linkname which contains string $dir.

Returns true on success, otherwise returns undef.

=cut
sub link_to_group {
	my $object = shift;
	my $linkname = shift;
	my $dir = shift;
	return undef unless defined $object and defined $linkname and defined $dir;

	my $vhffs = $object->get_vhffs;
	return 1 if $vhffs->get_config->use_vhffsfs;

	my $linkpath = $object->get_group->get_dir.'/'.$linkname;
	unless( symlink( $dir, $linkpath ) ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating symlink '.$linkpath.' -> '.$dir );
		return undef;
	}

	Vhffs::Robots::vhffs_log( $vhffs, 'Created symlink '.$linkpath.' -> '.$dir );
	return 1;
}

=pod

=head2 unlink_from_group

Vhffs::Robots::unlink_from_group( $object, $linkname );

Delete a symbolic link in C<$object> group home directory named $linkname.

Returns true on success, otherwise returns undef.

=cut
sub unlink_from_group {
	my $object = shift;
	my $linkname = shift;
	return undef unless defined $object and defined $linkname;

	my $vhffs = $object->get_vhffs;
	return 1 if $vhffs->get_config->use_vhffsfs;

	my $linkpath = $object->get_group->get_dir.'/'.$linkname;
	unless( unlink( $linkpath ) ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting symlink '.$linkpath.': '.$! );
		return undef;
	}

	Vhffs::Robots::vhffs_log( $vhffs, 'Deleted symlink '.$linkpath );
	return 1;
}

=pod

=head2 archive_targz

Vhffs::Robots::archive_targz( $object, $dir, \@namepart );

Create a tar.gz archive of C<$object> directory $dir.

Additionnal path elements (separed by _) can be added through \@namepart.

=cut
sub archive_targz {
	my $object = shift;
	my $dir = shift;
	my $namepart = shift;
	my $ret;

	return undef unless defined $object and defined $dir and -d $dir;

	my $robotconf = $object->get_vhffs->get_config->get_robots;
	return undef unless defined $robotconf and $robotconf->{'archive_deleted'} and defined $robotconf->{'archive_deleted_path'} and -d $robotconf->{'archive_deleted_path'};

	my $oldcwd = getcwd();
	return undef unless chdir($dir);

	my $label = $object->get_label;
	$label =~ s/\//_/g; # workaround for SCM which use / in object name
	my $tarfile = $robotconf->{'archive_deleted_path'}.'/'.time().'_'.$object->get_group->get_groupname.'_'.Vhffs::Functions::type_string_fs_from_type_id( $object->get_type ).'_'.$label.( defined $namepart ? '_'.join('_', @$namepart) : '' ).'.tar.gz';
	my $childpid = open( my $output, '-|', 'tar', 'czf', $tarfile, '.' );
	if($childpid) {
		# read process output then discard
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

	chdir($oldcwd);
	return (not defined $ret and -f $tarfile) ? 1 : undef;
}

=pod

=head2 tmpfile

my $tmpfile = Vhffs::Robots::tmpfile( $vhffs );

Returns an opened temporary file and its associated path.

=cut
sub tmpfile {
	my $vhffs = shift;
	my $robotconf = $vhffs->get_config->get_robots;
	my $path = $robotconf->{'tmpdir'};
	return undef unless defined $path;
	$path .= '/';
	for (0 .. 15) { $path .= ('a'..'z', 'A'..'Z', '0'..'9')[int rand 62]; }
	$path .= '-'.$$;
	open( my $file, '>', $path );
	if( defined $file ) {
		binmode($file);
	} else {
		undef $path;
	}
	return ( $file, $path );
}

=pod

head2 rotate_log

Vhffs::Robots::rotate_log( $logfile, $rotation, $compress );

Rotate $logfile, $rotation rotation maximum, $compress(ed) or not,
then create a new empty $logfile.

=cut
sub rotate_log {
	my $logfile = shift;
	my $rotation = shift;
	my $compress = shift;
	return unless -f $logfile;

	my ( $file, $dirname ) = File::Basename::fileparse( $logfile );

	# remove files out of the rotation
	opendir( my $dh, $dirname );
	return unless defined $dh;

	while( defined(my $item = readdir($dh)) ) {
		my ( $rotatenumber ) = ( $item =~ /^$file\.(\d+)(?:\..*)?$/ );
		unlink $dirname.'/'.$item if defined $rotatenumber and $rotatenumber >= $rotation-1;
	}
	closedir( $dh );

	# rotate logs
	for( my $i = $rotation-2 ; $i >= 0 ; $i-- ) {

		# found a file which is not compressed
		if ( -f $logfile.'.'.$i ) {

			# rotate it
			rename $logfile.'.'.$i, $logfile.'.'.($i+1);

			# compress it if compression is enabled
			if ( $compress )  {

				my $childpid = open( my $output, '-|', 'gzip', $logfile.'.'.($i+1) );
				if($childpid) {
					# read process output then discard
					while(<$output>) {}

					# wait for the child to finish
					waitpid( $childpid, 0 );

					# we don't care whether gzip succedded
				}
			}
		}

		# found a file which is already compressed
		elsif ( -f $logfile.'.'.$i.'.gz' )  {

			# rotate it
			rename $logfile.'.'.$i.'.gz', $logfile.'.'.($i+1).'.gz';

			# decompress it if compression is disabled
			unless( $compress )  {
				my $childpid = open( my $output, '-|', 'gzip', '-d', $logfile.'.'.($i+1).'.gz' );
				if($childpid) {
					# read process output then discard
					while(<$output>) {}

					# wait for the child to finish
					waitpid( $childpid, 0 );

					# we don't care whether gzip succedded
				}
			}
		}
	}

	# last rotate, log -> log.0
	rename $logfile, $logfile.'.0';

	# create an empty file
	open( my $emptyfile, '>', $logfile );
	close( $emptyfile ) if defined $emptyfile;
}

=pod

=head2 chmod_recur

	Vhffs::Functions::chmod_recur($dir, $fmod, $dmod);

Changes permissions on files and directories recursively.
C<$fmod> and C<$dmod> are the mod to apply to files and
directory, respectively. See the documentation of the
original C<chmod> function for more information.

=cut
sub chmod_recur {
	my ($dir, $fmod, $dmod) = @_;

	my @files = ( $dir );
	while( defined(my $file = shift @files) ) {
		if( -d $file ) {
			chmod( $dmod, $file );
			opendir( my $dh, $file );
			if( defined $dh ) {
				while( defined(my $item = readdir($dh)) ) {
					next if( $item eq '' or $item eq '..' or $item eq '.' );
					push @files, $file.'/'.$item;
				}
				closedir( $dh );
			}
		}
		else {
			chmod( $fmod, $file );
		}
	}

	return 1;
}

=pod

=head2 chmod_recur

	Vhffs::Functions::chown_recur($dir, $uid, $gid);

Changes the owner and group on files and directories recursively.
C<$uid> and C<$gid> are the uid and gid to apply to files and
directory, respectively. See the documentation of the
original C<chown> function for more information.

=cut
sub chown_recur {
	my ($dir, $uid, $gid) = @_;

	my @files = ($dir);
	while( defined(my $file = shift @files) ) {
		chown( $uid, $gid, $file );
		if( -d $file ) {
			opendir( my $dh, $file );
			if( defined $dh ) {
				while( defined(my $item = readdir($dh)) ) {
					next if( $item eq '' or $item eq '..' or $item eq '.' );
					push @files, $file.'/'.$item;
				}
				closedir( $dh );
			}
		}
	}

	return 1;
}

1;

__END__
