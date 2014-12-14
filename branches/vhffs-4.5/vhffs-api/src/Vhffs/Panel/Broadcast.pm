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
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name of vhffs nor the names of its contributors
#    may be used to endorse or promote products derived from this
#    software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

use strict;
use utf8;

package Vhffs::Panel::Broadcast;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Encode;

use Vhffs::Broadcast;

sub broadcast_list {
	my ($vhffs) = @_;

	my $sql = 'SELECT mailing_id as id, subject, message as body, date, state '.
	  'FROM vhffs_mailings m '.
	  'ORDER BY m.date DESC';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} });
}

sub create {
	my $panel = shift;
	return unless $panel->check_admin();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $subject = Encode::decode_utf8( scalar $cgi->param('subject') );
	my $body = Encode::decode_utf8( scalar $cgi->param('body') );
	my $vars = {};

	if(defined $subject and defined $body) {
		$panel->add_error( gettext('You have to enter a subject') ) unless $subject =~ /\S/;
		$panel->add_error( gettext('You have to enter a message body') ) unless $body =~ /\S/;

		unless( $panel->has_errors ) {
			if( Vhffs::Broadcast::create( $vhffs, $subject, $body ) ) {
				$panel->render('misc/message.tt',  {
				  message => gettext('Mailing successfully added'),
				  refresh_url => '?do=broadcastlist'
				  });
				return;
			}

			$panel->add_error( gettext('Error while queuing mailing') );
		}

		$vars->{subject} = $subject;
		$vars->{body} = $body;
	}

	$panel->render('admin/broadcast/create.tt', $vars);
}

sub list {
	my $panel = shift;
	return unless $panel->check_admin();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $vars = {};

	my $mailings = broadcast_list( $vhffs );
	foreach my $m(@$mailings) {
		if($m->{state} == Vhffs::Constants::BROADCAST_WAITING_TO_BE_SENT) {
			$m->{state} = gettext('Awaiting sending');
		} elsif($m->{state} == Vhffs::Constants::BROADCAST_SENT) {
			$m->{state} = gettext('Sent');
		} else {
			$m->{state} = gettext('Unknown');
		}
	}

	$vars->{mailings} = $mailings;
	$panel->render('admin/broadcast/list.tt', $vars);
}

sub view {
	my $panel = shift;
	return unless $panel->check_admin();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $mid = $cgi->param('mid');
	unless( defined $mid ) {
		$panel->render('misc/message.tt', {
		  message => gettext('CGI Error'),
		  refresh_url => '?do=broadcastlist'
		  });
		return;
	}
	my $mailing = Vhffs::Broadcast::get_by_mailing_id( $vhffs, $mid );
	unless( defined $mailing) {
		$panel->render('misc/message.tt', {
		  message => gettext('Mailing not found'),
		  refresh_url => '?do=broadcastlist'
		  });
		return;
	}

	if($mailing->{state} == Vhffs::Constants::BROADCAST_WAITING_TO_BE_SENT) {
		$mailing->{state} = gettext('Awaiting sending');
	} elsif($mailing->{state} == Vhffs::Constants::BROADCAST_SENT) {
		$mailing->{state} = gettext('Sent');
	} else {
		$mailing->{state} = gettext('Unknown');
	}

	$panel->render('admin/broadcast/view.tt', {
	  mailing => $mailing
	  });
}

sub delete {
	my $panel = shift;
	return unless $panel->check_admin();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $mid = $cgi->param('mid');
	unless( defined $mid ) {
		$panel->render('misc/message.tt', {
		  message => gettext('CGI Error'),
		  refresh_url => '?do=broadcastlist'
		  });
		return;
	}
	my $mailing = Vhffs::Broadcast::get_by_mailing_id( $vhffs, $mid );
	unless( defined $mailing) {
		$panel->render('misc/message.tt', {
		  message => gettext('Mailing not found'),
		  refresh_url => '?do=broadcastlist'
		  });
		return;
	}

	unless( $mailing->delete ) {
		$panel->render('misc/message.tt', {
		  message => gettext('An error occured while deleting this mailing')
		  });
		return;
	}

	$panel->render('misc/message.tt', {
	  message => gettext('Mailing successfully deleted'),
	  refresh_url => '?do=broadcastlist'
	  });
}

1;
