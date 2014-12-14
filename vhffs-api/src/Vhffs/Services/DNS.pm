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

=pod

=head1 NAME

Vhffs::Services::DNS - Handles domain name related stuff in VHFFS

=head1 SYNOPSIS

TODO

=head1 METHODS

=cut

use strict;
use utf8;

package Vhffs::Services::DNS;

use base qw(Vhffs::Object);
use DBI;

sub check_rr_name {
	my $name = shift;
	return ($name =~ /^(?:(?:[a-z0-9\-\_\*]{1,63}(?:\.[a-z0-9\-\_]{1,63})*)|@)$/ );
}

sub _new {
	my ($class, $vhffs, $dns_id, $domain, $owner_gid, $ns, $mbox, $serial, $refresh, $retry, $expire, $minimum, $ttl, $oid, $owner_uid, $date_creation, $state, $description, $a, $nsr, $cname, $mx, $srv, $aaaa, $txt) = @_;

	my $self = $class->SUPER::_new($vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_DNS);

	$self->{dns_id} = $dns_id;
	$self->{domain} = $domain;
	$self->{ns} = $ns;
	$self->{mbox} = $mbox;
	$self->{serial} = $serial;
	$self->{refresh} = $refresh;
	$self->{retry} = $retry;
	$self->{expire} = $expire;
	$self->{minimum} = $minimum;
	$self->{ttl} = $ttl;
	$self->{A} = $a;
	$self->{NS} = $nsr;
	$self->{CNAME} = $cname;
	$self->{MX} = $mx;
	$self->{SRV} = $srv;
	$self->{AAAA} = $aaaa;
	$self->{TXT} = $txt;

	return $self;
}

=pod

=head2 create

	my $dns = Vhffs::Services::DNS::create($vhffs, $domain, $description, $user, $group);
	die('Unable to create DNS') unless(defined $dns);

Create a new DNS in database and returns the corresponding object.
If the init section of the VHFFS config is filled, use it to add initial A, MX and NS records.

=cut
sub create {
	my($vhffs, $domain, $description, $user, $group) = @_;

	my $conf = $vhffs->get_config->get_service('dns');
	return undef unless defined $conf;


	return undef unless(defined($user) && defined($group));
	return undef unless(Vhffs::Functions::check_domain_name($domain));

	my $dbh = $vhffs->get_db();
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;
	my $self;

	eval {

		my $parent = Vhffs::Object::create($vhffs, $user->get_uid, $group->get_gid, $description, undef, Vhffs::Constants::TYPE_DNS);

		die('Unable to create parent object') unless(defined $parent);

		my $sql = 'INSERT INTO vhffs_dns (domain, object_id, ns, mbox, serial, refresh, retry, expire, minimum, ttl) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)';
		my ($day, $month, $year);
		(undef,undef,undef,$day,$month,$year) = localtime(time);
		my $serial = sprintf('%.4u%.2u%.2u01',$year+1900,$month+1,$day);

		my $sth = $dbh->prepare($sql);

		$sth->execute($domain, $parent->get_oid, $conf->{init}->{soa}->{ns}, $conf->{init}->{soa}->{mbox}, $serial,
			$conf->{init}->{soa}->{refresh}, $conf->{init}->{soa}->{retry}, $conf->{init}->{soa}->{expire}, $conf->{init}->{soa}->{minimum}, $conf->{init}->{soa}->{ttl} );

		$dbh->commit;
		$self = get_by_domainname($vhffs, $domain);
	};

	# Something went wrong, let's cancel everything
	if($@) {
		warn 'Error creating domain '.$domain.': '.$@."\n";
		$dbh->rollback;
		return undef;
	}

	# Fill in default information defined in configuration.
	if( defined $conf->{init} ) {
		my ($ip, $name, $prio);
		my $init = $conf->{init};

		if( defined $init->{a} ) {
			foreach( keys %{$init->{a}} ) {
				$name = $_;
				$ip = $init->{a}{$_};
				$self->add_a( $name , $ip );
			}
		}
		if( defined $init->{mx} ) {
			foreach( keys %{$init->{mx}} ) {
				$prio = $_;
				$ip = $init->{mx}{$_};
				$self->add_mx( '@', $ip , $prio );
			}
		}
		if( defined $init->{ns} ) {
			foreach( keys %{$init->{ns}} ) {
				$name = $_;
				$self->add_ns( '@', $name );
			}
		}
	}

	return $self;
}

