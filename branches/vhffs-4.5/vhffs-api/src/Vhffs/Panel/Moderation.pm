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

package Vhffs::Panel::Moderation;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Encode;

use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::ObjectFactory;

sub moderation {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $accept = $cgi->param('accept');
	my $refuse = $cgi->param('refuse');

	if(defined $accept or defined $refuse) {
		# Submitted
		my $oid = $cgi->param('oid');
		my $message = Encode::decode_utf8( scalar $cgi->param('message') );

		unless(defined $oid and defined $message) {
			$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
			return;
		}

		my $object = Vhffs::ObjectFactory::fetch_object( $vhffs , $oid );
		unless(defined $object) {
			$panel->render('misc/message.tt', { message => gettext( 'Object not found' ) } );
			return;
		}

		if( defined $refuse and $message !~ /\S/) {
			$panel->add_error( gettext('You have to enter a refuse reason') );
		} else {
			if(defined $refuse) {
				if($object->moderate_refuse( $message ) >= 0) {
					$panel->add_info( gettext('Object refused') );
				} else {
					$panel->add_error( gettext('Error while updating object') );
				}
			} else {
				if($object->moderate_accept( $message ) >= 0) {
					$panel->add_info( gettext('Object accepted') );
				} else {
					$panel->add_error( gettext('Error while updating object') );
				}
			}
		}
	}

	$panel->set_title( gettext('Moderation') );

	# TODO This is pure crap but I'm currently working
	# on Template::Toolkit and sweared no to touch anything
	# else...
	my $objects = Vhffs::Object::getall( $vhffs, undef, Vhffs::Constants::WAITING_FOR_VALIDATION );
	my $vars = {
		objects => [],
		use_notation => $vhffs->get_config->get_users->{'use_notation'}
	};
	foreach my $o(@$objects) {
		push @{$vars->{objects}}, Vhffs::ObjectFactory::fetch_object( $vhffs, $o->{object_id});
	}
	$panel->render('admin/moderation/index.tt', $vars);
}

1;
