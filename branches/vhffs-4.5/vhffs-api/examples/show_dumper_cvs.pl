#!%PERL% -w


use strict;

use Data::Dumper;
use lib '%VHFFS_LIB_DIR%';
use Vhffs::User;
use Vhffs::Group;
use Vhffs;
use Vhffs::Object;
use Vhffs::Services::Web;
use Vhffs::Panel::Group;
use Vhffs::Services::Cvs;

my $config;
my $mysql_config;
my $services_config;
my $user;
my $dbh;
my $backend;
my %infos;

my $vhffs = new Vhffs;

$config = $vhffs->get_config;

my $cvs = Vhffs::Services::Cvs::get_by_reponame( $vhffs , $ARGV[0] ) ;

print Dumper $cvs;

print $cvs->get_description;

