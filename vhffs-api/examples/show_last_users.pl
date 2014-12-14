#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';

use Vhffs;
use Vhffs::Panel::User;

my $vhffs = new Vhffs;

my $users = Vhffs::Panel::User::get_last_users( $vhffs );


use Data::Dumper;

print Dumper $users;
