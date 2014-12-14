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
use Vhffs::Broadcast;
use Vhffs::User;

package Vhffs::Robots::Broadcast;

sub send {
	my $mailing = shift;
	return undef unless defined $mailing and $mailing->get_status == Vhffs::Constants::BROADCAST_WAITING_TO_BE_SENT;

	my $vhffs = $mailing->get_vhffs;

	my $from = $vhffs->get_config->get_master_mail;
	unless( defined $from ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Cannot send mailing, From: (master mail) is not declared in config file' );
		return undef;
	}

	my $users = Vhffs::User::getall( $vhffs );
	foreach my $user ( @{$users} ) {
		Vhffs::Functions::send_mail( $vhffs, $from, $user->get_mail, $vhffs->get_config->get_mailtag, $mailing->{subject} , $mailing->{message} , 'bulk' );
	}

	$mailing->set_status( Vhffs::Constants::BROADCAST_SENT );
	$mailing->commit;
}

1;
