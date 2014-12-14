#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::DNS;

my $vhffs = new Vhffs;

die("Usage $0 domain_name, description, user, group") unless(@ARGV == 4);

my ($domain, $description, $username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

my $dns = Vhffs::Services::DNS::create( $vhffs , $domain, $description, $user , $group );

if( defined $dns )
{
	print "Domain $domain successfully created\n";
}
else
{
	die("Unable to create object, check syntax and uniqueness\n");
}

