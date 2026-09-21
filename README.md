# codex-termux

Run **OpenAI's Codex CLI natively on Android**, in Termux, with no glibc, no proot and no VM.

Codex is Rust, and the published `aarch64-unknown-linux-musl` build is **fully static** —
`ET_EXEC`, no `PT_INTERP`, no `DT_NEEDED`. No loader is involved at all: the kernel maps it
and jumps to the entry point. Nothing needs patching.

It does need one thing, though. musl's resolver is linked *into* the binary and reads
`/etc/resolv.conf`, which Android does not have, so name lookups fail from inside the
process. The visible symptom is that `codex login` opens your browser (Android resolves
that fine), you sign in, and then it fails:

```
Login server error: Token exchange failed: error sending request
for url (https://auth.openai.com/oauth/token)
```

So this repo installs the binaries, builds a small bionic-side DNS proxy, and ships a
wrapper that starts it and points Codex at it.

```
$ codex --version
codex-cli 0.155.1
```

## Install

```bash
git clone https://github.com/Aarstad/codex-termux
cd codex-termux
./install.sh                    # latest release
./install.sh --version 0.155.1  # or pin one
```

Then `codex login`.

## Requirements

- Termux on aarch64
- `curl`, `tar`, `gzip`
- ~230MB of storage, ~90MB of download
- A ChatGPT Plus/Pro/Business account or an OpenAI API key

## Code Mode

The Code Mode host is installed but off by default. To enable it, add to
`~/.codex/config.toml`:

```toml
[features]
code_mode_host = true
```

Skip the download with `./install.sh --no-code-mode` if you do not want it.

## Don't install it from npm

`npm install -g @openai/codex` gets you a binary that cannot run. The package declares
optional dependencies for `linux-arm64`, `darwin-arm64` and friends — but the Linux ones
are **glibc** builds, and there is no musl entry at all:

```
$ npm view @openai/codex optionalDependencies | grep -c musl
0
```

The musl binary exists only as a GitHub release asset. That is what `install.sh` fetches.

## What it does

`install.sh` installs three things: the `codex` binary, the **Code Mode host**
(`codex-code-mode-host`, a separate release asset Codex needs for Code Mode), and a DNS
proxy built from `dns-proxy.c`. The `codex` on your `PATH` is a wrapper that starts the
proxy, exports `*_proxy` for the session, and cleans it up on exit.

It resolves the latest release tag (or takes `--version`, with or without the
`rust-v` prefix), downloads `codex-aarch64-unknown-linux-musl.tar.gz`, and **runs the
binary to confirm it reports a version before installing it** — so a bad download fails
before anything lands on `PATH`. The binary goes to `$PREFIX/libexec/codex`, symlinked as
`$PREFIX/bin/codex`.

It also clears `~/.codex/tmp/arg0`. Codex resolves its helper commands
(`codex-linux-sandbox`, `codex-execve-wrapper`, `apply_patch`) through `argv[0]` symlinks
cached there and pinned to wherever the binary lived at first run. Installing from a
different directory later leaves them dangling, which is a confusing failure; clearing
them lets Codex recreate them against the current path.

## The sandbox does not work, and cannot

`codex sandbox` needs bubblewrap, which needs unprivileged user namespaces. Android does
not grant them — `unshare -Ur` fails and there is no
`/proc/sys/user/max_user_namespaces` — so `bwrap` cannot start even if you build it:

```
thread 'main' panicked at linux-sandbox/src/launcher.rs:51:13:
bubblewrap is unavailable
```

Run Codex with the sandbox off instead:

```bash
codex --sandbox danger-full-access
```

or set `sandbox_mode` in `~/.codex/config.toml`. `install.sh` prints this when it detects
the kernel denies namespaces.

**Know what you are trading.** Termux already runs inside Android's application sandbox,
so this removes a second layer rather than the only one — Codex still cannot reach outside
Termux's own data directory. But within it, model-generated commands run with your normal
permissions and no approval step. Codex's own docs intend this flag for environments that
are "externally sandboxed", which Termux is; that is a weaker claim than "it is safe".

## Everything else works

`codex doctor` passes every environment check on Termux — disk, git, ripgrep, locale,
terminal, state, config, install consistency. Subcommands, config loading and TLS are all
fine. The two things it flags are `auth` (until you log in) and a WebSocket warning; the
latter is a transport preference and Codex falls back to HTTPS on its own.

## Uninstall

```bash
./uninstall.sh            # removes the binary and the PATH symlink
./uninstall.sh --config   # …and ~/.codex
```

`~/.codex` — settings, credentials, session history — is not touched unless you ask.

## What about Claude Code and Antigravity?

**Claude Code** needs real work to run here: Anthropic's musl build is *dynamically*
linked, so it needs a musl loader placed and its interpreter repointed, plus a DNS shim
and `LD_PRELOAD` handling. That is a separate project:
[claude-code-termux-musl](https://github.com/Aarstad/claude-code-termux-musl).

**Google's Antigravity CLI** (`agy`) does not run natively, and it is the hard case.
Despite being Go — usually a static-binary language — it ships with cgo enabled, so it is
a dynamic PIE needing `/lib/ld-linux-aarch64.so.1` and `GLIBC_2.26`, with no musl asset
published. Worse, it bundles TCMalloc, which assumes a 48-bit virtual address space and
aborts before startup on the 39-bit-VA kernels most Android devices use
([#9](https://github.com/google-antigravity/antigravity-cli/issues/9),
[#64](https://github.com/google-antigravity/antigravity-cli/issues/64) — the latter on an
ARM64 router, not Android at all). That failure is independent of libc, so it happens
inside proot too.

[wallentx/antigravity-cli-termux](https://github.com/wallentx/antigravity-cli-termux/releases)
publishes patched native builds that work. Note they are *not* a musl port: the package is
a small bionic bootstrapper that clears `LD_PRELOAD` and re-execs the patched engine
against `$PREFIX/glibc/lib/ld-linux-aarch64.so.1`, so it needs Termux's full glibc
package. A musl build of `agy` is not currently possible from the published artifacts —
the payload is linked against `libc.so.6` and wants glibc-only symbols. It would take a
`CGO_ENABLED=0` build from Google, plus the VA fix.

## Credits

- OpenAI, for publishing a static musl build — which is why this repo is 150 lines and not
  a research project.
- [wallentx](https://github.com/wallentx), for the Termux launcher work that mapped out
  most of these problems in the first place.

## License

MIT
