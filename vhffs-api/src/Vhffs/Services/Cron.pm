#!%PERL%
# Copyright (c) vhffs project and its contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
# 3. Neither the name of vhffs nor the names of its contributors
#    may be used to endorse or promote products derived from this
#    software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# This file is a part of VHFFS4 Hosting Platform
# Please respect the licence of this file and the whole software


=pod

=head1 NAME

Vhffs::Services::Cron - Handle cron jobs in VHFFS

=head1 SYNOPSIS

TODO

=head1 METHODS

=cut

use strict;
use utf8;

package Vhffs::Services::Cron;

use base qw(Vhffs::Object);
use Vhffs::Group;

sub check_cronpath($) {
	my $name = shift;
	return ($name =~ /^\/[a-z0-9]+\/[a-z0-9]+\/[a-zA-Z0-9\.\_\-\/]+$/);
}

sub _new {
	my ($class, $vhffs, $cron_id, $cronpath, $interval, $reportmail, $lastrundate, $lastrunreturncode, $nextrundate, $running, $owner_uid, $owner_gid, $oid, $date_creation, $description, $state) = @_;

	my $self = $class->SUPER::_new($vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_CRON);
	return undef unless(defined $self);

	$self->{cron_id} = $cron_id;
	$self->{cronpath} = $cronpath;
	$self->{interval} = $interval;
	$self->{reportmail} = $reportmail;
	$self->{lastrundate} = $lastrundate;
	$self->{lastrunreturncode} = $lastrunreturncode;
	$self->{nextrundate} = $nextrundate;
	$self->{running} = $running;

	return $self;
}

=pod

=head2 create

	my $cron = Vhffs::Services::Cron::create($vhffs, $rname, $description, $user, $group);
	die('Unable to create cron') unless(defined $cron);

Creates a new cron job in database and return the corresponding
fully functional object.

=cut
sub create {
	my ($vhffs, $cronpath, $interval, $reportmail, $description, $user, $group, ) = @_;

	return undef unless ( defined $cronpath && defined $interval && defined $reportmail && defined $user && defined $group );
	return undef unless check_cronpath($cronpath);
	return undef unless Vhffs::Functions::valid_mail($reportmail);

	my $mininterval = $vhffs->get_config->get_service('cron')->{'minimum_interval'}*60;
	$interval = $mininterval if( $interval < $mininterval );

	my $cron;
	my $dbh = $vhffs->get_db();
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	eval {
		my $parent = Vhffs::Object::create($vhffs, $user->get_uid, $group->get_gid, $description, undef, Vhffs::Constants::TYPE_CRON);
		die('Unable to create parent object') unless(defined $parent);

		my $sql = 'INSERT INTO vhffs_cron(cronpath, interval, reportmail, running, object_id) VALUES(?, ?, ?, 0, ?)';
		my $sth = $dbh->prepare($sql);
		$sth->execute($cronpath, $interval, $reportmail, $parent->get_oid);

		$dbh->commit;
		$cron = get_by_cronpath($vhffs, $cronpath);
	};

	if($@) {
		warn 'Unable to create cron job '.$cronpath.': '.$@."\n";
		$dbh->rollback;
	}

	return $cron;
}

=head2 fill_object

See C<Vhffs::Object::fill_object

=cut
sub fill_object {
	my ($class, $obj) = @_;
	my $sql = q{SELECT cron_id, cronpath, interval, reportmail, lastrundate, lastrunreturncode, nextrundate, running
		FROM vhffs_cron WHERE object_id = ?};
	return $class->SUPER::_fill_object($obj, $sql);
}

sub getall {
	my ($vhffs, $state, $path, $group) = @_;

	my $repos = [];
	my @params;

	my $sql = 'SELECT c.cron_id, c.cronpath, c.interval, c.reportmail, c.lastrundate, c.lastrunreturncode, c.nextrundate, c.running, o.owner_uid, o.owner_gid, o.object_id, o.date_creation, o.description, o.state FROM vhffs_cron c
		INNER JOIN vhffs_object o ON c.object_id = o.object_id';
	if(defined($state)) {
		$sql .= ' AND o.state = ?';
		push(@params, $state);
	}
	if(defined $path) {
		$sql .= ' AND c.cronpath LIKE ?';
		push(@params, '%'.$path.'%');
	}
	if(defined($group)) {
		$sql .= ' AND o.owner_gid = ?';
		push(@params, $group->get_gid);
	}
	$sql .= ' ORDER BY c.cronpath';

	my $dbh = $vhffs->get_db();
	my $sth = $dbh->prepare($sql);
	$sth->execute(@params) or return undef;

	while(my $r = $sth->fetchrow_arrayref()) {
		push(@$repos, _new Vhffs::Services::Cron($vhffs, @$r));
	}
	return $repos;
}

=pod

=head2 get_by_cronpath

	my $repo = Vhffs::Services::Cron::get_by_cronpath($vhffs, $path);
	die('Cron not found') unless(defined $path);

Fetches an existing cron job.

=cut
sub get_by_cronpath($$) {
	my ($vhffs, $path) = @_;

	my @params;

	my $sql = 'SELECT c.cron_id, c.cronpath, c.interval, c.reportmail, c.lastrundate, c.lastrunreturncode, c.nextrundate, c.running, o.owner_uid, o.owner_gid, o.object_id, o.date_creation, o.description, o.state FROM vhffs_cron c
		INNER JOIN vhffs_object o ON o.object_id = c.object_id WHERE c.cronpath = ?';

	my $dbh = $vhffs->get_db();
	return undef unless(@params = $dbh->selectrow_array($sql, undef, $path));

	return _new Vhffs::Services::Cron($vhffs, @params);
}

