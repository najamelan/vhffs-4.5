#!%PERL% -w


use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs;

my $vhffs = new Vhffs;

die("Usage: $0 username new_firstname\n") unless(@ARGV == 2);

my ($username, $firstname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);

$user->set_firstname($firstname);
die("Unable to change firstname for user $username\n") unless($user->commit > 0);
print("User updated\n");

