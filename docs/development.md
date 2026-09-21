# Development notes

[Back to the setup guide](../README.md)

## Installation layout

`install.sh` downloads the `aarch64-unknown-linux-musl` release assets, runs the
Codex binary with `--version`, and builds the C proxy using Termux's compiler.
It installs:

| Path | Purpose |
| --- | --- |
| `$PREFIX/bin/codex` | Shell launcher |
| `$PREFIX/libexec/codex/codex` | Upstream Codex executable |
| `$PREFIX/libexec/codex/codex-code-mode-host` | Optional Code Mode executable |
| `$PREFIX/libexec/codex/dns-proxy` | Locally compiled proxy |

The launcher starts a loopback HTTP/CONNECT proxy when no HTTPS proxy is already
configured. It sets proxy environment variables for Codex and stops its proxy
when the session exits. `CODEX_NO_PROXY=1` skips this setup and uses the existing
environment instead.

The proxy resolves names using Android's native resolver. HTTPS uses CONNECT:
the proxy forwards bytes, while Codex handles TLS with the destination server.
This helps proxy-aware clients; it does not fix DNS for every musl program.

The installer and uninstaller clear `~/.codex/tmp/arg0`, the cache of helper
symlinks that can otherwise keep pointing at an old executable location.

## Optional Code Mode host

The installer downloads the Code Mode host by default. To skip its download:

```bash
./install.sh --no-code-mode
```

This does not remove a host installed previously. The installer does not enable
features in your user config. To explicitly enable the host on a compatible Codex
release, merge this into `~/.codex/config.toml`:

```toml
[features]
code_mode_host = true
```

If `[features]` already exists, add the key there. Ordinary first-run setup does
not require editing this feature setting.

## Proxy tests and memory measurements

The proxy stays in C to avoid a JavaScript runtime per CLI session. Development
checks build in a temporary directory and use loopback servers; they do not install
anything or replace the proxy used by an existing session. Run the commands below
from the repository root.

```bash
python3 tests/test_proxy.py
python3 tests/measure_memory.py
# Optional comparison with the sibling project's existing JavaScript implementation:
python3 tests/measure_memory.py --bun-js ../claude-code-termux-musl/libexec/dns-proxy.js
```

Tests require Python 3 and a C compiler with AddressSanitizer support. They cover
HTTP header/body forwarding, early CONNECT payload, unsupported chunked requests,
connection refusal, bidirectional backpressure, half-closes, buffered-peer cleanup,
and setup deadlines interrupted by signals. To test another source copy, set
`PROXY_SOURCE` to its path when running `tests/test_proxy.py`.

TCP connection attempts share a five-second deadline across resolved addresses;
each setup write also has a five-second deadline. DNS resolution still blocks in
bionic, and setup can pause existing tunnels. Plain HTTP `Transfer-Encoding`
requests receive **501** before connecting upstream because this proxy does not
decode their framing. HTTPS inside CONNECT tunnels is unaffected. The HTTP path
requests `Connection: close`; it is not a general-purpose HTTP framing parser.

A local measurement on this Android device used eight open CONNECT tunnels after
64 KiB in each direction per tunnel. Median samples from release builds were:

| Process | Idle RSS | RSS after traffic | Idle PSS | PSS after traffic | Threads idle/after |
| --- | ---: | ---: | ---: | ---: | ---: |
| C | 3,140 KiB | 3,140 KiB | 744 KiB | 775 KiB | 1 / 1 |
| Bun | 40,932 KiB | 46,348 KiB | 38,659 KiB | 44,415 KiB | 12 / 14 |

These are device/workload-specific snapshots, not peak-memory measurements. PSS
apportions shared resident pages; neither RSS nor PSS includes kernel socket/pipe
buffers. The benchmark uses an ordinary `-O2` build, without AddressSanitizer.

## Updating a running proxy safely

The installer writes directly to installation paths, so close Codex sessions
before running it. For proxy-only development updates, compile a new executable
to a different filename in the installed proxy's directory, verify it, save a
backup, then atomically rename the new file over `dns-proxy`.

Do not compile directly onto a running executable. Existing processes continue
using the old file after the rename; new launches use the replacement. Restart
Codex to launch the new proxy. A session inheriting an existing HTTPS proxy may
reuse that proxy instead.

The sibling projects currently contain copies of this C source at
`../claude-code-termux-musl/libexec/dns-proxy.c` and
`../agy-termux-musl/dns-proxy.c`. When changing shared behavior, compare those
copies and run this regression suite against each updated source.