sub commit {
	my $self = shift;

	my $query = 'UPDATE vhffs_cron SET interval=?, reportmail=?, lastrundate=?, lastrunreturncode=?, nextrundate=?, running=? WHERE cron_id=?';

	my $request = $self->get_db->prepare($query);
	$request->execute( $self->{'interval'} , $self->{'reportmail'} , $self->{'lastrundate'} , $self->{'lastrunreturncode'} , $self->{'nextrundate'} , $self->{'running'} , $self->{'cron_id'} ) or return -1;

	return -2 if( $self->SUPER::commit < 0 );
	return 1;
}

sub get_cron_id {
	my $self = shift;
	return $self->{'cron_id'};
}

sub get_label {
	my $self = shift;
	return $self->{'cronpath'};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_service('cron');
}

sub get_cronpath {
	my $self = shift;
	return $self->{'cronpath'};
}

sub get_name {
	my $self = shift;
	return $self->{'cronpath'};
}

sub get_interval {
	my $self = shift;
	return $self->{'interval'};
}

sub set_interval {
	my ($self, $value) = @_;
	my $mininterval = $self->get_config->{'minimum_interval'}*60;
	$value = $mininterval if( $value < $mininterval );
	$self->{'interval'} = $value;
	return 0;
}

sub get_reportmail {
	my $self = shift;
	return $self->{'reportmail'};
}

sub set_reportmail {
	my ($self, $value) = @_;
	if( $value eq '' || Vhffs::Functions::valid_mail($value) )  {
		$self->{'reportmail'} = $value;
		return 0;
	}
	return 1;
}

sub get_lastrundate {
	my $self = shift;
	return $self->{'lastrundate'};
}

sub set_lastrundate {
	my ($self, $value) = @_;
	if( $value =~ /^\d+$/ )  {
		$self->{'lastrundate'} = $value;
		return 0;
	}
	return 1;
}

sub get_lastrunreturncode {
	my $self = shift;
	return $self->{'lastrunreturncode'};
}

sub set_lastrunreturncode {
	my ($self, $value) = @_;
	if( $value =~ /^\d+$/ )  {
		$self->{'lastrunreturncode'} = $value;
		return 0;
	}
	return 1;
}

sub get_nextrundate {
	my $self = shift;
	return $self->{'nextrundate'};
}

sub set_nextrundate {
	my ($self, $value) = @_;
	if( $value =~ /^\d+$/ )  {
		$self->{'nextrundate'} = $value;
		return 0;
	}
	return 1;
}

sub get_running {
	my $self = shift;
	return $self->{'running'};
}

sub set_running {
	my ($self, $value) = @_;
	if( $value =~ /^\d+$/ )  {
		$self->{'running'} = $value;
		return 0;
	}
	return 1;
}

sub quick_set_running {
	my ($self, $value) = @_;
	return undef unless $value =~ /^\d+$/;
	my $query = 'UPDATE vhffs_cron SET running=? WHERE cron_id=?';
	my $request = $self->get_db->prepare($query);
	return $request->execute( $value , $self->{'cron_id'} );
}

sub quick_inc_running {
	my $self = shift;
	my $query = 'UPDATE vhffs_cron SET running=running+1 WHERE cron_id=?';
	my $request = $self->get_db->prepare($query);
	return $request->execute( $self->{'cron_id'} );
}

sub quick_dec_running {
	my $self = shift;
	my $query = 'UPDATE vhffs_cron SET running=running-1 WHERE cron_id=?';
	my $request = $self->get_db->prepare($query);
	return $request->execute( $self->{'cron_id'} );
}

sub quick_get_running {
	my $self = shift;
	my $query = 'SELECT running FROM vhffs_cron WHERE cron_id=?';
	my $request = $self->get_db->prepare($query);
	$request->execute( $self->{'cron_id'} ) or return undef;
	my @r = $request->fetchrow_array();
	return $r[0];
}

sub quick_set_nextrundate {
	my ($self , $value) = @_;
	return undef unless $value =~ /^\d+$/;
	my $query = 'UPDATE vhffs_cron SET nextrundate=? WHERE cron_id=?';
	my $request = $self->get_db->prepare($query);
	return $request->execute( $value , $self->{'cron_id'} );
}

sub quick_set_lastrun {
	my ($self , $date, $returncode) = @_;
	return undef unless $date =~ /^\d+$/ and $returncode =~ /^\d+$/;
	my $query = 'UPDATE vhffs_cron SET lastrundate=?, lastrunreturncode=? WHERE cron_id=?';
	my $request = $self->get_db->prepare($query);
	return $request->execute( $date , $returncode , $self->{'cron_id'} );
}

sub quick_reset {
	my ($self) = @_;
	my $query = 'UPDATE vhffs_cron SET running=0, lastrundate=NULL, lastrunreturncode=NULL WHERE cron_id=?';
	my $request = $self->get_db->prepare($query);
	return $request->execute( $self->{'cron_id'} );
}

1;

__END__

=head1 AUTHORS

Sylvain Rochet < gradator at gradator dot net >
