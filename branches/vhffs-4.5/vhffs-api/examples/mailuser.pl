#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::MailUser;
use Vhffs::Panel::Mail;

my $vhffs = new Vhffs;

die("Usage: $0 username\n") unless(@ARGV == 1);

my ($username) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);

my $mu = new Vhffs::Services::MailUser( $vhffs , $user );
die("Configuration error\n") if(!ref($mu));

if( $mu->exists_forward == 1 ) {
	print "User has a forward on this domain\n";
} else {
	print "User doesn't have forward\n";
}

if( $mu->exists_box == 1 ) {
	print "User has a box\n";
} else {
	print "User doesn't have a box\n";
}

