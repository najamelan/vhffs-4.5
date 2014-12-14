#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs;
use Vhffs::Services::Mail;

my $vhffs = new Vhffs;

die("Usage: $0 mxdomain localpart remote_address\n") unless(@ARGV == 3);

my ($domain, $local, $remote) = @ARGV;

my $mail = Vhffs::Services::Mail::get_by_mxdomain($vhffs, $domain);

die("Mail domain $domain not found\n") unless(defined $mail);


unless( $mail->add_redirect($local, $remote) ) {
    die "Unable to add forward $local\@". $mail->get_domain ." -> $remote\n";
}

print "Forward created\n";
