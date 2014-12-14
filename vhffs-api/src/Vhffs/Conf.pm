#!%PERL% -w
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

package Vhffs::Conf;

use strict;
use utf8;
use Encode;
use Config::General;

=pod

=head1 NAME

Vhffs::Conf - Handle VHFFS Configuration file.

=head1 METHODS

=cut

=pod

=head2 new

	my $conf = new Vhffs::Conf( $filename );

Returns a Vhffs::Conf object

=cut
sub new {
	my ( $this, $filename ) = @_;
	my $class = ref($this) || $this;

	my $conf = new Config::General(
		-ConfigFile => $filename,
		-DefaultConfig => {
			'global' => {
				'default_language' => 'en_US',
				'available_languages' => 'en_US'
			},
			'panel' => {
				'mail_obfuscation' => 'none'
			},
			'users' => {
				'available_shells' => '/bin/false',
				'default_shell' => '/bin/false'
			}
		},
		-MergeDuplicateBlocks => 1,
		-MergeDuplicateOptions => 1,
		-UTF8 => 1,
		-AutoTrue => 1,
		-LowerCaseNames => 1
		);
	return undef unless defined $conf;

	my %tmp = $conf->getall();
	return undef unless %tmp;
	my $config = \%tmp;

	# Workaround for \# escaping bug in Config::General
	my @entries = ( $config );
	while( defined(my $entry = shift @entries) ) {
		foreach( values(%{$entry}) ) {
			if( ref($_) ) {
				push @entries, $_;
			} else {
				s/\\#/#/g if defined $_;
			}
		}
	}

	$config->{'filename'} = $filename;
	(undef, undef, undef, undef, undef, undef, undef, undef, undef, $config->{'mtime'}, undef, undef, undef) = stat( $filename );

	my $self = $config;
	bless( $self, $class );
	return $self;
}

=head2 changed

$self->changed;

Return whether configuration file changed on disk (based on mtime).

=cut
sub changed {
	my $self = shift;
	my (undef, undef, undef, undef, undef, undef, undef, undef, undef, $mtime, undef, undef, undef) = stat( $self->{'filename'} );
	return ($mtime != $self->{'mtime'});
}

=pod
=head1 GET CONFIGURATION BLOCK
=pod

=head2 get_global

my $global = $conf->get_global;

Returns global configuration.

=cut
sub get_global {
	my $self = shift;
	return $self->{'global'};
}

=pod

=head2 get_panel

my $panelconf = $conf->get_panel;

Returns panel configuration.

=cut
sub get_panel {
	my $self = shift;
	return $self->{'panel'};
}

=pod

=head2 get_gpg

my $gpgconf = $conf->get_gpg;

Returns GPG configuration.

=cut
sub get_gpg {
	my $self = shift;
	return $self->{'gpg'};
}

=pod

=head2 get_database

my $dbconf = $conf->get_database;

Returns database (backend) configuration.

=cut
sub get_database {
	my $self = shift;
	return $self->{'database'};
}

=pod

=head2 get_users

my $userconf = $conf->get_users;

Returns users configuration.

=cut
sub get_users {
	my $self = shift;
	return $self->{'users'};
}

=pod

=head2 get_groups

my $groupconf = $conf->get_groups;

Returns groups configuration.

=cut
sub get_groups {
	my $self = shift;
	return $self->{'groups'};
}

=pod

=head2 get_service

my $serviceconf = $conf->get_service( $servicename );

Get a service configuration. If a parameter is given, the configuration of the service
will be returned, otherwise it returns the whole configuration for all services.

=cut
sub get_service {
	my ( $self, $service ) = @_;
	return $self->{"services"}{$service} if defined $service;
	return $self->{"services"};
}

=pod

=head2 get_service_availability

my $available = $conf->get_service_availability( $servicename );

Get availability of a service (return 1 if open, 0 if closed or unknown).

=cut
sub get_service_availability {
	my ( $self, $service ) = @_;
	return $self->{'services'}{$service}{'activate'};
}

=pod

=head2 get_available_services

my $services = $conf->get_available_services;

Returns an hashref with each entry set to 1 if the associated
service is available.

