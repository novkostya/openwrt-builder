# Fall back to xterm-256color when the client announces a terminal type we have no terminfo for
# (e.g. xterm-ghostty, xterm-kitty, wezterm), so ncurses tools and colors keep working.
if [ -n "$TERM" ]; then
  _t1=$(printf %s "$TERM" | cut -c1)
  [ -e "/usr/share/terminfo/$_t1/$TERM" ] || export TERM=xterm-256color
  unset _t1
fi