# Returns an array with ALL the DNS
# If ionly a ref of a Vhffs instance if given, it returns ALL DNS objects
# If a state (of Vhffs::Constants) is given more, it returns all DNS objects which have this state
sub getall {
	my ($vhffs, $state, $name, $group) = @_;

	my $domains = [];
	my @params;
	my $sql = 'SELECT d.domain
		FROM vhffs_dns d INNER JOIN vhffs_object o ON d.object_id = o.object_id';

	if(defined $state) {
		$sql .= ' AND o.state = ?';
		push @params, $state;
	}
	if(defined $name) {
		$sql .= ' AND d.domain LIKE ?';
		push @params, '%'.$name.'%';
	}
	if(defined $group) {
		$sql .= ' AND o.owner_gid = ?';
		push @params, $group->get_gid;
	}
	$sql .= ' ORDER BY d.domain';

	my $dbh = $vhffs->get_db();
	my $sth = $dbh->prepare($sql);
	$sth->execute(@params);
	while(my @d = $sth->fetchrow_array) {
		push @$domains, get_by_domainname($vhffs, $d[0]);
	}

	return $domains;
}

=head2 fill_object

See C<Vhffs::Object::fill_object>.

=cut
sub fill_object {
	my ($class, $obj) = @_;
	my $sql = q{SELECT dns_id, domain, ns, mbox, serial, refresh, retry,
		expire, minimum, ttl FROM vhffs_dns WHERE object_id = ?};
	$obj = $class->SUPER::_fill_object($obj, $sql);

	if($obj->isa('Vhffs::Services::DNS')) {
		my @records = fetch_records($obj->get_db, $obj->{dns_id});
		$obj->{A} = $records[0];
		$obj->{NS} = $records[1];
		$obj->{CNAME} = $records[2];
		$obj->{MX} = $records[3];
		$obj->{SRV} = $records[4];
		$obj->{AAAA} = $records[5];
		$obj->{TXT} = $records[6];
	}

	return $obj;
}

=head2 fetch_records

	my @records = fetch_records($dbh, $dns_id);

Returns an array of hashrefs containing all records for a given zone. The
records are pushed in the following order: A, NS, CNAME, MX, SRV, AAAA, TXT.

Internal module use only.

=cut
sub fetch_records {
	my ($dbh, $dns_id) = @_;
	my @records;
	# Fetches A records
	my $sql = 'SELECT id, zone, (CASE WHEN name = \'\' THEN \'@\' ELSE name END) AS name, type, data, aux, ttl FROM vhffs_dns_rr WHERE zone = ? AND type = \'A\'';
	my $sth = $dbh->prepare($sql);
	$sth->execute($dns_id);
	my $a = $sth->fetchall_hashref('id');
	push @records, $a;

	# Fetches NS records
	$sql = 'SELECT id, zone, (CASE WHEN name = \'\' THEN \'@\' ELSE name END) AS name, type, data, aux, ttl FROM vhffs_dns_rr WHERE zone = ? AND type = ?';
	$sth = $dbh->prepare($sql);
	$sth->execute($dns_id, 'NS');
	my $ns = $sth->fetchall_hashref('id');
	push @records, $ns;

	# Fetches CNAME records
	$sql = 'SELECT id, zone, (CASE WHEN name = \'\' THEN \'@\' ELSE name END) AS name, type, data, aux, ttl FROM vhffs_dns_rr WHERE zone = ? AND type = ?';
	$sth = $dbh->prepare($sql);
	$sth->execute($dns_id, 'CNAME');
	my $cname = $sth->fetchall_hashref('id');
	push @records, $cname;

	# Fetches MX records
	$sql = 'SELECT id, zone, (CASE WHEN name = \'\' THEN \'@\' ELSE name END) AS name, type, data, aux, ttl FROM vhffs_dns_rr WHERE zone = ? AND type = ?';
	$sth = $dbh->prepare($sql);
	$sth->execute($dns_id, 'MX');
	my $mx = $sth->fetchall_hashref('id');
	push @records, $mx;

	# Fetches SRV records
	$sql = 'SELECT id, zone, name, type, data, aux, ttl FROM vhffs_dns_rr WHERE zone = ? AND type = ?';
	$sth = $dbh->prepare($sql);
	$sth->execute($dns_id, 'SRV');
	my $srv = {};
	while(my $rr = $sth->fetchrow_hashref('NAME_lc')) {
		my @fields = split(/ /, $rr->{data});
		$rr->{weight} = shift(@fields);
		$rr->{port} = shift(@fields);
		$rr->{host} = join(' ', @fields);
		delete $rr->{data};
		$srv->{$rr->{id}} = $rr;
	}
	push @records, $srv;

	# Fetches AAAA records
	$sql = 'SELECT id, zone, (CASE WHEN name = \'\' THEN \'@\' ELSE name END) AS name, type, data, aux, ttl FROM vhffs_dns_rr WHERE zone = ? AND type = ?';
	$sth = $dbh->prepare($sql);
	$sth->execute($dns_id, 'AAAA');
	my $aaaa = $sth->fetchall_hashref('id');
	push @records, $aaaa;

	# Fetches TXT records
	$sql = 'SELECT id, zone, (CASE WHEN name = \'\' THEN \'@\' ELSE name END) AS name, type, data, aux, ttl FROM vhffs_dns_rr WHERE zone = ? AND type = ?';
	$sth = $dbh->prepare($sql);
	$sth->execute($dns_id, 'TXT');
	my $txt = $sth->fetchall_hashref('id');
	push @records, $txt;

	return @records;
}

