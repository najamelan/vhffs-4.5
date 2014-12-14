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



# This file is a part of VHFFS4
# Please respect the licence of this file, and the whole VHFFS software.

=pod

=head1 NAME

Vhffs::Services::Web - Handle Web Area in VHFFS hosting platform.

=head1 SYNOPSIS

TODO

=head1 METHODS

=cut

use strict;
use utf8;

package Vhffs::Services::Web;

use Vhffs::Functions;
use base qw(Vhffs::Object);
use DBI;

sub _new {
	my ($class, $vhffs, $httpd_id, $servername, $owner_uid, $owner_gid, $oid, $date_creation, $description, $state) = @_;

	my $self = $class->SUPER::_new($vhffs, $oid, $owner_uid, $owner_gid, $date_creation, $description, '', $state, Vhffs::Constants::TYPE_WEB);
	return undef unless(defined($self));

	$self->{http_id} = $httpd_id;
	$self->{servername} = $servername;

	return $self;
}

=pod

=head2 create

	my $httpd = Vhffs::Services::Web::create($vhffs, $servername, $description, $user, $group);
	die("Unable to create webarea $servername\n") unless(defined $httpd);

Creates a new webarea in database and returns the corresponding fully functional object.

=cut
sub create {
	my ($vhffs, $servername, $description, $user, $group) = @_;
	return undef unless defined $user and defined $group;
	return undef unless Vhffs::Functions::check_domain_name($servername);

	my $webconf = $vhffs->get_config->get_service('web');
	my $web;

	if( open(my $badwebareas, '<', $webconf->{'bad_webarea_file'} )) {
		while( <$badwebareas> ) {
			chomp;
			if ( $servername =~ /(?:^|\.)$_$/ ) {
				close $badwebareas;
				return undef;
			}
		}
		close $badwebareas;
	}

	my $dbh = $vhffs->get_db();
	local $dbh->{RaiseError} = 1;
	local $dbh->{PrintError} = 0;
	$dbh->begin_work;

	eval {
		my $parent =  Vhffs::Object::create($vhffs, $user->get_uid, $group->get_gid, $description, undef, Vhffs::Constants::TYPE_WEB);

		die('Unable to create parent object') unless(defined($parent));

		my $sql = 'INSERT INTO vhffs_httpd(servername, object_id) VALUES(?, ?)';

		my $sth = $dbh->prepare($sql);
		$sth->execute($servername, $parent->get_oid);

		$dbh->commit;
		$web = get_by_servername($vhffs, $servername);
	};

	if($@) {
		warn 'Unable to create webarea '.$servername.': '.$@."\n";
		$dbh->rollback;
	}
	return $web;
}

=head2 fill_object

See C<Vhffs::Object::fill_object>.

=cut
sub fill_object {
	my ($class, $obj) = @_;
	my $sql = q{SELECT httpd_id, servername
		FROM vhffs_httpd WHERE object_id = ?};
	return $class->SUPER::_fill_object($obj, $sql);
}

sub getall {
	my ($vhffs, $state, $name, $group) = @_;

	my $web = [];
	my @params;

	my $sql = 'SELECT h.httpd_id, h.servername, o.owner_uid, o.owner_gid, h.object_id, o.date_creation, o.description, o.state
		FROM vhffs_httpd h INNER JOIN vhffs_object o ON o.object_id = h.object_id';
	if(defined $state) {
		$sql .= ' AND o.state = ?';
		push(@params, $state);
	}
	if(defined $name) {
		$sql .= ' AND h.servername LIKE ?';
		push(@params, '%'.$name.'%');
	}
	if(defined $group) {
		$sql .= ' AND o.owner_gid = ?';
		push(@params, $group->get_gid);
	}
	$sql .= ' ORDER BY h.servername';

	my $dbh = $vhffs->get_db();

	my $sth = $dbh->prepare($sql);
	$sth->execute(@params) or return undef;

	while( my $s = $sth->fetchrow_arrayref() ) {
		push( @{$web}, _new Vhffs::Services::Web($vhffs, @$s) );
	}
	return $web;
}

=head2 get_by_servername

	my $httpd = Vhffs::Services::Web::get_by_servername($vhffs, $servername);
	die("Webarea $servername not found\n") unless(defined $httpd);

Fetches the webarea whose address is C<$servername>.

=cut
sub get_by_servername {
	my ($vhffs, $servername) = @_;
	my $sql = 'SELECT h.httpd_id, h.servername, o.owner_uid, o.owner_gid, h.object_id, o.date_creation, o.description, o.state
		FROM vhffs_httpd h INNER JOIN vhffs_object o ON o.object_id = h.object_id WHERE h.servername = ?';

	my $dbh = $vhffs->get_db();
	my @params;
	return undef unless(@params = $dbh->selectrow_array($sql, undef, $servername));

	return _new Vhffs::Services::Web($vhffs, @params);
}

=pod

=head2 commit

Commit modified changes to the database.

=cut
sub commit {
	my $self = shift;
	return $self->SUPER::commit;
}

=head2 get_servername

	my $servername = $httpd->get_servername;

Returns webarea server name.

=cut
sub get_servername {
	my $self = shift;
	return $self->{'servername'};
}

=head2 get_dir

	my $dir = $httpd->get_dir;

Returns webarea directory.

=cut
sub get_dir {
	my $self = shift;
	return $self->get_vhffs->get_config->get_datadir.'/web/'.$self->get_hash();
}

=head2 get_hash

	my $dir = $httpd->get_hash;

Same as get_dir, but only return the hashed part.

=cut
sub get_hash {
	my $self = shift;
	require Digest::MD5;
	my $hash = Digest::MD5::md5_hex( $self->{'servername'} );
	return substr( $hash, 0, 2 ).'/'.substr( $hash, 2, 2 ).'/'.substr( $hash, 4, 2 ).'/'.$self->{'servername'};
}

=head2 get_label

See C<Vhffs::Object::get_label>.

=cut
sub get_label {
	my $self = shift;
	return $self->{servername};
}

=head2 get_config

See C<Vhffs::Object::get_config>.

=cut
sub get_config {
	my $self = shift;
	return $self->get_vhffs->get_config->get_service('web');
}

1;

__END__

=head1 AUTHORS

soda < dieu at gunnm dot org >

Sebastien Le Ray < beuss at tuxfamily dot org >
