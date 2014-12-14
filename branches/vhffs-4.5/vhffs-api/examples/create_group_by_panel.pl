#!%PERL% -w


use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs;
use Vhffs::Panel::Group;

my $vhffs = new Vhffs;

die("Usage: $0 groupname owner_username decription\n") unless(@ARGV == 3);

my ($groupname, $username, $description) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User $username not found\n") unless(defined $user);


#add this group in database
my $group = Vhffs::Panel::Group::create_group( $groupname, $user , $vhffs, $description );
die("Unable to create group $groupname\n") unless(defined $group);

print("Group $groupname created\n");
