# Copyright (c) vhffs project and its contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#   notice, this list of conditions and the following disclaimer.
#2. Redistributions in binary form must reproduce the above copyright
#   notice, this list of conditions and the following disclaimer in
#   the documentation and/or other materials provided with the
#   distribution.
#3. Neither the name of vhffs nor the names of its contributors
#   may be used to endorse or promote products derived from this
#   software without specific prior written permission.
#
#THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
#"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
#LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
#FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
#COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
#INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
#BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
#LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
#CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

package Vhffs;

use strict;
use utf8;
use DBI;
use Vhffs::Constants;
use Vhffs::Functions;
use Vhffs::Conf;

=pod
=head1 NAME

Vhffs - The Main class of Vhffs API, Config file access and Backend access

=head1 SYNOPSIS

	use Vhffs;
	my $vhffs = new Vhffs or die();
	my $conf = $vhffs->get_config;

=head1 DESCRIPTION

The Vhffs object is the main Vhffs class. When you
invoke new Vhffs object that read configuration
and create a Vhffs::Conf object then create by default a connection to backend.

=head1 METHODS
=cut

=pod

=head1 init( \%opts )

my $vhffs = new Vhffs( { backend => 1 } ) or die();

=cut
sub new {
	my $class = ref( $_[0] ) || $_[0];
	my $opt = $_[1];

	# First, config stuff
	my $config = new Vhffs::Conf( Vhffs::Constants::CONF_PATH );
	return undef unless defined $config;

	# Next, create the object
	my $self={};
	bless( $self , $class );
	$self->{'config'} = $config;

	# Finally, backend stuff
	$opt->{backend} = 1 unless defined $opt->{backend};
	if( $opt->{backend} and not defined $self->connect ) {
		undef $self;
		return undef;
	}

	return $self;
}

=pod

=head1 get_db

my $dbh = $vhffs->get_db;

Returns a C<DBI> object if backend was connected, otherwise returns undef.

=cut
sub get_db {
	my $self = shift;
	return $self->{'db'};
}

=pod

=head1 get_config

my $config = $vhffs->get_cofig;

Returns a C<Vhffs::Conf> object.

=cut
sub get_config {
	my $self = shift;
	return $self->{'config'};
}

=pod

=head1 reload_config

$vhffs->reload_config;

Reload configuration file if necessary.

=cut
sub reload_config {
	my $self = shift;
	return unless $self->{'config'}->changed;
	$self->{'config'} = new Vhffs::Conf( Vhffs::Constants::CONF_PATH );
}

=pod

=head1 connect

my $dbh = $vhffs->connect;

Connect to backend, should only be used once, and only if backend was set to false in constructor options.

Returns a C<DBI> object if connection succeded, otherwise returns undef.

=cut
sub connect {
	my $self = shift;
	my $config = $self->{config}->get_database();

	unless( defined $config )  {
		warn 'Oops!: I wonder if I am blind but I cannot find the backend area in the Vhffs configuration file :/, could you help me ?'."\n";
		return undef;
	}

	if( $config->{'driver'} eq 'pg' )  {
		my $dbh = DBI->connect('DBI:Pg:'.$config->{'datasource'}, $config->{'username'}, $config->{'password'}, {pg_enable_utf8 => 1} );
		return undef unless defined $dbh;
		$dbh->do( 'SET CLIENT_ENCODING TO \'UTF8\'' );
		$self->{'db'} = $dbh;
		return $dbh;
	}

	warn 'Oops!: The specified backend in the configuration file is not supported by Vhffs'."\n";
	return undef;
}

=pod

=head1 is_connected

my $connected = $vhffs->is_connected;

Returns true if backend connection is alive, otherwise return false.

=cut
sub is_connected {
	my $self = shift;
	return (defined $self->{db} and $self->{db}->ping() > 0);
}

=pod

=head1 reconnect

my $dbh = $vhffs->reconnect;

Reconnect to the database if necessary.

Returns a C<DBI> object if everything went fine, otherwise returns undef.

=cut
sub reconnect {
	my $self = shift;
	return $self->{db} if defined $self->{db} and $self->{db}->ping() > 0;
	$self->{db}->disconnect if defined $self->{db};
	return $self->connect;
}

=pod

=head1 set_current_user

$vhffs->set_current_user( $user );

Set current user using the API (used for C<Vhffs::Object::add_history>)

=cut
sub set_current_user {
	my $self = shift;
	my $user = shift;
	$self->{current_user} = $user if defined $user;
	return $user;
}

=pod

=head1 get_current_user

my $user = $vhffs->get_current_user;

Get current user using the API (used for C<Vhffs::Object::add_history>)

=cut
sub get_current_user {
	my $self = shift;
	return $self->{current_user};
}

=pod

=head1 clear_current_user

$vhffs->clear_current_user;

Clear current user using the API. You should use it if Vhffs main class
is persistent and potentially used by more than one user.

=cut
sub clear_current_user {
	my $self = shift;
	delete $self->{current_user};
}

=pod

=head1 get_stats

my $stats = $vhffs->get_stats;

Returns and caches a C<Vhffs::Stats> object.

$time is an optional parameter, default to 3600, the cache is not going to be flushed if data were not flushed $time seconds ago.

=cut
sub get_stats {
	my $self = shift;
	my $time = shift;
	require Vhffs::Stats;
	$self->{stats} = new Vhffs::Stats( $self ) unless defined $self->{stats};
	$self->{stats}->flush( defined $time ? $time : 3600 );
	return $self->{stats};
}

1;

__END__

=head1 SEE ALSO
Vhffs::User, Vhffs::Group
