#!%PERL% -w


use strict;
use lib '%VHFFS_LIB_DIR%';

use Vhffs;
use Vhffs::Services::Mail;

my $vhffs = new Vhffs;

die("Usage: $0 mail_domain box\n") unless(@ARGV == 2);

my ($domain, $box) = @ARGV;

my $mail = Vhffs::Services::Mail::get_by_mxdomain($vhffs , $domain);

die("Domain $domain not found\n") unless(defined $mail);

die("Unable to delete box $box\@".$mail->get_domain."\n") if( $mail->delbox($box) < 0 );

print "Box $box\@".$mail->get_domain." deleted\n";


