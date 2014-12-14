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

# Mirroring script for exim on mx1.
# Set master & slave DB params and put it in a cron.

# Slave database must have
#  - vhffs_object
#  - vhffs_mx
#  - vhffs_mx_localpart
#  - vhffs_mx_redirect
#  - vhffs_mx_box
#  - vhffs_mx_catchall
#  - vhffs_mx_ml
#  - vhffs_mx_ml_subscribers
# tables from mx1-mirror.sql

use DBI;
use strict;
use utf8;

# Master DB params
my $MASTER_DB_DATASOURCE = 'database=vhffs;host=localhost;port=5432';
my $MASTER_DB_USER = 'vhffs';
my $MASTER_DB_PASS = 'vhffs';

# Slave DB params
my $SLAVE_DB_DATASOURCE = 'database=mailmirror;host=localhost;port=5432';
my $SLAVE_DB_USER = 'mailmirror';
my $SLAVE_DB_PASS = 'mirror';

# We've to connect to the master DB, fetch
# object, mx, boxes, redirects, ml & ml_subscribers
# tables and reinject them in slave DB

my $master_dbh = DBI->connect('DBI:Pg:'.$MASTER_DB_DATASOURCE, $MASTER_DB_USER, $MASTER_DB_PASS)
	or die('Unable to open master connection'."\n");

my $slave_dbh = DBI->connect('DBI:Pg:'.$SLAVE_DB_DATASOURCE, $SLAVE_DB_USER, $SLAVE_DB_PASS)
	or die('Unable to open slave connection'."\n");

# Create temporary tables
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_mx(LIKE vhffs_mx)')
	or die('Unable to create temporary MX domain table'."\n");
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_mx_catchall(LIKE vhffs_mx_catchall)')
	or die('Unable to create temporary catchall table'."\n");
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_mx_localpart(LIKE vhffs_mx_localpart)')
	or die('Unable to create temporary localparts table'."\n");
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_mx_box(LIKE vhffs_mx_box)')
	or die('Unable to create temporary boxes table'."\n");
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_mx_redirect(LIKE vhffs_mx_redirect)')
	or die('Unable to create temporary redirect table'."\n");
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_mx_ml(LIKE vhffs_mx_ml)')
	or die('Unable to create temporary ml table'."\n");
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_mx_ml_subscribers(LIKE vhffs_mx_ml_subscribers)')
	or die('Unable to create temporary ml_subscribers table'."\n");
$slave_dbh->do('CREATE TEMPORARY TABLE tmp_object(LIKE vhffs_object)')
	or die('Unable to create temporary object table'."\n");

$master_dbh->{AutoCommit} = 0;
$slave_dbh->{AutoCommit} = 0;

# We need to set transaction isolation level to serializable to avoid
# foreign key issues
$master_dbh->do('SET TRANSACTION ISOLATION LEVEL SERIALIZABLE')
	or die('Unable to set transaction level on master DB'."\n");

# Replicate vhffs_object table

# Type 60 is mail objects and 61 is ml objects.
my $msth = $master_dbh->prepare(q{SELECT o.object_id, o.owner_uid, o.owner_gid, o.date_creation, o.type
	FROM vhffs_object o
	WHERE o.state = 6 AND (o.type = 60 OR o.type = 61) })
	or die('Unable to prepare SELECT query for vhffs_object'."\n");
my $ssth = $slave_dbh->prepare(q{INSERT INTO tmp_object(object_id,
	owner_uid, owner_gid, date_creation, type) VALUES(?, ?, ?, ?, ?)})
	or die('Unable to prepare INSERT query for tmp_object'."\n");

$msth->execute()
	or die('Unable to execute SELECT query for vhffs_object'."\n");

while(my $row = $msth->fetchrow_hashref()) {
	$ssth->execute($row->{object_id}, $row->{owner_uid}, $row->{owner_gid},
	$row->{date_creation}, $row->{type})
	or die('Unable to insert object #'.$row->{object_id}."\n");
}

$ssth->finish();
$msth->finish();

# Replicate vhffs_mx table
my $msth = $master_dbh->prepare(q{SELECT d.mx_id, d.domain, d.object_id FROM vhffs_mx d
	INNER JOIN vhffs_object o ON o.object_id = d.object_id
	WHERE o.state = 6})
	or die('Unable to prepare SELECT query for vhffs_mx'."\n");
