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

# Mirroring script for exim on mx2 (no listengine).
# Set master & slave DB params and put it in a cron.

# Slave database must have
#  - vhffs_mx2
#  - vhffs_mx2_localpart
# tables from mx2-mirror.sql

use DBI;
use strict;
use utf8;

# Master DB params
my $MASTER_DB_DATASOURCE = 'database=vhffs;host=localhost;port=5432';
my $MASTER_DB_USER = 'vhffs';
my $MASTER_DB_PASS = 'vhffs';

# Slave DB params
my $SLAVE_DB_DATASOURCE = 'database=vhffs;host=localhost;port=5432';
my $SLAVE_DB_USER = 'vhffs';
my $SLAVE_DB_PASS = 'vhffs';

# We've to connect to the master DB, fetch
# mx, boxes, forward & ml
# tables and reinject them in slave DB
# We just fetch necessary fields for address verification

my $master_dbh = DBI->connect('DBI:Pg:'.$MASTER_DB_DATASOURCE, $MASTER_DB_USER, $MASTER_DB_PASS)
	or die('Unable to open master connection'."\n");

my $slave_dbh = DBI->connect('DBI:Pg:'.$SLAVE_DB_DATASOURCE, $SLAVE_DB_USER, $SLAVE_DB_PASS)
	or die('Unable to open slave connection'."\n");

# Create temporary tables
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_mx2(LIKE vhffs_mx2)')
	or die('Unable to create temporary MX domain table'."\n");
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_mx2_localpart(LIKE vhffs_mx2_localpart)')
	or die('Unable to create temporary boxes table'."\n");

$master_dbh->{AutoCommit} = 0;
$slave_dbh->{AutoCommit} = 0;

# We need to set transaction isolation level to serializable to avoid
# foreign key issues
$master_dbh->do('SET TRANSACTION ISOLATION LEVEL SERIALIZABLE')
	or die('Unable to set transaction level on master DB'."\n");

# Replicate vhffs_mx table
my $msth = $master_dbh->prepare(q{SELECT d.mx_id, d.domain
	FROM vhffs_mx d
	INNER JOIN vhffs_object o ON o.object_id = d.object_id
	WHERE o.state = 6})
	or die('Unable to prepare SELECT query for vhffs_mx'."\n");
my $ssth = $slave_dbh->prepare(q{INSERT INTO tmp_mx2(mx_id, domain, catchall)
	VALUES(?, ?, false)})
	or die('Unable to prepare INSERT query for tmp_mx2'."\n");

$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx'."\n");

while(my $r = $msth->fetchrow_hashref) {
	$ssth->execute( $r->{mx_id}, $r->{domain} )
	or die('Unable to insert mx #'.$r->{mx_id}."\n");
}

$ssth->finish();
$msth->finish();

# Replicate vhffs_mx_catchall table
my $msth = $master_dbh->prepare(q{SELECT mx.mx_id FROM vhffs_mx mx
	INNER JOIN vhffs_object o ON o.object_id=mx.object_id
	INNER JOIN vhffs_mx_catchall ca ON mx.mx_id=ca.mx_id
	INNER JOIN vhffs_mx_box box ON box.box_id=ca.box_id
	WHERE box.state=6 AND o.state=6 GROUP BY mx.mx_id})
	or die('Unable to prepare SELECT query for vhffs_mx_catchall'."\n");
my $ssth = $slave_dbh->prepare(q{UPDATE tmp_mx2 SET catchall=true WHERE mx_id=?})
	or die('Unable to prepare UPDATE query for tmp_mx2'."\n");

$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx_catchall'."\n");

while(my $r = $msth->fetchrow_hashref) {
	$ssth->execute( $r->{mx_id} )
	or die('Unable to set catchall for mx #'.$r->{mx_id}."\n");
}

$ssth->finish();
$msth->finish();

# Replicate all localparts
$ssth = $slave_dbh->prepare(q{INSERT INTO tmp_mx2_localpart(mx_id, localpart)
	VALUES(?, ?)})
	or die('Unable to prepare INSERT query for tmp_mx2_localpart'."\n");
my $distinct = {};

# Replicate boxes localparts
$msth = $master_dbh->prepare(q{SELECT d.mx_id, lp.localpart
	FROM vhffs_mx_localpart lp
	INNER JOIN vhffs_mx d ON d.mx_id = lp.mx_id
	INNER JOIN vhffs_object o ON o.object_id = d.object_id
	INNER JOIN vhffs_mx_box b ON b.localpart_id = lp.localpart_id
	WHERE o.state = 6 AND b.state = 6})
	or die('Unable to prepare SELECT query for vhffs_mx_box'."\n");
