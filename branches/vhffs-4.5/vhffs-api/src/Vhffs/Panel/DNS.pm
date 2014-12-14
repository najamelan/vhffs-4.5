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

use strict;
use utf8;

package Vhffs::Panel::DNS;

use locale;
use Locale::gettext;
use Vhffs::Constants;
use Vhffs::Services::DNS;


sub search_dns {
	my ($vhffs, $name) = @_;

	my @params;
	my $sql = 'SELECT ns.domain as label, g.groupname as owner_group, o.state, u.username as owner_user '.
	  'FROM vhffs_dns ns '.
	  'INNER JOIN vhffs_object o ON (o.object_id = ns.object_id) '.
	  'INNER JOIN vhffs_groups g ON (g.gid = o.owner_gid) '.
	  'INNER JOIN vhffs_users u ON (u.uid = o.owner_uid) ';

	if( defined $name ) {
		$sql .= 'WHERE ns.domain LIKE ? ';
		push(@params, '%'.lc($name).'%');
	}

	$sql .= 'ORDER BY ns.domain';

	my $dbh = $vhffs->get_db();
	return $dbh->selectall_arrayref($sql, { Slice => {} }, @params);
}

sub create_dns {
	my ( $vhffs , $dns_name, $description , $user , $group ) = @_;
	return undef unless defined $user;
	return undef unless defined $group;

	my $dns = Vhffs::Services::DNS::create( $vhffs , $dns_name, $description, $user , $group );
	return undef unless defined $dns;


	return $dns;
}


#Returns an array which contains | domain_name | object_id (from DNS)
sub getall_dns_per_user {
	my ( $user , $vhffs ) = @_ ;

	return undef if ( ! defined $user );

	my $query = "SELECT ns.domain, ns.object_id FROM vhffs_dns ns, vhffs_acl acl ,vhffs_users WHERE vhffs_users.object_id=acl.oid_src AND acl.oid_dst=ns.object_id AND vhffs_users.username='".$user->{'username'}."'";

	my $request = $vhffs->get_db->prepare( $query ) or return -1;

	return undef if ( $request->execute() <= 0);

	return( $request->fetchrow_arrayref() );
}

=pod

=head2 getall_per_group

	dns = Vhffs::Panel::Dns::getall_per_group($vhffs, $gid);

Returns an array of hashrefs (oid, displayname, active, state (localized string)) of all DNS owned by
a given group.

=cut
sub getall_per_group {
	my ( $vhffs, $gid ) = @_;

	my $dbh = $vhffs->get_db;
	my $sql = 'SELECT ns.object_id AS oid, ns.domain AS displayname, o.state FROM vhffs_dns ns INNER JOIN vhffs_object o ON ns.object_id = o.object_id WHERE o.owner_gid = ? ORDER BY ns.domain';
	my $sth = $dbh->prepare($sql) or return -1;
	$sth->execute($gid) or return -2;
	my $dns = [];
	while(my $d = $sth->fetchrow_hashref) {
		$d->{active} = ($d->{state} == Vhffs::Constants::ACTIVATED);
		$d->{refused} = ($d->{state} == Vhffs::Constants::VALIDATION_REFUSED);
		$d->{state} = Vhffs::Functions::status_string_from_status_id($d->{state});
		push @$dns, $d;
	}
	return $dns;
}

=pod

=head2 delete_record

	eval { Vhffs::Panel::DNS::delete_record($dns, $id, $type); };
	if($@) {
		print "An error occured: $@\n";
	} else {
		print "$type Record deleted\n";
	}

=cut
sub delete_record {
	my ($dns, $id, $type) = @_;
	die() unless defined $dns and defined $id and defined $type;
	die(gettext('You cannot delete NS records on origin')."\n") if $type eq 'NS' and defined $dns->{NS}->{$id}->{name} and $dns->{NS}->{$id}->{name} eq '@';
	my $rval = $dns->delete_record($id, $type);
	return 1 if $rval > 0;
	die(gettext('Invalid record')."\n") if $rval == -1;
	die(gettext('Record type doesn\'t exists')."\n") if $rval == -2;
	die(gettext('Record does not exists')."\n") if $rval == -3;
	die(gettext('Database error')."\n") if $rval == -4;
	die(gettext('Unknown error')."\n");
}



=pod

