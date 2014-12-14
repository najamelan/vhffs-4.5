#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::Mail;

my $vhffs = new Vhffs;

die("Usage $0 domain description owner_username owner_groupname") if(@ARGV != 4);
my ($domain, $description, $username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

my $mail = Vhffs::Services::Mail::create( $vhffs , $domain, $description, $user , $group);

if( defined $mail )
{
	print "Mail domain $domain created\n";
}
else
{
	print "Error creating domain (check syntax and uniqueness)\n";
	exit;
}

