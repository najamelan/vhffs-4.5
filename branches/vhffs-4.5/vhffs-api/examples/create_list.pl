#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::Mail;
use Vhffs::Services::MailingList;

my $vhffs = new Vhffs;

die("Usage: $0 localpart domain description owner_username owner_groupname\n") unless(@ARGV == 5);

my ($local, $domain, $description, $username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

my $mail = Vhffs::Services::MailingList::create($vhffs, $local, $domain, $description, $user, $group);

if( defined $mail )
{
	print "Mailing list $local\@$domain created\n";
}
else
{
	die("Unable to create mailing list $local\@$domain, please check syntax and uniqueness\n");
}