my $ssth = $slave_dbh->prepare(q{INSERT INTO tmp_mx(mx_id, domain, object_id) VALUES(?, ?, ?)})
	or die('Unable to prepare INSERT query for tmp_mx'."\n");

$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx'."\n");

while(my $row = $msth->fetchrow_hashref()) {
	$ssth->execute($row->{mx_id}, $row->{domain}, $row->{object_id})
	or die('Unable to insert mail domain #'.$row->{mx_id}."\n");
}

$ssth->finish();
$msth->finish();

# Replicate vhffs_mx_localpart table
$msth = $master_dbh->prepare(q{SELECT lp.localpart_id, lp.mx_id, lp.localpart, lp.password, lp.nospam, lp.novirus
	FROM vhffs_mx_localpart lp
	INNER JOIN vhffs_mx d ON lp.mx_id = d.mx_id
	INNER JOIN vhffs_object o ON o.object_id = d.object_id
	WHERE o.state = 6})
	or die('Unable to prepare SELECT query for vhffs_mx_localpart'."\n");
$ssth = $slave_dbh->prepare(q{INSERT INTO tmp_mx_localpart(localpart_id, mx_id,
	localpart, password, nospam, novirus)
	VALUES(?, ?, ?, ?, ?, ?)})
	or die('Unable to prepare INSERT query for tmp_mx_localpart'."\n");

$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx_localpart'."\n");

while(my $row = $msth->fetchrow_hashref()) {
	$ssth->execute($row->{localpart_id}, $row->{mx_id}, $row->{localpart},
	$row->{password}, $row->{nospam}, $row->{novirus})
	or die('Unable to insert localpart #'.$row->{localpart_id}."\n");
}
$ssth->finish();
$msth->finish();

# Replicate vhffs_mx_redirect table
$msth = $master_dbh->prepare(q{SELECT r.redirect_id, r.localpart_id, r.redirect
	FROM vhffs_mx_redirect r
	INNER JOIN vhffs_mx_localpart lp ON lp.localpart_id = r.localpart_id
	INNER JOIN vhffs_mx d ON d.mx_id = lp.mx_id
	INNER JOIN vhffs_object o ON o.object_id = d.object_id
	WHERE o.state = 6})
	or die('Unable to prepare SELECT query for vhffs_mx_redirect'."\n");
$ssth = $slave_dbh->prepare(q{INSERT INTO tmp_mx_redirect(redirect_id,
	localpart_id, redirect) VALUES(?, ?, ?)})
	or die('Unable to prepare INSERT query for vhffs_mx_redirect'."\n");

$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx_redirect'."\n");

while(my $row = $msth->fetchrow_hashref()) {
	$ssth->execute($row->{redirect_id}, $row->{localpart_id},
	$row->{redirect})
	or die('Unable to insert redirect #'.$row->{redirect_id}."\n");
}

$ssth->finish();
$msth->finish();

# Replicate vhffs_mx_box table
$msth = $master_dbh->prepare(q{SELECT b.box_id, b.localpart_id, b.allowpop, b.allowimap
	FROM vhffs_mx_box b
	INNER JOIN vhffs_mx_localpart lp ON lp.localpart_id = b.localpart_id
	INNER JOIN vhffs_mx d ON d.mx_id = lp.mx_id
	INNER JOIN vhffs_object o ON o.object_id = d.object_id
	WHERE o.state = 6 AND b.state = 6})
	or die('Unable to prepare SELECT query for vhffs_mx_box'."\n");
$ssth = $slave_dbh->prepare(q{INSERT INTO tmp_mx_box(box_id, localpart_id, allowpop,
	allowimap) VALUES(?, ?, ?, ?)})
	or die('Unable to prepare INSERT query for tmp_mx_box'."\n");

$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx_box'."\n");

while(my $row = $msth->fetchrow_hashref()) {
	$ssth->execute($row->{box_id}, $row->{localpart_id}, $row->{allowpop},
	$row->{allowimap})
	or die('Unable to insert box #'.$row->{box_id}."\n");
}
$ssth->finish();
$msth->finish();

