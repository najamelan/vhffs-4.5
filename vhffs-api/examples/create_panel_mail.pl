#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Panel::Mail;

my $vhffs = new Vhffs;

die("Usage: $0 domain description owner_username owner_groupname\n") unless(@ARGV == 4);

my ($domain, $description, $username, $groupname) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);
my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group not found\n") unless(defined $group);

my $mail = Vhffs::Panel::Mail::create_mail( $vhffs, $domain, $description, $user, $group);

die("Unable to create mail domain $domain\n") unless(defined $mail);
print("Mail domain $domain created\n");
