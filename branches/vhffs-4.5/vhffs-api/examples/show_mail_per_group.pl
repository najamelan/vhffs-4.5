#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::Group;
use Vhffs;
use Vhffs::Panel::Mail;

my $vhffs = new Vhffs;

die("Usage: $0 groupname\n") unless(@ARGV == 1);

my ($groupname) = @ARGV;

my $group = Vhffs::Group::get_by_groupname($vhffs, $groupname);
die("Group $groupname not found\n") unless(defined $group);

print Dumper(Vhffs::Panel::Mail::getall_mail_per_group( $group , $vhffs ));
