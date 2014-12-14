ALTER TABLE vhffs_pgsql ADD COLUMN dbencoding VARCHAR(20) NOT NULL DEFAULT 'LATIN1';

-- 16 bytes is not enough for vhffs_pgsql.dbuser
BEGIN;
ALTER TABLE vhffs_pgsql ADD COLUMN dbuser_new varchar(200);
UPDATE vhffs_pgsql SET dbuser_new = dbuser;
ALTER TABLE vhffs_pgsql DROP COLUMN dbuser; 
ALTER TABLE vhffs_pgsql RENAME COLUMN dbuser_new TO dbuser;
ALTER TABLE vhffs_pgsql ALTER COLUMN dbuser SET NOT NULL;
COMMIT;

-- add allowpop and allowimap field to vhffs_boxes
ALTER TABLE vhffs_boxes ADD COLUMN allowpop boolean;
ALTER TABLE vhffs_boxes ALTER COLUMN allowpop SET DEFAULT true;
UPDATE vhffs_boxes SET allowpop=true;
ALTER TABLE vhffs_boxes ALTER COLUMN allowpop SET NOT NULL;

ALTER TABLE vhffs_boxes ADD COLUMN allowimap boolean;
ALTER TABLE vhffs_boxes ALTER COLUMN allowimap SET DEFAULT true;
UPDATE vhffs_boxes SET allowimap=true;
ALTER TABLE vhffs_boxes ALTER COLUMN allowimap SET NOT NULL;

-- add vhffs_cron table
CREATE TABLE vhffs_cron
(
        cron_id SERIAL,
        cronpath varchar NOT NULL,
        interval int4 NOT NULL,
        reportmail varchar NOT NULL,
        lastrundate int8,
        lastrunreturncode int4,
        nextrundate int8,
        running int4,
        object_id int4 NOT NULL,
        CONSTRAINT vhffs_cron_pkey PRIMARY KEY( cron_id )
) WITH OIDS;
ALTER TABLE vhffs_cron ADD CONSTRAINT vhffs_cron_unique_cronpath UNIQUE (cronpath);
CREATE INDEX idx_vhffs_cron_nextrun ON vhffs_cron(nextrundate);
ALTER TABLE vhffs_cron ADD CONSTRAINT fk_vhffs_vhffs_cron_vhffs_object FOREIGN KEY (object_id) REFERENCES vhffs_object(object_id) ON DELETE CASCADE;

-- 128 bytes is not enough for vhffs_dns_rr.data, TXT fields might be bigger
BEGIN;
ALTER TABLE vhffs_dns_rr ADD COLUMN data_new varchar(512);
UPDATE vhffs_dns_rr SET data_new = data;
ALTER TABLE vhffs_dns_rr DROP COLUMN data; 
ALTER TABLE vhffs_dns_rr RENAME COLUMN data_new TO data;
ALTER TABLE vhffs_dns_rr ALTER COLUMN data SET NOT NULL;
COMMIT;

-- add Tags

CREATE TABLE vhffs_tag (
    tag_id SERIAL,
-- Label for the tag in platform's default language
    label VARCHAR(30) NOT NULL,
    description TEXT NOT NULL,
    updated int8 NOT NULL,
-- This tag's creator id, null if user has been deleted
    updater_id int4,
    category_id int4 NOT NULL,
    CONSTRAINT vhffs_tag_pkey PRIMARY KEY( tag_id )
) WITH OIDS;

-- Table containing all tag categories for this platform
-- See vhffs_tag for description...
CREATE TABLE vhffs_tag_category (
    tag_category_id SERIAL,
    label VARCHAR(30) NOT NULL,
    description TEXT NOT NULL,
-- Access level of the category
    visibility int4 NOT NULL DEFAULT 0,
    updated int8 NOT NULL,
    updater_id int4,
    CONSTRAINT vhffs_tag_category_pkey PRIMARY KEY( tag_category_id )
) WITH OIDS;

-- Tag categories' translations
CREATE TABLE vhffs_tag_category_translation (
    tag_category_id int4 NOT NULL,
    lang VARCHAR(16) NOT NULL,
    label VARCHAR(30) NOT NULL,
    description TEXT NOT NULL,
    updated int8 NOT NULL,
    updater_id int4,
    CONSTRAINT vhffs_tag_category_translation_pkey PRIMARY KEY( tag_category_id, lang )
) WITH OIDS;

-- Tags requested by users
CREATE TABLE vhffs_tag_request (
    tag_request_id SERIAL,
-- Label of the category. We could have a label
-- and an id and fill in the correct field depending
-- of the existence of the category
    category_label VARCHAR(30) NOT NULL,
    tag_label VARCHAR(30) NOT NULL,
    created int8 NOT NULL,
-- User who requested the tag
    requester_id int4,
-- For which object
    tagged_id int4,
    CONSTRAINT vhffs_tag_request_pkey PRIMARY KEY( tag_request_id )
);

-- Description & label translation for a tag
CREATE TABLE vhffs_tag_translation (
    tag_id int4 NOT NULL,
    lang VARCHAR(16) NOT NULL,
    label VARCHAR(30) NOT NULL,
    description TEXT NOT NULL,
    updated int8 NOT NULL,
    updater_id int4,
    CONSTRAINT vhffs_tag_translation_pkey PRIMARY KEY( tag_id, lang )
) WITH OIDS;


-- add necessary constraints on tags
ALTER TABLE vhffs_tag_category ADD CONSTRAINT vhffs_tag_category_unique_label UNIQUE(label);
ALTER TABLE vhffs_tag ADD CONSTRAINT vhffs_tag_unique_label_category UNIQUE(label , category_id);

ALTER TABLE vhffs_object_tag ADD CONSTRAINT fk_vhffs_object_tag_vhffs_users FOREIGN KEY ( updater_id ) REFERENCES vhffs_users( uid ) ON DELETE SET NULL;

-- and not necessary but useful
CREATE INDEX idx_vhffs_tag_category_visibility ON vhffs_tag_category(visibility);


-- delete duplicate values in vhffs_ml_subscribers (inserted members where not lowered)
DELETE FROM vhffs_ml_subscribers WHERE EXISTS ( SELECT 'x' FROM vhffs_ml_subscribers m WHERE LOWER(m.member) = LOWER(vhffs_ml_subscribers.member) AND m.ml_id = vhffs_ml_subscribers.ml_id AND m.sub_id < vhffs_ml_subscribers.sub_id );
UPDATE vhffs_ml_subscribers set member=LOWER(member);

-- Server encoding is always used to avoid compatibility issues
ALTER TABLE vhffs_pgsql DROP COLUMN dbencoding;
