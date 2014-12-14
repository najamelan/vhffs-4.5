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

package Vhffs::Panel::Acl;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Encode;

use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::Object;
use Vhffs::User;

sub acl {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $oid = $cgi->param('oid');
	unless( defined $oid ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		return;
	}

	# Object does not exist
	my $object = Vhffs::Object::get_by_oid($vhffs, $oid);
	unless( defined $object ) {
		$panel->render('misc/message.tt', { message => sprintf( gettext('Cannot get informations on object #%d'), $oid) } );
		return;
	}
	$panel->set_group( $object->get_group );

	# Object exists, we need to know if access is granted to the user
	unless( $user->can_view( $object ) ) {
		$panel->render('misc/message.tt', { message => gettext('You\'re not allowed to view this object\'s ACL') } );
		return;
	}

	# access OK, let's see if some action was requested
	if(defined $cgi->param('update_acl_submit')) {
		my $granted_oid = $cgi->param('granted_oid');
		my $perm = $cgi->param('perm'.$granted_oid);
		my $granted;
		unless( defined $granted_oid and defined $perm ) {
			$panel->add_error( gettext('CGI Error !') );
		} elsif( not defined( $granted = Vhffs::Object::get_by_oid( $vhffs, $granted_oid ) ) ) {
			$panel->add_error( gettext('Group or user not found') );
		} elsif( not $user->can_manageacl( $object ) ) {
			$panel->add_error( gettext('You\'re not allowed to manage this object\'s ACL') );
		} else {
			my $ret = $object->add_update_or_del_acl( $granted, $perm );
			unless( defined $ret ) {
				$panel->add_error( gettext('Sorry, can\'t add or update ACL') );
			} else {
				$panel->add_info( gettext('ACL added') ) if $ret == 1;
				$panel->add_info( gettext('ACL updated') ) if $ret == 2;
				$panel->add_info( gettext('ACL deleted') ) if $ret == 3;
			}
		}
	}

	$panel->set_title( gettext('ACL Administration') );
	my $vars = { target => $object };
	my ( $default_acl, $owner_acl, $users_acls ) = $object->get_acl;
	$vars->{default_acl} = $default_acl;
	$vars->{owner_acl} = $owner_acl;
	$vars->{users_acl} = $users_acls;

	$panel->render('acl/view.tt', $vars);
}

1;
