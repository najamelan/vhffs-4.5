#!%PERL% -w


use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Panel::Web;

my $vhffs = new Vhffs;

die("Usage: $0 servername description owner_username owner_groupname\n") unless(@ARGV == 4);

my ($servername, $description, $username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

die("Unable to create webarea $servername\n") unless(defined Vhffs::Panel::Web::create_web($vhffs, $servername, $description, $user, $group));
print("Webarea $servername created\n");
