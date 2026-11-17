# DriftWire

Patcher for the **OpenCode desktop app on Windows**. It adds a tray menu that gives only OpenCode another connection
(and a new IP when the free limit stops a chat), so the rest of your PC stays untouched.

> Unofficial. Not affiliated with OpenCode. It changes the exit IP of one app; you are responsible for following the
> terms of the services you use.

## Install

Open **PowerShell** and run:

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/driftwire/main/install.ps1') } -start"
```

Mirror (if GitHub raw is blocked):

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/driftwire/main/install.ps1') } -m -start"
```

OpenCode not installed yet? Add `-download` and the original is fetched from the official GitHub releases first.

## Uninstall

```ps1
iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/driftwire/main/install.ps1') } -uninstall"
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
| **Restart / Quit** | Restarts, or closes everything (tunnel and background service included) |

It also removes the persistent "Free limit reached / Subscribe to Go" tray that replaces the prompt box.

## How it works

- The installer adds one entry file to `resources\app.asar` and points `package.json` `main` to it. The untouched original is kept as
  `app.asar.driftwire.bak`. It also stops the app from saving the free-limit time that keeps that tray on screen.
- That entry starts a small proxy on `127.0.0.1` and points only OpenCode (and its background service) to it. Changing the connection
  is instant, with no restart.
- Built-in WARP is a user-mode WireGuard client: Noise handshake, ChaCha20-Poly1305, X25519, BLAKE2s, plus a small IPv4/IPv6/TCP/UDP
  stack and DNS through the tunnel. The free account is registered over Cloudflare's API, like `wgcf` does.
- OpenCode's own updater is pointed at nothing (an update would replace the patch). Undo it with `-block_update_off`.

Files of the tool are in `%LOCALAPPDATA%\driftwire` (`proxy.json` = settings and proxy list, `driftwire.log`, `backup\`, `wg\`).

## Parameters

| Parameter | |
|---|---|
| `-start` | Open OpenCode when done |
| `-uninstall` | Remove the patch |
| `-status` | Show what is installed |
| `-download` | Install the original OpenCode first if it is missing |
| `-version 2.3.0` | Version to download with `-download` |
| `-block_update_off` | Let OpenCode update itself again (updates remove the patch) |
| `-path <folder>` | OpenCode folder, if it is not in the default place |
| `-m` | (installer) use the mirror |

## Notes and limits

- **Free public proxies are untrusted.** HTTPS stays encrypted end to end, but the proxy operator sees which hosts you connect to.
  They are also slow and short-lived. Prefer Built-in WARP or your own WireGuard file.
- A WARP account has no fixed IP: Cloudflare gives the exit of the nearest server, so *New IP* may return the same block.
- WireGuard needs UDP to the server (WARP: port 2408). If your network blocks it, the tunnel cannot start and the app returns to Direct.
- An OpenCode update replaces the patch. Run the installer again after updating.
- Tested on OpenCode 2.3.0.

## License

MIT
