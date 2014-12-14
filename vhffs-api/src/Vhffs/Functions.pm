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

=pod

=head1 NAME

Vhffs::Functions - Utility functions for VHFFS.

=head1 METHODS

=cut

package Vhffs::Functions;
require Exporter;
@ISA    = qw(Exporter);
@EXPORT = qw( send_mail );

use strict;
use utf8;
use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Vhffs::Constants;

srand(time ^ $$);

=head2 send_mail

my $ret = Vhffs::Functions::send_mail( $vhffs, $from, $to, $mailtag, $subject, $message, $precedence );

Send an email.

=cut
sub send_mail {
	use MIME::Lite;
	use MIME::Base64;
	use Encode;
	use Crypt::GPG;

	my $vhffs = shift;
	my $from = shift;
	my $to = shift;
	my $mailtag = shift;
	my $subject = shift;
	my $message = shift;
	my $precedence = shift;

	chomp $message;
	$message .= "\n";

	my ( $gpgbin, $gpgconf );
	if( defined $vhffs->get_config->get_gpg && defined $vhffs->get_config->get_gpg->{'gpg_bin'} ) {
		$gpgbin = $vhffs->get_config->get_gpg->{'gpg_bin'};
		my ( $cleanfrom ) = ( $from =~ /<(.+)>/ );
		$gpgconf = $vhffs->get_config->get_gpg->{ $cleanfrom || $from };
	}

	$subject = $mailtag.' '.$subject if defined $mailtag;
	$subject = Encode::encode_utf8( $subject );
	$subject = '=?UTF-8?B?'.MIME::Base64::encode_base64( $subject , '' ).'?=';
	$message = Encode::encode_utf8( $message );

	if( defined $gpgconf ) {

		my $msg = new MIME::Lite(
			From        => $from,
			To          => $to,
			Subject     => $subject,
			Type        => 'multipart/signed; micalg=pgp-sha1; protocol="application/pgp-signature"',
			Disposition => 'inline'
			);
		$msg->add('Precedence' => $precedence) if defined $precedence;

		my $data = $msg->attach(
			Type => 'text/plain; charset=utf-8',
			Encoding => '8bit',
			Disposition => 'inline',
			Data => $message
			);

		$ENV{'GNUPGHOME'} = $gpgconf->{'gnupghome'};
		my $gpg = new Crypt::GPG;
		$gpg->gpgbin( $gpgbin );
		$gpg->secretkey( $gpgconf->{'secretkey'} );
		$gpg->passphrase( $gpgconf->{'passphrase'} );
		my $sign;
		eval{ $sign = $gpg->sign( $data->as_string ); };
		if( defined $sign ) {
			my $signature = $msg->attach(
				Type => 'application/pgp-signature; name="signature.asc"',
				Encoding => '7bit',
				Disposition => 'inline',
				Data => $sign
				);
			$signature->attr( 'content-description' => 'Digital signature' );

			$msg->send;
		} else {
			undef $gpgconf;
		}
		delete $ENV{'GNUPGHOME'};
	}

	unless( defined $gpgconf ) {

		my $msg = new MIME::Lite(
			From    => $from,
			To      => $to,
			Subject => $subject,
			Type    => 'text/plain; charset=utf-8',
			Encoding => '8bit',
			Data    => $message
			);
		$msg->add('Precedence' => $precedence) if defined $precedence;

		$msg->send;
	}

	return 1;
}

=head2 obfuscate_email

my $obfuscated = Vhffs::Functions::obfuscate_email( $mail );

Returns an obfuscated mail.

=cut
sub obfuscate_email($$) {
	my ($vhffs, $mail) = @_;

	my $tech = $vhffs->get_config->get_panel->{'mail_obfuscation'};

	return $mail if $tech eq 'none';

	if($tech eq 'simple') {
		$mail =~ s/@/ AT REMOVEME /g;
		$mail =~ s/\./ DOT /g;
		return $mail;
	}

	if($tech eq 'entities') {
		my @chars = split //, $mail;
		$mail = '';
		foreach(@chars) {
			if($_ eq '@') {
				$mail .= '&#64;';
			} else {
				my $ord = ord($_);
				if( ($ord >= ord('a') && $ord <= ord('z') )
				  || ($ord >= ord('A') && $ord <= ord('Z') ) ) {
					$mail .= "&#$ord;";
				} else {
					$mail .= $_;
				}
			}
		}
		return $mail;
	}

	if($tech eq 'javascript') {
		return js_encode_mail($mail);
	}

	if($tech eq 'swap')  {
		my @both = split /@/, $mail;
		return $both[1].'/'.$both[0];
	}

	return 'Unsupported email obfuscation method !'."\n";
}

=head2 js_encode_mail

my $encoded = Vhffs::Functions::js_encode_mail( $mail );

