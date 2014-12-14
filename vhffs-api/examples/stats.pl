#!%PERL%

use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::Stats;

my $vhffs = new Vhffs;
my $stats = new Vhffs::Stats( $vhffs );

print "Users total : ";
print $stats->get_user_total;
print "\n";