=head2 add_a

	eval { Vhffs::Panel::DNS::add_a($dns, $redirect, $name, $ip); };
	if($@) {
		print "An error occured: $@\n";
	} else {
		print "A Record added\n";
	}

Add a new A resource record to $dns. If $redirect is true, $name points
to default address defined in configuration, else, it points on $ip.

=cut

sub add_a {
	my ($dns, $redirect, $name, $ip) = @_;
	die() unless defined $dns and defined $redirect and defined $name and defined $ip;
	my $rval;
	if($redirect) {
		$rval = $dns->add_a($name);
	} else {
		$rval = $dns->add_a($name, $ip);
	}
	return 1 if $rval > 0;
	die(gettext('Invalid prefix')."\n") if $rval == -1;
	die(gettext('Prefix already exists')."\n") if $rval == -2;
	die(gettext('Unable to find default redirection address, please contact administrators')."\n") if $rval == -3;
	die(gettext('Invalid IP address')."\n") if $rval == -4;
	die(gettext('Database error')."\n") if $rval == -5;
	die(gettext('Unknown error')."\n");
}

sub update_a {
	my ($dns, $id, $ip) = @_;
	die() unless defined $dns and defined $id and defined $ip;
	my $rval = $dns->update_a($id, $ip);
	return 1 if $rval > 0;
	die(gettext('Invalid record')."\n") if $rval == -1;
	die(gettext('Record does not exists')."\n") if $rval == -2;
	die(gettext('Invalid IP address')."\n") if $rval == -3;
	die(gettext('Database error')."\n") if $rval == -4;
	die(gettext('Unknown error')."\n");
}

sub add_aaaa {
	my ($dns, $redirect, $name, $ip) = @_;
	die() unless defined $dns and defined $redirect and defined $name and defined $ip;
	my $rval;
	if($redirect) {
		$rval = $dns->add_aaaa($name);
	} else {
		$rval = $dns->add_aaaa($name, $ip);
	}
	return 1 if $rval > 0;
	die(gettext('Invalid prefix')."\n") if $rval == -1;
	die(gettext('Prefix already exists')."\n") if $rval == -2;
	die(gettext('Unable to find default redirection address, please contact administrators')."\n") if $rval == -3;
	die(gettext('Invalid IP v6 address')."\n") if $rval == -4;
	die(gettext('Database error')."\n") if $rval == -5;
	die(gettext('Unknown error')."\n");
}

sub update_aaaa {
	my ($dns, $id, $ip) = @_;
	die() unless defined $dns and defined $id and defined $ip;
	my $rval = $dns->update_aaaa($id, $ip);
	return 1 if $rval > 0;
	die(gettext('Invalid record')."\n") if $rval == -1;
	die(gettext('Record does not exists')."\n") if $rval == -2;
	die(gettext('Invalid IP address')."\n") if $rval == -3;
	die(gettext('Database error')."\n") if $rval == -4;
	die(gettext('Unknown error')."\n");
}

sub add_mx {
	my ($dns, $name, $host, $priority) = @_;
	die() unless defined $dns and defined $name and defined $host and defined $priority;
	my $rval = $dns->add_mx( $name, $host, $priority);
	return 1 if $rval > 0;
	die(gettext('Invalid hostname')."\n") if $rval == -1;
	die(gettext('Invalid priority')."\n") if $rval == -2;
	die(gettext('An MX record with the same name already exists for this domain')."\n") if($rval == -3);
	die(gettext('Database error')."\n") if $rval == -4;
	die(gettext('Invalid prefix')."\n") if $rval == -5;
	die(gettext('Unknown error')."\n");
}

sub update_mx {
	my ($dns, $id, $host) = @_;
	die() unless defined $dns and defined $id and defined $host;
	my $rval = $dns->update_mx($id, $host);
	return 1 if $rval > 0;
	die(gettext('Invalid record')."\n") if $rval == -1;
	die(gettext('Record does not exists')."\n") if $rval == -2;
	die(gettext('Invalid host')."\n") if $rval == -3;
	die(gettext('Database error')."\n") if $rval == -4;
	die(gettext('Unknown error')."\n"),;
}

sub add_ns {
	my ($dns, $name, $host) = @_;
	die() unless defined $dns and defined $name and defined $host;
	die(gettext('You cannot add NS records on origin')."\n") if $name eq '@';
	my $rval = $dns->add_ns($name, $host);
	return 1 if $rval > 0;
	die(gettext('Invalid hostname')."\n") if $rval == -1;
	die(gettext('An NS record with the same name already exists for this domain')."\n") if $rval == -2;
	die(gettext('Database error')."\n") if $rval == -3;
	die(gettext('Invalid prefix')."\n") if $rval == -5;
	die(gettext('Unknown error')."\n");
}