=cut
sub get_available_services {
	my $self = shift;

	my $result = {};
	foreach(qw/web mysql pgsql cvs svn git mercurial bazaar dns repository mail mailinglist cron/) {
		$result->{$_} = $self->get_service_availability($_);
	}
	return $result;
}

=pod

=head2 get_listengine

my $listengineconf = $conf->get_listengine;

Returns Listengine configuration.

=cut
sub get_listengine {
	my $self = shift;
	return $self->{'listengine'};
}

=pod

=head2 get_robots

my $robotsconf = $conf->get_robots;

Returns robots configuration.

=cut
sub get_robots {
	my $self = shift;
	return $self->{'robots'};
}

=pod

=head2 get_irc

my $ircconf = $conf->get_irc;

Returns IRC configuration.

=cut
sub get_irc {
	my $self = shift;
	return $self->{'irc'};
}

=pod
=head1 GET GLOBAL PARAMETERS
=cut

=pod

=head2 get_host_name

my $hostname = $conf->get_host_name;

Returns hosting service name.

=cut
sub get_host_name {
	my $self = shift;
	return $self->{'global'}{'host_name'};
}

=pod

=head2 get_host_website

my $hostwebsite = $conf->get_host_website;

Returns hosting main website URL.

=cut
sub get_host_website {
	my $self = shift;
	return $self->{'global'}{'host_website'};
}

=pod

=head2 get_datadir

my $datadir = $conf->get_datadir;

Returns datadir (such as '/data');

=cut
sub get_datadir {
	my $self = shift;
	return $self->{'global'}{'datadir'};
}

=pod

=head2 get_templatedir

my $templatedir = $conf->get_templatedir;

Returns templates directory (such as '/usr/share/vhffs/templates');

=cut
sub get_templatedir {
	my $self = shift;
	return $self->{'global'}{'templatedir'};
}

=pod

=head2 get_default_language

my $defaultlang = $conf->get_default_language;

Returns default language (such as 'en_US').

=cut
sub get_default_language {
	my $self = shift;
	return $self->{'global'}{'default_language'};
}

=pod

=head2 get_master_mail

my $mastermail = $conf->get_master_mail;

Returns value used as From: in emails sent to users.

=cut
sub get_master_mail {
	my $self = shift;
	return $self->{'global'}{'vhffs_master'};
}

=pod

=head2 get_moderator_mail

my $modomail = $conf->get_moderator_mail;

Returns value used as From: in emails sent to users about moderation.

=cut
sub get_moderator_mail {
	my $self = shift;
	return $self->{'global'}{'vhffs_moderator'};
}

=pod

=head2 get_mailtag

my $mailtag = $conf->get_mailtag;

Returns tag used in subject mails sent by VHFFS.

=cut
sub get_mailtag {
	my $self = shift;
	return $self->{'global'}{'mailtag'};
}

=pod

=head2 get_allow_subscribe

my $allowsub = $conf->get_allow_subscribe;

Returns 1 if users subscription are allowed, otherwise returns 0.

=cut
sub get_allow_subscribe {
	my $self = shift;
	return $self->{'global'}{'allow_subscribe'};
}

=pod

=head2 get_alert_mail

my $alertmail = $conf->get_alert_mail;

Returns value used as To: in mails sent through the panel contact page.

=cut
sub get_alert_mail {
	my $self = shift;
	return $self->{'global'}{'alert_mail'};
}

=pod

=head2 get_moderation

my $use_moderation = $conf->get_moderation;

Returns 1 if objects should be moderated, otherwise returns 0.

=cut
sub get_moderation {
	my $self = shift;
	return $self->{'global'}{'moderation'};
}

=pod

=head2 use_vhffsfs

my $use_vhffsfs = $conf->use_vhffsfs;

Returns 1 if we are using vhffsfs, otherwise returns 0.

=cut
sub use_vhffsfs {
	my $self = shift;
	return $self->{'global'}{'use_vhffsfs'};
}

=pod

=head2 get_available_languages

my @languages = $conf->get_available_languages;

Returns an array of enabled languages.

=cut
sub get_available_languages {
	my $self = shift;
	return split /\s+/, $self->{'global'}{'available_languages'};
}

1;
