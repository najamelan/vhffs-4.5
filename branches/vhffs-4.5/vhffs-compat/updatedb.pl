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
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name of vhffs nor the names of its contributors
#    may be used to endorse or promote products derived from this
#    software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#

use strict;
use utf8;

use lib '%VHFFS_LIB_DIR%';
use Term::ReadPassword;
use File::Basename;
use File::Temp;
use DBI;
use Cwd qw(abs_path getcwd);
use Vhffs;
use IO::File;

#my $SQL_DIR = '%VHFFS_BACKEND_DIR%/';
my $SQL_DIR = '/root/vhffs/vhffs/trunk/vhffs-backend/src/pgsql/';


sub confirm($) {
    my $text = shift;
    my $answer;
    do {
        print "$text (Y/n) ? ";
        chomp($answer = <STDIN>);
        $answer = lc($answer);
    } while($answer ne 'y' and $answer ne 'n' and $answer ne '');

    return($answer ne 'n');
}

sub upgrade_41() {
    my $script = '%VHFFS_COMPAT_DIR%/4.1.sql';
    system("psql -f $script");
}

print "**** VHFFS UPDATEDB ****\nThis script will upgrade your database to the VHFFS ???'s schema.\nEnsure that VHFFS is *stopped* !\nUse this script to your own risks!!!\n";
if(!confirm('Do you still want to continue')) {
    exit(-1);
}

my ($dbhost, $dbname, $dbuser, $dbpass);

print 'Enter VHFFS DB hostname [localhost] : ';
chomp($dbhost = <STDIN>);
$dbhost = 'localhost' unless($dbhost);
print 'Enter VHFFS DB name [vhffs] : ';
chomp($dbname = <STDIN>);
$dbname = 'vhffs' unless($dbname);
print 'Enter VHFFS DB username [vhffs] : ';
chomp($dbuser = <STDIN>);
$dbuser = 'vhffs' unless($dbuser);
$dbpass = read_password('Enter VHFFS DB password : ');

my $dbh = DBI->connect("DBI:Pg:dbname=$dbname;host=$dbhost;port=5432",$dbuser, $dbpass);
if(!$dbh) {
    die "Cant connect to VHFFS DB\n";
}

`psql --version` =~ /^.*?(\d+)/;
my $version = $1;
if($version == 7) {
    print "You may be asked for you pgsql password during upgrade (psql 7.x doesn't support file authentication).\n";
}

# psql and pg_dump will not ask for a password using this
my $pgpass = new File::Temp(DIR => '/tmp');
print $pgpass "*:*:$dbname:$dbuser:$dbpass";
$ENV{'PGHOST'} = $dbhost;
$ENV{'PGDATABASE'} = $dbname;
$ENV{'PGUSER'} = $dbuser;
$ENV{'PGPASSFILE'} = $pgpass->filename;

if(confirm('Do you want to perform a backup right now')) {
    print 'Enter a filename for the backup file [/tmp/vhffs-backup.sql] : ';
    my $backupfile = <STDIN>;
    chomp($backupfile);
    $backupfile = '/tmp/vhffs-backup.sql' unless($backupfile);
    my $bfh = new IO::File($backupfile, 'w');
    die("Unable to open $backupfile : $!\n") unless($bfh);
    my $pg_dump = new IO::File("pg_dump |");
    while(<$pg_dump>) {
        print $bfh $_;
    }
    $bfh->close();
}

upgrade_41();

