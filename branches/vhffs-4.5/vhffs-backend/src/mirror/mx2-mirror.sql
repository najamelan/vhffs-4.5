CREATE TABLE vhffs_mx2 (
	mx_id int4 NOT NULL,
	domain varchar NOT NULL,
	catchall bool NOT NULL DEFAULT false,
	CONSTRAINT vhffs_mx2_unique_mx_id PRIMARY KEY (mx_id),
	CONSTRAINT vhffs_mx2_unique_domain UNIQUE (domain)
) WITH (OIDS);

CREATE TABLE vhffs_mx2_localpart (
	mx_id int4 NOT NULL,
	localpart varchar NOT NULL,
	CONSTRAINT vhffs_mx2_localpart_unique_mx_id_localpart PRIMARY KEY (mx_id, localpart),
	CONSTRAINT fk_vhffs_mx2_localpart_vhffs_mx2 FOREIGN KEY (mx_id) REFERENCES vhffs_mx2(mx_id) ON DELETE CASCADE
) WITH (OIDS);
