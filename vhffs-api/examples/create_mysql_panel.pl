#!%PERL% -w


use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Panel::Mysql;

my $vhffs = new Vhffs;


die("Usage: $0 dbname dbuser dbpass description owner_username owner_groupname\n") unless(@ARGV == 6);

my ($dbname, $dbuser, $dbpass, $description, $username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

my $mysql = Vhffs::Panel::Mysql::create_mysql( $vhffs, $dbname, $user, $group, $dbuser, $dbpass, $description );

die("Unable to create mysql service $dbname\n") unless(defined $mysql);
print("MySQL service created\n");
