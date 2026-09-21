#!/data/data/com.termux/files/usr/bin/bash
# Install OpenAI's Codex CLI to run natively in Termux.
#
#   ./install.sh                 install the latest release
#   ./install.sh --version X     install a specific release
#   ./install.sh --no-code-mode  skip the Code Mode host (~24MB download)
#
# The binaries need no loader: OpenAI's aarch64 musl builds are fully static
# (ET_EXEC, no PT_INTERP, no DT_NEEDED), so the kernel runs them directly.
#
# They do need DNS help. musl's resolver is linked into the binary and reads
# /etc/resolv.conf, which Android does not have, so name lookups fail from
# inside the process — including the OAuth token exchange, which makes login
# impossible. The `codex` wrapper starts a small bionic-side proxy for that.
#
# Not "#!/usr/bin/env bash" on purpose: Android has no /usr/bin/env.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LIBEXEC="$PREFIX/libexec/codex"
REPO="${CODEX_REPO:-openai/codex}"
VERSION=latest
CODE_MODE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --version) shift; VERSION="${1:?--version needs a value}" ;;
    --no-code-mode) CODE_MODE=0 ;;
    -h|--help) sed -n '2,6p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "install.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
die() { echo "install.sh: $*" >&2; exit 1; }

# --- preflight ---------------------------------------------------------------
[ "$(uname -m)" = "aarch64" ] || die "this targets aarch64; found $(uname -m)"
[ -d "$PREFIX/bin" ] || die "no $PREFIX/bin — this installs into Termux"
command -v curl >/dev/null || die "curl is required (pkg install curl)"
command -v tar  >/dev/null || die "tar is required"
# tar shells out to gzip; without it extraction fails in a way that looks like a
# corrupt download rather than a missing tool.
command -v gzip >/dev/null || die "gzip is required (pkg install gzip)"
command -v cc   >/dev/null || die "a compiler is required for the DNS proxy (pkg install clang)"

# --- resolve the release -----------------------------------------------------
if [ "$VERSION" = latest ]; then
  say "resolving the latest release"
  TAG="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
         | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$TAG" ] || die "could not resolve the latest release of $REPO"
else
  # Accept both "0.155.1" and "rust-v0.155.1"; the tags carry the rust-v prefix.
  case "$VERSION" in
    rust-v*) TAG="$VERSION" ;;
    *)       TAG="rust-v$VERSION" ;;
  esac
fi

BASE="https://github.com/$REPO/releases/download/$TAG"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

fetch() {  # fetch <asset-stem> <dest-name>
  local stem="$1" dest="$2"
  curl -fsSL --retry 3 -o "$tmp/$stem.tar.gz" \
    "$BASE/$stem-aarch64-unknown-linux-musl.tar.gz" \
    || die "could not download $stem from $TAG"
  tar xzf "$tmp/$stem.tar.gz" -C "$tmp" || die "could not extract $stem"
  [ -f "$tmp/$stem-aarch64-unknown-linux-musl" ] \
    || die "no binary inside the $stem archive"
  mv "$tmp/$stem-aarch64-unknown-linux-musl" "$tmp/$dest"
  chmod 755 "$tmp/$dest"
}

say "fetching Codex $TAG — about 90MB"
fetch codex codex

# Prove it runs before installing it, so a bad download fails here rather than
# leaving a broken `codex` on PATH.
v="$("$tmp/codex" --version 2>&1 || true)"
case "$v" in
  *codex*) say "verified: $v" ;;
  *) die "the downloaded binary did not report a version (said: ${v:-nothing})" ;;
esac

if [ "$CODE_MODE" = 1 ]; then
  say "fetching the Code Mode host — about 24MB"
  fetch codex-code-mode-host codex-code-mode-host
fi

# --- install -----------------------------------------------------------------
# Codex resolves helper commands through argv[0] symlinks that point back at
# wherever this binary lives, so it needs a permanent home, not a temp dir.
say "installing to $LIBEXEC"
mkdir -p "$LIBEXEC"
install -m 755 "$tmp/codex" "$LIBEXEC/codex"
if [ "$CODE_MODE" = 1 ]; then
  install -m 755 "$tmp/codex-code-mode-host" "$LIBEXEC/codex-code-mode-host"
fi

say "building the DNS proxy"
cc -O2 -o "$LIBEXEC/dns-proxy" "$HERE/dns-proxy.c" || die "could not build the DNS proxy"

install -m 755 "$HERE/codex" "$PREFIX/bin/codex"
rm -rf "$tmp"; trap - EXIT

# Those helper symlinks are cached under ~/.codex/tmp/arg0 and pinned to the path
# the binary had when they were made. A previous install from another directory
# would leave them dangling, so they are cleared and left to be recreated.
rm -rf "$HOME/.codex/tmp/arg0" 2>/dev/null || true

say "installed: $("$PREFIX/bin/codex" --version 2>&1)"

# --- notes -------------------------------------------------------------------
if [ "$CODE_MODE" = 1 ]; then
  echo
  echo "  Code Mode is installed but off by default. To enable it, add to"
  echo "  ~/.codex/config.toml:"
  echo
  echo "      [features]"
  echo "      code_mode_host = true"
fi

# Codex's own sandbox needs bubblewrap, which needs unprivileged user
# namespaces. Android does not grant them, so this is reported rather than
# worked around: Termux already runs inside Android's own app sandbox.
if ! unshare -Ur true >/dev/null 2>&1; then
  echo
  echo "  note: this kernel denies unprivileged user namespaces, so Codex's"
  echo "        bubblewrap sandbox cannot start. Termux is already confined by"
  echo "        Android's app sandbox, but model-generated commands will run"
  echo "        with your normal Termux permissions. Use:"
  echo "            codex --sandbox danger-full-access"
  echo "        or set sandbox_mode in ~/.codex/config.toml."
fi

echo
echo "  run it with:   codex"
echo "  log in first:  codex login"
echo "  check health:  codex doctor"
echo "  remove it:     ./uninstall.sh"
