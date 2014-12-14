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

package Vhffs::Panel::Auth;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;

use Vhffs::Constants;

sub display_login {
	my $panel = shift;
	my $vhffs = $panel->{'vhffs'};

	my $hostname = $vhffs->get_config->get_host_name;
	my $website = $vhffs->get_config->get_host_website;
	my $cgi = $panel->{cgi};
	my $vars = {};
	$vars->{username} = scalar $cgi->param('username');
	$vars->{subscription_allowed} = $vhffs->get_config->get_allow_subscribe;
	$vars->{website} = $website;
	$vars->{hostname} = $hostname;
	if( $panel->get_config->{'stats_on_home'} ) {
		my $stats = $vhffs->get_stats;
		$vars->{stats} = {
			users => $stats->get_user_total,
			groups => $stats->get_groups_activated
		};
	}

	$panel->render( 'anonymous/login.tt', $vars, 'anonymous.tt' );
}

sub login {
	my $panel = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};

	unless( defined $cgi->param('login_submit') ) {
		return display_login( $panel );
	}

	# User tried to log in, we try to clean the previous session
	my $oldsid = $cgi->cookie( CGI::Session::name() );
	if( defined $oldsid ) {
		my $oldsession = new CGI::Session('driver:File', $oldsid, { Directory => '/tmp' });
		if( defined $oldsession ) {
			$oldsession->delete();
			$oldsession->flush(); # Recommended practice says use flush() after delete().
		}
	}

	my $user = Vhffs::User::get_by_username($vhffs, scalar $cgi->param('username') );
	my $password = $cgi->param('password');

	# Incomplete input
	unless( defined $user and defined $password and $user->check_password( $password ) ) {
		$panel->add_error( gettext('Login failed !') );
		return display_login( $panel );
	}

	unless( $user->get_status == Vhffs::Constants::ACTIVATED ) {
		$panel->add_error( gettext('User is not active yet') );
		return display_login( $panel );
	}

	# Creates the new session
	my $session = new CGI::Session('driver:File', undef, { Directory => '/tmp' });
	unless( defined $session ) {
		$panel->add_error( gettext('Cannot create session file, please check that /tmp is readable and writeable') );
		return display_login( $panel );
	}
	$session->expires('+1h');
	$session->param('uid', $user->get_uid);
	$session->flush();

	$panel->add_cookie( $cgi->cookie( -name=>$session->name, -value=>$session->id ) );

	# Refresh cookies (avoid theme and language loss when user deletes cookies).
	$panel->add_cookie( $cgi->cookie( -name=>'theme', -value=>$user->get_theme, -expires=>'+10y' ) );
	$panel->add_cookie( $cgi->cookie( -name=>'language', -value=>$user->get_lang, -expires=>'+10y' ) );

	# Set last login panel to current time
	$user->update_lastloginpanel;
	$user->commit;

	$panel->redirect('?do=groupindex');
	return;
}

sub logout {
	my $panel = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};

	# clean session
	my $oldsid = $cgi->cookie( CGI::Session::name() );
	if( defined $oldsid )  {
		my $oldsession = new CGI::Session('driver:File', $oldsid, { Directory => '/tmp' });
		if( defined $oldsession ) {
			$oldsession->delete();
			$oldsession->flush(); # Recommended practice says use flush() after delete().
		}
	}

	$panel->add_info( gettext('You left your VHFFS session!') );
	return display_login( $panel );
}

sub lost {
	my $panel = shift;
	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};

	unless( defined $cgi->param('lost_submit') ) {
		$panel->render('anonymous/lost-password.tt', undef, 'anonymous.tt');
		return;
	}

	# username submitted
	my $user = Vhffs::User::get_by_username( $vhffs, scalar $cgi->param('username') );
	if( defined $user and $user->{'state'} == Vhffs::Constants::ACTIVATED )  {

		# create a new password for this user
		my $password = Vhffs::Functions::generate_random_password();
		$user->set_password( $password );
		$user->commit;

		my $mu = new Vhffs::Services::MailUser( $vhffs, $user );
		if( defined $mu and defined $mu->get_localpart ) {
			$mu->get_localpart->set_password( $password );
			$mu->get_localpart->commit;
		}

		# Send a mail with plain text password inside
		my $subject = sprintf('Password changed on %s', $vhffs->get_config->get_host_name );
		my $content = sprintf("Hello %s %s,\n\nYou asked for a new password, here are your new login information:\nUser: %s\nPassword: %s\n\n%s Administrators\n", $user->get_firstname, $user->get_lastname, $user->get_username, $password , $vhffs->get_config->get_host_name );
		$user->send_mail_user( $subject, $content );

		$panel->render('anonymous/lost-password-ack.tt',
		  { message => sprintf( gettext('Please wait %s, a new password will be sent to you in a few minutes...'), $user->get_username ) },
		  'anonymous.tt' );
	}
	else {
		$panel->render('anonymous/lost-password-ack.tt',
		  { message => gettext('Password recovery failed!') },
		  'anonymous.tt' );
	}
}

1;
