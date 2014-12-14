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


# **** WARNING ***** This file should be owned by root and chmoded 500
use DBI;
use Getopt::Long;
use strict;
use utf8;

# Master DB params
my $PG_DB_DATASOURCE = 'database=vhffs;host=localhost;port=5432';
my $PG_DB_USER = 'vhffs';
my $PG_DB_PASS = 'vhffs';

my $ST_PW_DB = '/var/db/passwd.sqlite'; # SQLite users database
my $ST_SP_DB = '/var/db/shadow.sqlite'; # SQLite shadow database

# Enforced shell value if any
my $shell;
# Enforced homedir if any
my $homedir;
# Flag
my $showhelp;
# Flag, set if shadow informations doesn't have to be replicated
my $skipshadow;

sub usage() {
    print <<EOF;

nss-mirror.pl: Replicates users information for libnss-sqlite
    --help                     this help
    --force-shell shell_path   force 'shell' field value to shell_path
    --force-homedir home_path  force 'homedir' field value to home_path
    --no-shadow                shadowed passwords won't be replicated

EOF
    exit(0);
}

if(!GetOptions( 'force-homedir=s'   => \$homedir,
            'force-shell=s'         => \$shell,
            'help'                  => \$showhelp,
            'no-shadow'            => \$skipshadow
          )) {
    exit(-1);
}

if($showhelp) {
    usage();
}

# Let's open pg connection
my $pg_dbh = DBI->connect('DBI:Pg:'.$PG_DB_DATASOURCE, $PG_DB_USER, $PG_DB_PASS)
    or die("Unable to open pg connection\n");

# SQLite connection now
my $pw_dbh = DBI->connect("DBI:SQLite:dbname=$ST_PW_DB", '', '')
    or die("Unable to open SQLite passwd connection\n");

# SQLite shadow connection, will be opened later if needed
my $sp_dbh;

# Ok, we have to fetch everything from pg and put it into SQLite. Use a
# transaction to speedup things.

$pw_dbh->{AutoCommit} = 0;

$pw_dbh->do(q{CREATE TEMP TABLE tmp_passwd(uid INTEGER, gid INTEGER, username TEXT NOT NULL, gecos TEXT NOT NULL default '', shell TEXT NOT NULL,  homedir TEXT NOT NULL)})
    or die("Unable to create temporary passwd table\n");

$pw_dbh->do(q{CREATE TEMP TABLE tmp_groups(gid INTEGER, groupname TEXT NOT NULL, passwd TEXT NOT NULL DEFAULT '')})
    or die("Unable to create temporary groups table\n");

$pw_dbh->do(q{CREATE TEMP TABLE tmp_user_group(uid INTEGER, gid INTEGER, CONSTRAINT pk_user_groups PRIMARY KEY(uid, gid))})
    or die("Unable to create temporary user_group table\n");


my $select = q{SELECT u.uid, u.gid, u.username %s %s FROM vhffs_users u INNER JOIN vhffs_object o ON o.object_id = u.object_id WHERE o.state = 6};
my $ssth = $pg_dbh->prepare( sprintf($select, ($homedir ? '' : ', u.homedir'),
    ($shell ? '' : ', u.shell') ) )
    or die("Unable to prepare users SELECT statement\n");
my $sth = $pw_dbh->prepare(q{INSERT INTO tmp_passwd(uid, gid, username, shell, homedir) VALUES(?, ?, ?, ?, ?)})
    or die("Unable to prepare passwd insert statement\n");;

$ssth->execute() or die("Unable to execute users SELECT statement\n");

while(my $row = $ssth->fetchrow_hashref()) {
    $sth->execute($row->{uid}, $row->{gid}, $row->{username},
        ($shell ? $shell : $row->{shell}), ($homedir ? $homedir : $row->{homedir}))
        or die('Unable to insert passwd entry #'.$row->{uid}."\n");
}
$sth->finish();

$ssth = $pg_dbh->prepare(q{SELECT g.gid, g.groupname, g.passwd FROM vhffs_groups g INNER JOIN vhffs_object o ON o.object_id = g.object_id WHERE o.state = 6}) or die("Unable to prepare groups SELECT statement\n");
$sth = $pw_dbh->prepare(q{INSERT INTO tmp_groups(gid, groupname, passwd) VALUES(?, ?, ?)})
    or die("Unable to prepare groups insert statement\n");

$ssth->execute() or die("Unable to execute groups SELECT statement\n");

while(my $row = $ssth->fetchrow_hashref()) {
    $sth->execute($row->{gid}, $row->{groupname}, ($row->{passwd} or ''))
        or die("unable to insert groups\n");
}
$sth->finish();

$ssth = $pg_dbh->prepare(q{SELECT uid, gid FROM vhffs_user_group WHERE state = 6})
    or die("Unable to prepare user_group SELECT statement\n");
$sth = $pw_dbh->prepare(q{INSERT INTO tmp_user_group(uid, gid) VALUES(?, ?)})
    or die("Unable to prepare user_group insert statement\n");

$ssth->execute();

while(my $row = $ssth->fetchrow_hashref()) {
    $sth->execute($row->{uid}, $row->{gid})
        or die("Unable to insert user_group\n");
}
$sth->finish();

unless($skipshadow) {
    $sp_dbh = DBI->connect("DBI:SQLite:dbname=$ST_SP_DB", '', '')
        or die("Unable to open SQLite shadow connection\n");

    $sp_dbh->do(q{CREATE TEMPORARY TABLE tmp_shadow
        (username TEXT, passwd TEXT)})
        or die("Unable to create temporary shadow table\n");

    $ssth = $pg_dbh->prepare(q{SELECT username, passwd FROM vhffs_users u
    INNER JOIN vhffs_object o ON o.object_id = u.object_id WHERE o.state = 6})
        or die("Unable to prepare shadow SELECT statement\n");
    $sth = $sp_dbh->prepare(q{INSERT INTO tmp_shadow(username, passwd)
        VALUES(?, ?)})
        or die("Unable to prepare shadow INSERT statement\n");

    $ssth->execute();

    while(my $row = $ssth->fetchrow_hashref()) {
        $sth->execute($row->{username}, $row->{passwd})
            or die('Unable to insert shadow user '.$row->{username}."\n");
    }
}


# Required to avoid warning "closing dbh with active statement handles"
undef $sth;

$pg_dbh->disconnect();

$pw_dbh->do(q{DELETE FROM passwd WHERE uid NOT IN(SELECT uid FROM tmp_passwd)});
$pw_dbh->do(q{DELETE FROM groups WHERE gid NOT IN(SELECT gid FROM tmp_groups)});
$pw_dbh->do(q{DELETE FROM user_group WHERE NOT EXISTS(SELECT * FROM tmp_user_group
WHERE tmp_user_group.uid = user_group.uid AND tmp_user_group.gid = user_group.gid)});
$sp_dbh->do(q{DELETE FROM shadow WHERE username NOT IN(SELECT username FROM
    tmp_shadow)}) unless($skipshadow);

$pw_dbh->do(q{INSERT OR REPLACE INTO passwd SELECT * FROM tmp_passwd});
$pw_dbh->do(q{INSERT OR REPLACE INTO groups SELECT * FROM tmp_groups});
$pw_dbh->do(q{INSERT OR IGNORE INTO user_group SELECT * FROM tmp_user_group});
$sp_dbh->do(q{INSERT OR REPLACE INTO shadow SELECT * FROM tmp_shadow})
    unless($skipshadow);

$pw_dbh->commit();
$pw_dbh->disconnect();
