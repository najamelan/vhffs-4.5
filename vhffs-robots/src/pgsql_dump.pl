#!/usr/bin/perl
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

########################################################
# This robot make dump for each PgSQL database
# and put it on each group directory
#

use strict;
use utf8;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::Robots::Pgsql;

my $vhffs = new Vhffs;
exit 1 unless defined $vhffs;

my $pgsqlconf = $vhffs->get_config->get_service('pgsql');
die 'Error, pg_dump is not present on this system in path "'.$pgsqlconf->{'pgdump_path'}.'"'."\n" unless -x $pgsqlconf->{'pgdump_path'};

Vhffs::Robots::lock( $vhffs, 'dumppgsql' );

my $repos = Vhffs::Services::Pgsql::getall( $vhffs, Vhffs::Constants::ACTIVATED );
foreach ( @{$repos} ) {
	Vhffs::Robots::Pgsql::dump_night( $_ );
}

Vhffs::Robots::unlock( $vhffs, 'dumppgsql' );
exit 0;
