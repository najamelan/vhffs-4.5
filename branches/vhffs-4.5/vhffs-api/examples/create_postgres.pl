#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::Pgsql;

my $vhffs = new Vhffs;


die("Usage: $0 dbname dbuser dbpass description user group\n") unless(@ARGV == 6);

my ($dbname, $dbuser, $dbpass, $description, $username, $groupname) = @ARGV;


my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

my $sql = Vhffs::Services::Pgsql::create( $vhffs , $dbname, $dbuser, $dbpass, $description, $user, $group);

if( defined $sql )
{
	print "Postgres Service $dbname created\n";
}
else
{
    die("Unable to create $dbname, check syntax and uniqueness\n");
}