# Replicate vhffs_mx_catchall table
$msth = $master_dbh->prepare(q{SELECT c.catchall_id, c.mx_id, c.box_id
	FROM vhffs_mx_catchall c
	INNER JOIN vhffs_mx d ON d.mx_id = c.mx_id
	INNER JOIN vhffs_object o ON o.object_id = d.object_id
	INNER JOIN vhffs_mx_box b ON b.box_id = c.box_id
	INNER JOIN vhffs_mx_localpart lpb ON lpb.localpart_id = b.localpart_id
	INNER JOIN vhffs_mx mxb ON mxb.mx_id = lpb.mx_id
	INNER JOIN vhffs_object ob ON ob.object_id = mxb.object_id
	WHERE o.state = 6 AND b.state = 6 AND ob.state = 6})
	or die('Unable to prepare SELECT query for vhffs_mx_box'."\n");
$ssth = $slave_dbh->prepare(q{INSERT INTO tmp_mx_catchall(catchall_id, mx_id, box_id)
	VALUES(?, ?, ?)})
	or die('Unable to prepare INSERT query for tmp_mx_catchall'."\n");

$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx_catchall'."\n");

while(my $row = $msth->fetchrow_hashref()) {
	$ssth->execute($row->{catchall_id}, $row->{mx_id}, $row->{box_id})
	or die('Unable to insert catchall #'.$row->{catchall_id}."\n");
}
$ssth->finish();
$msth->finish();

# Replicate vhffs_mx_ml table
$msth = $master_dbh->prepare(q{SELECT ml.ml_id, ml.localpart_id, ml.prefix,
	ml.object_id, ml.sub_ctrl, ml.post_ctrl, ml.reply_to, ml.open_archive,
	ml.signature FROM vhffs_mx_ml ml
	INNER JOIN vhffs_object o ON o.object_id = ml.object_id
	INNER JOIN vhffs_mx_localpart lp ON lp.localpart_id = ml.localpart_id
	INNER JOIN vhffs_mx d ON d.mx_id = lp.mx_id
	INNER JOIN vhffs_object mxo ON mxo.object_id = d.object_id
	WHERE o.state = 6 AND mxo.state = 6})
	or die('Unable to prepare SELECT query for vhffs_mx_ml'."\n");
$ssth = $slave_dbh->prepare(q{INSERT INTO tmp_mx_ml(ml_id, localpart_id,
	prefix, object_id, sub_ctrl, post_ctrl, reply_to, open_archive,
	signature) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)})
	or die('Unable to prepare INSERT query for tmp_mx_ml'."\n");

$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx_ml'."\n");

while(my $row = $msth->fetchrow_hashref()) {
	$ssth->execute($row->{ml_id}, $row->{localpart_id},
	$row->{prefix}, $row->{object_id}, $row->{sub_ctrl}, $row->{post_ctrl},
	$row->{reply_to}, $row->{open_archive}, $row->{signature})
	or die('Unable to insert ml #'.$row->{mx_id}."\n");
}

$ssth->finish();
$msth->finish();

# Replicate vhffs_mx_ml_subscribers table
$msth = $master_dbh->prepare(q{SELECT ms.sub_id, ms.member, ms.perm, ms.hash,
	ms.ml_id, ms.language
	FROM vhffs_mx_ml_subscribers ms
	INNER JOIN vhffs_mx_ml ml ON ms.ml_id = ml.ml_id
	INNER JOIN vhffs_object o ON o.object_id = ml.object_id
	INNER JOIN vhffs_mx_localpart lp ON lp.localpart_id = ml.localpart_id
	INNER JOIN vhffs_mx d ON d.mx_id = lp.mx_id
	INNER JOIN vhffs_object mxo ON mxo.object_id = d.object_id
	WHERE o.state = 6 AND mxo.state = 6})
	or die("Unable to prepare SELECT query for vhffs_mx_ml_subscribers\n");
$ssth = $slave_dbh->prepare(q{INSERT INTO tmp_mx_ml_subscribers(sub_id, member,
	perm, hash, ml_id, language) VALUES(?, ?, ?, ?, ?, ?)})
	or die('Unable to prepare INSERT query for tmp_mx_ml_subscribers'."\n");

$msth->execute()
	or die('Unable to execute SELECT query for vhffs_mx_ml_subscribers'."\n");

while(my $row = $msth->fetchrow_hashref()) {
	$ssth->execute($row->{sub_id}, $row->{member}, $row->{perm}, $row->{hash},
	$row->{ml_id}, $row->{language})
	or die('Unable to insert ml_subscriber #'.$row->{sub_id});
}

