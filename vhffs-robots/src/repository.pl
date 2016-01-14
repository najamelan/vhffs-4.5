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

use lib '%VHFFS_LIB_DIR%';
use Vhffs::Robots::Repository;

my $vhffs = new Vhffs;
exit 1 unless defined $vhffs;

Vhffs::Robots::lock( $vhffs, 'repository' );

my $repos = Vhffs::Services::Repository::getall( $vhffs, Vhffs::Constants::WAITING_FOR_CREATION );
foreach ( @{$repos} ) {
	Vhffs::Robots::Repository::create( $_ );
}

$repos = Vhffs::Services::Repository::getall( $vhffs, Vhffs::Constants::WAITING_FOR_DELETION );
foreach ( @{$repos} ) {
	Vhffs::Robots::Repository::delete( $_ );
}

$repos = Vhffs::Services::Repository::getall( $vhffs, Vhffs::Constants::WAITING_FOR_MODIFICATION );
foreach ( @{$repos} ) {
	Vhffs::Robots::Repository::modify( $_ );
}

Vhffs::Robots::unlock( $vhffs, 'repository' );
exit 0;