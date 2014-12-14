#!%PERL% -w

use strict;

use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;

my $config;
my $mysql_config;
my $services_config;
my $user;
my $dbh;
my $backend;
my %infos;

my $vhffs = new Vhffs;

$config = $vhffs->get_config;
my $cmail = $config->get_service( "dns" );

if( defined $cmail->{init} )
{
	my $init = $cmail->{init};
	use Data::Dumper;
	print Dumper $init;

	if( defined $init->{a} )
	{
		foreach( keys %{$init->{a}} )
		{
			print "a : $_ , valeur :" . $init->{a}{$_} . "\n";
		}
	}
	if( defined $init->{mx} )
	{
		foreach( keys %{$init->{mx}} )
		{
			print "a : $_ , valeur :" . $init->{mx}{$_} . "\n";
		}
	}

	if( defined $init->{ns} )
	{
		foreach( keys %{$init->{ns}} )
		{
			print "a : $_ \n";
		}
	}

}
