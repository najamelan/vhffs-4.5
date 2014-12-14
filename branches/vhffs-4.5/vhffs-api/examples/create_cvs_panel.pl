#!%PERL% -w


use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Panel::Cvs;

my $vhffs = new Vhffs;

die("Usage: $0 cvsroot description owner_username owner_groupname\n") unless(@ARGV == 4);

my ($cvsroot, $description, $username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

my $cvs = Vhffs::Panel::Cvs::create_cvs( $vhffs, $cvsroot, $description, $user, $group );

die("Unable to create cvs $cvsroot\n") unless(defined $cvs);
print "CVS $cvsroot created\n";
