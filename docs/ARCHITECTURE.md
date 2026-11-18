# Architecture

Slipstream ships as **one file**, `run.ps1`, because the one-line installer is `iex "& { $(iwr ...run.ps1) }"`.
That file is **generated**: you edit the modules in `src/`, and `npm run build` joins them.

```
src/
  manifest.json              order and grouping of every file below
  installer/                 PowerShell: what the user runs (in this order)
    00-header.ps1              help text and the parameters
    10-ui.ps1                  Say/Step/Ok..., the language loader, banner, PowerShell/Windows checks
    20-locate.ps1              find OpenCode, stop its processes
    30-questions.ps1           the [Y/N] questions, latest version, download bar
    40-data-protection.ps1     save and verify chats, login, settings around an update
    50-download.ps1            download and install the official OpenCode
    60-embed-boot.ps1          embeds the desktop patch  ($BootJs)
    70-terminal.ps1            embeds the terminal build ($CliShim, $CliMain) and installs it
    80-flow.ps1                update / status / uninstall
    90-asar.ps1                read and rewrite app.asar
    95-install.ps1             the patch itself
  runtime/                   JavaScript
    core/                      the engine, shared by desktop and terminal
      00-runtime.js              log, messages, the one-action-at-a-time guard
      20-settings.js             proxy.json
      25-i18n.js                 language choice and t()
      30-gate.js                 the local proxy OpenCode talks to, upstream dialing (HTTP, SOCKS5, tunnel)
      wireguard/                 our own WireGuard client, no .exe
        10-crypto.js               BLAKE2s, ChaCha20-Poly1305, X25519
        20-packets.js              IPv4/IPv6/TCP/UDP packets and checksums
        30-tcp.js                  a small TCP stack that turns packets into streams
        40-tunnel.js               handshake, keep-alive, DNS, connect (IPv6 first)
        50-conf.js                 WireGuard .conf import
      warp.js                    free Cloudflare WARP account + bringing the tunnel up
      free-proxies.js            public proxy lists
      actions.js                 New IP, Status, switching the connection
    boot/                      only the desktop (Electron) patch
      00-header.js 10-pending.js 20-desktop-actions.js 30-auto-rotate.js 40-tray.js 50-upsell.js 99-handover.js
    cli/                       only the terminal build
      shim.js                    stand-ins for Electron
      00-head.js 10-bring-up.js 20-control.js 30-run.js 40-commands.js
  i18n/
    app/<code>.js              the tray menu and messages, one file per language
    installer/<code>.json      the installer's messages, one file per language
assets/                      logo.svg, logo.png, tray-icon.png
build/build.mjs              joins src/ into run.ps1
tests/                       node --test (crypto vectors, packets, i18n, build, installer logic)
```

## How the pieces end up in run.ps1

- `installer/*.ps1` are joined in the manifest order.
- `@@BOOT_JS@@`, `@@CLI_SHIM@@`, `@@CLI_MAIN@@` are replaced by the JavaScript parts (`manifest.boot`, `cliShim`, `cliMain`).
- The terminal version is **not** a second program: at install time `Get-CliSource` takes the boot JavaScript up to the tray, swaps the
  Electron import for `runtime/cli/shim.js`, gives it its own settings (`cli.json`), WARP account and proxy port, and appends `runtime/cli/*.js`.
  That is why `core/` must never touch Electron objects directly, only `app`, `dialog`, `shell`, `Notification` (the shim provides them).
- `@@INSTALLER_I18N@@` is the Base64 of all `installer/<code>.json`; the app's languages are inserted at `@@APP_LANGS@@`.
- Every non-ASCII character is written as `\uXXXX`, so `run.ps1` is plain ASCII. Windows PowerShell 5.1 reads a BOM-less file as ANSI.

Files are text plus one final newline; joining puts a single newline between files. Keep that, and the build stays byte-for-byte reproducible.

## Everyday tasks

| Task | Do |
|---|---|
| Build | `npm run build` |
| Is `run.ps1` current? | `npm run check` (CI runs it) |
| Test | `npm test` |
| Add a language | add `src/i18n/app/<code>.js` and `src/i18n/installer/<code>.json`, add `<code>` to `languages` in `manifest.json`, map the system locale in `core/25-i18n.js` if the code is not the language's two letters. The i18n test fails until every message and `{placeholder}` matches English |
| Add a connection mode | engine in `core/`, the name in `MODES` (`20-settings.js`), `upstream()` (`30-gate.js`), `switchMode`/`newIp`/`status` (`actions.js`), a radio in `boot/40-tray.js`, a case in `cli/40-commands.js`, the texts in every language |
| Change the installer | edit the matching `installer/*.ps1`, build, run `.\run.ps1 -status` |

## Release

1. `npm run build && npm test`
2. commit `src/` **and** the regenerated `run.ps1`
3. push to `main`: the raw URL serves it immediately (the one-line installer always runs the newest `run.ps1`)
4. tag it (`v1.0.1`) and attach `run.ps1`, `install.ps1` and `SHA256SUMS` to a GitHub release
