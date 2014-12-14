#!/usr/bin/perl
=head1 update-POTFILE.in.pl - Updates i18n strings

This script generates a list of files that may contain
internationalized strings. It also extract i15d strings from
templates.

=cut

use strict;
use warnings;

use File::Basename;
use File::Find;
use File::Spec;

my $script = File::Spec->rel2abs(__FILE__);
my $src_root = File::Basename::dirname(dirname($script));
my @src_subdirs = qw/vhffs-contrib vhffs-panel vhffs-listengine
	vhffs-tools vhffs-mw vhffs-api vhffs-shells vhffs-public
	vhffs-jabber vhffs-irc vhffs-stsmon vhffs-intl/;

# First extract strings from templates

my @tt_files;

foreach my $sd(@src_subdirs) {
	File::Find::find(sub {
		push @tt_files, $File::Find::name if($File::Find::name =~ /\.tt$/)
	}, File::Spec->catfile($src_root, $sd));
}

open my $strings, '>', File::Spec->catfile($src_root, 'vhffs-intl', 'template_strings.pl');
print $strings "#!/usr/bin/perl\nexit(0);\n";

foreach my $f(@tt_files) {
	open my $tt, '<', $f;
	my $str;
	while(<$tt>) {
		foreach( split /%]/ ) {
			( ($str) = /\[%\s+'([^|]+?)'\s*\|\s*i18n\b/ ) or next;
			print $strings "# $f:$.\n";
			print $strings "gettext('$str');\n";
		}
	};
	close $tt;
}

close $strings;

# Then make a list of files
my @files;
foreach my $sd(@src_subdirs) {
	File::Find::find(sub {
		my $f = $File::Find::name;
		if($f =~ /\.p[ml]$/) {
			$f =~ s/$src_root\///;
			push @files, $f;
		}
	}, File::Spec->catfile($src_root, $sd));
}

open my $potfiles, '>', 'POTFILES.in';
print $potfiles join("\n", sort @files)."\n";
close $potfiles;
