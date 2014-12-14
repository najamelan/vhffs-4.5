#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::Mysql;

my $vhffs = new Vhffs;

die("Usage: $0 dbname dbuser dbpass description owner_username owner_groupname\n") unless(@ARGV == 6);

my ($dbname, $dbuser, $dbpass, $description, $username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);


my $sql = Vhffs::Services::Mysql::create($vhffs , $dbname, $dbuser, $dbpass, $description, $user, $group);

if( defined $sql )
{
	print "Mysql service $dbname created\n";
}
else
{
	die("Unable to create MySQL service $dbname\n");
}

