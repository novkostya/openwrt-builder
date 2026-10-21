# etcgit's login warnings. The logic lives in /usr/bin/etcgit: sysupgrade keeps /etc/profile.d (base-files),
# so a changed copy here would outlive the image that shipped it.
[ -t 1 ] && etcgit banner
