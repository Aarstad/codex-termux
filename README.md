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
- `clang` (for the DNS proxy)
- ~300MB of storage, ~115MB of download
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
before anything lands on `PATH`. The binaries go to `$PREFIX/libexec/codex`, and the wrapper is installed as
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
terminal, state, config, install consistency, auth and reachability. Login, authenticated
API calls and interactive sessions all work.

Run the raw binary without the wrapper and `doctor` reports `✗ reachability — one or more
required provider endpoints are unreachable`, which is the DNS problem above.

## Uninstall

```bash
./uninstall.sh            # removes the binaries, the proxy and the wrapper
./uninstall.sh --config   # …and ~/.codex
```

`~/.codex` — settings, credentials, session history — is not touched unless you ask.

## What about Claude Code and Antigravity?

**Claude Code** needs real work to run here: Anthropic's musl build is *dynamically*
linked, so it needs a musl loader placed and its interpreter repointed, plus a DNS shim
and `LD_PRELOAD` handling. That is a separate project:
[claude-code-termux-musl](https://github.com/Aarstad/claude-code-termux-musl).

**Google's Antigravity CLI** (`agy`) is the hard case, but it does run natively now:
[agy-termux-musl](https://github.com/Aarstad/agy-termux-musl). It ships glibc-only, so it
needs a musl loader, a ten-symbol shim, the same DNS proxy, a CA-bundle path, and 24 bytes
of binary patches for two hardcoded glibc layout assumptions (reported upstream as
[#1075](https://github.com/google-antigravity/antigravity-cli/issues/1075) and
[#1079](https://github.com/google-antigravity/antigravity-cli/issues/1079)). It also
bundles TCMalloc, which assumes a 48-bit address space and aborts on the 39-bit-VA kernels
most Android devices use — that part is
[wallentx's](https://github.com/wallentx/antigravity-cli-termux) 82-byte patch, and is
independent of libc.

## Credits

- OpenAI, for publishing a static musl build — no loader, no patching, no disassembly.
- [wallentx](https://github.com/wallentx), for the Termux launcher work that mapped out
  most of these problems in the first place.

## License

MIT
