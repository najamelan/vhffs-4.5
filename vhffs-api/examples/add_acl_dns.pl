#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs;
use Vhffs::Services::DNS;

my $vhffs = new Vhffs;

die("Usage: $0 domain user level\n") unless(@ARGV == 3);

my ($domain, $username, $level) = @ARGV;

my $dns = Vhffs::Services::DNS::get_by_domainname($vhffs , $domain);
die("Domain $domain not found\n") unless(defined $dns);

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User $username not found\n") unless(defined $user);

$dns->add_acl( $user, $level );

print "User $username has now access level $level domain $domain\n";