sub update_cname {
	my ($dns, $id, $dest) = @_;
	die() unless defined $dns and defined $id and defined $dest;
	my $rval = $dns->update_cname($id, $dest);
	return 1 if $rval > 0;
	die(gettext('Invalid record')."\n") if $rval == -1;
	die(gettext('Record does not exists')."\n") if $rval == -2;
	die(gettext('Invalid destination')."\n") if $rval == -3;
	die(gettext('Database error')."\n") if $rval == -4;
	die(gettext('Unknown error')."\n");

}

sub add_cname {
	my ($dns, $name, $dest) = @_;
	die() unless defined $dns and defined $name and defined $dest;
	my $rval = $dns->add_cname($name, $dest);
	return 1 if $rval > 0;
	die(gettext('Invalid alias')."\n") if $rval == -1;
	die(gettext('Invalid destination host')."\n") if $rval == -2;
	die(gettext('A CNAME, A or AAAA record with the same name already exists for this domain')."\n") if $rval == -3;
	die(gettext('Database error')."\n") if $rval == -4;
	die(gettext('Unknown error')."\n");
}

sub add_srv {
	my ($dns, $name, $proto, $svc, $host, $port, $priority, $weight) = @_;
	die() unless defined $dns and defined $name and defined $proto and defined $svc and defined $host and defined $port and defined $priority and defined $weight;
	my $rval = $dns->add_srv($name, $proto, $svc, $host, $port, $priority, $weight);
	return 1 if $rval > 0;
	die(gettext('Invalid protocol syntax')."\n") if $rval == -1;
	die(gettext('Invalid service syntax')."\n") if $rval == -2;
	die(gettext('Invalid destination domain name')."\n") if $rval == -3;
	die(gettext('Invalid port')."\n") if $rval == -4;
	die(gettext('Invalid priority')."\n") if $rval == -5;
	die(gettext('Invalid weight')."\n") if $rval == -6;
	die(gettext('Invalid record')."\n") if $rval == -7;
	die(gettext('This host is already registered for this service')."\n") if $rval == -8;
	die(gettext('Database error')."\n") if $rval == -9;
	die(gettext('Unknown error')."\n");
}

sub update_srv {
	my ($dns, $id, $host, $port, $priority, $weight) = @_;
	die() unless defined $dns and defined $host and defined $port and defined $priority and defined $weight;
	my $rval = $dns->update_srv($id, $host, $port, $priority, $weight);
	return 1 if $rval > 0;
	die(gettext('Invalid record')."\n") if $rval == -1;
	die(gettext('Record does not exists')."\n") if $rval == -2;
	die(gettext('Invalid destination domain name')."\n") if $rval == -3;
	die(gettext('Invalid port')."\n") if $rval == -4;
	die(gettext('Invalid priority')."\n") if $rval == -5;
	die(gettext('Invalid weight')."\n") if $rval == -6;
	die(gettext('Database error')."\n") if $rval == -7;
	die(gettext('Unknown error')."\n");
}

sub add_txt {
	my ($dns, $name, $txt) = @_;
	die() unless defined $dns and defined $name and defined $txt;
	my $rval = $dns->add_txt($name, $txt);
	return 1 if $rval > 0;
	die(gettext('Invalid prefix')."\n") if $rval == -1;
	die(gettext('Text can\'t be empty')."\n") if $rval == -2;
	die(gettext('A TXT record with the same name already exists for this domain')."\n") if $rval == -3;
	die(gettext('Database error')."\n") if $rval == -4;
	die(gettext('Unknown error')."\n");
}

sub update_txt {
	my ($dns, $id, $txt) = @_;
	die() unless defined $dns and defined $id and defined $txt;
	my $rval = $dns->update_txt($id, $txt);
	return 1 if $rval > 0;
	die(gettext('Invalid record')."\n") if $rval == -1;
	die(gettext('Record does not exists')."\n") if $rval == -2;
	die(gettext('Text can\'t be empty')."\n") if $rval == -3;
	die(gettext('Database error')."\n") if $rval == -4;
	die(gettext('Unknown error')."\n"),;
}