$ssth->finish();
$msth->finish();

# We're done fetching data
$master_dbh->disconnect();

my $count;

($count = $slave_dbh->do(q{DELETE FROM vhffs_mx_ml_subscribers WHERE
	sub_id NOT IN (SELECT sub_id FROM tmp_mx_ml_subscribers)}))
	or die('Unable to delete no more existing ml users'."\n");
print int($count).' subscribers deleted'."\n";

($count = $slave_dbh->do(q{DELETE FROM vhffs_mx_ml
	WHERE ml_id NOT IN (SELECT ml_id FROM tmp_mx_ml)}))
	or die('Unable to delete no more existing ml'."\n");
print int($count).' mailing lists deleted'."\n";

($count = $slave_dbh->do(q{DELETE FROM vhffs_mx_redirect
	WHERE redirect_id
	NOT IN (SELECT redirect_id FROM tmp_mx_redirect)}))
	or die('Unable to delete no more existing redirects'."\n");
print int($count).' redirects deleted'."\n";

($count = $slave_dbh->do(q{DELETE FROM vhffs_mx_catchall
	WHERE catchall_id
	NOT IN (SELECT catchall_id FROM tmp_mx_catchall)}))
	or die('Unable to delete no more existing catchall'."\n");
print int($count).' catchalls deleted'."\n";

($count = $slave_dbh->do(q{DELETE FROM vhffs_mx_box
	WHERE box_id
	NOT IN (SELECT box_id FROM tmp_mx_box)}))
	or die('Unable to delete no more existing boxes'."\n");
print int($count).' boxes deleted'."\n";

($count = $slave_dbh->do(q{DELETE FROM vhffs_mx_box
	WHERE box_id
	NOT IN (SELECT box_id FROM tmp_mx_box)}))
	or die('Unable to delete no more existing boxes'."\n");
print int($count).' boxes deleted'."\n";

($count = $slave_dbh->do(q{DELETE FROM vhffs_mx_localpart
	WHERE localpart_id
	NOT IN (SELECT localpart_id FROM tmp_mx_localpart)}))
	or die('Unable to delete no more existing localparts'."\n");
print int($count).' localparts deleted'."\n";

($count = $slave_dbh->do(q{DELETE FROM vhffs_object
	WHERE object_id NOT IN(SELECT object_id FROM vhffs_object)}))
	or die('Unable to delete no more existing objects'."\n");
print int($count).' objects deleted'."\n";

# Update boxes/redirects/ml/domains

# The only potential change in object is owner_uid, owner_gid
# Type are always set to 60 or 61 for us
($count = $slave_dbh->do(q{UPDATE vhffs_object SET owner_uid = tmp.owner_uid,
	owner_gid = tmp.owner_gid, date_creation = tmp.date_creation
	FROM tmp_object tmp WHERE tmp.object_id = vhffs_object.object_id}))
	or die('Unable to update object table'."\n");

# nothing to update for vhffs_mx

# nothing to update for vhffs_mx_catchall

$slave_dbh->do(q{UPDATE vhffs_mx_localpart SET password = tmp.password,
	nospam = tmp.nospam, novirus = tmp.novirus
	FROM tmp_mx_localpart tmp WHERE tmp.localpart_id = vhffs_mx_localpart.localpart_id})
	or die('Unable to update boxes data'."\n");

$slave_dbh->do(q{UPDATE vhffs_mx_box SET allowpop = tmp.allowpop,
	allowimap = tmp.allowimap
	FROM tmp_mx_box tmp WHERE tmp.box_id = vhffs_mx_box.box_id})
	or die('Unable to update boxes data'."\n");

$slave_dbh->do(q{UPDATE vhffs_mx_redirect SET redirect = tmp.redirect
	FROM tmp_mx_redirect tmp
	WHERE tmp.redirect_id = vhffs_mx_redirect.redirect_id})
	or die('Unable to update redirecs data'."\n");

$slave_dbh->do(q{UPDATE vhffs_mx_ml SET prefix = tmp.prefix,
	sub_ctrl = tmp.sub_ctrl, post_ctrl = tmp.post_ctrl,
	reply_to = tmp.reply_to, open_archive = tmp.open_archive,
	signature = tmp.signature FROM tmp_mx_ml tmp
	WHERE tmp.ml_id = vhffs_mx_ml.ml_id})
	or die('Unable to update mailing lists data'."\n");

