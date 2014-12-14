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
use Vhffs::Services::DNS;

package Vhffs::Robots::DNS;

sub create {
	my $dns = shift;
	return undef unless defined $dns and $dns->get_status == Vhffs::Constants::WAITING_FOR_CREATION;

	my $vhffs = $dns->get_vhffs;

	$dns->set_status( Vhffs::Constants::ACTIVATED );
	$dns->commit;
	Vhffs::Robots::vhffs_log( $vhffs, 'Created DNS '.$dns->get_domain );

	$dns->send_created_mail;
	return 1;
}

sub delete {
	my $dns = shift;
	return undef unless defined $dns and $dns->get_status == Vhffs::Constants::WAITING_FOR_DELETION;

	my $vhffs = $dns->get_vhffs;

	if( $dns->delete ) {
		Vhffs::Robots::vhffs_log( $vhffs, 'Deleted DNS '.$dns->get_domain );
	} else {
		Vhffs::Robots::vhffs_log( $vhffs, 'An error occured while deleting DNS '.$dns->get_domain );
		$dns->set_status( Vhffs::Constants::DELETION_ERROR );
		$dns->commit();
		return undef;
	}

	return 1;
}

sub modify {
	my $dns = shift;
	return undef unless defined $dns and $dns->get_status == Vhffs::Constants::WAITING_FOR_MODIFICATION;
	$dns->set_status( Vhffs::Constants::ACTIVATED );
	$dns->commit;
	return 1;
}

1;