sub create {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined $group and $user->can_modify( $group ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}
	$panel->set_group( $group );

	my $submitted = defined($cgi->param('dns_submit'));
	my $domain_name = '';
	my $description = '';
	my $vars = {};

	if( $submitted ) {
		$domain_name = $cgi->param('DOMAIN_NAME');
		$description = Encode::decode_utf8( scalar $cgi->param('DESCRIPTION') );

		unless( defined $domain_name and defined $description ) {
			$panel->add_error( gettext('CGI Error !') );
		} else {
			$panel->add_error( gettext('Invalid domain name') ) unless Vhffs::Functions::check_domain_name($domain_name);
			$panel->add_error( gettext('You must enter a description') ) unless $description !~ /^\s*$/;
		}

		unless( $panel->has_errors() ) {
			my $dns = Vhffs::Panel::DNS::create_dns( $vhffs, $domain_name, $description, $user, $group );
			if( defined $dns ) {
				my $url = '?do=groupview;group='.$group->get_groupname.';msg='.gettext('The DNS object was successfully created !');
				$panel->redirect($url);
				return;
			}

			$panel->add_error( gettext('An error occured while creating the object. The domain is not correct or aleady exists in Vhffs database') );
		}

		$vars->{domain} = $domain_name;
		$vars->{description} = $description;
	}

	my $conf = $vhffs->get_config->get_service('dns');
	$vars->{group} = $group;
	$vars->{ns} = $conf->{init}{ns};
	$vars->{help_url} = $conf->{url_doc};
	$panel->render('dns/create.tt', $vars);
}

