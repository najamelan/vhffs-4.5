CREATE TABLE vhffs_dns_soa (
	id INTEGER NOT NULL,
	origin varchar(255) NOT NULL,
	ns varchar(255) NOT NULL,
	mbox varchar(255) NOT NULL,
	serial INTEGER NOT NULL DEFAULT 1,
	refresh INTEGER NOT NULL DEFAULT 28800,
	retry INTEGER NOT NULL DEFAULT 7200,
	expire INTEGER NOT NULL DEFAULT 604800,
	minimum INTEGER NOT NULL DEFAULT 86400,
	ttl INTEGER NOT NULL DEFAULT 86400,
	CONSTRAINT vhffs_dns_soa_pkey PRIMARY KEY (id),
	CONSTRAINT vhffs_dns_unique_origin UNIQUE (origin)
) WITH (OIDS);

CREATE TABLE vhffs_dns_rr (
	id INTEGER NOT NULL,
	zone INTEGER NOT NULL,
	name varchar(64) NOT NULL,
	type VARCHAR(5) NOT NULL,
	data varchar(512) NOT NULL,
	aux INTEGER NOT NULL DEFAULT 0,
	ttl INTEGER NOT NULL DEFAULT 86400,
	CONSTRAINT vhffs_dns_rr_pkey PRIMARY KEY (id),
	CONSTRAINT fk_vhffs_dns_rr_chk_type CHECK (type='A' OR type='AAAA' OR type='CNAME' OR type='HINFO' OR type='MX' OR type='NS' OR type='PTR' OR type='RP' OR type='SRV' OR type='TXT'),
	CONSTRAINT fk_vhffs_dns_rr_vhffs_dns_soa FOREIGN KEY (zone) REFERENCES vhffs_dns_soa(id) ON DELETE CASCADE
) WITH (OIDS);
CREATE INDEX idx_vhffs_dns_rr_zone ON vhffs_dns_rr(zone);
CREATE INDEX idx_vhffs_dns_rr_type ON vhffs_dns_rr(type);
CREATE INDEX idx_vhffs_dns_rr_name ON vhffs_dns_rr(name);
