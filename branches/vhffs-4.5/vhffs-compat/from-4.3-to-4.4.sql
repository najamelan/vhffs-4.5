-- Old VHFFS users have unused ACL perm level 12 in their databases
UPDATE vhffs_acl SET perm=10 WHERE perm=12;

-- Remove useless and buggy ACL
-- There was a stupid ACL where granted_oid is the primary group of a user (so this is a default ACL on users of this group given ACL terminology used in VHFFS)
--   BUT target_oid is the user itself. So it means that the user of its own group, so the user itself (granted) gets ACL_DENIED perm on the user itself (target).
-- VHFFS have to handle user primary groups outside of ACL scope, we can remove all of those ACL.
-- Although, default ACL is ACL_DENIED, which is what we want for users on their primary group.
DELETE FROM vhffs_acl acl WHERE acl.target_oid IN (SELECT object_id FROM vhffs_object WHERE type=10) AND acl.granted_oid IN (SELECT object_id FROM vhffs_object WHERE type=11);

-- Removed useless ACL on users where user is currently the owner_uid of the object, thus already having ACL_DELETE privilege
DELETE FROM vhffs_acl acl
	WHERE acl.granted_oid IN (SELECT acl.granted_oid FROM vhffs_acl acl INNER JOIN vhffs_object ot ON ot.object_id=acl.target_oid INNER JOIN vhffs_object og ON og.object_id=acl.granted_oid WHERE og.type=10 AND og.owner_uid=ot.owner_uid)
	AND acl.target_oid IN (SELECT acl.target_oid FROM vhffs_acl acl INNER JOIN vhffs_object ot ON ot.object_id=acl.target_oid INNER JOIN vhffs_object og ON og.object_id=acl.granted_oid WHERE og.type=10 AND og.owner_uid=ot.owner_uid);

-- Removed useless ACL on groups where group is currently the owner_gid of the object and where the perm is set to ACL_VIEW, which is the default privilege
DELETE FROM vhffs_acl acl
	WHERE acl.granted_oid IN (SELECT acl.granted_oid FROM vhffs_acl acl INNER JOIN vhffs_object ot ON ot.object_id=acl.target_oid INNER JOIN vhffs_object og ON og.object_id=acl.granted_oid WHERE og.type=11 AND og.owner_gid=ot.owner_gid AND acl.perm=2)
	AND acl.target_oid IN (SELECT acl.target_oid FROM vhffs_acl acl INNER JOIN vhffs_object ot ON ot.object_id=acl.target_oid INNER JOIN vhffs_object og ON og.object_id=acl.granted_oid WHERE og.type=11 AND og.owner_gid=ot.owner_gid AND acl.perm=2);

-- Set new mailings states
ALTER TABLE vhffs_mailings RENAME COLUMN id_mailing TO mailing_id;
UPDATE vhffs_mailings SET state=0 WHERE state=3;
UPDATE vhffs_mailings SET state=1 WHERE state=6;
