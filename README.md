<p align="center"><img src="assets/logo.png" alt="Slipstream" width="128"></p>

<h1 align="center">Slipstream</h1>

<p align="center"><b>English</b> · <a href="README.pt-BR.md">Português (Brasil)</a></p>

<p align="center">Per-app connection patcher for Windows.<br>
Gives one app its own route (WireGuard, proxy), a new IP on demand and safe clean-ups,<br>
while the rest of your PC stays exactly as it is.</p>

**Supported apps:** OpenCode desktop. More apps are planned; the connection engine does not depend on any one app.

> Unofficial. Not affiliated with the apps it supports. It changes the exit IP of one app; you are responsible for following the
> terms of the services you use.

## Install

Open **PowerShell** and run:

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -start"
```

Mirror (if GitHub raw is blocked):

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -m -start"
```

OpenCode not installed yet? Add `-download` and the original is fetched from the official GitHub releases first.

## What the installer does

It talks to you like SpotX does. Run it and it checks what is installed, then asks (answer `Y` or `N`):

1. OpenCode not found: download and install the official one?
2. A newer OpenCode exists: update?
3. Block OpenCode's own updates (they would remove the patch)?
4. Also install Slipstream for the terminal?

Then: `Downloading OpenCode 2.3.2` (with a progress bar), `Installing OpenCode`, `Patching OpenCode...`, `installation completed`.
The questions are in your Windows language. `-yes` answers Yes to all of them, and with no console it uses the safe defaults.

### Updating without losing anything

Before an update it saves, and after it checks, everything that is yours and lives outside the app:

- your chats (`opencode.db`) and your login (`auth.json`)
- OpenCode's settings and drafts
- Slipstream's own settings, WARP account and WireGuard file

Each file is copied to `%LOCALAPPDATA%\slipstream\backup\update-<date>` (the 3 newest are kept) and compared byte for byte afterwards.
If any file differs or is missing, it is put back from the backup and the installer says so.

## Uninstall

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -uninstall"
```

This puts the original `app.asar` back. Nothing else of OpenCode is changed.

## Requirements

- Windows 10 / 11, PowerShell 5.1 or above (also works on PowerShell 7)
- OpenCode desktop (the official installer)
- No admin rights, no driver, no extra program

## What you get

A tray icon next to the clock:

| Item | What it does |
|---|---|
| **New IP** | Gets a new IP for the current connection |
| **Connection ▸ Direct** | OpenCode uses your normal connection |
| **Connection ▸ Built-in WARP** | Own WireGuard client (written in JS, no `.exe`) with a free Cloudflare WARP account. **IPv6 first**, IPv4 as fallback |
| **Connection ▸ WireGuard file** | Any WireGuard `.conf` (Route64, Proton, Mullvad, your server). Choose it with *Choose WireGuard file...* |
| **Connection ▸ Free public proxies** | Tests public proxy lists and uses the first one that works (untrusted, see below) |
| **Connection ▸ Own proxy list** | Your own `http://`, `socks5://` proxies, edited in *Edit proxy list* |
| **Auto-rotate** | When a chat stops on the free limit: new IP, then the message is sent again |
| **Clear ▸ Login** | Backs up `auth.json` and removes it. Chats are kept |
| **Clear ▸ Restore login** | Puts the last backup back |
| **Clear ▸ Cache and logs** | Frees disk space. Chats are kept |
| **Status** | The IP OpenCode is using |
| **Language** | Menu language (automatic by default) |
| **Restart / Quit** | Restarts, or closes everything (tunnel and background service included) |

It also removes the persistent "Free limit reached / Subscribe to Go" tray that replaces the prompt box.

## Terminal version

The same engine for the OpenCode **terminal** (v2 `@opencode/cli`, and the older v1 `opencode-ai`). Needs Node.js 20+.

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -terminal"
```

Add `-update` to also update the terminal OpenCode to the newest version (v2 as `opencode` / `opencode2`, v1 apart as `opencode1`):

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -terminal -update"
```

Then, in any terminal:

```
slipstream opencode            # the OpenCode desktop app
slipstream cli                 # OpenCode v2 in this terminal (same as: slipstream opencode cli, or opencode2)
slipstream cli run "..."       # non-interactive: a free-limit error changes the IP and runs it again
slipstream ip                  # new IP. Use it from a SECOND terminal while a session is running
slipstream status              # the IP in use
slipstream mode wg             # direct | wg | wgfile | free | list
slipstream wgfile my.conf      # use a WireGuard file
slipstream proxy add socks5://host:1080
slipstream context opencode/deepseek-v4.1-flash-free 1000000
slipstream clear login|restore|cache
slipstream lang pt-BR
slipstream run <any program>   # any program through the same route
```

