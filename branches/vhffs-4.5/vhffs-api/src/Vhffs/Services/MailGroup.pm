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

# Author : Sylvain Rochet < gradator at gradator dot net >

#This module helps you to manage a simple maildomain
#for all hosted people

use strict;
use utf8;

package Vhffs::Services::MailGroup;

use DBI;
use Vhffs::Group;
use Vhffs::Services::Mail;


# Create a new instance of the current class
sub new {
	my $class = shift;
	my $vhffs = shift;
	my $group = shift;

	return unless defined $vhffs and defined $group and $vhffs->get_config->get_service_availability('mailgroup');
	my $config = $vhffs->get_config->get_service('mailgroup');

	# Fetches the mail domain defined in config
	my $mail = Vhffs::Services::Mail::get_by_mxdomain( $vhffs, $config->{domain} );
	return unless defined $mail;

	# Fetch only the localpart we need
	my $lp = $mail->fetch_localpart( $group->get_groupname );	

	my $this = {};
	$this->{vhffs} = $vhffs;
	$this->{group} = $group;
	$this->{mail} = $mail;
	bless( $this, $class );
	return $this;
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->{vhffs}->get_config->get_service('mailgroup');
}

sub use_nospam {
	my $self = shift;
	return $self->{mail}->get_config->{use_nospam};
}

sub use_novirus {
	my $self = shift;
	return $self->{mail}->get_config->{use_novirus};
}

sub get_domain {
	my $self = shift;
	return $self->{mail}->get_domain;
}

sub get_localpart {
	my $self = shift;
	return $self->{mail}->get_localpart( $self->{group}->get_groupname );
}

sub get_redirect {
	my $self = shift;
	my $redirects = $self->{mail}->get_redirects( $self->{group}->get_groupname );
	return unless defined $redirects;
	return ((values %{$redirects})[0]);
}

sub get_box {
	my $self = shift;
	return $self->{mail}->get_box( $self->{group}->get_groupname );
}

sub add_redirect {
	my $self = shift;
	my $remote = shift;
	my $redirect = $self->get_redirect;
	if( defined $redirect ) {
		return unless $redirect->set_redirect( $remote );
		return unless $redirect->commit;
		return $redirect;
	}
	$redirect = $self->{mail}->add_redirect( $self->{group}->get_groupname, $remote );
	$self->delete_box if defined $redirect;
	return $redirect;
}

sub add_box {
	my $self = shift;
	my $password = shift;
	my $box = $self->{mail}->add_box( $self->{group}->get_groupname, $password );
	$self->delete_redirect if defined $box;
	return $box;
}

sub delete_redirect {
	my $self = shift;
	my $redirect = $self->get_redirect;
	return unless defined $redirect;
	return $redirect->delete;
}

sub delete_box {
	my $self = shift;
	my $box = $self->get_box;
	return unless defined $box;
	$box->set_status( Vhffs::Constants::WAITING_FOR_DELETION );
	return $box->commit;
}

sub delete {
	my $self = shift;
	$self->delete_redirect;
	$self->delete_box;
}

1;
