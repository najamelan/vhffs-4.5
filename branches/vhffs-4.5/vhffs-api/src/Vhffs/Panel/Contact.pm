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

package Vhffs::Panel::Contact;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Encode;
use Vhffs::Functions;

sub contact {

	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	unless( defined $cgi->param('contact_submit') ) {
		$panel->render('misc/alert.tt');
		return;
	}

	my $vars = {};

	if( defined  $cgi->param('subject') and defined $cgi->param('message') ) {
		my $to = $vhffs->get_config->get_alert_mail;
		my $from = $user->get_mail;
		my $subject = Encode::decode_utf8( scalar $cgi->param('subject') );
		my $message = gettext('Message sent by the following account').': '.$user->get_username."\n\n".Encode::decode_utf8( scalar $cgi->param('message') );

		Vhffs::Functions::send_mail( $vhffs , $from , $to , undef , $subject , $message );
		$vars->{message} = gettext('Message sent successfully');
	}
	else  {
		$vars->{message} = gettext('Cannot send message, CGI error...');
	}

	$panel->render('misc/message.tt', $vars);
}

1;