Notes:
- `slipstream opencode` opens the desktop app (patched by the installer). The terminal build is `slipstream cli`, `slipstream opencode cli` or `slipstream opencode2`; the older v1 is `slipstream opencode1`.
- The terminal has its own settings (`cli.json`), its own WARP account and its own proxy port, so it can run next to the desktop app.
- In the interactive screen there is no safe way to watch for the free limit. When it stops you, run `slipstream ip` in another terminal and send your message again.
- v1 and v2 cannot share one database, so `slipstream opencode1` keeps its data in `%LOCALAPPDATA%\opencode-v1\xdg` (its own login too).
- Remove it with `-terminal -uninstall`.

## Update OpenCode desktop

`-update` removes the patch, installs the newest official OpenCode, and patches it again (OpenCode's own updater is blocked because it would drop the patch):

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/slipstream/main/install.ps1') } -update -start"
```

## Languages

The tray menu, its messages and the installer follow your Windows language automatically. 12 languages:

English, Português (Brasil), Español, Français, Deutsch, Русский, 简体中文, 日本語, 한국어, हिन्दी, العربية, Bahasa Indonesia.

Change the menu language any time in the tray: **Language**. For the installer use `-lang pt-BR` (or `es`, `fr`, `de`, `ru`, `zh-CN`, `ja`, `ko`, `hi`, `ar`, `id`).
Technical details (network errors, the log file) stay in English.

## How it works

- The installer adds one entry file to `resources\app.asar` and points `package.json` `main` to it. The untouched original is kept as
  `app.asar.slipstream.bak`. It also stops the app from saving the free-limit time that keeps that tray on screen.
- That entry starts a small proxy on `127.0.0.1` and points only OpenCode (and its background service) to it. Changing the connection
  is instant, with no restart.
- Built-in WARP is a user-mode WireGuard client: Noise handshake, ChaCha20-Poly1305, X25519, BLAKE2s, plus a small IPv4/IPv6/TCP/UDP
  stack and DNS through the tunnel. The free account is registered over Cloudflare's API, like `wgcf` does.
- OpenCode's own updater is pointed at nothing (an update would replace the patch). Undo it with `-block_update_off`.

Files of the tool are in `%LOCALAPPDATA%\slipstream` (`proxy.json` = settings and proxy list, `slipstream.log`, `backup\`, `wg\`).

## Parameters

| Parameter | |
|---|---|
| `-start` | Open OpenCode when done |
| `-uninstall` | Remove the patch |
| `-status` | Show what is installed |
| `-download` | Install the original OpenCode first if it is missing |
| `-yes` / `-y` | Answer Yes to every question |
| `-update` | Update OpenCode to the newest version and patch it again (chats, login and settings are saved and checked) |
| `-terminal` | The terminal version (add `-update` to update the terminal OpenCode too, `-uninstall` to remove it) |
| `-version 2.3.0` | Version to download with `-download` |
| `-block_update_off` | Let OpenCode update itself again (updates remove the patch) |
| `-path <folder>` | OpenCode folder, if it is not in the default place |
| `-lang pt-BR` | Installer language (default: your Windows language) |
| `-m` | (installer) use the mirror |

## Notes and limits

- **Free public proxies are untrusted.** HTTPS stays encrypted end to end, but the proxy operator sees which hosts you connect to.
  They are also slow and short-lived. Prefer Built-in WARP or your own WireGuard file.
- A WARP account has no fixed IP: Cloudflare gives the exit of the nearest server, so *New IP* may return the same block.
- WireGuard needs UDP to the server (WARP: port 2408). If your network blocks it, the tunnel cannot start and the app returns to Direct.
- An OpenCode update replaces the patch. Run the installer again after updating.
- Tested on OpenCode 2.3.2 (desktop and terminal) and 1.19.6 (terminal).

## Development

`run.ps1` is generated from the modules in `src/`; do not edit it by hand. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```
src/installer/   PowerShell, in order       src/runtime/core/  the engine (own WireGuard, proxy, actions)
src/runtime/boot the desktop patch          src/runtime/cli/   the terminal build
src/i18n/        one file per language      build/build.mjs    joins everything into run.ps1
tests/           npm test                   assets/            logo, tray icon (desktop), tray icon (CLI)
```

```ps1
npm run build    # regenerate run.ps1
npm run check    # fail if run.ps1 is out of date (CI does this)
npm test         # crypto vectors, packets, languages, build, installer logic
```

## License

MIT
