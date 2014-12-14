#
# This is a sample cron job for VHFFS robots
# Please modify it depending on your needs (disable uneeded bots
# and adjust run frequencies).
#
0 4	* * *	root	[ -x /usr/bin/vhffs_maintenance ] && /usr/bin/vhffs_maintenance
