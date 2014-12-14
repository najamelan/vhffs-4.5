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

package Vhffs::Panel::Subscribe;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Encode;
use Captcha::reCAPTCHA;

use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::User;


sub subscribe {

	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};

	my $submitted = $cgi->param( 'create_submit' );
	my $message;

	my $usecaptcha = $panel->get_config->{'use_captcha'};
	my $captcha_pubkey = $panel->get_config->{'captcha_pubkey'};
	my $captcha_privkey = $panel->get_config->{'captcha_privkey'};

	unless( $vhffs->get_config->get_allow_subscribe )  {
		# Subscribe isn't allowed, inform user
		$panel->render('misc/message.tt', { message => gettext('You cannot subscribe to VHFFS') }, 'anonymous.tt');
		return;
	}

	my $vars = {};

	if( defined $submitted ) {

		# get filled in parameters
		my $mail       = $cgi->param('mail');
		my $username   = $cgi->param('username');
		my $firstname  = Encode::decode_utf8( scalar $cgi->param('firstname') );
		my $lastname   = Encode::decode_utf8( scalar $cgi->param('lastname') );
		my $city       = Encode::decode_utf8( scalar $cgi->param('city') );
		my $zipcode    = Encode::decode_utf8( scalar $cgi->param('zipcode') );
		my $country    = Encode::decode_utf8( scalar $cgi->param('country') );
		my $address    = Encode::decode_utf8( scalar $cgi->param('address') );
		my $newslettercheckbox = $cgi->param('newsletter');
		$newslettercheckbox = ( defined $newslettercheckbox and $newslettercheckbox eq 'on' );

		if( $usecaptcha ) {
			my $captcha = new Captcha::reCAPTCHA();
			my $challenge = $cgi->param('recaptcha_challenge_field');
			my $response = $cgi->param('recaptcha_response_field');
			my $result = $captcha->check_answer( $captcha_privkey, $cgi->remote_addr, $challenge, $response);
			$panel->add_error( gettext('Codes do not match')) unless $result->{is_valid};
		}

		$panel->add_error( gettext('You must declare your username') ) unless defined $username;
		$panel->add_error( gettext('Invalid username, it must contain between 3 and 12 alphanumeric characters, all in lowercase') ) unless Vhffs::User::check_username($username);
		$panel->add_error( gettext('You must declare your country') ) unless defined $country;
		$panel->add_error( gettext('You must declare your city') ) unless defined $city;
		$panel->add_error( gettext('You must declare your zipcode') ) unless defined $zipcode;
		$panel->add_error( gettext('You must declare your firstname') ) unless defined $firstname;
		$panel->add_error( gettext('You must declare your lastname') ) unless defined $lastname;
		$panel->add_error( gettext('You must declare your mail address') ) unless defined $mail and length( $mail ) >= 6;
		$panel->add_error( gettext('You must declare a valid mail address') ) unless Vhffs::Functions::valid_mail( $mail );
		$panel->add_error( gettext('Your zipcode is not correct! Please enter a correct zipcode')) unless defined $zipcode and $zipcode =~ /^[\w\d\s\-]+$/;
		$panel->add_error( gettext('Please enter a correct firstname') ) unless defined $firstname and $firstname =~ /^[^<>"]+$/;
		$panel->add_error( gettext('Please enter a correct lastname') ) unless defined $lastname and $lastname =~ /^[^<>"]+$/;
		$panel->add_error( gettext('Please enter a correct city') ) unless defined $city and $city =~ /^[^<>"]+$/;
		$panel->add_error( gettext('Please enter a correct country') ) unless defined $country and $country !~ /^[<>"]+$/;

		unless( $panel->has_errors ) {
			my $user = Vhffs::User::create( $vhffs, $username, undef, 0,
			  $mail, $firstname, $lastname, $city, $zipcode, $country, $address, undef, $panel->get_lang);

			unless( defined $user )  {
				$panel->add_error( gettext('Cannot create user, the username you entered already exists') );
			}
			else {
				#We set informations user fill in the form
				$user->set_status( Vhffs::Constants::WAITING_FOR_CREATION );

				#Commit all the changes for the current user
				if( $user->commit < 0 ) {
					$panel->add_error( gettext('Cannot apply changes to the user') );
				}
				else {

					# Newsletter
					if( $vhffs->get_config->get_service_availability('newsletter') ) {
						require Vhffs::Services::Newsletter;
						my $newsletter = new Vhffs::Services::Newsletter( $vhffs , $user );
						if( defined $newsletter and (
						  ( $newsletter->get_collectmode == Vhffs::Services::Newsletter::ACTIVE_OPTIN && $newslettercheckbox )
						  or ( $newsletter->get_collectmode == Vhffs::Services::Newsletter::PASSIVE_OPTIN && $newslettercheckbox )
						  or ( $newsletter->get_collectmode == Vhffs::Services::Newsletter::ACTIVE_OPTOUT && !$newslettercheckbox )
						  or ( $newsletter->get_collectmode == Vhffs::Services::Newsletter::PASSIVE_OPTOUT )
						  or ( $newsletter->get_collectmode == Vhffs::Services::Newsletter::PERMANENT )
						) ) {
							$newsletter->add;
						}
					}
					$panel->render('anonymous/account_created.tt', $vars, 'anonymous.tt');
					return;
				}
			}
		}

		if ( $panel->has_errors ) {
			$vars->{username} = $username;
			$vars->{mail} = $mail;
			$vars->{firstname} = $firstname;
			$vars->{lastname} = $lastname;
			$vars->{zipcode} = $zipcode;
			$vars->{city} = $city;
			$vars->{country} = $country;
			$vars->{address} = $address;
			$vars->{newsletter_checked} = $newslettercheckbox;
		}
	}

	if( not defined $submitted or $panel->has_errors )  {
	        $vars->{captcha_pubkey} = $captcha_pubkey if $usecaptcha;

		if( $vhffs->get_config->get_service_availability('newsletter') ) {
			my $conf = $vhffs->get_config->get_service('newsletter');
			$vars->{newsletter} = { prompt => ($conf->{'collectmode'} eq 'active_optout' ? gettext('Don\'t subscribe to the newsletter') : gettext('Subscribe to the newsletter') ) } if $conf->{'collectmode'} ne 'passive_optout' and $conf->{'collectmode'} ne 'permanent';
			$vars->{newsletter_checked} = 1 if $conf->{'collectmode'} eq 'passive_optin' and not defined $submitted;
		}

		$panel->render('anonymous/subscribe.tt', $vars, 'anonymous.tt');
	}
}

1;
