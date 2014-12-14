CREATE TABLE vhffs_object (
	object_id integer,
	owner_uid int4,
	owner_gid int4,
	date_creation int8,
	type int4 NOT NULL DEFAULT 0,
	CONSTRAINT vhffs_object_pkey PRIMARY KEY (object_id)
) WITH OIDS;
CREATE INDEX idx_vhffs_object_owner_uid ON vhffs_object(owner_uid);
CREATE INDEX idx_vhffs_object_owner_gid ON vhffs_object(owner_gid);
CREATE INDEX idx_vhffs_object_type ON vhffs_object(type);
CREATE INDEX idx_vhffs_object_date_creation ON vhffs_object(date_creation);

CREATE TABLE vhffs_mx (
	mx_id serial,
	domain varchar NOT NULL,
	object_id int4 NOT NULL,
	CONSTRAINT vhffs_mx_pkey PRIMARY KEY (mx_id),
	CONSTRAINT vhffs_mx_unique_domain UNIQUE (domain),
	CONSTRAINT vhffs_mx_unique_object_id UNIQUE (object_id)
) WITH (OIDS);

CREATE TABLE vhffs_mx_catchall (
	catchall_id serial,
	mx_id int4 NOT NULL,
	box_id int4 NOT NULL,
	CONSTRAINT vhffs_mx_catchall_pkey PRIMARY KEY (catchall_id),
	CONSTRAINT vhffs_mx_catchall_unique_domain_box UNIQUE (mx_id, box_id)
) WITH (OIDS);

CREATE TABLE vhffs_mx_localpart (
	localpart_id serial,
	mx_id int4 NOT NULL,
	localpart varchar NOT NULL,
	password varchar,
	nospam boolean NOT NULL DEFAULT FALSE,
	novirus boolean NOT NULL DEFAULT FALSE,
	CONSTRAINT vhffs_mx_localpart_pkey PRIMARY KEY (localpart_id),
	CONSTRAINT vhffs_mx_localpart_unique_domain_localpart UNIQUE (mx_id, localpart)
) WITH (OIDS);

CREATE TABLE vhffs_mx_redirect (
	redirect_id serial,
	localpart_id int4 NOT NULL,
	redirect varchar NOT NULL,
	CONSTRAINT vhffs_mx_redirect_pkey PRIMARY KEY (redirect_id),
	CONSTRAINT vhffs_mx_redirect_unique_localpart_redirect UNIQUE (localpart_id, redirect)
) WITH (OIDS);

CREATE TABLE vhffs_mx_box (
	box_id serial,
	localpart_id int4 NOT NULL,
	allowpop boolean NOT NULL DEFAULT TRUE,
	allowimap boolean NOT NULL DEFAULT TRUE,
	CONSTRAINT vhffs_mx_box_pkey PRIMARY KEY (box_id),
	CONSTRAINT vhffs_mx_box_unique_domain_localpart UNIQUE (localpart_id)
) WITH (OIDS);

CREATE TABLE vhffs_mx_ml (
	ml_id serial,
	localpart_id int4 NOT NULL,
	object_id int4 NOT NULL,
	prefix varchar,
	sub_ctrl int4 NOT NULL,
	post_ctrl int4 NOT NULL,
	reply_to boolean NOT NULL DEFAULT FALSE,
	open_archive boolean NOT NULL DEFAULT FALSE,
	signature text,
	CONSTRAINT vhffs_mx_ml_pkey PRIMARY KEY (ml_id),
	CONSTRAINT vhffs_mx_ml_unique_domain_localpart UNIQUE (localpart_id),
	CONSTRAINT vhffs_mx_ml_unique_object_id UNIQUE (object_id)
) WITH (OIDS);
CREATE INDEX idx_vhffs_mx_ml_open_archive ON vhffs_mx_ml(open_archive);

CREATE TABLE vhffs_mx_ml_subscribers (
	sub_id serial,
	ml_id int4 NOT NULL,
	member varchar NOT NULL,
	perm int4 NOT NULL,
	hash varchar,
	language varchar(16),
	CONSTRAINT vhffs_mx_ml_subscribers_pkey PRIMARY KEY (sub_id),
	CONSTRAINT vhffs_mx_ml_subscribers_member_list UNIQUE (ml_id, member)
) WITH (OIDS);

-- Foreign key constraints
ALTER TABLE vhffs_mx ADD CONSTRAINT fk_vhffs_mx_vhffs_object FOREIGN KEY (object_id) REFERENCES vhffs_object(object_id) ON DELETE CASCADE;

ALTER TABLE vhffs_mx_localpart ADD CONSTRAINT fk_vhffs_mx_localpart_vhffs_mx FOREIGN KEY (mx_id) REFERENCES vhffs_mx(mx_id) ON DELETE CASCADE;

ALTER TABLE vhffs_mx_catchall ADD CONSTRAINT fk_vhffs_mx_catchall_vhffs_mx FOREIGN KEY (mx_id) REFERENCES vhffs_mx(mx_id) ON DELETE CASCADE;
ALTER TABLE vhffs_mx_catchall ADD CONSTRAINT fk_vhffs_mx_catchall_vhffs_mx_box FOREIGN KEY (box_id) REFERENCES vhffs_mx_box(box_id) ON DELETE CASCADE;

ALTER TABLE vhffs_mx_box ADD CONSTRAINT fk_vhffs_mx_box_vhffs_localpart FOREIGN KEY (localpart_id) REFERENCES vhffs_mx_localpart(localpart_id) ON DELETE CASCADE;

ALTER TABLE vhffs_mx_redirect ADD CONSTRAINT fk_vhffs_mx_redirect_vhffs_localpart FOREIGN KEY (localpart_id) REFERENCES vhffs_mx_localpart(localpart_id) ON DELETE CASCADE;

ALTER TABLE vhffs_mx_ml ADD CONSTRAINT fk_vhffs_mx_ml_vhffs_object FOREIGN KEY (object_id) REFERENCES vhffs_object(object_id) ON DELETE CASCADE;
ALTER TABLE vhffs_mx_ml ADD CONSTRAINT fk_vhffs_mx_ml_vhffs_localpart FOREIGN KEY (localpart_id) REFERENCES vhffs_mx_localpart(localpart_id) ON DELETE CASCADE;

ALTER TABLE vhffs_mx_ml_subscribers ADD CONSTRAINT fk_vhffs_mx_ml_subscribers_vhffs_mx_ml FOREIGN KEY (ml_id) REFERENCES vhffs_mx_ml(ml_id) ON DELETE CASCADE;
