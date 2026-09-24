# Codex for Termux

Run OpenAI's Codex CLI on an Android phone through Termux. Codex can help you
understand code, edit files, and run commands from your terminal.

This community installer sets up the native ARM64 binary and a small proxy that
makes its network connections work on Android. No root, proot, or VM is needed.

## What you need

- Termux on an ARM64 Android device. Run `uname -m`: it should print `aarch64`.
- A ChatGPT account with Codex access, or an OpenAI API key. API usage is billed
  separately; see [OpenAI's sign-in guide](https://learn.chatgpt.com/docs/auth).
- Space for the download, extracted binaries, and Termux build tools. Allow several
  hundred megabytes; the exact amount varies by release and installed packages.

## 1. Install

Run these commands **inside Termux**:

```bash
pkg update
pkg install git curl tar gzip clang

git clone https://github.com/Aarstad/codex-termux.git
cd codex-termux
./install.sh
```

The installer downloads Codex and builds the small networking helper. When it
finishes, check:

```bash
codex --version
```

Use this installer for the Termux setup described here. It selects the musl
release build and installs the launcher that provides the networking workaround.

## 2. Sign in

```bash
codex login
```

Follow the browser sign-in instructions, then return to Termux. If the browser
does not open automatically, open the URL printed in the terminal.

Check that sign-in completed:

```bash
codex login status
```

For API-key sign-in or a browser callback problem, see
[Login and network problems](#login-and-network-problems) below.

## 3. Start Codex with the Termux settings

Codex's Linux command sandbox does not work on the Android setup tested here.
The command below disables that sandbox and turns off animations, which fixed a
Termux glitch that kept scrolling to the bottom of the conversation.

**With the command sandbox disabled, Codex can access files and run commands with
your Termux permissions.** It is not confined to the current project. Android's
app permissions still apply, including any shared-storage access you have granted
Termux. Approval prompts are a separate setting; do not assume every command will
ask first. See [OpenAI's security guide](https://learn.chatgpt.com/docs/agent-approvals-security).

Start in a practice folder, or change into a project you want to work on:

```bash
mkdir -p ~/projects/codex-playground
cd ~/projects/codex-playground
codex --sandbox danger-full-access -c tui.animations=false
```

For a first task, try: **“Create a simple HTML page that says hello.”**

### Save these settings for future sessions

To avoid typing the flags each time, put these settings in
`~/.codex/config.toml`. If you are new to terminal editors:

```bash
pkg install nano
mkdir -p ~/.codex
nano ~/.codex/config.toml
```

For an otherwise empty config file:

```toml
sandbox_mode = "danger-full-access"

[tui]
animations = false
```

If the file already has settings, preserve them: put `sandbox_mode` at the top,
**before any `[section]`**, or update its existing top-level entry. Put
`animations = false` under the existing `[tui]` section, or add that section if
missing. Do not create duplicate keys or sections.

In nano, save with **Ctrl+O**, press **Enter**, then exit with **Ctrl+X**. Restart
Codex after changing the file. From then on, start it from your project folder with:

```bash
codex
```

## Troubleshooting

### Screen keeps jumping down / cannot scroll up

Codex's animated sparkles, shimmer, or spinner can cause repeated scrolling to the
bottom in Termux. Disabling animations fixed this on our test device.

Use `-c tui.animations=false` when launching, or save `animations = false` under
`[tui]` as shown above, then restart Codex. This is the setting documented in the
[official configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).

### “bubblewrap is unavailable” or sandbox errors

Use `--sandbox danger-full-access` or save the setting from step 3. On the tested
Android kernel, the Linux sandbox's required user namespaces are unavailable;
installing a `bwrap` executable alone does not solve that.

### Login and network problems

If you see **“Token exchange failed”** after browser sign-in, or health checks
report unreachable endpoints, first make sure you are using the installed launcher:

```bash
command -v codex
codex doctor
```

`command -v codex` should point to `$PREFIX/bin/codex` (normally
`/data/data/com.termux/files/usr/bin/codex`). Run `codex`, rather than the executable
inside `libexec/codex`, so the networking helper is started. If you have configured
`HTTPS_PROXY`, `https_proxy`, or `CODEX_NO_PROXY`, check those settings too: they can
bypass the bundled helper.

If browser sign-in cannot return to the CLI, try device-code login:

```bash
codex login --device-auth
```

Device-code login may need enabling in your ChatGPT security settings or workspace
permissions. For API-key login, if `OPENAI_API_KEY` is already set in your shell:

```bash
printenv OPENAI_API_KEY | codex login --with-api-key
```

See [OpenAI's authentication guide](https://learn.chatgpt.com/docs/auth) for details.
When reporting an issue, include `codex --version`, `uname -m`, and the error text;
remove credentials and other private information from anything you share.

## Update or install a specific version

Codex's own `codex update` cannot work here: it only recognises npm, Homebrew
and similar installers, and stops with "Could not detect the Codex installation
method". Use the updater this repository installs instead (`codex update` is
redirected to it):

```bash
codex-update            # update to the latest release
codex-update --check    # just compare installed and latest versions
codex-update --rollback # go back to the previous binary
```

It keeps the previous binary as `codex.prev` next to the new one (pass
`--no-backup` to skip that, or delete the file later). It reruns `install.sh`
from the folder where you cloned this repository, so keep that clone around;
if you move it, set `CODEX_TERMUX_DIR` to the new location. Your settings and
sign-in are retained.

To pick up changes to the launcher or DNS proxy as well, pull this repository
and reinstall:

```bash
git pull --ff-only
./install.sh
```

To request a particular Codex release instead, pass its version, for example:

```bash
codex-update --version 0.155.1
```

That is a version-pinning example, not a claim about the latest release.

## Uninstall

Close Codex, then run this from the cloned repository:

```bash
./uninstall.sh
```

This removes the installed executables and launcher, while keeping your settings,
credentials, and conversation history. To delete those too, use
`./uninstall.sh --config` instead; it removes `~/.codex`.

## How it works
 
The installer uses OpenAI's static musl build, which runs directly on this Android
setup. Its built-in DNS resolver expects a conventional Linux setup (`/etc/resolv.conf`),
so networking needs help.

The launcher bridges this seamlessly:
- Detects if the shared `termux-dns-proxy` daemon is active on `127.0.0.1:18080` and reuses
  it immediately with zero startup delay and zero process proliferation.
- If not running, it automatically spawns an ephemeral companion C proxy that resolves names
  through Android's bionic resolver and terminates when Codex exits.
- Respects existing ambient `http_proxy` / `https_proxy` or `CODEX_NO_PROXY=1`.

For installation paths, the optional Code Mode host, proxy tests, and memory
measurements, see the [development notes](docs/development.md).

## Related projects and credits

Looking for another CLI on Termux?
[Claude Code](https://github.com/Aarstad/claude-code-termux-musl) and
[Antigravity](https://github.com/Aarstad/agy-termux-musl) have separate installers.

Thanks to OpenAI for publishing the musl build, and
[wallentx](https://github.com/wallentx) for the Termux launcher groundwork.

[MIT license](LICENSE).
