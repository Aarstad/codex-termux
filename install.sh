#!/data/data/com.termux/files/usr/bin/bash
# Install the Codex CLI to run natively in Termux.
#
#   ./install.sh              install as `codex`
#   ./install.sh --version X  install a specific release (default: latest)
#
# No loader and no patching are needed: OpenAI publishes a statically linked
# aarch64 musl binary, which Android's bionic runs as-is.
#
# Not "#!/usr/bin/env bash" on purpose: Android has no /usr/bin/env, and the
# termux-exec shim that normally rewrites that is absent inside Claude Code sessions.
set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
LIBEXEC="$PREFIX/libexec/codex"
REPO="${CODEX_REPO:-openai/codex}"
VERSION=latest

while [ $# -gt 0 ]; do
  case "$1" in
    --version) shift; VERSION="${1:-latest}" ;;
    -h|--help) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
# tar shells out to gzip; without it the extraction fails in a way that looks like a
# corrupt download rather than a missing tool.
command -v gzip >/dev/null || die "gzip is required (pkg install gzip)"

# --- resolve the release -----------------------------------------------------
# The musl asset is what makes this work: it is statically linked, so there is no
# interpreter to repoint and no libc to supply. The glibc asset of the same name
# would need everything install.sh does for Claude Code, and more.
ASSET="codex-aarch64-unknown-linux-musl.tar.gz"

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

URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"

# --- fetch -------------------------------------------------------------------
say "fetching Codex $TAG — about 90MB"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 -o "$tmp/codex.tar.gz" "$URL" \
  || die "could not download $URL (does $TAG ship an aarch64 musl build?)"

tar xzf "$tmp/codex.tar.gz" -C "$tmp" || die "could not extract the release tarball"
bin="$tmp/codex-aarch64-unknown-linux-musl"
[ -f "$bin" ] || die "no codex binary inside $ASSET (extraction failed?)"

# Prove it runs before installing it, so a bad download fails here rather than
# leaving a broken `codex` on PATH.
chmod 755 "$bin"
v="$("$bin" --version 2>&1 || true)"
case "$v" in
  *codex*) say "verified: $v" ;;
  *) die "the downloaded binary did not report a version (said: ${v:-nothing})" ;;
esac

# --- install -----------------------------------------------------------------
# Codex resolves its sandbox helpers through argv[0] symlinks that point back at
# wherever this binary lives, so it needs a permanent home — not a temp dir.
say "installing to $LIBEXEC"
mkdir -p "$LIBEXEC"
install -m 755 "$bin" "$LIBEXEC/codex"
ln -sf "$LIBEXEC/codex" "$PREFIX/bin/codex"
rm -rf "$tmp"; trap - EXIT

# Those helper symlinks are cached under ~/.codex/tmp/arg0 and pinned to the path
# the binary had when they were made. A previous install from another directory
# would leave them dangling, so they are cleared and left to be recreated.
rm -rf "$HOME/.codex/tmp/arg0" 2>/dev/null || true

say "installed: $("$PREFIX/bin/codex" --version 2>&1)"

# --- sandbox note ------------------------------------------------------------
# Codex's Linux sandbox needs bubblewrap, which needs unprivileged user
# namespaces. Android does not grant them, so this is reported rather than
# worked around: Termux already runs inside Android's own app sandbox.
if ! unshare -Ur true >/dev/null 2>&1; then
  echo
  echo "  note: this kernel denies unprivileged user namespaces, so Codex's"
  echo "        bubblewrap sandbox cannot start. Termux is already confined by"
  echo "        Android's app sandbox. To run commands, pass:"
  echo "            codex --sandbox danger-full-access"
  echo "        or set sandbox_mode in ~/.codex/config.toml."
fi

echo
echo "  run it with:   codex"
echo "  log in first:  codex login"
echo "  check health:  codex doctor"
echo "  remove it:     ./uninstall.sh"
