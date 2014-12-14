#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::Web;
use Vhffs::Panel::Group;

my $vhffs = new Vhffs;

die("Usage: $0 objectID\n") unless(@ARGV == 1);

my ($oid) = @ARGV;

my $obj = Vhffs::Object::get_by_oid($vhffs, $oid);
die("Object #$oid not found\n") unless(defined $obj);

print Dumper $obj;
