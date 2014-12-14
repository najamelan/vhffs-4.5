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

use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::Robots;
use Vhffs::Services::Mail;

package Vhffs::Robots::Mail;

sub getall_boxes {
	my ( $vhffs, $state ) = @_;
	my @params;

	my $sql = 'SELECT mx.domain, lp.localpart FROM vhffs_mx_box mb INNER JOIN vhffs_mx_localpart lp ON lp.localpart_id=mb.localpart_id INNER JOIN vhffs_mx mx ON mx.mx_id=lp.mx_id';
	if( defined $state)   {
		$sql .= ' WHERE mb.state=?';
		push(@params, $state);
	}

	my $boxes = [];
	my $request = $vhffs->get_db->prepare( $sql );
	return unless $request->execute( @params );
	while( my $s = $request->fetchrow_hashref() ) {
		my $mail = Vhffs::Services::Mail::get_by_mxdomain( $vhffs, $s->{domain} );
		next unless defined $mail;
		my $lp = $mail->fetch_localpart( $s->{localpart} );
		next unless defined $lp and defined $lp->get_box;
		push( @$boxes, $lp->get_box );
	}

	return $boxes;
}

sub create {
	my $mail = shift;
	return undef unless defined $mail and $mail->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $mail->get_vhffs;

	$mail->set_status( Vhffs::Constants::ACTIVATED );
	$mail->commit;
	Vhffs::Robots::vhffs_log( $vhffs, 'Created mail domain '.$mail->get_domain );

	$mail->send_created_mail;
	return 1;
}

sub delete {
	my $mail = shift;
	return undef unless defined $mail and $mail->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $mail->get_vhffs;
	my $dir = $mail->get_dir;

	my $localparts = $mail->fetch_localparts;
	foreach my $localpart ( values %{$localparts} ) {
		my $box = $localpart->get_box;
		if( defined $box ) {
			$box->set_status( Vhffs::Constants::WAITING_FOR_DELETION );  # We don't have to commit
			return 1 unless delete_mailbox( $box );
		}
		my $ml = $localpart->get_ml;
		if( defined $ml ) {
			require Vhffs::Robots::MailingList;
			my $fml = $ml->get_ml_object;
			$fml->set_status( Vhffs::Constants::WAITING_FOR_DELETION );  # We don't have to commit
			return 1 unless Vhffs::Robots::MailingList::delete( $fml );
		}
	}

	File::Path::remove_tree( $dir, { error => \my $errors });
	# Mail domain directories are hashed on two levels, so we've potentially two empty directories to delete
	my $parent = File::Basename::dirname($dir);
	rmdir $parent;
	$parent = File::Basename::dirname($parent);
	rmdir $parent;

	if(@$errors) {
		$mail->set_status( Vhffs::Constants::DELETION_ERROR );
		$mail->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while removing mail domain '.$mail->get_domain.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	if( $mail->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted mail domain '.$mail->get_domain );
	} else {
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting mail domain '.$mail->get_domain );
		$mail->set_status( Vhffs::Constants::DELETION_ERROR );
		$mail->commit;
		return undef;
	}

	return 1;
}

sub modify {
	my $mail = shift;
	return undef unless defined $mail and $mail->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;
	$mail->set_status( Vhffs::Constants::ACTIVATED );
	$mail->commit;
	return 1;
}

sub create_mailbox {
	my $box = shift;
	return undef unless defined $box and $box->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $mail = $box->get_mail;
	my $vhffs = $mail->get_vhffs;
	my $mailconf = $mail->get_config;
	my $dir = $box->get_dir;

	my $prevumask = umask 0;
	File::Path::make_path( $dir, { mode => 0755, error => \my $errors } );
	File::Path::make_path( $dir.'/Maildir/cur', $dir.'/Maildir/new', $dir.'/Maildir/tmp', { mode => 0700, error => \$errors }) unless @$errors;
	umask $prevumask;

	if( @$errors ) {
		$box->set_status( Vhffs::Constants::CREATION_ERROR );
		$box->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while creating mail box '.$box->get_localpart->get_localpart.'@'.$mail->get_domain.' to the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	# make_path owner and group directives do not seem to work if owner and group and numeric
	Vhffs::Robots::chown_recur( $dir, $mailconf->{'boxes_uid'}, $mailconf->{'boxes_gid'} );
	chmod 0700, $dir;

	Vhffs::Robots::vhffs_log( $vhffs, 'Created mail box '.$box->get_localpart->get_localpart.'@'.$mail->get_domain );
	$box->set_status( Vhffs::Constants::ACTIVATED );
	$box->commit;
	return 1;
}

sub delete_mailbox {
	my $box = shift;
	return undef unless defined $box and $box->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $mail = $box->get_mail;
	my $vhffs = $mail->get_vhffs;
	my $mailconf = $mail->get_config;
	my $dir = $box->get_dir;

	Vhffs::Robots::archive_targz( $mail, $dir, [ $box->get_localpart->get_localpart ] );

	File::Path::remove_tree( $dir, { error => \my $errors } );
	# Remove the letter/ directory if empty
	rmdir File::Basename::dirname($dir);

	if( @$errors ) {
		$box->set_status( Vhffs::Constants::DELETION_ERROR );
		$box->commit;
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting mail box '.$box->get_localpart->get_localpart.'@'.$mail->get_domain.' from the filesystem: '.join(', ', @$errors) );
		return undef;
	}

	Vhffs::Robots::vhffs_log( $vhffs, 'Deleted mail box '.$box->get_localpart->get_localpart.'@'.$mail->get_domain );
	return $box->delete;
}

1;