=head2 get_by_domainname

	my $dns = Vhffs::Services::DNS::get_by_domainname($vhffs, $domainname);
	die('Domain not found') unless(defined $dns);

Fetches the DNS object whose domainname is $domainname. Returned object is fully
functionnal. A, NS, CNAME, I<etc.> records are filled and accessible using
C<$dns->get_xxx_type>.

=cut
sub get_by_domainname($$) {
	my ($vhffs, $name) = @_;

	my $sql = 'SELECT d.dns_id, d.domain, o.owner_gid, d.ns, d.mbox, d.serial, d.refresh, d.retry, d.expire, d.minimum, d.ttl, o.object_id, o.owner_uid, o.date_creation, o.state, o.description FROM vhffs_dns d INNER JOIN vhffs_object o ON o.object_id = d.object_id WHERE d.domain = ?';

	my $dbh = $vhffs->get_db();
	my @params;
	return undef unless(@params = $dbh->selectrow_array($sql, undef, $name));
	my $dns_id = $params[0];

	push @params, fetch_records($dbh, $dns_id);

	return _new Vhffs::Services::DNS($vhffs, @params);
}

=pod

=head2 name_exists

	print 'A rr with the same name already exists in type A or CNAME' if($dns->name_exists($name, 'A', 'CNAME'));

Tests if a name already exists in given record types. Returns true if the name already exists
false otherwise.

=cut
sub name_exists {
	my $self = shift;
	my $name = shift;
	my @types = @_;
	my $dbh = $self->get_db;
	my $in = '?'.(', ?' x (scalar(@types) - 1));
	my $sql = 'SELECT id FROM vhffs_dns_rr WHERE name = ? AND zone = ? AND type IN('.$in.') LIMIT 1';
	return ($dbh->do($sql, undef, $name, $self->{dns_id}, @types) != 0);
}

=pod

=head2 delete_record

	die("Unable to delete $type record #$id") unless($dns->delete_record($id, $type) > 0);

Delete record of type C<$type> whose id is C<$id>.

=cut
sub delete_record {
	my ($self, $id, $type) = @_;

	return -1 unless($id =~ /^\d+$/ );
	return -2 unless(exists $self->{$type});
	my $rr = $self->{$type}{$id};
	return -3 unless(defined $rr);

	my $dbh = $self->get_db;
	my $sql = 'DELETE FROM vhffs_dns_rr WHERE id = ? AND type = ? AND zone = ?';
	$dbh->do($sql, undef, $id, $type, $self->{dns_id}) or return -3;

	$self->add_history('Deleted '.$type.' record '.$rr->{name});
	delete $self->{$type}{$id};

	#Update SOA
	$self->update_serial();
	return 1;
}

