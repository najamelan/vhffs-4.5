#!%PERL%


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::Services::Mysql;

my $vhffs = new Vhffs;

die("Usage: $0 dbname\n\tShows ACL for MySQL service dbname\n") unless(@ARGV == 1);

my ($dbname) = @ARGV;

my $sql = Vhffs::Services::Mysql::get_by_dbname($vhffs, $dbname);

die("MySQL service $dbname not found\n") unless(defined $sql);

my $acl = $sql->get_acl();
print Dumper $acl;
