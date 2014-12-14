-- Removed vhffs_users.passwd varchar limit in order to accept crypt sha512 strings
BEGIN;
DROP VIEW vhffs_forum;
DROP VIEW vhffs_shadow;
ALTER TABLE vhffs_users ALTER COLUMN passwd TYPE varchar;
CREATE VIEW vhffs_forum AS
SELECT users.username, users.passwd, users.firstname, users.lastname, users.mail, object.date_creation, object.state
FROM vhffs_users users, vhffs_object object
WHERE object.object_id=users.object_id;
CREATE VIEW vhffs_shadow AS
SELECT uid, gid, username, shell, passwd, '0'::int4 as newtok , '0'::int4 as expired , homedir
FROM vhffs_users;
COMMIT;

-- Former indexes on service.object_id are actually more comfortable with uniqueness
DROP INDEX idx_vhffs_cvs_object_id;
DROP INDEX idx_vhffs_dns_object_id;
DROP INDEX idx_vhffs_groups_object_id;
DROP INDEX idx_vhffs_users_object_id;
DROP INDEX idx_vhffs_httpd_object_id;
DROP INDEX idx_vhffs_ml_object_id;
DROP INDEX idx_vhffs_mxdomain_object_id;
DROP INDEX idx_vhffs_mysql_object_id;
DROP INDEX idx_vhffs_pgsql_object_id;
DROP INDEX idx_vhffs_repository_object_id;
DROP INDEX idx_vhffs_svn_object_id;
DROP INDEX idx_vhffs_git_object_id;
DROP INDEX idx_vhffs_mercurial_object_id;
DROP INDEX idx_vhffs_bazaar_object_id;
ALTER TABLE vhffs_cvs ADD CONSTRAINT vhffs_cvs_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_dns ADD CONSTRAINT vhffs_dns_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_groups ADD CONSTRAINT vhffs_groups_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_users ADD CONSTRAINT vhffs_users_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_httpd ADD CONSTRAINT vhffs_httpd_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_ml ADD CONSTRAINT vhffs_ml_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_mxdomain ADD CONSTRAINT vhffs_mxdomain_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_mysql ADD CONSTRAINT vhffs_mysql_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_pgsql ADD CONSTRAINT vhffs_pgsql_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_repository ADD CONSTRAINT vhffs_repository_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_svn ADD CONSTRAINT vhffs_svn_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_git ADD CONSTRAINT vhffs_git_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_mercurial ADD CONSTRAINT vhffs_mercurial_unique_object_id UNIQUE(object_id);
ALTER TABLE vhffs_bazaar ADD CONSTRAINT vhffs_bazaar_unique_object_id UNIQUE(object_id);

-- Migration to the new VHFFS mail database

-- Mail domains
CREATE TABLE vhffs_mx (
	mx_id serial,
-- Domain name
	domain varchar NOT NULL,
	object_id int4 NOT NULL,
	CONSTRAINT vhffs_mx_pkey PRIMARY KEY (mx_id),
	CONSTRAINT vhffs_mx_unique_domain UNIQUE (domain),
	CONSTRAINT vhffs_mx_unique_object_id UNIQUE (object_id)
) WITH (OIDS);

-- Catchall boxes
CREATE TABLE vhffs_mx_catchall (
	catchall_id serial,
-- Mail domain
	mx_id int4 NOT NULL,
-- Box
	box_id int4 NOT NULL,
	CONSTRAINT vhffs_mx_catchall_pkey PRIMARY KEY (catchall_id),
	CONSTRAINT vhffs_mx_catchall_unique_domain_box UNIQUE (mx_id, box_id)
) WITH (OIDS);

-- Mail localparts
CREATE TABLE vhffs_mx_localpart (
	localpart_id serial,
-- Mail domain
	mx_id int4 NOT NULL,
-- Local part of the address (part before @)
	localpart varchar NOT NULL,
-- Password (of the box and/or a future redirect administration)
	password varchar,
-- Is antispam activated ?
	nospam boolean NOT NULL DEFAULT FALSE,
-- Is antivirus activated ?
	novirus boolean NOT NULL DEFAULT FALSE,
	CONSTRAINT vhffs_mx_localpart_pkey PRIMARY KEY (localpart_id),
	CONSTRAINT vhffs_mx_localpart_unique_domain_localpart UNIQUE (mx_id, localpart)
) WITH (OIDS);

-- Mail redirects
CREATE TABLE vhffs_mx_redirect (
	redirect_id serial,
-- Local part
	localpart_id int4 NOT NULL,
-- Mail address to which mails are forwarded
	redirect varchar NOT NULL,
	CONSTRAINT vhffs_mx_redirect_pkey PRIMARY KEY (redirect_id),
	CONSTRAINT vhffs_mx_redirect_unique_localpart_redirect UNIQUE (localpart_id, redirect)
) WITH (OIDS);

