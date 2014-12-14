#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::Services::Mail;

my $vhffs = new Vhffs;

die("Usage: $0 mail_domain localpart password\n") unless(@ARGV == 3);

my ($domain, $local, $pass) = @ARGV;

my $mail = Vhffs::Services::Mail::get_by_mxdomain($vhffs, $domain);
die("Mail domain $domain not found\n") unless(defined $mail);

die("Unable to create box $local\@$domain\n") if( $mail->add_box($local, $pass) < 0 );
print "Box $local\@$domain successfully created\n";
