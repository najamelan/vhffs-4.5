#!%PERL% -w


use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;

my $vhffs = new Vhffs;

die("Usage: $0 username password\n") unless(@ARGV == 2);

my ($username, $password) = @ARGV;

my $user = Vhffs::User::create($vhffs, $username, $password);

if( !defined $user )
{
	die "Unable to create user $username\n";
}
else
{
	print "User $username created!\n";
}

exit;