-- Mail boxes
CREATE TABLE vhffs_mx_box (
	box_id serial,
-- Local part
	localpart_id int4 NOT NULL,
-- Allow pop login ?
	allowpop boolean NOT NULL DEFAULT TRUE,
-- Allow imap login ?
	allowimap boolean NOT NULL DEFAULT TRUE,
-- State of the box (we don't have object for this entity...)
	state int4 NOT NULL,
	CONSTRAINT vhffs_mx_box_pkey PRIMARY KEY (box_id),
	CONSTRAINT vhffs_mx_box_unique_domain_localpart UNIQUE (localpart_id)
) WITH (OIDS);
-- state is used in vhffs_mx_box in where clauses
CREATE INDEX idx_vhffs_mx_box_state ON vhffs_mx_box(state);

-- Mailing lists
CREATE TABLE vhffs_mx_ml (
	ml_id serial,
-- Local part
	localpart_id int4 NOT NULL,
-- Object
	object_id int4 NOT NULL,
-- Prefix prepended to all subjects
	prefix varchar,
-- How are subscriptions managed
	sub_ctrl int4 NOT NULL,
-- Posting policy
	post_ctrl int4 NOT NULL,
-- Add Reply-To header?
	reply_to boolean NOT NULL DEFAULT FALSE,
-- Do we keep open archives for this list?
	open_archive boolean NOT NULL DEFAULT FALSE,
-- Signature appended to all messages
	signature text,
	CONSTRAINT vhffs_mx_ml_pkey PRIMARY KEY (ml_id),
	CONSTRAINT vhffs_mx_ml_unique_domain_localpart UNIQUE (localpart_id),
	CONSTRAINT vhffs_mx_ml_unique_object_id UNIQUE (object_id)
) WITH (OIDS);
-- vhffs_mx_ml.open_archive may be used in where clause to select on public ml
CREATE INDEX idx_vhffs_mx_ml_open_archive ON vhffs_mx_ml(open_archive);

-- Subscribers of a mailing list
CREATE TABLE vhffs_mx_ml_subscribers (
	sub_id serial,
-- Mailing list to which this address has subscribed
	ml_id int4 NOT NULL,
-- Email address of the subscriber
	member varchar NOT NULL,
-- Access level of this member
	perm int4 NOT NULL,
-- Hash for activation
	hash varchar,
-- Language of the subscriber
	language varchar(16),
	CONSTRAINT vhffs_mx_ml_subscribers_pkey PRIMARY KEY (sub_id),
	CONSTRAINT vhffs_mx_ml_subscribers_member_list UNIQUE (ml_id, member)
) WITH (OIDS);


ALTER TABLE vhffs_mx ADD CONSTRAINT fk_vhffs_mx_vhffs_object FOREIGN KEY (object_id) REFERENCES vhffs_object(object_id) ON DELETE CASCADE;
ALTER TABLE vhffs_mx_ml ADD CONSTRAINT fk_vhffs_mx_ml_vhffs_object FOREIGN KEY (object_id) REFERENCES vhffs_object(object_id) ON DELETE CASCADE;

ALTER TABLE vhffs_mx_catchall ADD CONSTRAINT fk_vhffs_mx_catchall_vhffs_mx FOREIGN KEY (mx_id) REFERENCES vhffs_mx(mx_id) ON DELETE CASCADE;
ALTER TABLE vhffs_mx_catchall ADD CONSTRAINT fk_vhffs_mx_catchall_vhffs_mx_box FOREIGN KEY (box_id) REFERENCES vhffs_mx_box(box_id) ON DELETE CASCADE;

ALTER TABLE vhffs_mx_localpart ADD CONSTRAINT fk_vhffs_mx_localpart_vhffs_mx FOREIGN KEY (mx_id) REFERENCES vhffs_mx(mx_id) ON DELETE CASCADE;

ALTER TABLE vhffs_mx_redirect ADD CONSTRAINT fk_vhffs_mx_redirect_vhffs_localpart FOREIGN KEY (localpart_id) REFERENCES vhffs_mx_localpart(localpart_id) ON DELETE CASCADE;
ALTER TABLE vhffs_mx_box ADD CONSTRAINT fk_vhffs_mx_box_vhffs_localpart FOREIGN KEY (localpart_id) REFERENCES vhffs_mx_localpart(localpart_id) ON DELETE CASCADE;
ALTER TABLE vhffs_mx_ml ADD CONSTRAINT fk_vhffs_mx_ml_vhffs_localpart FOREIGN KEY (localpart_id) REFERENCES vhffs_mx_localpart(localpart_id) ON DELETE CASCADE;

ALTER TABLE vhffs_mx_ml_subscribers ADD CONSTRAINT fk_vhffs_mx_ml_subscribers_vhffs_mx_ml FOREIGN KEY (ml_id) REFERENCES vhffs_mx_ml(ml_id) ON DELETE CASCADE;

-- Migrate data from previous mail tables

-- fill vhffs_mx from former vhffs_mxdomain
INSERT INTO vhffs_mx (domain, object_id) SELECT domain, object_id FROM vhffs_mxdomain;

-- migrate boxes from vhffs_boxes to vhffs_mx_localpart,vhffs_mx_box
INSERT INTO vhffs_mx_localpart (mx_id,localpart,password,nospam,novirus) SELECT mx.mx_id,mb.local_part,mb.password,mb.nospam,mb.novirus FROM vhffs_mx mx INNER JOIN vhffs_boxes mb ON mb.domain=mx.domain;
INSERT INTO vhffs_mx_box (localpart_id,allowpop,allowimap,state) SELECT mxl.localpart_id,mb.allowpop,mb.allowimap,mb.state FROM vhffs_mx mx INNER JOIN vhffs_boxes mb ON mb.domain=mx.domain INNER JOIN vhffs_mx_localpart mxl ON mxl.localpart=mb.local_part AND mxl.mx_id=mx.mx_id;

-- migrate catchall from vhffs_mxdomain to vhffs_mx_localpart,vhffs_redirect
-- We only migrate catchall on box, catchall on any address is no more supported
INSERT INTO vhffs_mx_catchall (mx_id,box_id) SELECT mx.mx_id,mb.box_id FROM vhffs_mxdomain mxd INNER JOIN vhffs_mx mx ON mx.domain=mxd.domain INNER JOIN vhffs_mx_localpart mxl ON mxl.mx_id=mx.mx_id INNER JOIN vhffs_mx_box mb ON mb.localpart_id=mxl.localpart_id WHERE mxd.catchall IS NOT NULL AND mxd.catchall != '' AND mxl.localpart=substring(mxd.catchall from '(.*)@') AND mx.domain=substring(mxd.catchall from '@(.*)');

-- migrate forwards from vhffs_forwards to vhffs_mx_localpart,vhffs_mx_redirect
INSERT INTO vhffs_mx_localpart (mx_id,localpart) SELECT mx.mx_id,mf.local_part FROM vhffs_mx mx INNER JOIN vhffs_forward mf ON mf.domain=mx.domain;
INSERT INTO vhffs_mx_redirect (localpart_id,redirect) SELECT mxl.localpart_id,mf.remote_name FROM vhffs_mx mx INNER JOIN vhffs_forward mf ON mf.domain=mx.domain INNER JOIN vhffs_mx_localpart mxl ON mxl.localpart=mf.local_part AND mxl.mx_id=mx.mx_id;

-- migrate mailing list from vhffs_ml to vhffs_mx_ml
INSERT INTO vhffs_mx_localpart (mx_id,localpart) SELECT mx.mx_id,ml.local_part FROM vhffs_ml ml INNER JOIN vhffs_mx mx ON mx.domain=ml.domain;
INSERT INTO vhffs_mx_ml (ml_id,localpart_id,object_id,prefix,sub_ctrl,post_ctrl,reply_to,open_archive,signature) SELECT ml.ml_id,mxl.localpart_id,ml.object_id,ml.prefix,ml.sub_ctrl,ml.post_ctrl,ml.reply_to,ml.open_archive,ml.signature FROM vhffs_ml ml INNER JOIN vhffs_mx mx ON mx.domain=ml.domain INNER JOIN vhffs_mx_localpart mxl ON mxl.localpart=ml.local_part AND mxl.mx_id=mx.mx_id;
SELECT setval('vhffs_mx_ml_ml_id_seq', (SELECT COALESCE(MAX(ml_id), 1) FROM vhffs_mx_ml));

-- migrate mailing list subscribers
INSERT INTO vhffs_mx_ml_subscribers (sub_id,member,perm,hash,ml_id,language) SELECT sub_id,member,perm,hash,ml_id,language FROM vhffs_ml_subscribers;
SELECT setval('vhffs_mx_ml_subscribers_sub_id_seq', (SELECT COALESCE(MAX(sub_id), 1) FROM vhffs_mx_ml_subscribers));

-- DROP old tables

DROP TABLE vhffs_ml_subscribers;
DROP TABLE vhffs_ml;
DROP TABLE vhffs_boxes;
DROP TABLE vhffs_forward;
DROP TABLE vhffs_mxdomain;

-- update vhffs states values
BEGIN;
	UPDATE vhffs_object SET state=15 WHERE state=8;
	UPDATE vhffs_object SET state=14 WHERE state=7;
	UPDATE vhffs_mailings SET state=15 WHERE state=8;
	UPDATE vhffs_mailings SET state=14 WHERE state=7;
	UPDATE vhffs_user_group SET state=15 WHERE state=8;
	UPDATE vhffs_user_group SET state=14 WHERE state=7;
	UPDATE vhffs_mx_box SET state=15 WHERE state=8;
	UPDATE vhffs_mx_box SET state=14 WHERE state=7;
COMMIT;

-- add validated bool field to vhffs_users, so that we don't automatically delete users who used to be in a group/projet
ALTER TABLE vhffs_users ADD COLUMN validated BOOLEAN NOT NULL DEFAULT false;
UPDATE vhffs_users SET validated=true WHERE uid IN (SELECT ug.uid FROM vhffs_user_group ug);
