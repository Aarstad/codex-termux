#!/data/data/com.termux/files/usr/bin/bash
# Remove the Codex install. Leaves ~/.codex (your settings, credentials, history) alone.
#
#   ./uninstall.sh            remove the Codex install
#   ./uninstall.sh --config   …and ~/.codex
#
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LIBEXEC="$PREFIX/libexec/codex"
DROP_CONFIG=0
[ "${1:-}" = "--config" ] && DROP_CONFIG=1

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }

# Only remove the `codex` on PATH if it is ours; a different install keeps its name.
# The wrapper on PATH is ours if it mentions our libexec directory; anything
# else there belongs to a different install and is left alone.
if [ -f "$PREFIX/bin/codex" ] && grep -q 'libexec/codex' "$PREFIX/bin/codex" 2>/dev/null; then
  rm -f "$PREFIX/bin/codex"
  say "removed $PREFIX/bin/codex"
elif [ -e "$PREFIX/bin/codex" ]; then
  say "left $PREFIX/bin/codex alone (not installed by us)"
fi

rm -f "$PREFIX/bin/codex-update"

freed="$(du -ms "$LIBEXEC" 2>/dev/null | cut -f1 || echo 0)"
rm -rf "$LIBEXEC"
say "removed the binaries and DNS proxy (${freed}MB)"

if [ "$DROP_CONFIG" = 1 ]; then
  rm -rf "$HOME/.codex"
  say "removed ~/.codex"
else
  # The argv[0] helper symlinks point at the binary just deleted, so they are
  # cleared either way; the rest of ~/.codex is the user's.
  rm -rf "$HOME/.codex/tmp/arg0" 2>/dev/null || true
  say "kept ~/.codex (pass --config to remove it)"
fi

echo
[ "$DROP_CONFIG" = 1 ] || echo "  ~/.codex was not touched: settings, credentials and history are intact."