sub update_a {
	my ( $self , $id, $ip, $ttl ) = @_;

	return -1 unless($id =~ /^\d+$/ );
	my $rr = $self->{A}{$id};
	return -2 unless(defined $rr);
	return -3 unless( Vhffs::Functions::check_ip($ip) );
	$ttl = $rr->{ttl} unless(defined $ttl and $ttl =~ /^\d+$/);

	my $dbh = $self->get_db;
	my $sql = 'UPDATE vhffs_dns_rr SET data = ?, ttl = ? WHERE id = ? AND zone = ? AND type = \'A\'';
	$dbh->do($sql, undef, $ip, $ttl, $id, $self->{dns_id}) or return -4;

	$rr->{data} = $ip;

	$self->add_history('Updated A record '.$rr->{name}.' pointing now on '.$ip.' (TTL '.$ttl.')');

	$self->update_serial();
	return 1;
}

sub add_ns {
	my ($self, $name, $host, $ttl) = @_;

	$ttl = 900 unless defined $ttl;
	return -5 unless check_rr_name($name);
	$name = '' if $name eq '@';

	return -1 unless( Vhffs::Functions::check_domain_name($host) || ( $host =~ /[a-z0-9\-]{1,63}/ ) );

	my $sql = 'SELECT * FROM vhffs_dns_rr WHERE zone=? AND type=\'NS\' AND name=? AND data=?';
	my $dbh = $self->get_db;
	return -2 if($dbh->do($sql, undef, $self->{dns_id}, $name, $host) != 0);

	$sql = 'INSERT INTO vhffs_dns_rr(zone, name, type, data, aux, ttl) VALUES(?, ?, \'NS\', ?, 0, ?)';
	$dbh->do($sql, undef, $self->{dns_id}, $name, $host, $ttl) or return -3;

	my $id = $dbh->last_insert_id(undef, undef, 'vhffs_dns_rr', undef);

	my $ns = {id => $id,
		zone => $self->{dns_id},
		name => $name,
		type => 'NS',
		data => $host,
		aux => 0,
		ttl => $ttl
		};
	$self->{NS}{$id} = $ns;

	$self->update_serial;

	$self->add_history('Added a NS record with name '.($name or '@').' pointing to '.$host);
	return $id;
}

sub add_a {
	my ( $self , $name , $ip , $ttl ) = @_;

	$ttl = 900 unless defined $ttl;
	return -1 unless check_rr_name($name);
	$name = '' if $name eq '@';
	return -2 if ( $self->name_exists( $name, 'A', 'CNAME' ) != 0 );

	unless( defined $ip ) {
		my $dnsconfig = $self->get_config;
		if( defined $dnsconfig->{'default_a'} ) {
		    $ip = $dnsconfig->{'default_a'};
		} else {
		    return -3;
		}
	}

	return -4 unless( Vhffs::Functions::check_ip($ip) );

	my $dbh = $self->get_db;
	my $sql = 'INSERT INTO vhffs_dns_rr (zone, name, type, data, aux, ttl) VALUES(?, ?, \'A\', ?, 0, ?)';
	$dbh->do($sql, undef, $self->{dns_id}, $name, $ip, $ttl) or return -5;

	my $id = $dbh->last_insert_id(undef, undef, 'vhffs_dns_rr', undef);
	$name = '@' if($name eq '');
	my $a = {id => $id,
		zone => $self->{dns_id},
		name => $name,
		type => 'A',
		data => $ip,
		aux => 0,
		ttl => $ttl
		};
	$self->{A}{$id} = $a;

	$self->update_serial();

	$self->add_history('Added a A TYPE with name '.$name.' pointing on '.$ip);
	return $id;
}

=pod

=head2 update_mx

	$dns->update_mx($rr_id, $host[, $priority, $ttl]);

Replace address for MX record C<$rr_id>.

=cut
sub update_mx {
	my ($self, $id, $host, $priority, $ttl) = @_;

	return -1 unless($id =~ /^\d+$/);
	my $rr = $self->{MX}{$id};
	$priority = $rr->{aux} unless(defined $priority and $priority =~ /^\d+$/);
	$ttl = $rr->{ttl} unless(defined $ttl and $ttl =~ /^\d+$/);
	return -2 unless(defined $rr);
	return -3 unless( Vhffs::Functions::check_domain_name($host, 1) || check_rr_name($host) );

	my $sql = 'UPDATE vhffs_dns_rr SET data = ?, aux = ?, ttl = ? WHERE id = ? AND zone = ? AND type=\'MX\'';
	my $dbh = $self->get_db;

	$dbh->do($sql, undef, $host, $priority, $ttl, $id, $self->{dns_id}) or return -4;

	$rr->{data} = $host;

	$self->add_history('Changed the MX for priority '.$rr->{aux}.': '.$host);

	$self->update_serial();
}

