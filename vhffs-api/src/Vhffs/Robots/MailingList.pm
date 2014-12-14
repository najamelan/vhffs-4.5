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

use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::Robots;
use Vhffs::Services::MailingList;

package Vhffs::Robots::MailingList;

sub create {
	my $ml = shift;
	return undef unless defined $ml and $ml->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $ml->get_vhffs;

	$ml->set_status( Vhffs::Constants::ACTIVATED );
	$ml->commit;
	Vhffs::Robots::vhffs_log( $vhffs, 'Created mailing list '.$ml->get_listname );

	$ml->send_created_mail;
	return 1;
}

sub delete {
	my $ml = shift;
	return undef unless defined $ml and $ml->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $ml->get_vhffs;

	# TODO: Archives of archives, remove public archives

	if( $ml->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted mailing list '.$ml->get_listname );
	} else {
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting mailing list '.$ml->get_listname );
		$ml->set_status( Vhffs::Constants::DELETION_ERROR );
		$ml->commit;
		return undef;
	}

	return 1;
}

sub modify {
	my $ml = shift;
	return undef unless defined $ml and $ml->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;
	$ml->set_status( Vhffs::Constants::ACTIVATED );
	$ml->commit;
	return 1;
}

sub mhonarc_archives {
	require File::Path;
	require Template;

	my $ml = shift;
	return undef unless defined $ml;

	my $vhffs = $ml->get_vhffs;
	my $listengineconfig = $vhffs->get_config->get_listengine;
	my $mhonarcconfig = '%VHFFS_BOTS_DIR%/misc/mhonarc.config';

	my $publicdir = $listengineconfig->{'datadir'}.'/public/'.$ml->get_domain.'/'.$ml->get_localpart;
	my $archivedir = $listengineconfig->{'datadir'}.'/archives/'.$ml->get_domain.'/'.$ml->get_localpart;

	# delete previous public archives (if available) if there is no public archives for this list
	unless( $ml->get_open_archive )  {
		File::Path::remove_tree($publicdir);
		return 1;
	}

	File::Path::make_path( $publicdir, { mode => 0755, error => \my $errors } );
	if(@$errors) {
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating mailing list archives '.$publicdir.' directory: '.join(', ', @$errors) );
		return undef;
	}

	# -- index : main page
	my $template = new Template({
		INCLUDE_PATH => '%VHFFS_BOTS_DIR%/misc/',
	});

	my $monthly_data = [];
	my $vars = {
		list => $ml,
		monthly_data => $monthly_data
	};

	opendir( my $listdir, $archivedir ) or return undef;
	my @years = readdir( $listdir );
	closedir( $listdir );
	foreach my $year ( reverse sort @years ) {
		next if $year =~ /^\..*$/;

		my $archivesyeardir = $archivedir.'/'.$year;
		opendir( my $yeardir, $archivesyeardir );
		unless( defined $yeardir ) {
			Vhffs::Robots::vhffs_log( $vhffs, 'Unable to open '.$archivesyeardir.' directory: '.$! );
			return undef;;
		}

		my $publicyeardir = $publicdir.'/'.$year;
		mkdir($publicyeardir, 0755);
		unless( -d $publicyeardir ) {
			Vhffs::Robots::vhffs_log( $vhffs, 'Unable to create '.$publicyeardir.' directory: '.$! );
			return undef;
		}

		my @months = readdir( $yeardir );
		closedir( $yeardir );
		foreach my $month ( reverse sort @months ) {
			next if $month =~ /^\..*$/;

			my $archivesmonthdir = $archivesyeardir.'/'.$month;
			opendir( my $monthdir, $archivesmonthdir );
			unless( defined $monthdir ) {
				Vhffs::Robots::vhffs_log( $vhffs, 'Unable to open '.$monthdir.' directory: '.$! );
				return undef;
			}

			my $publicmonthdir = $publicyeardir.'/'.$month;
			mkdir($publicmonthdir, 0755);
			unless( -d $publicmonthdir ) {
				Vhffs::Robots::vhffs_log( $vhffs, 'Unable to create '.$publicmonthdir.' directory: '.$! );
				return undef;
			}

			# -- index : part
			my $month = {
				year => $year,
				month => $month
			};

			my $mailnb = 0;
			my $mailsize = 0;
			my @glob;

			my @days = readdir ( $monthdir);
			closedir( $monthdir );
			foreach my $day ( @days ) {
				next if $day =~ /^\..*$/;

				my $daypath = $archivesmonthdir.'/'.$day;

				opendir( my $daydir, $daypath );
				unless( defined $daydir ) {
					Vhffs::Robots::vhffs_log( $vhffs, 'Unable to open '.$daydir.' directory: '.$! );
					return undef;
				}

				my @mails = readdir ( $daydir );
				closedir( $daydir );
				foreach my $mail ( @mails ) {
					next if $mail =~ /^\..*$/;

					my $mailpath = $daypath.'/'.$mail;

					push @glob, $mailpath;
					if( @glob >= 100 ) {
						my $childpid = open( my $output, '-|', 'mhonarc', '-add', '-quiet', '-rc', $mhonarcconfig, '-definevar', 'MAIN-TITLE='.$ml->get_domain.'/'.$ml->get_localpart, '-outdir', $publicmonthdir, @glob );
						if($childpid) {
						# read process output and print
						while(<$output>) { print $_; }

							# wait for the child to finish
							waitpid( $childpid, 0 );
						}

						@glob = ();
					}
					$mailnb++;

					my (undef,undef,undef,undef,undef,undef,undef,$size,undef,undef,undef,undef,undef) = stat( $mailpath );
					$mailsize += $size;
				}
			}

			# Handle remaining mails
			if( @glob ) {
				my $childpid = open( my $output, '-|', 'mhonarc', '-add', '-quiet', '-rc', $mhonarcconfig, '-definevar', 'MAIN-TITLE='.$ml->get_domain.'/'.$ml->get_localpart, '-outdir', $publicmonthdir, @glob );
				if($childpid) {
				# read process output and print
				while(<$output>) { print $_; }

					# wait for the child to finish
					waitpid( $childpid, 0 );
				}
			}

			my $totalsize = sprintf('%d', $mailsize/1000 );
			$month->{number} = $mailnb;
			$month->{size} = $totalsize.'kB';

			push @$monthly_data, $month;
		}
	}

	$template->process( 'mhonarc.indexmain.tt', $vars, $publicdir.'/index.html' );
	return 1;
}

1;