sub prefs {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $domain_name = $cgi->param('name');
	unless( defined $domain_name ) {
		$panel->render('misc/message.tt', { message => gettext( 'CGI Error !' ) } );
		return;
	}

	my $dns = Vhffs::Services::DNS::get_by_domainname( $vhffs , $domain_name );
	unless( defined $dns ) {
		$panel->render('misc/message.tt', { message => gettext('Cannot get informations on this object') } );
		return;
	}
	$panel->set_group( $dns->get_group );

	unless( $user->can_view( $dns ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) } );
		return;
	}

	my $thirdtemplate;
	my $template;
	my $output = "";
	my $message;

	my $action = $cgi->param('action');

	ACTION: {
		if(defined $action) {

			# Check user's rights
			unless( $user->can_modify( $dns ) ) {
				$panel->add_error( gettext( 'You\'re not allowed to do this, object is not in active state or you don\'t have enough ACL rights' ) );
				last ACTION;
			}

			my $id = $cgi->param('rr_id');
			my $data = $cgi->param('data');
			my $namerr = $cgi->param('namerr');
			my $aux = $cgi->param('aux');

			if($action eq 'manage_a') {
				if(defined $cgi->param('modify_a_submit')) {
					# User just want to modify an A record
					eval { Vhffs::Panel::DNS::update_a($dns, $id, $data); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to modify A record: %s'), $@)); }
					else { $panel->add_info(gettext('A Record updated')); }
				} else {
					# User wants to delete it
					eval { Vhffs::Panel::DNS::delete_record($dns, $id, 'A'); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to delete A record: %s'), $@)); }
					else { $panel->add_info(gettext('A Record deleted')); }
				}
			} elsif($action eq 'manage_aaaa') {
				if(defined $cgi->param('modify_aaaa_submit')) {
					# User just want to modify an AAAA record
					eval { Vhffs::Panel::DNS::update_aaaa($dns, $id, $data); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to modify AAAA record: %s'), $@)); }
					else { $panel->add_info(gettext('AAAA Record updated')); }
				} else {
					# User wants to delete it
					eval { Vhffs::Panel::DNS::delete_record($dns, $id, 'AAAA'); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to delete AAAA record: %s'), $@)); }
					else { $panel->add_info(gettext('AAAA Record deleted')); }
				}
			} elsif($action eq 'add_aaaa') {
				my $redirect = $cgi->param('redirect');
				eval { Vhffs::Panel::DNS::add_aaaa($dns, (defined $redirect && $redirect eq 'true'), $namerr, $data); };
				if($@) { $panel->add_error(sprintf(gettext('Unable to add AAAA record: %s'), $@)); }
				else { $panel->add_info(gettext('AAAA record added')); }
			} elsif($action eq 'add_a') {
				my $redirect = $cgi->param('redirect');
				eval { Vhffs::Panel::DNS::add_a($dns, (defined $redirect && $redirect eq 'true'), $namerr, $data); };
				if($@) { $panel->add_error(sprintf(gettext('Unable to add A record: %s'), $@)); }
				else { $panel->add_info(gettext('A record added')); }
			} elsif($action eq 'manage_mx') {
				if(defined $cgi->param('modify_mx_submit')) {
					# User wants to modify an MX record
					eval { Vhffs::Panel::DNS::update_mx($dns, $id, $data); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to modify MX record: %s'), $@)); }
					else { $panel->add_info(gettext('MX Record updated')); }
				} else {
					# MX deletion
					eval { Vhffs::Panel::DNS::delete_record($dns, $id, 'MX'); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to delete MX record: %s'), $@)); }
					else { $panel->add_info(gettext('MX Record deleted')); }
				}
			} elsif($action eq 'add_mx') {
				eval { Vhffs::Panel::DNS::add_mx($dns, $namerr, $data, $aux); };
				if($@) { $panel->add_error(sprintf(gettext('Unable to add MX record: %s'), $@)); }
				else { $panel->add_info(gettext('MX Record added')); }
			} elsif($action eq 'manage_ns') {
				# Only deletion is allowed for NS record
				eval { Vhffs::Panel::DNS::delete_record($dns, $id, 'NS'); };
				if($@) { $panel->add_error(sprintf(gettext('Unable to delete NS record: %s'), $@)); }
				else { $panel->add_info(gettext('NS Record deleted')); }
			} elsif($action eq 'add_ns') {
				eval { Vhffs::Panel::DNS::add_ns($dns, $namerr, $data); };
				if($@) { $panel->add_error(sprintf(gettext('Unable to add NS record: %s'), $@)); }
				else { $panel->add_info(gettext('NS Record added')); }
			} elsif($action eq 'manage_cname') {
				if(defined $cgi->param('modify_cname_submit')) {
					eval { Vhffs::Panel::DNS::update_cname($dns, $id, $data); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to modify CNAME record: %s'), $@)); }
					else { $panel->add_info(gettext('CNAME Record updated')); }
				} else {
					eval { Vhffs::Panel::DNS::delete_record($dns, $id, 'CNAME'); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to delete CNAME record: %s'), $@)); }
					else { $panel->add_info(gettext('CNAME Record deleted')); }
				}
			} elsif($action eq 'add_cname') {
				eval { Vhffs::Panel::DNS::add_cname($dns, $namerr, $data); };
				if($@) { $panel->add_error(sprintf(gettext('Unable to add CNAME record: %s'), $@)); }
				else { $panel->add_info(gettext('CNAME Record added')); }
			} elsif($action eq 'manage_srv') {
				if(defined $cgi->param('modify_srv_submit')) {
					my $host = $cgi->param('host');
					my $port = $cgi->param('port');
					my $weight = $cgi->param('weight');
					eval { Vhffs::Panel::DNS::update_srv($dns, $id, $host, $port, $aux, $weight); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to modify SRV record: %s'), $@)); }
					else { $panel->add_info(gettext('SRV Record updated')); }
				} else {
					eval { Vhffs::Panel::DNS::delete_record($dns, $id, 'SRV'); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to delete SRV record: %s'), $@)); }
					else { $panel->add_info(gettext('SRV Record deleted')); }
				}
			} elsif($action eq 'add_srv') {
				my $proto = $cgi->param('protocol');
				my $svc = $cgi->param('service');
				my $host = $cgi->param('host');
				my $port = $cgi->param('port');
				my $aux = $cgi->param('aux');
				my $weight = $cgi->param('weight');
				eval { Vhffs::Panel::DNS::add_srv($dns, $namerr, $proto, $svc, $host, $port, $aux, $weight); };
				if($@) { $panel->add_error(sprintf(gettext('Unable to add SRV record: %s'), $@)); }
				else { $panel->add_info(gettext('SRV Record added')); }
			} elsif($action eq 'add_txt') {
				eval { Vhffs::Panel::DNS::add_txt($dns, $namerr, $data); };
				if($@) { $panel->add_error(sprintf(gettext('Unable to add TXT record: %s'), $@)); }
				else { $panel->add_info(gettext('TXT Record added')); }
			} elsif($action eq 'manage_txt') {
				if(defined $cgi->param('modify_txt_submit')) {
					# User wants to modify an TXT record
					eval { Vhffs::Panel::DNS::update_txt($dns, $id, $data); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to modify TXT record: %s'), $@)); }
					else { $panel->add_info(gettext('TXT Record updated')); }
				} else {
					# TXT deletion
					eval { Vhffs::Panel::DNS::delete_record($dns, $id, 'TXT'); };
					if($@) { $panel->add_error(sprintf(gettext('Unable to delete TXT record: %s'), $@)); }
					else { $panel->add_info(gettext('TXT Record deleted')); }
				}
			}
		}
	}

	my $vars = { dns => $dns };
	my @sorted_a = sort {$a->{name} cmp $b->{name}} values(%{$dns->get_a_type});
	my @sorted_aaaa = sort {$a->{name} cmp $b->{name}} values(%{$dns->get_aaaa_type});
	my @sorted_mx = sort {$a->{aux} <=> $b->{aux}} values(%{$dns->get_mx_type});
	my @sorted_cname = sort {$a->{name} cmp $b->{name}} values(%{$dns->get_cname_type});
	my @sorted_ns = sort {$a->{name} cmp $b->{name}} values(%{$dns->get_ns_type});
	my @sorted_srv = sort {$a->{name} cmp $b->{name}} values(%{$dns->get_srv_type});
	my @sorted_txt = sort {$a->{name} cmp $b->{name}} values(%{$dns->get_txt_type});
	$vars->{sorted_a} = \@sorted_a;
	$vars->{sorted_aaaa} = \@sorted_aaaa;
	$vars->{sorted_mx} = \@sorted_mx;
	$vars->{sorted_cname} = \@sorted_cname;
	$vars->{sorted_ns} = \@sorted_ns;
	$vars->{sorted_srv} = \@sorted_srv;
	$vars->{sorted_txt} = \@sorted_txt;

	$panel->set_title(sprintf(gettext("DNS Administration - %s"), $domain_name));
	$panel->render('dns/prefs.tt', $vars);
}

sub index {
	my $panel = shift;

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $group = Vhffs::Group::get_by_groupname( $vhffs , scalar $cgi->param('group') );
	unless( defined($group) ) {
		$panel->render('misc/message.tt', { message => gettext('You have to select a group first') } );
		return;
	}

	unless($group->get_status == Vhffs::Constants::ACTIVATED) {
		$panel->render( 'misc/message.tt', { message => gettext('This group is not activated yet') } );
		return;
	}

	unless( $user->can_view( $group ) ) {
		$panel->render('misc/message.tt', { message => gettext( 'You\'re not allowed to do this (ACL rights)' ) } );
		return;
	}

	$panel->set_group( $group );
	$panel->set_title( sprintf(gettext('Domain names for %s'), $group->get_groupname) );
	my $dns = Vhffs::Panel::DNS::getall_per_group( $vhffs, $group->get_gid );
	if($dns < 0) {
		$panel->render('misc/message.tt', { message => gettext('Unable to get DNS') } );
		return;
	}

	$panel->render( 'misc/service-index.tt', {
	  label => 'Domain names',
	  group => $group,
	  list => $dns,
	  help_url => $vhffs->get_config->get_service('dns')->{url_doc},
	  type => 'dns'
	  });
}

sub search {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	my $name = $cgi->param('name');
	my $vars = {};

	unless( defined $name ) {

		$panel->render('admin/misc/search.tt', {
		  search_title => gettext('DNS search'),
		  type => 'dns'
		  });
		return;
	}

	if( $name =~ /^\s*$/ ) {
		$vars->{list_title} = gettext('List of all DNS');
		undef $name;
	} else {
		$vars->{list_title} = sprintf( gettext('Search result for %s'), $name );
	}
	$vars->{list} = search_dns( $vhffs , $name );
	$vars->{type} = 'dns';
	$panel->render('admin/misc/list.tt', $vars);
}

sub adminindex {
	my $panel = shift;
	return unless $panel->check_modo();

	my $vhffs = $panel->{'vhffs'};
	my $cgi = $panel->{'cgi'};
	my $session = $panel->{'session'};
	my $user = $panel->{'user'};

	$panel->set_title(gettext('DNS administration'));
	require Vhffs::Panel::Admin;
	$panel->render('admin/index.tt', { categories => [ Vhffs::Panel::Admin::get_dns_category() ] } );
}


1;
