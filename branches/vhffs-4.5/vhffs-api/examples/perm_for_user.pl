#!%PERL%

use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::Mysql;
use Vhffs::Services::Web;

my $vhffs = new Vhffs;

die("Usage: $0 servername username\n") unless(@ARGV == 2);

my ($servername, $username) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User $username not found\n") unless(defined $user);

my $httpd = Vhffs::Services::Web::get_by_servername($vhffs, $servername);
die("Webarea $servername not found\n") unless(defined $httpd);

print "Permission: ";
print $user->get_perm( $httpd );
print "\n";