$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx_box'."\n");
while(my $r = $msth->fetchrow_hashref) {
	unless( exists $distinct->{$r->{mx_id}}->{$r->{localpart}} ) {
		$ssth->execute( $r->{mx_id}, $r->{localpart} )
		or die('Unable to insert localpart #'.$r->{localpart_id}."\n");
		$distinct->{$r->{mx_id}}->{$r->{localpart}} = undef;
	}
}
$msth->finish();

# Replicate redirects localparts
$msth = $master_dbh->prepare(q{SELECT d.mx_id, lp.localpart
	FROM vhffs_mx_localpart lp
	INNER JOIN vhffs_mx d ON d.mx_id = lp.mx_id
	INNER JOIN vhffs_object o ON o.object_id = d.object_id
	INNER JOIN vhffs_mx_redirect r ON r.localpart_id = lp.localpart_id
	WHERE o.state = 6})
	or die('Unable to prepare SELECT query for vhffs_mx_redirect'."\n");
$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx_redirect'."\n");
while(my $r = $msth->fetchrow_hashref) {
	unless( exists $distinct->{$r->{mx_id}}->{$r->{localpart}} ) {
		$ssth->execute( $r->{mx_id}, $r->{localpart} )
		or die('Unable to insert localpart #'.$r->{localpart_id}."\n");
		$distinct->{$r->{mx_id}}->{$r->{localpart}} = undef;
	}
}
$msth->finish();

# Replicate mailing lists localparts
$msth = $master_dbh->prepare(q{SELECT d.mx_id, lp.localpart
	FROM vhffs_mx_localpart lp
	INNER JOIN vhffs_mx d ON d.mx_id = lp.mx_id
	INNER JOIN vhffs_object o ON o.object_id = d.object_id
	INNER JOIN vhffs_mx_ml ml ON ml.localpart_id = lp.localpart_id
	INNER JOIN vhffs_object mlo ON mlo.object_id = ml.object_id
	WHERE o.state = 6 AND mlo.state = 6})
	or die('Unable to prepare SELECT query for vhffs_mx_ml'."\n");
$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx_ml'."\n");
while(my $r = $msth->fetchrow_hashref) {
	unless( exists $distinct->{$r->{mx_id}}->{$r->{localpart}} ) {
		$ssth->execute( $r->{mx_id}, $r->{localpart} )
		or die('Unable to insert localpart #'.$r->{localpart_id}.."\n");
		$distinct->{$r->{mx_id}}->{$r->{localpart}} = undef;
	}
	# -request localpart for mailing lists
	$ssth->execute($r->{mx_id}, $r->{localpart}.'-request')
	or die('Unable to insert ml request address for localpart #'.$r->{localpart_id}."\n");
}
$msth->finish();

$distinct = {};
$ssth->finish();

# We're done fetching data
$master_dbh->disconnect();

my $count;

# Delete old localparts/domains
($count = $slave_dbh->do(q{DELETE FROM vhffs_mx2_localpart WHERE
	NOT EXISTS(SELECT * FROM tmp_mx2_localpart t
	WHERE t.mx_id = vhffs_mx2_localpart.mx_id
	AND t.localpart = vhffs_mx2_localpart.localpart)}))
	or die('Unable to delete no more existing localparts'."\n");
print int($count).' localparts deleted'."\n";

($count = $slave_dbh->do(q{DELETE from vhffs_mx2
	WHERE mx_id NOT IN(SELECT mx_id FROM tmp_mx2)}))
	or die('Unable to delete o more existing domains'."\n");
print int($count).' domains deleted'."\n";

# Insert new localparts/domains
($count = $slave_dbh->do(q{INSERT INTO vhffs_mx2(mx_id, domain, catchall)
	SELECT mx_id, domain, catchall FROM tmp_mx2 WHERE mx_id NOT
	IN(SELECT mx_id FROM vhffs_mx2)}))
	or die('Unable to insert new mail domains'."\n");
print int($count).' domains added'."\n";

($count = $slave_dbh->do(q{INSERT INTO vhffs_mx2_localpart(mx_id, localpart)
	SELECT mx_id, localpart FROM tmp_mx2_localpart tmp WHERE NOT EXISTS(
	SELECT * FROM vhffs_mx2_localpart a WHERE a.mx_id = tmp.mx_id AND
	a.localpart = tmp.localpart)}))
	or die('Unable to insert new localparts'."\n");
print int($count).' localparts added'."\n";

# Update catchall field
$slave_dbh->do(q{UPDATE vhffs_mx2 SET catchall = tmp.catchall
	FROM tmp_mx2 tmp WHERE tmp.mx_id = vhffs_mx2.mx_id})
	or die('Unable to update mx data'."\n");

$slave_dbh->commit();
$slave_dbh->disconnect();
