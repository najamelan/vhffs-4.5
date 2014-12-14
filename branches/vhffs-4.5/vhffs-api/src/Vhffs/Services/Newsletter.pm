#!%PERL%
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


# This file is a part of VHFFS4 software, a hosting platform suite
# Please respect the licence of this file and whole program

# This module helps you to manage a newsletter to contact your users

use strict;
use utf8;

package Vhffs::Services::Newsletter;

use Vhffs::Services::MailingList;

use constant {
	ACTIVE_OPTIN => 1,
	PASSIVE_OPTIN => 2,
	ACTIVE_OPTOUT => 3,
	PASSIVE_OPTOUT => 4,
	PERMANENT => 5,
};

# Create a new instance of the current class
sub new {
	my $class = shift;
	my $vhffs = shift;
	my $user = shift;

	return undef unless defined $vhffs and defined $user and $vhffs->get_config->get_service_availability('newsletter');
	my $config = $vhffs->get_config->get_service('newsletter');
	return unless defined $config and defined $config->{'mailinglist'};

	# Fetches the mail domain defined in config
	my ( $localpart, $domain ) = ( $config->{'mailinglist'} =~ /(.+)\@(.+)/ );
	my $mailinglist_service = Vhffs::Services::MailingList::get_by_mladdress( $vhffs, $localpart, $domain );
	return unless defined $mailinglist_service;
	$mailinglist_service->fetch_sub( $user->get_mail );

	my $this = {};
	$this->{vhffs} = $vhffs;
	$this->{user} = $user;
	$this->{collectmode} = ACTIVE_OPTIN;
	if( defined $config->{'collectmode'} ) {
		$this->{collectmode} = PASSIVE_OPTIN if $config->{'collectmode'} eq 'passive_optin';
		$this->{collectmode} = ACTIVE_OPTOUT if $config->{'collectmode'} eq 'active_optout';
		$this->{collectmode} = PASSIVE_OPTOUT if $config->{'collectmode'} eq 'passive_optout';
		$this->{collectmode} = PERMANENT if $config->{'collectmode'} eq 'permanent';
	}
	$this->{mailinglist_service} = $mailinglist_service;
	bless( $this, $class );
	return $this;
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->{vhffs}->get_config->get_service('newsletter');
}

sub exists {
	my $self = shift;
	return defined $self->{'mailinglist_service'}->get_members->{ $self->{'user'}->get_mail };
}

sub add {
	my $self = shift;
	return $self->{'mailinglist_service'}->add_sub( $self->{'user'}->get_mail , Vhffs::Constants::ML_RIGHT_SUB );
}

sub del {
	my $self = shift;
	return $self->{'mailinglist_service'}->del_sub( $self->{'user'}->get_mail );
}

sub get_collectmode {
	my $self = shift;
	return $self->{collectmode};
}

1;
