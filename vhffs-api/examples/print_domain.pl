#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::Services::DNS;

my $vhffs = new Vhffs;

die("Usage: $0 domainname\n") unless(@ARGV == 1);

my ($domainname) = @ARGV;

my $dns = Vhffs::Services::DNS::get_by_domainname($vhffs, $domainname);

die("Domain name not found\n") unless(defined $dns);

print Dumper $dns;