sub add_mx {
	my ($self, $name, $host, $priority, $ttl) = @_;

	$ttl = 900 unless defined $ttl;
	$priority = 10 unless defined $priority;
	return -5 unless check_rr_name($name);
	$name = '' if $name eq '@';

	return -1 unless( Vhffs::Functions::check_domain_name($host, 1) || check_rr_name($host) );
	return -2 unless( $priority =~ /^\d+$/ );

	my $sql = 'SELECT id FROM vhffs_dns_rr WHERE zone=? AND type=\'MX\' AND name=? AND data=?';
	my $dbh = $self->get_db;
	return -3 if($dbh->do($sql, undef, $self->{dns_id}, $name, $host) != 0);

	$sql = 'INSERT INTO vhffs_dns_rr(zone, name, type, data, aux, ttl) VALUES(?, ?, \'MX\', ?, ?, ?)';
	$dbh->do($sql, undef, $self->{dns_id}, $name, $host, $priority, $ttl) or return -4;

	my $id = $dbh->last_insert_id(undef, undef, 'vhffs_dns_rr', undef);
	my $mx = {id => $id,
		zone => $self->{dns_id},
		name => $name,
		type => 'MX',
		data => $host,
		aux => $priority,
		ttl => $ttl
		};
	$self->{MX}->{$id} = $mx;

	$self->add_history('Added an MX record, name: '.($name or '@').' - exchanger: '.$host.' - priority: '.$priority);

	$self->update_serial();
	return $id;
}

=pod

