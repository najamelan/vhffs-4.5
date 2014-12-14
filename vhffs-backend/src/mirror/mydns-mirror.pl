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

# Mirroring script for myDNS.
# Set master & slave DB params and put it in a cron.
# Slave database must have at least vhffs_dns_soa and
# vhffs_dns_rr tables

use DBI;
use strict;
use utf8;

# Master DB params
my $MASTER_DB_DATASOURCE = 'database=vhffs;host=localhost;port=5432';
my $MASTER_DB_USER = 'vhffs';
my $MASTER_DB_PASS = 'vhffs';

# Slave DB params
my $SLAVE_DB_DATASOURCE = 'database=dns;host=localhost;port=5432';
my $SLAVE_DB_USER = 'dns';
my $SLAVE_DB_PASS = 'dns';

# We've to connect to the master DB, fetch soa & rr
# tables and reinject them in slave DB

my $master_dbh = DBI->connect('DBI:Pg:'.$MASTER_DB_DATASOURCE, $MASTER_DB_USER, $MASTER_DB_PASS)
	or die('Unable to open master connection'."\n");

my $slave_dbh = DBI->connect('DBI:Pg:'.$SLAVE_DB_DATASOURCE, $SLAVE_DB_USER, $SLAVE_DB_PASS)
	or die('Unable to open slave connection'."\n");

# Create temporary tables
# mirror table containing SOA must be named vhffs_dns_soa
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_dns_soa(LIKE vhffs_dns_soa)')
    or die("Unable to create temporary DNS SOA table\n");
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_dns_rr(LIKE vhffs_dns_rr)')
    or die("Unable to create temporary DNS RR table\n");

$master_dbh->{AutoCommit} = 0;
$slave_dbh->{AutoCommit} = 0;

# We need to set transaction isolation level to serializable to avoid
# foreign key issues
$master_dbh->do('SET TRANSACTION ISOLATION LEVEL SERIALIZABLE')
    or die("Unable to set transaction level on master DB\n");

# Replicate vhffs_dns_soa table
my $msth = $master_dbh->prepare(q{SELECT id, origin, ns, mbox, serial, refresh, retry, expire, minimum, ttl FROM vhffs_dns_soa})
    or die("Unable to prepare SELECT query for master vhffs_dns_soa\n");
my $ssth = $slave_dbh->prepare('INSERT INTO tmp_dns_soa(id, origin, ns, mbox, serial, refresh, retry, expire, minimum, ttl) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)') or die("Unable to prepare INSERT query for tmp_dns_soa\n");

$msth->execute()
    or die("Unable to execute SELECT query for master vhffs_dns_soa\n");;

while(my $row = $msth->fetchrow_hashref()) {
    $ssth->execute($row->{id}, $row->{origin}, $row->{ns}, $row->{mbox},
        $row->{serial}, $row->{refresh}, $row->{retry}, $row->{expire},
        $row->{minimum}, $row->{ttl})
    or die('Unable to insert soa record #'.$row->{id}."\n");
}

$ssth->finish();
$msth->finish();

# Replicate vhffs_dns_rr table

$msth = $master_dbh->prepare(q{SELECT r.id, r.zone, r.name, r.type, r.data, r.aux, r.ttl FROM vhffs_dns_rr r INNER JOIN vhffs_dns_soa s ON r.zone = s.id})
    or die("Unable to prepare resource records SELECT statement\n");
$ssth = $slave_dbh->prepare(q{INSERT INTO tmp_dns_rr(id, zone, name, type, data, aux, ttl) VALUES(?, ?, ?, ?, ?, ?, ?)})
    or die("Unable to prepare INSERT statement for tmp_dns_rr\n");

$msth->execute()
    or die("Unable to execute SELECT query for master vhffs_dns_rr\n");

while(my $row = $msth->fetchrow_hashref()) {
    $ssth->execute($row->{id}, $row->{zone}, $row->{name}, $row->{type},
        $row->{data}, $row->{aux}, $row->{ttl})
            or die('Unable to insert rr #'.$row->{id}."\n");
}

$ssth->finish();
$msth->finish();

# We're done fetching data
$master_dbh->disconnect();

$slave_dbh->do(q{DELETE FROM vhffs_dns_rr WHERE id NOT IN(SELECT id FROM tmp_dns_rr)})
    or die("Unable to delete no more existing rr\n");
$slave_dbh->do(q{DELETE FROM vhffs_dns_soa WHERE id NOT IN (SELECT id FROM tmp_dns_soa)})
    or die("Unable to delete no more existing soa\n");

# Unfortunately, PostgreSQL doesn't support INSERT OR REPLACE statements
# so we first update what was already existing, and then insert new
# records
$slave_dbh->do(q{UPDATE vhffs_dns_rr SET zone = tmp.zone, name = tmp.name,
    type = tmp.type, data = tmp.data, aux = tmp.aux, ttl = tmp.ttl FROM
    tmp_dns_rr tmp WHERE tmp.id = vhffs_dns_rr.id})
    or die("Unable to update existing rr\n");
$slave_dbh->do(q{UPDATE vhffs_dns_soa SET origin = tmp.origin, ns = tmp.ns,
    mbox = tmp.mbox, serial = tmp.serial, refresh = tmp.refresh,
    retry = tmp.retry, expire = tmp.expire, minimum = tmp.minimum,
    ttl = tmp.ttl FROM tmp_dns_soa tmp WHERE vhffs_dns_soa.id = tmp.id})
    or die("Unable to update existing soa\n");

$slave_dbh->do(q{INSERT INTO vhffs_dns_soa(id, origin, ns, mbox, serial,
    refresh, retry, expire, minimum, ttl) SELECT id, origin, ns,
    mbox, serial, refresh, retry, expire, minimum, ttl FROM tmp_dns_soa
    WHERE id NOT IN(SELECT id FROM vhffs_dns_soa)})
    or die("Unable to insert new soa records\n");
$slave_dbh->do(q{INSERT INTO vhffs_dns_rr(id, zone, name, type, data,
    aux, ttl) SELECT id, zone, name, type, data, aux, ttl FROM
    tmp_dns_rr WHERE id NOT IN(SELECT id FROM vhffs_dns_rr)})
    or die("Unable to insert new rr\n");
$slave_dbh->commit();
