#!%PERL% -w


use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs;
use Vhffs::Services::Web;

my $vhffs = new Vhffs;

die("Usage: $0 servername username level\n") if(@ARGV != 3);

my ($servername, $username, $level) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User $username not found\n") unless(defined $user);

my $httpd = Vhffs::Services::Web::get_by_servername($vhffs, $servername);
die("Webarea $servername not found\n") unless(defined $httpd);

$httpd->add_acl( $user, $level );
