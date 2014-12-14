-- update_id field is cleared when the user is unsubscribing
ALTER TABLE vhffs_object_tag ALTER COLUMN updater_id DROP NOT NULL;

-- add the user who modified the object in the object's history
ALTER TABLE vhffs_history ADD COLUMN source_uid INTEGER DEFAULT NULL;
ALTER TABLE vhffs_history ADD CONSTRAINT fk_vhffs_history_vhffs_users FOREIGN KEY (source_uid) REFERENCES vhffs_users(uid);

-- add mercurial table
CREATE TABLE vhffs_mercurial
(
	mercurial_id SERIAL,
	reponame varchar NOT NULL,
	public int4 NOT NULL,
	ml_name varchar,
	object_id int4 NOT NULL,
	CONSTRAINT vhffs_mercurial_pkey PRIMARY KEY( mercurial_id )
) WITH OIDS;

ALTER TABLE vhffs_mercurial ADD CONSTRAINT vhffs_mercurial_unique_reponame UNIQUE (reponame);
CREATE INDEX idx_vhffs_mercurial_public ON vhffs_mercurial(public);
CREATE INDEX idx_vhffs_mercurial_object_id ON vhffs_mercurial(object_id);
ALTER TABLE vhffs_mercurial ADD CONSTRAINT fk_vhffs_mercurial_vhffs_object FOREIGN KEY (object_id) REFERENCES vhffs_object(object_id) ON DELETE CASCADE;

-- add ircnick in vhffs_users
ALTER TABLE vhffs_users ADD COLUMN ircnick VARCHAR(16) DEFAULT NULL;
ALTER TABLE vhffs_users ADD CONSTRAINT vhffs_users_unique_ircnick UNIQUE (ircnick);

-- add bazaar table
CREATE TABLE vhffs_bazaar
(
	bazaar_id SERIAL,
	reponame varchar NOT NULL,
	public int4 NOT NULL,
	ml_name varchar,
	object_id int4 NOT NULL,
	CONSTRAINT vhffs_bazaar_pkey PRIMARY KEY( bazaar_id )
) WITH OIDS;

ALTER TABLE vhffs_bazaar ADD CONSTRAINT vhffs_bazaar_unique_reponame UNIQUE (reponame);
CREATE INDEX idx_vhffs_bazaar_public ON vhffs_bazaar(public);
CREATE INDEX idx_vhffs_bazaar_object_id ON vhffs_bazaar(object_id);
ALTER TABLE vhffs_bazaar ADD CONSTRAINT fk_vhffs_bazaar_vhffs_object FOREIGN KEY (object_id) REFERENCES vhffs_object(object_id) ON DELETE CASCADE;

ALTER TABLE vhffs_history ADD CONSTRAINT fk_vhffs_history_vhffs_users2 FOREIGN KEY (source_uid) REFERENCES vhffs_users(uid) ON DELETE SET NULL;
ALTER TABLE vhffs_history DROP CONSTRAINT fk_vhffs_history_vhffs_users;
ALTER TABLE vhffs_history ADD CONSTRAINT fk_vhffs_history_vhffs_users FOREIGN KEY (source_uid) REFERENCES vhffs_users(uid) ON DELETE SET NULL;
ALTER TABLE vhffs_history DROP CONSTRAINT fk_vhffs_history_vhffs_users2;
