# Sourced by /sbin/sysupgrade (include /lib/upgrade) before it builds the config backup.
# etcgit writes its repo in /overlay/upper/etc directly, so the merged /etc view can still serve stale
# /etc/.git files; the backup reads /etc/.git through that view. Drop the VFS caches first so the
# backup gets the current refs and index, whoever last wrote to the repo.
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
