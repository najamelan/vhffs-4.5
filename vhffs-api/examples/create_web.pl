#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::Web;

my $vhffs = new Vhffs;

die("Usage: $0 servername description owner_username owner_groupname\n") unless(@ARGV == 4);

my($servername, $description, $username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

my $httpd = Vhffs::Services::Web::create($vhffs, $servername, $description, $user, $group);

if( defined $httpd )
{
	print "Webarea $servername created\n";
}
else
{
	die "Unable to create webarea $servername\n";
}
