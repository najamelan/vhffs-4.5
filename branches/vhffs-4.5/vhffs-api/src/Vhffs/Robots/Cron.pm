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
use Vhffs::Services::Cron;

package Vhffs::Robots::Cron;

sub get_runnable_jobs {
	my $vhffs = shift;

	my $sql = 'SELECT c.cron_id, c.cronpath, c.interval, c.reportmail, c.lastrundate, c.lastrunreturncode, c.nextrundate, c.running, o.owner_uid, o.owner_gid, o.object_id, o.date_creation, o.description, o.state FROM vhffs_cron c INNER JOIN vhffs_object o ON c.object_id=o.object_id WHERE o.state=? AND c.running=0 AND ( c.nextrundate IS NULL OR c.nextrundate<? )';
	my $dbh = $vhffs->get_db();
	my $sth = $dbh->prepare($sql);
	$sth->execute( Vhffs::Constants::ACTIVATED , time() ) or return undef;

	my $repos = [];
	while(my $r = $sth->fetchrow_arrayref()) {
		push(@$repos, _new Vhffs::Services::Cron($vhffs, @$r));
	}
	return $repos;
}

sub get_stalled_jobs {
	my $vhffs = shift;
	my $maxexectime = shift;

	my $sql = 'SELECT c.cron_id, c.cronpath, c.interval, c.reportmail, c.lastrundate, c.lastrunreturncode, c.nextrundate, c.running, o.owner_uid, o.owner_gid, o.object_id, o.date_creation, o.description, o.state FROM vhffs_cron c INNER JOIN vhffs_object o ON c.object_id=o.object_id WHERE o.state=? AND c.running!=0 AND ( c.nextrundate IS NULL OR c.nextrundate<? )';
	my $dbh = $vhffs->get_db();
	my $sth = $dbh->prepare($sql);
	$sth->execute( Vhffs::Constants::ACTIVATED , time() - $maxexectime ) or return undef;

	my $repos = [];
	while(my $r = $sth->fetchrow_arrayref()) {
		push(@$repos, _new Vhffs::Services::Cron($vhffs, @$r));
	}
	return $repos;
}

sub create {
	my $cron = shift;
	return undef unless defined $cron and $cron->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $cron->get_vhffs;

	$cron->set_status( Vhffs::Constants::ACTIVATED );
	$cron->commit;
	Vhffs::Robots::vhffs_log( $vhffs, 'Created cron job '.$cron->get_cronpath );

	$cron->send_created_mail;
	return 1;
}

sub delete {
	my $cron = shift;
	return undef unless defined $cron and $cron->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $cron->get_vhffs;

	if( $cron->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted cron job '.$cron->get_cronpath );
	} else {
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting cron job '.$cron->get_cronpath );
		$cron->set_status( Vhffs::Constants::DELETION_ERROR );
		$cron->commit;
		return undef;
	}

	return 1;
}

sub modify {
	my $cron = shift;
	return undef unless defined $cron and $cron->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;
	$cron->set_status( Vhffs::Constants::ACTIVATED );
	$cron->commit;
	return 1;
}

1;
