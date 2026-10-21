# Sourced by /sbin/sysupgrade (include /lib/upgrade) before it builds the config backup.
# Only for a repo still in the old place, /overlay/upper/etc/.git: etcgit writes it behind overlayfs, so
# the merged /etc view can still serve stale /etc/.git files to the backup. Drop the VFS caches first.
# Goes when no device has a repo there.
[ -d /overlay/upper/etc/.git ] || return 0
sync
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
