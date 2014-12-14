#!%PERL% -w


use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;

my $vhffs = new Vhffs;

die("Usage: $0 groupname owner_username description\n") unless(@ARGV == 3);

my ($groupname, $realname, $username, $description) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);

my $group = Vhffs::Group::create($vhffs, $groupname, $realname, $user->get_uid, undef, $description) ;

if( !defined $group )
{
    die "Unable to create group $groupname\n";
}
else
{
	print "Group $groupname created!\n";
}
