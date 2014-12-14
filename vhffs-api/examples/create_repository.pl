#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::Repository;

my $vhffs = new Vhffs;

die("Usage: $0 reponame description username groupname\n") unless(@ARGV == 4);

my ($reponame, $description, $username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

my $repo = Vhffs::Services::Repository::create($vhffs, $reponame, $description, $user, $group );

if( defined $repo )
{
	print "Repository $reponame created\n";
}
else
{
	print "Unable to create $reponame, check syntax and uniqueness\n";
	exit;
}

