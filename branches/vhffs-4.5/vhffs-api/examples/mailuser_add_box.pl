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

die("Usage: $0 username password\n") unless(@ARGV == 2);

my ($username, $password) = @ARGV;

my $user = Vhffs::User::get_by_username($vhffs, $username);
die("User not found\n") unless(defined $user);

my $mu = new Vhffs::Services::MailUser( $vhffs , $user );

die("Unable to create box $username\@".$mu->{domain}."\n") unless($mu->addbox( $password ) > 0);
print "Box $username\@".$mu->{domain}." created\n";