=head2 add_srv

	die('Unable to add SRV record') unless($dns->add_srv($protocol, $service, $host, $port, $priority, $weight);

Add a SRV record to the $dns object. C<$protocol> and $service may start with an underscore or not.
See IETF RFC 2782 for more details.

=cut
sub add_srv {
	my ($self, $name, $proto, $svc, $host, $port, $priority, $weight) = @_;
	return -1 unless($proto =~ /^(?:_\w+)|(?:[^_]\w*)$/);
	return -2 unless($svc =~ /^(?:_\w+)|(?:[^_]\w*)$/);
	return -3 unless( Vhffs::Functions::check_domain_name($host, 1) || ( check_rr_name($host) ) );
	return -4 unless($port =~ /^\d+$/ && $port <= 65535 && $port > 0);
	return -5 unless($priority =~ /^\d+$/ && $priority <= 65535 && $priority >= 0);
	return -6 unless($weight =~ /^\d+$/ && $weight <= 65535 && $weight >= 0);
	return -7 unless check_rr_name($name);

	$proto = '_'.$proto unless($proto =~ /^_/);
	$proto = lc($proto);
	$svc = '_'.$svc unless($svc =~ /^_/);
	$svc = lc($svc);
	$name = '' if $name eq '@';
	$name = $svc.'.'.$proto.'.'.$name;
	$name =~ s/\.$//;
	my $data = $weight.' '.$port.' '.$host;


	# Looks if this host is already registered for the same service
	# and the same protocol.
	my $sql = 'SELECT id FROM vhffs_dns_rr WHERE type=\'SRV\' AND name=? AND data LIKE ? AND zone=?';
	my $dbh = $self->get_db;
	return -8 if($dbh->do($sql, undef, $name, '%'.$host, $self->{dns_id}) != 0);

	$sql = 'INSERT INTO vhffs_dns_rr(zone, name, type, data, aux, ttl) VALUES(?, ?, \'SRV\', ?, ?, 900)';
	$dbh->do($sql, undef, $self->{dns_id}, $name, $data, $priority) or return -9;

	my $id = $dbh->last_insert_id(undef, undef, 'vhffs_dns_rr', undef);
	my $srv = {id => $id,
		zone => $self->{dns_id},
		name => $name,
		type => 'SRV',
		host => $host,
		port => $port,
		weight => $weight,
		aux => $priority,
		ttl => 900
		};
	$self->{SRV}->{$id} = $srv;

	$self->add_history('Added an SRV record, '.$name.' -> '.$data.' - priority : '.$priority);

	$self->update_serial();
	return $id;

}

=pod

=head2 update_srv

	die("Unable to update SRV record #$id\n") unless($dns->update_srv($id, $newhost, $newport, $newpriority, $newweight) > 0);

Updates data about SRV resource record which id is C<$id>.

=cut
sub update_srv {
	my ($self, $id, $host, $port, $priority, $weight) = @_;
	return -1 unless($id =~ /^\d+$/);
	my $rr = $self->{SRV}{$id};
	return -2 unless(defined $rr);
	return -3 unless( Vhffs::Functions::check_domain_name($host, 1) || check_rr_name($host) );
	return -4 unless($port =~ /^\d+$/ && $port <= 65535 && $port > 0);
	return -5 unless($priority =~ /^\d+$/ && $priority <= 65535 && $priority >= 0);
	return -6 unless($weight =~ /^\d+$/ && $weight <= 65535 && $weight >= 0);

	my $data = $weight.' '.$port.' '.$host;

	my $sql = 'UPDATE vhffs_dns_rr SET data = ?, aux = ? WHERE id = ? AND zone = ? AND type = \'SRV\'';
	my $dbh = $self->get_db;
	$dbh->do($sql, undef, $data, $priority, $id, $self->{dns_id}) or return -7;

	$rr->{aux} = $priority;
	$rr->{weight} = $weight;
	$rr->{host} = $host;
	$rr->{port} = $port;

	$self->add_history('Updated an SRV record, '.$rr->{name}.' -> '.$data.' - priority : '.$priority);

	$self->update_serial();


}

=pod

=head2 add_aaaa

	die('Unable to add A Record\n') unless($dns->($name, $ip) > 0)

Add an IPv6 AAAA record.

=cut
sub add_aaaa {
	my ( $self , $name , $ip , $ttl ) = @_;

	$ttl = 900 unless defined $ttl;
	return -1 unless check_rr_name($name);
	$name = '' if $name eq '@';
	return -2 if ( $self->name_exists( $name, 'CNAME', 'AAAA' ) != 0 );

	unless( defined $ip ) {
		my $dnsconfig = $self->get_config;
		if( defined $dnsconfig->{'default_aaaa'} ) {
		    $ip = $dnsconfig->{'default_aaaa'};
		} else {
		    return -3;
		}
	}

	return -4 unless( Vhffs::Functions::check_ipv6($ip) );

	my $dbh = $self->get_db;
	my $sql = 'INSERT INTO vhffs_dns_rr (zone, name, type, data, aux, ttl) VALUES(?, ?, \'AAAA\', ?, 0, ?)';
	$dbh->do($sql, undef, $self->{dns_id}, $name, $ip, $ttl) or return -5;

	my $id = $dbh->last_insert_id(undef, undef, 'vhffs_dns_rr', undef);
	$name = '@' if($name eq '');
	my $aaaa = {id => $id,
	zone => $self->{dns_id},
	name => $name,
	type => 'AAAA',
	data => $ip,
	aux => 0,
	ttl => $ttl
	};
	$self->{AAAA}{$id} = $aaaa;

	$self->update_serial();

	$self->add_history('Added a AAAA TYPE with name '.$name.' pointing on '.$ip);
	return $id;
}

=pod

=head2 update_aaaa

	die("Unable to update AAAA record #$id\n") unless($dns->update_aaaa($id, $newip);

Updates IPv6 address for an AAAA record

=cut
sub update_aaaa {
	my ( $self , $id, $ip, $ttl ) = @_;

	return -1 unless($id =~ /^\d+$/ );
	my $rr = $self->{AAAA}{$id};
	return -2 unless(defined $rr);
	return -3 unless( Vhffs::Functions::check_ipv6($ip) );
	$ttl = $rr->{ttl} unless(defined $ttl);

	my $dbh = $self->get_db;
	my $sql = 'UPDATE vhffs_dns_rr SET data = ?, ttl = ? WHERE id = ? AND zone = ? AND type = \'AAAA\'';
	$dbh->do($sql, undef, $ip, $ttl, $id, $self->{dns_id}) or return -4;

	$rr->{data} = $ip;

	$self->add_history('Updated AAAA record '.$rr->{name}.' pointing now on '.$ip);

	$self->update_serial();
	return 1;
}

=pod

=head2 add_txt

	die('Unable to add TXT record') unless($dns->add_txt($prefix, $txt));

Associate text $txt to hostname $prefix.

=cut
sub add_txt {
	my ($self, $name, $data, $ttl) = @_;

	$ttl = 900 unless defined $ttl;
	return -1 unless( check_rr_name($name) );
	$name = '' if( $name eq '@' );
	return -2 if($data =~ /^\s*$/);
	return -3 if ( $self->name_exists( $name, 'TXT', 'CNAME' ) != 0 );

	my $dbh = $self->get_db;
	my $sql = 'INSERT INTO vhffs_dns_rr (zone, name, type, data, aux, ttl) VALUES(?, ?, \'TXT\', ?, 0, ?)';
	$dbh->do($sql, undef, $self->{dns_id}, $name, $data, $ttl) or return -4;

	my $id = $dbh->last_insert_id(undef, undef, 'vhffs_dns_rr', undef);
	$name = '@' if($name eq '');
	my $txt = {id => $id,
		zone => $self->{dns_id},
		name => $name,
		type => 'TXT',
		data => $data,
		aux => 0,
		ttl => $ttl
		};
	$self->{TXT}{$id} = $txt;

	$self->update_serial();

	$self->add_history('Added a TXT record for prefix '.$name.' ('.$txt.')');
	return $id;


}

=pod

=head2 update_txt

	die("Unable to set new value $newtxt for TXT record #$id\n") unless($dns->update_txt($id, $newtxt));

Update data for a TXT record.

=cut
sub update_txt {
	my ($self, $id, $data, $ttl) = @_;

	return -1 unless($id =~ /^\d+$/);
	my $rr = $self->{TXT}{$id};
	return -2 unless(defined $rr);
	return -3 if($data =~ /^\s*$/);
	$ttl = $rr->{ttl} unless(defined $ttl and $ttl =~ /^\d+$/);

	my $sql = 'UPDATE vhffs_dns_rr SET data = ?, ttl = ? WHERE id = ? AND zone = ? AND type=\'TXT\'';
	my $dbh = $self->get_db;

	$dbh->do($sql, undef, $data, $ttl, $id, $self->{dns_id}) or return -4;

	$rr->{data} = $data;

	$self->add_history('Changed the TXT data for '.$rr->{name}.': '.$data);

	$self->update_serial();
}

sub update_cname {
	my ($self, $id, $dest, $ttl) = @_;

	return -1 unless($id =~ /^\d+$/ );
	my $rr = $self->{CNAME}{$id};
	return -2 unless(defined $rr);
	return -3 unless( Vhffs::Functions::check_domain_name($dest, 1) || check_rr_name($dest) );
	$ttl = $rr->{ttl} unless(defined $ttl and $ttl =~ /^\d+$/);

	my $dbh = $self->get_db;
	my $sql = 'UPDATE vhffs_dns_rr SET data = ?, ttl = ? WHERE id = ? AND type = \'CNAME\' AND zone = ?';
	$dbh->do($sql, undef, $dest, $ttl, $id, $self->{dns_id})or return -4;

	$rr->{data} = $dest;

	$self->add_history('Updated CNAME '.$rr->{data}.' pointing now on '.$dest);
	$self->update_serial();
}

sub add_cname {
	my ($self, $name, $dest, $ttl) = @_;

	$ttl = 900 unless defined $ttl;
	return -1 unless( check_rr_name($name) );
	return -2 unless( Vhffs::Functions::check_domain_name($dest, 1) || check_rr_name( $dest ) );
	$name = '' if( $name eq '@' );
	return -3 if ( $self->name_exists( $name, 'A', 'AAAA', 'CNAME' ) != 0 );

	my $dbh = $self->get_db;

	my $sql = 'INSERT INTO vhffs_dns_rr(zone, name, type, data, aux, ttl) VALUES(?, ?, \'CNAME\', ?, 0, ?)';
	$dbh->do($sql, undef, $self->{dns_id}, $name, $dest, $ttl) or return -4;
	my $id = $dbh->last_insert_id(undef, undef, 'vhffs_dns_rr', undef);

	$name = '@' if($name eq '');
	my $cname = {id => $id,
		zone => $self->{dns_id},
		name => $name,
		type => 'CNAME',
		data => $dest,
		aux => 0,
		ttl => $ttl};

	$self->{CNAME}{$id} = $cname;

	$self->add_history('Added a CNAME record ('.$name.' -> '.$dest.')');

	$self->update_serial();
	return $id;
}

# Submit changes to the backend
sub commit {
	my $self = shift;
	return -1 unless ( defined $self && defined $self->{'dns_id'} );

	my $conf = $self->get_config;
	return -1 unless defined $conf;

	#Update the serial to refresh the domain
	$self->{serial} = $self->get_next_serial();

	#First, commit the SOA
	my $request = $self->get_db->prepare( 'UPDATE vhffs_dns SET ns=? , mbox=? , serial=? , refresh=? , retry=? , expire=? , minimum=? , ttl=? WHERE dns_id=?' );
	$request->execute( $self->{'ns'} , $self->{'mbox'} , $self->{'serial'} , $self->{'refresh'} , $self->{'retry'} , $self->{'expire'} , $self->{'minimum'} , $self->{'ttl'} , $self->{'dns_id'} ) or return -2;

	# Commit the object part
	$self->SUPER::commit;
}

sub get_next_serial {
	my $self = shift;
	my ($second,$minutes,$hours,$day,$month,$year) = localtime(time);
	my $newserial = sprintf('%.4u%.2u%.2u',$year+1900,$month+1,$day);

	if( $self->{serial} =~ /^$newserial/  ||  $self->{serial} > $newserial.'01' ) {
		return ($self->{serial} + 1);
	} else {
		return $newserial.'01';
	}
}

sub update_serial {
	my $self = shift;
	my $dbh = $self->get_db;
	$self->{'serial'} = $self->get_next_serial();
	$dbh->do( 'UPDATE vhffs_dns SET serial=? WHERE dns_id=?' , undef, $self->{'serial'}, $self->{'dns_id'} );
}

########################################
# ACCESSORS
########################################

=head2 get_label

See C<Vhffs::Object::get_label>.

=cut
sub get_label {
	my $self = shift;
	return $self->{domain};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_service('dns');
}

sub get_dns_id {
	my $self = shift;
	return $self->{dns_id};
}

sub get_mx_type {
	my $self = shift;
	return $self->{MX};
}

sub get_a_type {
	my $self = shift;
	return $self->{A};
}

sub get_aaaa_type {
	my $self = shift;
	return $self->{AAAA};
}

sub get_cname_type {
	my $self = shift;
	return $self->{CNAME};
}

sub get_ns_type {
	my $self = shift;
	return $self->{NS};
}

sub get_srv_type {
	my $self = shift;
	return $self->{SRV};
}

sub get_txt_type {
	my $self = shift;
	return $self->{TXT};
}

sub get_soa_ns {
	my $self = shift;
	return $self->{'ns'};
}

sub get_soa_mbox {
	my $self = shift;
	return $self->{'mbox'};
}

sub get_soa_serial {
	my $self = shift;
	return $self->{'serial'};
}

sub get_soa_refresh {
	my $self = shift;
	return $self->{'refresh'};
}

sub get_soa_retry {
	my $self = shift;
	return $self->{'retry'};
}

sub get_soa_expire {
	my $self = shift;
	return $self->{'expire'};
}

sub get_soa_minimum {
	my $self = shift;
	return $self->{'minimum'};
}

sub get_soa_ttl {
	my $self = shift;
	return $self->{'ttl'};
}

sub set_soa_ns {
	my $self  = shift;
	my $value = shift;

	$self->{'ns'} = $value;
}

sub set_soa_mbox {
	my $self  = shift;
	my $value = shift;

	$self->{'mbox'} = $value;
}

sub set_soa_serial {
	my $self  = shift;
	my $value = shift;

	$self->{'serial'} = $value;
}

sub set_soa_refresh {
	my $self  = shift;
	my $value = shift;

	$self->{'refresh'} = $value;
}

sub set_soa_retry {
	my $self  = shift;
	my $value = shift;

	$self->{'retry'} = $value;
}

sub set_soa_expire {
	my $self  = shift;
	my $value = shift;

	$self->{'expire'} = $value;
}

sub set_soa_minimum {
	my $self  = shift;
	my $value = shift;

	$self->{'minimum'} = $value;
}

sub set_soa_ttl {
	my $self  = shift;
	my $value = shift;

	$self->{'ttl'} = $value;
}

sub get_domain {
	my $self = shift;
	return $self->{domain};
}

1;
__END__

=head1 AUTHORS

soda < dieu at gunnm dot org >

Sebastien Le Ray < beuss at tuxfamily dot org>
