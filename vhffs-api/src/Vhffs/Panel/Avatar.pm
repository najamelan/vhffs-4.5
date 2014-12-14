#!%PERL% -w
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

package Vhffs::Panel::Avatar;

use POSIX qw(locale_h);
use locale;
use Locale::gettext;
use Encode;
use GD;
use GD::Text::Wrap;

use Vhffs::Constants;
use Vhffs::Functions;
use Digest::MD5 qw(md5_hex);

sub store_avatar {
	my $vhffs = shift;
	my $object = shift;
	my $file = shift;
	my $type = shift;
	my $config = $vhffs->get_config;
	my $datadir = $config->get_datadir . '/avatar';
	my $oid = $object->get_oid;

	return -1 unless -d $datadir;

	my $digest = md5_hex( $oid );
	my $dir = $datadir.'/'.substr( $digest , 0 , 2 ).'/'.substr( $digest , 2 , 2 ).'/'.substr( $digest , 4 , 2 );
	my $path = $dir.'/'.$oid;
#	$path .= ".".$type if( defined $type );

	# TODO: check make_path
	File::Path::make_path( $dir );

	open( my $forig, '<', $file ) or return -2;
	open( my $fcopy, '>', $path ) or return -3;

	my $buffer;
	binmode( $fcopy );
	while( read( $forig , $buffer , 1024 ) ) {
		print $fcopy $buffer;
	}

	close( $fcopy );
	close( $forig );
	return 1;
}

sub exists_avatar {
	my $vhffs = shift;
	my $object = shift;

	return undef unless defined $object;

	my $digest = md5_hex( $object->get_oid );
	my $path = $vhffs->get_config->get_datadir.'/avatar/'.substr( $digest , 0 , 2 ).'/'.substr( $digest , 2 , 2 ).'/'.substr( $digest , 4 , 2 ).'/'.$object->get_oid;;

	return undef unless -f $path;
	return $path;
}

sub get {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $oid	= $cgi->param( 'oid' );
	unless( defined $oid ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		return;
	}

	unless( $panel->use_avatars ) {
		$panel->render('misc/message.tt', { message => gettext('This platform does not provide avatar support') } );
		return;
	}

	my $object = Vhffs::Object::get_by_oid( $vhffs , $oid );
	unless( defined $object ) {
		$panel->render('misc/message.tt', { message => gettext('Cannot get informations on this object') } );
		return;
	}

	# Assume the user has set FONT_PATH or TTF_FONT_PATH
	#$wp->font_path('/usr/share/fonts/ttfonts');
	print $cgi->header( -type=>'image/png' );
	binmode STDOUT;

	my $path = exists_avatar( $vhffs , $object );
	if( $path and open ( my $forig , '<', $path ) ) {
		my $buf;
		while( read( $forig , $buf , 1024 ) ) {
			print STDOUT $buf;
		}
		close( $forig );

	} else {
		my $gd = GD::Image->new(70,100);
		my $white = $gd->colorAllocate(255,255,255);
		my $black = $gd->colorAllocate(  0,  0,  0);
		my $blue  = $gd->colorAllocate(127,127,255);
		my $wp = GD::Text::Wrap->new($gd,
			width       => 70,
			line_space  => 0,
			color       => $black,
			text        => 'No avatar',
		);
		$wp->set_font(GD::Font->Large, 14);
		$wp->set(align => 'center');
		$wp->draw(0,5);
		$wp->set(para_space => 10, preserve_nl => 0);
		print STDOUT $gd->png();
	}

	close STDOUT;
}

sub put {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $oid = $cgi->param( 'oid' );
	my $filename = $cgi->param( 'avatar' );
	my $tmpfile = $cgi->tmpFileName( $filename ) if defined $filename;
	unless( defined $oid and defined $filename and defined $tmpfile and -f $tmpfile ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		goto PUTEND;
	}

	unless( $panel->use_avatars ) {
		$panel->render('misc/message.tt', { message => gettext('This platform does not provide avatar support') } );
		goto PUTEND;
	}

	my $object = Vhffs::Object::get_by_oid( $vhffs , $oid );
	unless( defined $object ) {
		$panel->render('misc/message.tt', { message => gettext('Cannot get informations on this object') } );
		goto PUTEND;
	}

	unless( $user->can_modify( $object ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		goto PUTEND;
	}

	unless( $filename =~ /\.[Pp][Nn][Gg]$/ ) {
		$panel->render('misc/message.tt', { message => gettext( 'Filetype not supported, only png is supported' ) } );
		goto PUTEND;
	}

	my (undef, undef ,undef ,undef ,undef ,undef, undef, $fsize, undef, undef, undef, undef, undef) = stat( $tmpfile );
	unless( $fsize < 200000 ) {
		$panel->render('misc/message.tt', { message => gettext( 'Uploaded file is too big. The maximum size is 200 kbytes' ) } );
		goto PUTEND;
	}

	my ( $type ) = ( $filename =~ ( /\.([a-zA-Z]+)$/ ) );
	my $avatar = store_avatar( $vhffs, $object, $tmpfile, $type );
	if( $avatar < 0 ) {
		$panel->render('misc/message.tt', { message => gettext( 'Error when uploading avatar for this object' ) } );
		goto PUTEND;
	}

	$panel->render('misc/message.tt', { message => gettext( 'Successfully created or updated avatar' ) } );

PUTEND:
	unlink $tmpfile if defined $tmpfile and -f $tmpfile;
	return;
}

sub delete {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $oid = $cgi->param( 'oid' );
	unless( defined $oid ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		return;
	}

	unless( $panel->use_avatars ) {
		$panel->render('misc/message.tt', { message => gettext('This platform does not provide avatar support') } );
		return;
	}

	my $object = Vhffs::Object::get_by_oid( $vhffs , $oid );
	unless( defined $object ) {
		$panel->render('misc/message.tt', { message => gettext('Cannot get informations on this object') } );
		return;
	}

	unless( $user->can_modify( $object ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	my $path = exists_avatar( $vhffs , $object );
	unless( defined $path ) {
		$panel->render('misc/message.tt', { message => gettext( 'This object does not have an avatar' ) } );
		return;
	}

	unless( unlink $path ) {
		$panel->render('misc/message.tt', { message => gettext( 'Cannot delete this avatar' ) } );
		return;
	}

	$panel->render('misc/message.tt', { message => gettext( 'Avatar deleted' ) } );
}

1;


__END__

=head1 NAME

Vhffs::Panel::Avatar - upload and get avatar for VHFFS

=head1 SYNOPSIS

	use Vhffs;
	use Vhffs::Panel::Avatar;

	my $vhffs = new Vhffs;

	....
	(considers that you create or handle an object in $object var)
	....
	Vhffs::Panel::Avatar::store_avatar( $vhffs , $object , $filename );

	my $path = Vhffs::Panel::Avatar::exists_avatar( $vhffs , $object );
	if( ! defined ( $path ) ) )
	{
		print "No avatar for this object" );
	}
	else
	{
		print "The avatar for this object is stored in the file " . $path ;
	}

=head1 AUTHOR

	Julien Delange <julien AT gunnm DOT org>

=head1 COPYRIGHT

	Copyright 2006 Julien Delange
