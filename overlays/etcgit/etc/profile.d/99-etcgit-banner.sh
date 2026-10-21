# Show etcgit tips and warnings on interactive shells
[ -t 1 ] || return 0

if [ ! -d /overlay/upper/etc/.git ]; then
  cat <<'BANNER'

 ┌─────────────────────────────────────────────────────────────┐
 │  /etc is not under git yet                                  │
 │                                                             │
 │  Initialize new repo:   etcgit init [REMOTE_URL] [BRANCH]   │
 │  Import from remote:    etcgit import <REMOTE_URL> [BRANCH] │
 │                                                             │
 │  Examples:                                                  │
 │    etcgit init                                              │
 │    etcgit import git@github.com:you/openwrt-etc.git main    │
 │                                                             │
 │  Tip: put your SSH key at /root/.ssh/id_ed25519             │
 └─────────────────────────────────────────────────────────────┘

BANNER
  return 0
fi

# Repo exists: show useful warnings
branch="$(etcgit rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
status_porcelain="$(etcgit status --porcelain 2>/dev/null || true)"
status_short="$(etcgit status -sb 2>/dev/null || true)"

# Ahead/behind detection (only if upstream configured)
upstream="$(etcgit rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)"
ahead="0"
behind="0"
if [ -n "$upstream" ]; then
  set -- $(etcgit rev-list --left-right --count "$upstream"...HEAD 2>/dev/null || echo "0 0")
  behind="$1"
  ahead="$2"
fi

warned=0
if [ -n "$status_porcelain" ]; then
  warned=1
  echo
  echo "⚠ Uncommitted changes in /etc (branch: $branch)"
  echo "$status_short" | sed 's/^/   /'
  # Show a concise diff summary (avoid flooding the terminal)
  diffstat="$(etcgit --no-pager diff --stat 2>/dev/null || true)"
  [ -n "$diffstat" ] && { echo; echo "$diffstat" | sed 's/^/   /'; }
  echo "→ Commit/push:  etcgit add -A && etcgit commit -m \"...\" && etcgit push"
fi

if [ "$ahead" -gt 0 ]; then
  [ "$warned" -eq 0 ] && echo
  echo "⚠ Local branch '$branch' is ahead of '$upstream' by $ahead commit(s)."
  echo "→ Push:  etcgit push"
  warned=1
fi

if [ "$behind" -gt 0 ]; then
  [ "$warned" -eq 0 ] && echo
  echo "⚠ Local branch '$branch' is behind '$upstream' by $behind commit(s)."
  echo "→ Update:  etcgit pull --rebase"
  warned=1
fi

[ "$warned" -eq 1 ] && echo
unset branch status_porcelain status_short upstream ahead behind warned
