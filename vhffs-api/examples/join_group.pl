#!%PERL% -w


use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;

my $vhffs = new Vhffs;

die("Usage: $0 username groupname\n") unless(@ARGV == 2);

my ($username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

die("Unable to add $username to group $groupname\n") unless($group->add_user($user) > 0);
