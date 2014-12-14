#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs;
use Vhffs::Panel::DNS;

my $vhffs = new Vhffs;

die("Usage: $0 username\n") unless(@ARGV == 1);

my ($username) = @ARGV;

my $user = Vhffs::User::get_by_username( $vhffs, $username );
die("User $username not found\n") unless(defined $user);

print Dumper( Vhffs::Panel::DNS::getall_dns_per_user( $user , $vhffs ));
