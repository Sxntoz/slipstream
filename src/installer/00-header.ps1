<#
  Slipstream - per-app connection patcher for Windows.
  Gives one app its own route (WireGuard, proxy), a new IP on demand and safe clean-ups, without touching the rest of the PC.
  Supported apps: OpenCode desktop (more to come).

  Run:
    .\run.ps1                    install / update the patch
    .\run.ps1 -uninstall         remove it, back to the original
    .\run.ps1 -status            show what is installed
    .\run.ps1 -start             open OpenCode when done
    .\run.ps1 -download          install the ORIGINAL OpenCode from GitHub first, if it is missing
    .\run.ps1 -yes               answer Yes to every question (the installer asks nothing)
    .\run.ps1 -update            update OpenCode to the newest official version, then patch it again.
                                  Your chats, login and settings are saved first and checked afterwards: nothing is lost
    .\run.ps1 -desktop           Slipstream Desktop only: the tray icon for the OpenCode app (no question)
    .\run.ps1 -cli               Slipstream CLI only: a tray icon + the terminal commands  slipstream cli / opencode1 / opencode2
                                 (-terminal is the same). Add -update to also update the terminal OpenCode (v2 and v1).
                                 With none of these the installer asks: Desktop, CLI or both.
    .\run.ps1 -block_update_off  let OpenCode update itself again (updates remove the patch)
    .\run.ps1 -path <folder>     OpenCode folder, if it is not in the default place
    .\run.ps1 -lang pt-BR        installer language (default: your Windows language; the tray menu has its own Language item)

  What it adds (tray icon next to the clock):
    New IP .............. built-in WARP (our own WireGuard in JS, no .exe): new account and tunnel / next proxy of your list
    Connection .......... Direct | Built-in WARP | WireGuard file (.conf) | Free public proxies | Own proxy list
                          (only OpenCode uses it; the rest of the PC stays as it is. IPv6 first, IPv4 as fallback)
    Auto-rotate ......... when the free limit stops a chat: new IP, then the message is sent again by itself
    Clear > ............. Login (auth.json, backed up first) | Restore login | Cache and logs. Chats are never touched.
    Restart / Quit ...... restart OpenCode, or close it completely (tunnel included)
    Status .............. the IP OpenCode is using
  And it removes the "Free limit reached / subscribe to Go" tray and popup.

  How: app.asar gets a new entry file; the original is saved as app.asar.slipstream.bak. -uninstall puts it back.
  Files of the tool: %LOCALAPPDATA%\slipstream  (proxy.json = settings and proxy list, slipstream.log)
#>
param(
  [switch]$uninstall,
  [switch]$status,
  [switch]$start,
  [switch]$download,
  [Alias('y')][switch]$yes,
  [switch]$update,
  [switch]$desktop,
  [Alias('cli')][switch]$terminal,
  [switch]$block_update_off,
  [string]$version = '',
  [string]$path = '',
  [string]$lang = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

