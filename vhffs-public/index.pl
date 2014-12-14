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


require 5.004;
use utf8;
use POSIX;
use strict;
use locale;
use Locale::gettext;
#use CGI::Fast qw(:standard);
use CGI();
use CGI::Fast();
use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::Panel::Public;

# -- prefork
CGI->compile();

my $vhffs = new Vhffs( { backend => 0 } );
exit 1 unless defined $vhffs;

$vhffs->connect;

# -- requests loop
while (my $cgi = new CGI::Fast) {

	$vhffs->reload_config;

	my $panel = new Vhffs::Panel::Public( $vhffs, $cgi );
	next unless defined $panel;

	my $do = ( $cgi->url_param('do') or 'lastgroups' );

	if( $do eq 'lastgroups' ) {
		Vhffs::Panel::Public::lastgroups( $panel );
	} elsif( $do eq 'groupsearch' ) {
		Vhffs::Panel::Public::groupsearch( $panel );
	} elsif( $do eq 'group' ) {
		Vhffs::Panel::Public::group( $panel );
	} elsif( $do eq 'allgroups' ) {
		Vhffs::Panel::Public::allgroups( $panel );
	} elsif( $do eq 'lastusers' ) {
		Vhffs::Panel::Public::lastusers( $panel );
	} elsif( $do eq 'usersearch' ) {
		Vhffs::Panel::Public::usersearch( $panel );
	} elsif( $do eq 'user' ) {
		Vhffs::Panel::Public::user( $panel );
	} elsif( $do eq 'avatar' ) {
		require Vhffs::Panel::Avatar;
		Vhffs::Panel::Avatar::get( $panel );
	} elsif( $do eq 'tags' ) {
		Vhffs::Panel::Public::tags( $panel );
	} elsif( $do eq 'externnewusersrss' ) {
		Vhffs::Panel::Public::externnewusersrss( $panel );
	} elsif( $do eq 'externnewgroupsrss' ) {
		Vhffs::Panel::Public::externnewgroupsrss( $panel );
	} elsif( $do eq 'externstats' ) {
		Vhffs::Panel::Public::externstats( $panel );
	} else {
		$panel->render('misc/message.tt',  { message => gettext('CGI Error !') });
	}
}

exit 0;
