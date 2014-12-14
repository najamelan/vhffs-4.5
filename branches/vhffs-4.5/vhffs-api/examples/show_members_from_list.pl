#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::Services::MailingList;

my $vhffs = new Vhffs;

die("Usage: $0 mladdress\n") unless(@ARGV == 1);

my ($address) = @ARGV;

my ($local, $domain) = split(/@/, $address);
die("$address is not a valid email address\n") unless(defined $local && defined $domain);

my $ml = Vhffs::Services::MailingList::get_by_mladdress($vhffs, $local, $domain);
die("Mailing list $address not found\n") unless(defined $ml);

my $subs = $ml->get_members;

print Dumper $subs;