This function does the opposite of the JS function decode_mail.

=cut
sub js_encode_mail($) {
	my $clear = shift;
	my $crypted = '';
	my @chars = split //, $clear;
	foreach(@chars) {
		my $c = chr(ord($_) + 1);
		if($c eq "'") {
			$crypted .= '\\\'';
		} else {
			$crypted .= $c;
		}
	}

	return '<script type="text/javascript">document.write(decode_mail(\''.$crypted.'\'));</script>';
}

=pod

=head2 generate_random_password

my $pass = Vhffs::Functions::generate_random_password();

Returns a randomized plain text password.

=cut
sub generate_random_password {
	my $password;
	for (0 .. 7) { $password .= ('a'..'z', 'A'..'Z', '0'..'9')[int rand 62]; }
	return $password;
}

=pod

=head2 valid_mail

die "mail is invalid" unless Vhffs::Functions::valid_mail( $mail );

Checks for mail validity.

=cut
sub valid_mail {
	my $mail = shift;

	my ( $localpart, $domain ) = ( $mail =~ /(.+)\@(.+)/ );
	return 0 unless Vhffs::Functions::check_domain_name( $domain );

	use Email::Valid;
	return 1 if Email::Valid->rfc822( $mail );
	return 0;
}

=pod

=head2 status_string_from_status_id

	my $statusstr = Vhffs::Functions::status_string_from_status_id( $id );

Returns status string from status id.

=cut
sub status_string_from_status_id($) {
	my $status = shift;
	return gettext( Vhffs::Constants::STATUS_STRINGS->{$status} or 'Unknown' );
}

=pod

=head2 type_string_from_type_id

	my $typestr = Vhffs::Functions::type_string_from_type_id( $id );

Returns type string from type id.

=cut
sub type_string_from_type_id($) {
	my $type = shift;
	return gettext( Vhffs::Constants::TYPES->{$type}->{'name'} or 'Unknown' );
}

=pod

=head2 type_string_fs_from_type_id

	my $typestrfs = Vhffs::Functions::type_string_fs_from_type_id( $id );

Returns type string for filesystem from type id.

=cut
sub type_string_fs_from_type_id($) {
	my $type = shift;
	return ( Vhffs::Constants::TYPES->{$type}->{'fs'} or 'unknown' );
}

=pod

=head2 type_class_from_type_id

	my $class = Vhffs::Functions::type_class_from_type_id( $id );

Returns class from type id.

=cut
sub type_class_from_type_id($) {
	my $type = shift;
	return ( Vhffs::Constants::TYPES->{$type}->{'class'} or 'unknown' );
}

=pod

=head2 check_domain_name

	die "Domain name is invalid (you can't use FQDN)\n" unless Vhffs::Functions::check_domain_name($name);
	die "Domain name is invalid (could be FQDN or not)\n" unless Vhffs::Functions::check_domain_name($name, 1);

Checks for domain name validity.

=cut
sub check_domain_name($;$) {
	my $domain_name = shift;
	my $fqdn = shift;
	$domain_name =~ s/\.$// if($fqdn);
	return (defined $domain_name and length($domain_name) >= 5 and $domain_name =~ /^(?:[a-z0-9\-]{1,63}[.])+([a-z0-9]{2,10})$/);
}

=pod

=head2 check_ip

die "IPv4 is invalid" unless Vhffs::Functions::check_ip( $name );

Checks for IPv4 validity.

=cut
sub check_ip($) {
	my $ip = shift;
	return (defined $ip and $ip =~ /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/);
}

=pod

=head2 check_ipv6

die "IPv6 is invalid" unless Vhffs::Functions::check_ipv6( $name );

Checks for IPv6 validity.

=cut
sub check_ipv6($) {
	my $ip = shift;
	return (defined $ip and $ip =~ /^((([0-9A-Fa-f]{1,4}:){7}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){6}:[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){5}:([0-9A-Fa-f]{1,4}:)?[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){4}:([0-9A-Fa-f]{1,4}:){0,2}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){3}:([0-9A-Fa-f]{1,4}:){0,3}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){2}:([0-9A-Fa-f]{1,4}:){0,4}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){6}((\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b)\.){3}(\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b))|(([0-9A-Fa-f]{1,4}:){0,5}:((\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b)\.){3}(\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b))|(::([0-9A-Fa-f]{1,4}:){0,5}((\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b)\.){3}(\b((25[0-5])|(1\d{2})|(2[0-4]\d)|(\d{1,2}))\b))|([0-9A-Fa-f]{1,4}::([0-9A-Fa-f]{1,4}:){0,5}[0-9A-Fa-f]{1,4})|(::([0-9A-Fa-f]{1,4}:){0,6}[0-9A-Fa-f]{1,4})|(([0-9A-Fa-f]{1,4}:){1,7}:))$/);
}

1;