$slave_dbh->do(q{UPDATE vhffs_mx_ml_subscribers SET perm = tmp.perm,
	hash = tmp.hash, language = tmp.language FROM tmp_mx_ml_subscribers tmp
	WHERE tmp.sub_id = vhffs_mx_ml_subscribers.sub_id})
	or die('Unable to update subscribers data'."\n");

# Insert new boxes/redirects/ml/domains

($count = $slave_dbh->do(q{INSERT INTO vhffs_object(object_id, owner_uid, owner_gid,
	date_creation, type) SELECT object_id, owner_uid, owner_gid, date_creation, type
	FROM tmp_object tmp WHERE tmp.object_id NOT IN(SELECT object_id FROM vhffs_object)}))
	or die('Unable to insert new objects'."\n");
print int($count).' objects inserted'."\n";

($count = $slave_dbh->do(q{INSERT INTO vhffs_mx(mx_id, domain, object_id)
	SELECT mx_id, domain, object_id FROM tmp_mx
	WHERE mx_id NOT IN(SELECT mx_id FROM vhffs_mx)}))
	or die('Unable to insert new mail domains'."\n");
print int($count).' domains inserted'."\n";

($count = $slave_dbh->do(q{INSERT INTO vhffs_mx_localpart(localpart_id, mx_id,
	localpart, password, nospam, novirus)
	SELECT localpart_id, mx_id, localpart, password, nospam, novirus
	FROM tmp_mx_localpart WHERE localpart_id
	NOT IN(SELECT localpart_id FROM vhffs_mx_localpart)}))
	or die('Unable to insert new localparts'."\n");
print int($count).' localparts inserted'."\n";

($count = $slave_dbh->do(q{INSERT INTO vhffs_mx_redirect(redirect_id, localpart_id,
	redirect)
	SELECT redirect_id, localpart_id, redirect FROM tmp_mx_redirect tmp
	WHERE tmp.redirect_id NOT IN (SELECT redirect_id FROM vhffs_mx_redirect)}))
	or die('Unable to insert new redirects'."\n");
print int($count).' redirects inserted'."\n";

($count = $slave_dbh->do(q{INSERT INTO vhffs_mx_box(box_id, localpart_id, allowpop,
	allowimap)
	SELECT box_id, localpart_id, allowpop, allowimap FROM tmp_mx_box tmp
	WHERE tmp.box_id NOT IN(SELECT box_id FROM vhffs_mx_box)}))
	or die('Unable to insert new boxes'."\n");
print int($count).' boxes inserted'."\n";

($count = $slave_dbh->do(q{INSERT INTO vhffs_mx_catchall(catchall_id, mx_id, box_id)
	SELECT catchall_id, mx_id, box_id FROM tmp_mx_catchall tmp
	WHERE tmp.catchall_id NOT IN(SELECT catchall_id FROM vhffs_mx_catchall)}))
	or die('Unable to insert new catchalls'."\n");
print int($count).' catchalls inserted'."\n";

($count = $slave_dbh->do(q{INSERT INTO vhffs_mx_ml(ml_id, localpart_id, prefix,
	object_id, sub_ctrl, post_ctrl, reply_to, open_archive, signature)
	SELECT ml_id, localpart_id, prefix, object_id, sub_ctrl, post_ctrl,
	reply_to, open_archive, signature
	FROM tmp_mx_ml tmp WHERE tmp.ml_id NOT IN (SELECT ml_id FROM vhffs_mx_ml)}))
	or die('Unable to insert new ml'."\n");
print int($count).' mailing lists inserted'."\n";

($count = $slave_dbh->do(q{INSERT INTO vhffs_mx_ml_subscribers(sub_id, member, perm, hash,
	ml_id, language) SELECT sub_id, member, perm, hash, ml_id, language FROM
	tmp_mx_ml_subscribers ms WHERE ms.sub_id NOT IN(SELECT sub_id FROM
	vhffs_mx_ml_subscribers)}))
	or die('Unable to insert new subscribers'."\n");
print int($count).' subscribers inserted'."\n";

$slave_dbh->commit();
$slave_dbh->disconnect();
