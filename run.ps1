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
    .\run.ps1 -block_update_off  let OpenCode update itself again (updates remove the patch)
    .\run.ps1 -path <folder>     OpenCode folder, if it is not in the default place

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
  [switch]$block_update_off,
  [string]$version = '',
  [string]$path = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

function Say($m, $c = 'White') { Write-Host $m -ForegroundColor $c }
function Step($m) { Write-Host '  > ' -NoNewline -ForegroundColor Cyan; Write-Host $m }
function Ok($m)   { Write-Host '  + ' -NoNewline -ForegroundColor Green; Write-Host $m }
function Warn($m) { Write-Host '  ! ' -NoNewline -ForegroundColor Yellow; Write-Host $m }
function Fail($m) { Write-Host '  x ' -NoNewline -ForegroundColor Red; Write-Host $m }

$ScriptVersion = '1.0.0'
Say @"

  +-------------------------------------+
  |  Welcome to Slipstream for Windows  |
  +-------------------------------------+
  patcher $ScriptVersion

"@ Cyan

if ($PSVersionTable.PSVersion.Major -lt 5) { Fail 'PowerShell 5.1 or above is required.'; Say '  Script is stopped' Red; return }
if ($env:OS -ne 'Windows_NT') { Fail 'This patcher is for Windows.'; Say '  Script is stopped' Red; return }

# ---------------------------------------------------------------- locate OpenCode
$exeName = 'OpenCode.exe'
$candidates = @($path, (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop'), (Join-Path $env:ProgramFiles 'OpenCode'), (Join-Path $env:LOCALAPPDATA 'Programs\OpenCode')) | Where-Object { $_ }
function Find-Install { foreach ($c in $candidates) { if (Test-Path (Join-Path $c $exeName)) { return $c } }; $null }

function Stop-OpenCode {
  $n = 0
  foreach ($p in 'OpenCode', 'opencode-cli') {
    Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill(); $n++ } catch {} }
  }
  if ($n) { Start-Sleep 2; Step "closed $n process(es)" }
}

# ---------------------------------------------------------------- download the original
function Get-Original([string]$want) {
  if ($want) { $tag = "v$($want.TrimStart('v'))" }
  else {
    Step 'looking for the newest OpenCode desktop release...'
    $rels = Invoke-RestMethod 'https://api.github.com/repos/anomalyco/opencode/releases?per_page=30' -Headers @{ 'User-Agent' = 'slipstreame' }
    $tag = ($rels | Where-Object { $_.tag_name -match '^v\d+\.\d+\.\d+$' -and $_.assets.name -contains 'opencode-desktop-win-x64.exe' } |
            Sort-Object { [version]($_.tag_name.TrimStart('v')) } -Descending | Select-Object -First 1).tag_name
  }
  if (-not $tag) { throw 'no release with a Windows installer was found' }
  $out = Join-Path $env:TEMP "opencode-desktop-win-x64-$tag.exe"
  Step "downloading $tag ..."
  for ($try = 1; $try -le 3; $try++) {
    try { Invoke-WebRequest "https://github.com/anomalyco/opencode/releases/download/$tag/opencode-desktop-win-x64.exe" -OutFile $out -UseBasicParsing; break }
    catch {
      Warn "Error downloading ($($_.Exception.Message))"
      if ($try -eq 3) { throw 'Check your network settings and run the installation again' }
      Warn 'Will re-request in 5 seconds...'; Start-Sleep 5
    }
  }
  Step 'installing the original (silent)...'
  Start-Process $out -ArgumentList '/S' -Wait
  Remove-Item $out -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- the module that goes inside app.asar
$BootJs = @'
// Slipstream - slipstream-boot.js. package.json "main" points here; it sets things up and then loads the original index.js.
import { app, Tray, Menu, Notification, shell, dialog, nativeImage } from "electron"
import { execFileSync } from "node:child_process"
import dgram from "node:dgram"
import { lookup as dnsLookup } from "node:dns/promises"
import crypto, { generateKeyPairSync } from "node:crypto"
import { existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, rmSync, readdirSync, statSync } from "node:fs"
import https from "node:https"
import net from "node:net"
import os from "node:os"
import path from "node:path"
import { Duplex } from "node:stream"
import tls from "node:tls"

const home = os.homedir()
const dataDir = path.join(process.env.XDG_DATA_HOME ?? path.join(home, ".local", "share"), "opencode")
const userData = path.join(process.env.APPDATA ?? path.join(home, "AppData", "Roaming"), "ai.opencode.desktop")
const stateDir = path.join(process.env.LOCALAPPDATA ?? path.join(home, ".local", "state"), "slipstream")
mkdirSync(stateDir, { recursive: true })

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const log = (m) => { try { writeFileSync(path.join(stateDir, "slipstream.log"), `${new Date().toISOString()} ${m}\n`, { flag: "a" }) } catch {} }
const why = (e) => [e?.message, e?.cause?.code, e?.cause?.message].filter(Boolean).join(" - ") || String(e)
// Windows often swallows toasts of unpackaged apps, so results are also logged and shown in a message box.
const say = (body) => {
  log(body)
  try { new Notification({ title: "Slipstream", body: String(body) }).show() } catch {}
  dialog.showMessageBox({ type: "info", title: "Slipstream", message: String(body), buttons: ["OK"] }).catch(() => {})
}
const note = (body) => { log(body); try { new Notification({ title: "Slipstream", body: String(body) }).show() } catch {} }
let busy = false
const guard = (fn) => async () => {
  if (busy) return say("Another action is still running.")
  busy = true
  try { say(await fn()) } catch (e) { say(why(e)) } finally { busy = false }
}

// ---------------------------------------------------------------- before the app starts: pending clean-ups
// The Clear actions restart the app and are done here, while nothing is locked and the service cannot write auth.json back.
const pendingFile = path.join(stateDir, "pending.json")
const backupDir = path.join(stateDir, "backup")
// Caches and logs only. Chats (opencode.db), settings, drafts and the undo snapshots are never in these lists.
const CACHE = ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache", "GPUPersistentCache", "Crashpad", "logs", "Shared Dictionary"]
const dirBytes = (d) => {
  let n = 0
  try { for (const e of readdirSync(d, { withFileTypes: true })) { const f = path.join(d, e.name); n += e.isDirectory() ? dirBytes(f) : statSync(f).size } } catch {}
  return n
}
const newestBackup = () => { try { return readdirSync(backupDir).filter((n) => existsSync(path.join(backupDir, n, "auth.json"))).sort().at(-1) } catch { return undefined } }
let afterStart = ""      // what the last clean-up did, shown once the app is up
try {
  if (existsSync(pendingFile)) {
    const todo = JSON.parse(readFileSync(pendingFile, "utf8"))
    rmSync(pendingFile, { force: true })
    const auth = path.join(dataDir, "auth.json")
    if (todo.includes("tokens") && existsSync(auth)) {
      const dir = path.join(backupDir, new Date().toISOString().replace(/[:.]/g, "-"))
      mkdirSync(dir, { recursive: true })
      copyFileSync(auth, path.join(dir, "auth.json"))
      if (readFileSync(auth).equals(readFileSync(path.join(dir, "auth.json")))) { rmSync(auth, { force: true }); afterStart = "Login removed (a copy is saved). Chats kept." }   // removed only after the copy is verified
      else afterStart = "Could not verify the login backup, so the login was not removed."
    }
    if (todo.includes("restore")) {
      const from = newestBackup()
      if (from && !existsSync(auth)) { mkdirSync(dataDir, { recursive: true }); copyFileSync(path.join(backupDir, from, "auth.json"), auth); afterStart = `Login restored from ${from}.` }
    }
    if (todo.includes("cache")) {
      let bytes = 0
      for (const d of [...CACHE.map((n) => path.join(userData, n)), path.join(dataDir, "log")]) { bytes += dirBytes(d); rmSync(d, { recursive: true, force: true }) }
      afterStart = `Cache and logs cleared (${(bytes / 1048576).toFixed(1)} MB). Chats kept.`
    }
  }
} catch (e) { log("clean-up failed: " + why(e)); afterStart = "Clean-up failed: " + why(e) }

// The app keeps the free-limit time in its database after a limit error and shows its tray until then. Clear it before the app opens the database.
try {
  const { DatabaseSync } = await import("node:sqlite")
  const db = new DatabaseSync(path.join(userData, "drafts.sqlite"))
  db.prepare("update state set value = ? where name = 'opencode.global.dat' and key = 'free-limit'").run('{"resetAt":null}')
  db.close()
} catch (e) { log("free-limit state not cleared: " + why(e)) }

// ---------------------------------------------------------------- settings (proxy.json)
const proxyFile = path.join(stateDir, "proxy.json")
const MODES = ["none", "wg", "wgfile", "free", "list"]
const DEFAULT_CFG = { mode: "none", autoRotate: true, gatePort: 0, current: "", list: ["# one proxy per line: http://user:pass@host:port | socks5://host:port | host:port"] }
const loadCfg = () => {
  let c = {}
  try { c = JSON.parse(readFileSync(proxyFile, "utf8")) } catch {}
  const cfg = { ...DEFAULT_CFG, ...c }
  if (!MODES.includes(cfg.mode)) cfg.mode = "none"
  return cfg
}
const saveCfg = (c) => writeFileSync(proxyFile, JSON.stringify(c, null, 2))
let cfg = loadCfg()
if (!existsSync(proxyFile)) saveCfg(cfg)

// ---------------------------------------------------------------- local gate: the only proxy OpenCode talks to
// 127.0.0.1:<port> forwards to the current upstream (built-in WARP, a proxy of the list, or direct). Changing the upstream is instant.
function parseUp(s) {
  const m = /^(?:(\w+):\/\/)?(?:([^:@\/]*):([^@\/]*)@)?([^:\/\s]+):(\d+)/.exec(String(s).trim())
  if (!m) return undefined
  return { kind: (m[1] ?? "http").toLowerCase().startsWith("socks") ? "socks" : "http", user: m[2], pass: m[3], host: m[4], port: Number(m[5]) }
}
let wg = null          // the WireGuard tunnel (see UserWireGuard)
let freeCurrent = ""   // the public proxy in use while the mode is "free"
const DEAD = { kind: "http", host: "127.0.0.1", port: 1 }
const upstream = () =>
  cfg.mode === "list" ? parseUp(cfg.current)
  : cfg.mode === "wg" || cfg.mode === "wgfile" ? (wg?.session ? { kind: "wg" } : DEAD)   // tunnel down = no connection, never the real IP
  : cfg.mode === "free" ? (freeCurrent ? parseUp(freeCurrent) : DEAD)
  : undefined

const readUntil = (sock, test) => new Promise((resolve, reject) => {
  let buf = Buffer.alloc(0)
  const on = (d) => { buf = Buffer.concat([buf, d]); const n = test(buf); if (n >= 0) { cleanup(); resolve({ buf, n }) } }
  const bad = (e) => { cleanup(); reject(e ?? new Error("closed")) }
  const cleanup = () => { sock.off("data", on); sock.off("error", bad); sock.off("close", bad) }
  sock.on("data", on); sock.once("error", bad); sock.once("close", bad)
})

// A tunnel to host:port through the upstream (undefined = direct).
async function dial(up, host, port, timeout = 15000) {
  const open = (h, p) => new Promise((res, rej) => {
    const s = net.connect({ host: h, port: p }, () => res(s))
    s.once("error", rej); s.setTimeout(timeout, () => s.destroy(new Error("timeout")))
  })
  if (up?.kind === "wg") return await wg.connect(host, port)
  if (!up) { const s = await open(host, port); s.setTimeout(0); return s }
  const s = await open(up.host, up.port)
  try {
    if (up.kind === "http") {
      const auth = up.user ? `Proxy-Authorization: Basic ${Buffer.from(`${up.user}:${up.pass}`).toString("base64")}\r\n` : ""
      s.write(`CONNECT ${host}:${port} HTTP/1.1\r\nHost: ${host}:${port}\r\n${auth}\r\n`)
      const { buf, n } = await readUntil(s, (b) => b.indexOf("\r\n\r\n"))
      if (!/^HTTP\/1\.[01] 200/.test(buf.toString("latin1", 0, 20))) throw new Error("proxy refused: " + buf.toString("latin1", 0, 40).split("\r\n")[0])
      const rest = buf.subarray(n + 4); if (rest.length) s.unshift(rest)
    } else {
      s.write(up.user ? Buffer.from([5, 2, 0, 2]) : Buffer.from([5, 1, 0]))
      let r = await readUntil(s, (b) => (b.length >= 2 ? 2 : -1))
      if (r.buf[0] !== 5 || r.buf[1] === 0xff) throw new Error("socks: no acceptable auth")
      if (r.buf[1] === 2) {
        const u = Buffer.from(up.user ?? ""), p = Buffer.from(up.pass ?? "")
        s.write(Buffer.concat([Buffer.from([1, u.length]), u, Buffer.from([p.length]), p]))
        r = await readUntil(s, (b) => (b.length >= 2 ? 2 : -1))
        if (r.buf[1] !== 0) throw new Error("socks: bad login")
      }
      const h = Buffer.from(host)
      s.write(Buffer.concat([Buffer.from([5, 1, 0, 3, h.length]), h, Buffer.from([port >> 8, port & 255])]))
      r = await readUntil(s, (b) => { if (b.length < 5) return -1; const need = b[3] === 1 ? 10 : b[3] === 4 ? 22 : 7 + b[4]; return b.length >= need ? need : -1 })
      if (r.buf[1] !== 0) throw new Error("socks: connect failed (" + r.buf[1] + ")")
      const rest = r.buf.subarray(r.n); if (rest.length) s.unshift(rest)
    }
  } catch (e) { s.destroy(); throw e }
  s.setTimeout(0)
  return s
}

const isLocal = (h) => /^(localhost|127\.\d+\.\d+\.\d+|::1|\[::1\])$/i.test(h)   // OpenCode's own service is always reached directly
const gate = net.createServer((client) => {
  client.on("error", () => {})
  let buf = Buffer.alloc(0)
  const onData = async (d) => {
    buf = Buffer.concat([buf, d])
    const end = buf.indexOf("\r\n\r\n"); if (end < 0) { if (buf.length > 65536) client.destroy(); return }
    client.off("data", onData); client.pause()
    const head = buf.toString("latin1", 0, end), rest = buf.subarray(end + 4)
    const [method, target, ver] = head.split("\r\n")[0].split(" ")
    try {
      if (method === "CONNECT") {
        const i = target.lastIndexOf(":"), host = target.slice(0, i).replace(/^\[|\]$/g, "")
        const out = await dial(isLocal(host) ? undefined : upstream(), host, Number(target.slice(i + 1)))
        out.on("error", () => client.destroy()); client.write("HTTP/1.1 200 Connection Established\r\n\r\n")
        if (rest.length) out.write(rest); client.pipe(out); out.pipe(client); client.resume()
      } else {
        const u = new URL(target), out = await dial(isLocal(u.hostname) ? undefined : upstream(), u.hostname, Number(u.port || 80))
        out.on("error", () => client.destroy())
        out.write(Buffer.concat([Buffer.from(`${method} ${u.pathname}${u.search} ${ver}\r\n${head.split("\r\n").slice(1).filter((l) => !/^proxy-/i.test(l)).join("\r\n")}\r\n\r\n`, "latin1"), rest]))
        client.pipe(out); out.pipe(client); client.resume()
      }
    } catch { client.end("HTTP/1.1 502 Bad Gateway\r\n\r\n") }
  }
  client.on("data", onData)
})
// The same port every time: OpenCode's background service outlives the app and keeps the proxy address it was started with.
gate.on("error", () => {})
const listenOn = (port) => new Promise((res) => { const fail = () => res(0); gate.once("error", fail); gate.listen(port, "127.0.0.1", () => { gate.off("error", fail); res(gate.address().port) }) })
let gatePort = cfg.gatePort ? await listenOn(cfg.gatePort) : 0
if (!gatePort) { gatePort = await listenOn(0); cfg.gatePort = gatePort; saveCfg(cfg) }
const gateUrl = `http://127.0.0.1:${gatePort}`
// Only this process and the OpenCode service it starts are pointed at the gate.
for (const k of ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"]) process.env[k] = gateUrl
process.env.NO_PROXY = process.env.no_proxy = "localhost,127.0.0.1,::1"
app.commandLine.appendSwitch("proxy-server", gateUrl)
app.commandLine.appendSwitch("proxy-bypass-list", "localhost;127.0.0.1;[::1]")

// The IP the internet sees through an upstream.
async function traceVia(up) {
  const t = tls.connect({ socket: await dial(up, "www.cloudflare.com", 443, 8000), servername: "www.cloudflare.com" })
  t.write("GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\n\r\n")
  const chunks = []
  await new Promise((res, rej) => { t.on("data", (c) => chunks.push(c)); t.on("end", res); t.on("error", rej); setTimeout(() => rej(new Error("timeout")), 8000) })
  t.destroy()
  return /^ip=(.*)$/m.exec(Buffer.concat(chunks).toString())?.[1]?.trim()
}

// ---------------------------------------------------------------- built-in WARP: our own WireGuard, no .exe, no WARP app
// ---------------------------------------------------------------- user-mode WireGuard (all JS: crypto, handshake, IPv4/TCP/UDP, DNS)
// No driver, no .exe, no admin: UDP to the WARP endpoint, and a tiny TCP/IP stack that turns the tunnel into streams.
const B2_IV = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19])
const B2_SIGMA = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4], [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13], [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11], [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5], [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
]
const rotr = (x, n) => ((x >>> n) | (x << (32 - n))) >>> 0
function blake2s(input, outlen = 32, key = Buffer.alloc(0)) {
  const h = new Uint32Array(B2_IV)
  h[0] ^= 0x01010000 ^ (key.length << 8) ^ outlen
  const data = key.length ? Buffer.concat([Buffer.concat([key, Buffer.alloc(64 - key.length)]), input]) : input
  const blocks = Math.max(1, Math.ceil(data.length / 64))
  const v = new Uint32Array(16), m = new Uint32Array(16)
  for (let b = 0; b < blocks; b++) {
    const last = b === blocks - 1
    const blk = Buffer.alloc(64)
    data.copy(blk, 0, b * 64, Math.min(data.length, (b + 1) * 64))
    for (let i = 0; i < 16; i++) m[i] = blk.readUInt32LE(i * 4)
    v.set(h); v.set(B2_IV, 8)
    v[12] ^= last ? data.length : (b + 1) * 64
    if (last) v[14] = ~v[14]
    const G = (a, b2, c, d, x, y) => {
      v[a] = v[a] + v[b2] + x; v[d] = rotr(v[d] ^ v[a], 16)
      v[c] = v[c] + v[d]; v[b2] = rotr(v[b2] ^ v[c], 12)
      v[a] = v[a] + v[b2] + y; v[d] = rotr(v[d] ^ v[a], 8)
      v[c] = v[c] + v[d]; v[b2] = rotr(v[b2] ^ v[c], 7)
    }
    for (let r = 0; r < 10; r++) {
      const s = B2_SIGMA[r]
      G(0, 4, 8, 12, m[s[0]], m[s[1]]); G(1, 5, 9, 13, m[s[2]], m[s[3]]); G(2, 6, 10, 14, m[s[4]], m[s[5]]); G(3, 7, 11, 15, m[s[6]], m[s[7]])
      G(0, 5, 10, 15, m[s[8]], m[s[9]]); G(1, 6, 11, 12, m[s[10]], m[s[11]]); G(2, 7, 8, 13, m[s[12]], m[s[13]]); G(3, 4, 9, 14, m[s[14]], m[s[15]])
    }
    for (let i = 0; i < 8; i++) h[i] ^= v[i] ^ v[i + 8]
  }
  const out = Buffer.alloc(32)
  for (let i = 0; i < 8; i++) out.writeUInt32LE(h[i], i * 4)
  return out.subarray(0, outlen)
}

const wgHash = (...p) => blake2s(Buffer.concat(p))
function wgHmac(key, data) {
  const k = Buffer.concat([key.length > 64 ? wgHash(key) : key, Buffer.alloc(64)]).subarray(0, 64)
  const ik = Buffer.from(k).map((x) => x ^ 0x36), ok = Buffer.from(k).map((x) => x ^ 0x5c)
  return wgHash(ok, wgHash(ik, data))
}
const kdf1 = (key, input) => wgHmac(wgHmac(key, input), Buffer.from([1]))
function kdf2(key, input) { const t0 = wgHmac(key, input), t1 = wgHmac(t0, Buffer.from([1])); return [t1, wgHmac(t0, Buffer.concat([t1, Buffer.from([2])]))] }
function kdf3(key, input) { const [t1, t2] = kdf2(key, input), t0 = wgHmac(key, input); return [t1, t2, wgHmac(t0, Buffer.concat([t2, Buffer.from([3])]))] }

const wgNonce = (n) => { const b = Buffer.alloc(12); b.writeBigUInt64LE(BigInt(n), 4); return b }

// ChaCha20 (RFC 8439)
const rotl = (x, n) => ((x << n) | (x >>> (32 - n))) >>> 0
function chachaBlock(key, counter, nonce) {
  const st = new Uint32Array(16)
  st[0] = 0x61707865; st[1] = 0x3320646e; st[2] = 0x79622d32; st[3] = 0x6b206574
  for (let i = 0; i < 8; i++) st[4 + i] = key.readUInt32LE(i * 4)
  st[12] = counter
  for (let i = 0; i < 3; i++) st[13 + i] = nonce.readUInt32LE(i * 4)
  const x = new Uint32Array(st)
  const qr = (a, b, c, d) => {
    x[a] += x[b]; x[d] = rotl(x[d] ^ x[a], 16); x[c] += x[d]; x[b] = rotl(x[b] ^ x[c], 12)
    x[a] += x[b]; x[d] = rotl(x[d] ^ x[a], 8); x[c] += x[d]; x[b] = rotl(x[b] ^ x[c], 7)
  }
  for (let i = 0; i < 10; i++) { qr(0, 4, 8, 12); qr(1, 5, 9, 13); qr(2, 6, 10, 14); qr(3, 7, 11, 15); qr(0, 5, 10, 15); qr(1, 6, 11, 12); qr(2, 7, 8, 13); qr(3, 4, 9, 14) }
  const out = Buffer.alloc(64)
  for (let i = 0; i < 16; i++) out.writeUInt32LE((x[i] + st[i]) >>> 0, i * 4)
  return out
}
function chachaXor(key, counter, nonce, data) {
  const out = Buffer.alloc(data.length)
  for (let off = 0; off < data.length; off += 64, counter++) {
    const ks = chachaBlock(key, counter, nonce), n = Math.min(64, data.length - off)
    for (let i = 0; i < n; i++) out[off + i] = data[off + i] ^ ks[i]
  }
  return out
}
// Poly1305 (BigInt: simple, and fast enough for tunnel-sized packets)
const P1305 = (1n << 130n) - 5n
const leBig = (b) => { let n = 0n; for (let i = b.length - 1; i >= 0; i--) n = (n << 8n) | BigInt(b[i]); return n }
function poly1305(key, msg) {
  const r = leBig(key.subarray(0, 16)) & 0x0ffffffc0ffffffc0ffffffc0fffffffn, sKey = leBig(key.subarray(16, 32))
  let acc = 0n
  for (let i = 0; i < msg.length; i += 16) {
    const chunk = msg.subarray(i, i + 16)
    acc = ((acc + leBig(chunk) + (1n << BigInt(8 * chunk.length))) * r) % P1305
  }
  const tag = Buffer.alloc(16); let t = (acc + sKey) & ((1n << 128n) - 1n)
  for (let i = 0; i < 16; i++) { tag[i] = Number(t & 255n); t >>= 8n }
  return tag
}
const pad16 = (b) => Buffer.alloc((16 - (b.length % 16)) % 16)
function aeadTag(key, nonce, aad, ct) {
  const polyKey = chachaBlock(key, 0, nonce).subarray(0, 32)
  const lens = Buffer.alloc(16); lens.writeBigUInt64LE(BigInt(aad.length), 0); lens.writeBigUInt64LE(BigInt(ct.length), 8)
  return poly1305(polyKey, Buffer.concat([aad, pad16(aad), ct, pad16(ct), lens]))
}
function aeadSeal(key, counter, plain, aad) {
  const n = wgNonce(counter), ct = chachaXor(key, 1, n, plain)
  return Buffer.concat([ct, aeadTag(key, n, aad, ct)])
}
function aeadOpen(key, counter, data, aad) {
  const n = wgNonce(counter), ct = data.subarray(0, data.length - 16)
  if (!crypto.timingSafeEqual(aeadTag(key, n, aad, ct), data.subarray(data.length - 16))) throw new Error("bad tag")
  return chachaXor(key, 1, n, ct)
}

// X25519 (RFC 7748)
const P25519 = (1n << 255n) - 19n
const mod = (a) => ((a % P25519) + P25519) % P25519
function powmod(b, e) { let r = 1n; b = mod(b); while (e > 0n) { if (e & 1n) r = (r * b) % P25519; b = (b * b) % P25519; e >>= 1n } return r }
const X_BASE = Buffer.concat([Buffer.from([9]), Buffer.alloc(31)])
function x25519(priv, pub) {
  const k = Buffer.from(priv); k[0] &= 248; k[31] &= 127; k[31] |= 64
  const kn = leBig(k), x1 = leBig(pub) & ((1n << 255n) - 1n)
  let x2 = 1n, z2 = 0n, x3 = x1, z3 = 1n, swap = 0n
  for (let t = 254; t >= 0; t--) {
    const kt = (kn >> BigInt(t)) & 1n
    swap ^= kt
    if (swap) { [x2, x3] = [x3, x2]; [z2, z3] = [z3, z2] }
    swap = kt
    const A = x2 + z2, AA = mod(A * A), B = x2 - z2, BB = mod(B * B), E = AA - BB, C = x3 + z3, D = x3 - z3
    const DA = mod(D * A), CB = mod(C * B)
    x3 = mod((DA + CB) * (DA + CB)); z3 = mod(x1 * mod((DA - CB) * (DA - CB)))
    x2 = mod(AA * BB); z2 = mod(E * (AA + 121665n * E))
  }
  if (swap) { [x2, x3] = [x3, x2]; [z2, z3] = [z3, z2] }
  let r = mod(x2 * powmod(z2, P25519 - 2n))
  const out = Buffer.alloc(32)
  for (let i = 0; i < 32; i++) { out[i] = Number(r & 255n); r >>= 8n }
  return out
}
const WG_C0 = wgHash(Buffer.from("Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s"))
const WG_H0 = wgHash(WG_C0, Buffer.from("WireGuard v1 zx2c4 Jason@zx2c4.com"))
const NOTHING = Buffer.alloc(0)

function tai64n() {
  const b = Buffer.alloc(12), ms = Date.now()
  b.writeBigUInt64BE(BigInt(Math.floor(ms / 1000)) + (1n << 62n) + 10n, 0)
  b.writeUInt32BE((ms % 1000) * 1000000, 8)
  return b
}

// ---- IPv4 / IPv6 / TCP / UDP packets
const ip4 = (s) => Buffer.from(s.split(".").map(Number))
function ip6(s) {
  s = s.split("%")[0]
  const [head, tail = ""] = s.split("::")
  const h = head ? head.split(":") : [], t = tail ? tail.split(":") : []
  const groups = s.includes("::") ? [...h, ...Array(8 - h.length - t.length).fill("0"), ...t] : h
  const b = Buffer.alloc(16)
  groups.forEach((g, i) => b.writeUInt16BE(parseInt(g || "0", 16), i * 2))
  return b
}
const ipText = (b) => (b.length === 4 ? [...b].join(".") : Array.from({ length: 8 }, (_, i) => b.readUInt16BE(i * 2).toString(16)).join(":"))
function checksum(buf, init = 0) {
  let sum = init
  for (let i = 0; i + 1 < buf.length; i += 2) sum += buf.readUInt16BE(i)
  if (buf.length & 1) sum += buf[buf.length - 1] << 8
  while (sum > 0xffff) sum = (sum & 0xffff) + (sum >>> 16)
  return ~sum & 0xffff
}
let ipId = 1
function buildIp(proto, src, dst, payload) {
  if (src.length === 16) {
    const h = Buffer.alloc(40)
    h[0] = 0x60; h.writeUInt16BE(payload.length, 4); h[6] = proto; h[7] = 64
    src.copy(h, 8); dst.copy(h, 24)
    return Buffer.concat([h, payload])
  }
  const h = Buffer.alloc(20)
  h[0] = 0x45; h.writeUInt16BE(20 + payload.length, 2); h.writeUInt16BE(ipId++ & 0xffff, 4); h.writeUInt16BE(0x4000, 6); h[8] = 64; h[9] = proto
  src.copy(h, 12); dst.copy(h, 16); h.writeUInt16BE(checksum(h), 10)
  return Buffer.concat([h, payload])
}
function pseudo(src, dst, proto, len) {
  if (src.length === 16) { const p = Buffer.alloc(40); src.copy(p, 0); dst.copy(p, 16); p.writeUInt32BE(len, 32); p[39] = proto; return p }
  const p = Buffer.alloc(12); src.copy(p, 0); dst.copy(p, 4); p[9] = proto; p.writeUInt16BE(len, 10); return p
}
function tcpSegment(src, dst, sport, dport, seq, ack, flags, win, data = NOTHING, mss = 0) {
  const opt = mss ? Buffer.from([2, 4, mss >> 8, mss & 255]) : NOTHING
  const h = Buffer.alloc(20 + opt.length + data.length)
  h.writeUInt16BE(sport, 0); h.writeUInt16BE(dport, 2); h.writeUInt32BE(seq >>> 0, 4); h.writeUInt32BE(ack >>> 0, 8)
  h[12] = ((20 + opt.length) / 4) << 4; h[13] = flags; h.writeUInt16BE(win, 14)
  opt.copy(h, 20); data.copy(h, 20 + opt.length)
  h.writeUInt16BE(checksum(h, ~checksum(pseudo(src, dst, 6, h.length)) & 0xffff), 16)
  return h
}
function udpDatagram(src, dst, sport, dport, data) {
  const h = Buffer.alloc(8 + data.length)
  h.writeUInt16BE(sport, 0); h.writeUInt16BE(dport, 2); h.writeUInt16BE(h.length, 4); data.copy(h, 8)
  const c = checksum(h, ~checksum(pseudo(src, dst, 17, h.length)) & 0xffff)
  h.writeUInt16BE(c || 0xffff, 6)
  return h
}

const TCP_FIN = 1, TCP_SYN = 2, TCP_RST = 4, TCP_PSH = 8, TCP_ACK = 16
const seqLt = (a, b) => ((a - b) | 0) < 0
const seqLe = (a, b) => ((a - b) | 0) <= 0

class WgTcp extends Duplex {
  constructor(wg, dstIp, dstPort, synTries = 5) {
    super({ allowHalfOpen: true })
    this.wg = wg; this.dst = dstIp; this.dport = dstPort; this.sport = wg.allocPort()
    this.local = dstIp.length === 16 ? wg.addr6 : wg.addr
    this.maxMss = wg.mtu - (dstIp.length === 16 ? 60 : 40)       // MTU minus IP and TCP headers
    this.iss = crypto.randomBytes(4).readUInt32BE(0)
    this.sndUna = this.iss; this.sndNxt = (this.iss + 1) >>> 0
    this.rcvNxt = 0; this.peerWnd = 65535; this.mss = this.maxMss
    this.state = "syn"; this.out = []; this.outBytes = 0; this.inflight = []; this.ooo = new Map(); this.finSent = false; this.ending = false
    this.drainCb = null; this.tries = 0
    wg.tcp.set(this.sport, this)
    this.sendSeg(TCP_SYN, this.iss, NOTHING, this.maxMss)
    this.synTimer = setInterval(() => {
      if (this.state !== "syn") return clearInterval(this.synTimer)
      if (++this.tries >= synTries) return this.destroy(new Error("connect timed out through the tunnel"))
      this.sendSeg(TCP_SYN, this.iss, NOTHING, this.maxMss)
    }, 1500)
    this.rtoTimer = setInterval(() => this.retransmit(), 400)
  }
  sendSeg(flags, seq, data = NOTHING, mss = 0) {
    const seg = tcpSegment(this.local, this.dst, this.sport, this.dport, seq, flags & TCP_ACK ? this.rcvNxt : 0, flags, 65535, data, mss)
    this.wg.sendIp(buildIp(6, this.local, this.dst, seg))
  }
  ackNow() { this.sendSeg(TCP_ACK, this.sndNxt) }
  _read() {}
  _write(chunk, _enc, cb) {
    this.out.push(chunk); this.outBytes += chunk.length
    this.pump()
    if (this.outBytes < 256 * 1024) cb(); else this.drainCb = cb
  }
  _final(cb) { this.ending = true; this.pump(); cb() }
  pump() {
    if (this.state !== "est" && this.state !== "closeWait") return
    const flight = () => (this.sndNxt - this.sndUna) >>> 0
    const room = () => Math.min(this.peerWnd, 48 * 1024) - flight()
    while (this.outBytes > 0 && room() > 0) {
      let want = Math.min(this.mss, room(), this.outBytes)
      const parts = []
      while (want > 0) {
        const head = this.out[0]
        if (head.length <= want) { parts.push(head); want -= head.length; this.out.shift() }
        else { parts.push(head.subarray(0, want)); this.out[0] = head.subarray(want); want = 0 }
      }
      const data = Buffer.concat(parts)
      this.outBytes -= data.length
      const seg = { seq: this.sndNxt, data, sentAt: Date.now(), tries: 0 }
      this.inflight.push(seg); this.sndNxt = (this.sndNxt + data.length) >>> 0
      this.sendSeg(TCP_ACK | TCP_PSH, seg.seq, data)
    }
    if (this.drainCb && this.outBytes < 128 * 1024) { const cb = this.drainCb; this.drainCb = null; cb() }
    if (this.ending && !this.finSent && this.outBytes === 0) {
      this.finSent = true
      this.inflight.push({ seq: this.sndNxt, data: NOTHING, fin: true, sentAt: Date.now(), tries: 0 })
      this.sendSeg(TCP_ACK | TCP_FIN, this.sndNxt)
      this.sndNxt = (this.sndNxt + 1) >>> 0
    }
  }
  retransmit() {
    const now = Date.now()
    for (const seg of this.inflight) {
      const rto = Math.min(1000 * 2 ** seg.tries, 8000)
      if (now - seg.sentAt < rto) break
      if (++seg.tries > 8) return this.destroy(new Error("tunnel stopped answering"))
      seg.sentAt = now
      this.sendSeg(TCP_ACK | (seg.fin ? TCP_FIN : TCP_PSH), seg.seq, seg.data)
      break
    }
  }
  onSegment(h, data) {
    const flags = h.flags
    if (flags & TCP_RST) return this.destroy(new Error("connection reset by the remote host"))
    if (this.state === "syn") {
      if ((flags & (TCP_SYN | TCP_ACK)) === (TCP_SYN | TCP_ACK) && h.ack === this.sndNxt) {
        this.rcvNxt = (h.seq + 1) >>> 0; this.sndUna = h.ack; this.peerWnd = h.win
        if (h.mss) this.mss = Math.min(this.maxMss, h.mss)
        this.state = "est"; clearInterval(this.synTimer)
        this.ackNow(); this.emit("tunnel-connect"); this.pump()
      }
      return
    }
    if (flags & TCP_ACK) {
      this.peerWnd = h.win
      if (seqLt(this.sndUna, h.ack) && seqLe(h.ack, this.sndNxt)) {
        this.sndUna = h.ack
        this.inflight = this.inflight.filter((s) => seqLt(h.ack, (s.seq + Math.max(1, s.data.length)) >>> 0))
      }
      this.pump()
      if (this.finSent && this.inflight.length === 0 && this.state === "closeWait") return this.close()
    }
    if (data.length || flags & TCP_FIN) {
      let seq = h.seq
      if (seqLt(seq, this.rcvNxt)) {                 // partly or fully old: keep what is new
        const skip = (this.rcvNxt - seq) >>> 0
        if (skip >= data.length && !(flags & TCP_FIN && skip === data.length)) return this.ackNow()
        data = data.subarray(Math.min(skip, data.length)); seq = this.rcvNxt
      }
      if (seq === this.rcvNxt) {
        if (data.length) { this.rcvNxt = (this.rcvNxt + data.length) >>> 0; this.push(data) }
        if (flags & TCP_FIN) this.gotFin()
        while (this.ooo.has(this.rcvNxt)) {
          const next = this.ooo.get(this.rcvNxt); this.ooo.delete(this.rcvNxt)
          this.rcvNxt = (this.rcvNxt + next.length) >>> 0; this.push(next)
        }
      } else if (this.ooo.size < 64) this.ooo.set(seq, Buffer.from(data))
      this.ackNow()
    }
  }
  gotFin() {
    if (this.state === "closeWait") return
    this.rcvNxt = (this.rcvNxt + 1) >>> 0
    this.state = "closeWait"
    this.push(null)
  }
  close() { clearInterval(this.rtoTimer); clearInterval(this.synTimer); this.wg.tcp.delete(this.sport); this.wg.ports.delete(this.sport) }
  _destroy(err, cb) {
    if (this.state !== "syn" || err) { try { this.sendSeg(TCP_RST | TCP_ACK, this.sndNxt) } catch {} }
    this.close(); cb(err)
  }
}

class UserWireGuard {
  // opts: { priv, peerKey (base64), psk? (base64), endpoint "host:port", v4?, v6?, dns? ("1.1.1.1"), mtu? (1280), preferV6? (true) }
  constructor(opts) {
    this.opts = opts
    this.sPriv = Buffer.from(opts.priv, "base64"); this.sPub = x25519(this.sPriv, X_BASE)
    this.rPub = Buffer.from(opts.peerKey, "base64")
    this.psk = opts.psk ? Buffer.from(opts.psk, "base64") : Buffer.alloc(32)
    this.addr = opts.v4 ? ip4(opts.v4) : null
    this.addr6 = opts.v6 ? ip6(opts.v6) : null
    this.mtu = opts.mtu || 1280
    this.dns = ip4(opts.dns || "1.1.1.1")
    this.preferV6 = opts.preferV6 !== false
    this.tcp = new Map(); this.udp = new Map(); this.ports = new Set()
    this.session = null; this.prev = null; this.pending = null; this.dnsCache = new Map()
  }
  allocPort() { for (;;) { const p = 20000 + crypto.randomInt(40000); if (!this.ports.has(p) && !this.tcp.has(p) && !this.udp.has(p)) { this.ports.add(p); return p } } }
  async start() {
    const [host, port] = this.opts.endpoint.split(":")
    const { address } = await dnsLookup(host, { family: 4 })
    this.remote = { address, port: Number(port || 2408) }
    this.sock = dgram.createSocket("udp4")
    this.sock.on("message", (m) => { try { this.onUdp(m) } catch {} })
    this.sock.on("error", () => {})
    await new Promise((res) => this.sock.bind(0, res))
    let lastErr = new Error("no handshake answer")
    for (let attempt = 0; attempt < 4 && !this.session; attempt++) {
      await this.handshake().catch((e) => (lastErr = e))
    }
    if (!this.session) { this.stop(); throw new Error("WireGuard handshake failed: " + lastErr.message + " (is UDP " + this.remote.port + " blocked?)") }
    this.keep = setInterval(() => this.send(NOTHING), 20000)                       // keep-alive
    this.rekey = setInterval(() => this.handshake().catch(() => {}), 100000)        // WireGuard replaces keys every 2 minutes
  }
  stop() {
    clearInterval(this.keep); clearInterval(this.rekey)
    for (const t of [...this.tcp.values()]) t.destroy()
    try { this.sock?.close() } catch {}
    this.session = null
  }
  handshake() {
    return new Promise((resolve, reject) => {
      const index = crypto.randomBytes(4).readUInt32LE(0)
      let C = WG_C0, H = wgHash(WG_H0, this.rPub)
      const ePriv = crypto.randomBytes(32), ePub = x25519(ePriv, X_BASE)
      C = kdf1(C, ePub); H = wgHash(H, ePub)
      let k; [C, k] = kdf2(C, x25519(ePriv, this.rPub))
      const encS = aeadSeal(k, 0, this.sPub, H); H = wgHash(H, encS);
      [C, k] = kdf2(C, x25519(this.sPriv, this.rPub))
      const encT = aeadSeal(k, 0, tai64n(), H); H = wgHash(H, encT)
      const msg = Buffer.alloc(148)
      msg[0] = 1; msg.writeUInt32LE(index, 4); ePub.copy(msg, 8); encS.copy(msg, 40); encT.copy(msg, 88)
      blake2s(msg.subarray(0, 116), 16, wgHash(Buffer.from("mac1----"), this.rPub)).copy(msg, 116)
      const done = (err) => { clearTimeout(timer); this.pending = null; err ? reject(err) : resolve() }
      const timer = setTimeout(() => done(new Error("no answer from the WireGuard server")), 5000)
      this.pending = { index, C, H, ePriv, done }
      this.sock.send(msg, this.remote.port, this.remote.address)
    })
  }
  onUdp(m) {
    const type = m[0]
    if (type === 2 && m.length === 92 && this.pending && m.readUInt32LE(8) === this.pending.index) {
      const p = this.pending
      let { C, H } = p
      const er = m.subarray(12, 44)
      C = kdf1(C, er); H = wgHash(H, er)
      C = kdf1(C, x25519(p.ePriv, er)); C = kdf1(C, x25519(this.sPriv, er))
      const [c3, tau, k] = kdf3(C, this.psk); C = c3
      H = wgHash(H, tau)
      try { aeadOpen(k, 0, m.subarray(44, 60), H) } catch { return p.done(new Error("handshake answer failed its check")) }
      const [send, recv] = kdf2(C, NOTHING)
      this.prev = this.session
      this.session = { send, recv, counter: 0, theirIndex: m.readUInt32LE(4), at: Date.now() }
      p.done()
      this.send(NOTHING)
    } else if (type === 4 && m.length >= 32) {
      const counter = Number(m.readBigUInt64LE(8)), body = m.subarray(16)
      let pt
      for (const s of [this.session, this.prev]) {
        if (!s) continue
        try { pt = aeadOpen(s.recv, counter, body, NOTHING); break } catch {}
      }
      if (!pt || pt.length < 20) return
      const len = (pt[0] >> 4) === 6 ? 40 + pt.readUInt16BE(4) : pt.readUInt16BE(2)
      this.onIp(pt.subarray(0, Math.min(pt.length, len)))
    }
  }
  send(plain) {
    const s = this.session
    if (!s) return
    const padded = Buffer.alloc(Math.ceil(plain.length / 16) * 16); plain.copy(padded)
    const hdr = Buffer.alloc(16); hdr[0] = 4; hdr.writeUInt32LE(s.theirIndex, 4); hdr.writeBigUInt64LE(BigInt(s.counter), 8)
    this.sock.send(Buffer.concat([hdr, aeadSeal(s.send, s.counter++, padded, NOTHING)]), this.remote.port, this.remote.address)
  }
  sendIp(pkt) { this.send(pkt) }
  onIp(p) {
    const ver = p[0] >> 4
    let proto, pl
    if (ver === 4) { proto = p[9]; pl = p.subarray((p[0] & 15) * 4) }
    else if (ver === 6) { proto = p[6]; pl = p.subarray(40) }       // extension headers are not used by the servers we talk to
    else return
    if (proto === 6 && pl.length >= 20) {
      const conn = this.tcp.get(pl.readUInt16BE(2))
      if (!conn) return
      const off = (pl[12] >> 4) * 4
      let mss = 0
      for (let i = 20; i + 3 < off;) { const kind = pl[i]; if (kind === 0) break; if (kind === 1) { i++; continue } if (kind === 2) mss = pl.readUInt16BE(i + 2); i += pl[i + 1] || 1 }
      conn.onSegment({ seq: pl.readUInt32BE(4), ack: pl.readUInt32BE(8), flags: pl[13], win: pl.readUInt16BE(14), mss }, pl.subarray(off))
    } else if (proto === 17 && pl.length >= 8) {
      const h = this.udp.get(pl.readUInt16BE(2))
      if (h) h(pl.subarray(8))
    }
  }
  // One DNS question through the tunnel (over IPv4 UDP to the tunnel's DNS server); returns the raw answers of that type.
  async dnsQuery(name, qtype) {
    if (!this.addr) throw new Error("this tunnel has no IPv4 address for DNS")
    const sport = this.allocPort(), id = crypto.randomBytes(2)
    const labels = name.split(".").map((l) => Buffer.concat([Buffer.from([l.length]), Buffer.from(l)]))
    const q = Buffer.concat([id, Buffer.from([1, 0, 0, 1, 0, 0, 0, 0, 0, 0]), ...labels, Buffer.from([0, qtype >> 8, qtype & 255, 0, 1])])
    const answer = await new Promise((resolve, reject) => {
      let tries = 0, timer
      const fire = () => {
        if (++tries > 3) { this.udp.delete(sport); this.ports.delete(sport); return reject(new Error("DNS through the tunnel timed out for " + name)) }
        this.sendIp(buildIp(17, this.addr, this.dns, udpDatagram(this.addr, this.dns, sport, 53, q)))
        timer = setTimeout(fire, 2000)
      }
      this.udp.set(sport, (data) => { if (data.subarray(0, 2).equals(id)) { clearTimeout(timer); this.udp.delete(sport); this.ports.delete(sport); resolve(data) } })
      fire()
    })
    let pos = 12
    for (let i = 0; i < answer.readUInt16BE(4); i++) { while (answer[pos] !== 0) pos += (answer[pos] & 0xc0) === 0xc0 ? 1 : answer[pos] + 1; pos += 5 }
    const found = []
    for (let i = 0; i < answer.readUInt16BE(6); i++) {
      while (answer[pos] !== 0 && (answer[pos] & 0xc0) !== 0xc0) pos += answer[pos] + 1
      pos += (answer[pos] & 0xc0) === 0xc0 ? 2 : 1
      const type = answer.readUInt16BE(pos), len = answer.readUInt16BE(pos + 8)
      if (type === qtype) found.push(Buffer.from(answer.subarray(pos + 10, pos + 10 + len)))
      pos += 10 + len
    }
    return found
  }
  // { v4, v6 } addresses (Buffers) of a name; literal addresses are returned as they are.
  async resolve(name) {
    if (/^\d+\.\d+\.\d+\.\d+$/.test(name)) return { v4: ip4(name) }
    if (name.includes(":")) return { v6: ip6(name) }
    const hit = this.dnsCache.get(name)
    if (hit && hit.until > Date.now()) return hit.r
    const [a, aaaa] = await Promise.all([this.dnsQuery(name, 1).catch(() => []), this.addr6 ? this.dnsQuery(name, 28).catch(() => []) : []])
    const r = { v4: a.find((x) => x.length === 4), v6: aaaa.find((x) => x.length === 16) }
    if (!r.v4 && !r.v6) throw new Error("no address for " + name)
    this.dnsCache.set(name, { r, until: Date.now() + 60000 })
    return r
  }
  tcpTo(ip, port, synTries) {
    const t = new WgTcp(this, ip, port, synTries)
    return new Promise((res, rej) => { t.once("tunnel-connect", () => res(t)); t.once("error", rej); t.once("close", () => rej(new Error("closed"))) })
  }
  // A TCP stream through the tunnel. IPv6 first when the host has it and the tunnel does (then IPv4 as a fallback).
  async connect(host, port) {
    if (!this.session) throw new Error("the WireGuard tunnel is down")
    const r = await this.resolve(host)
    const v6 = this.addr6 && r.v6, v4 = this.addr && r.v4
    const order = this.preferV6 ? [v6, v4] : [v4, v6]
    let lastErr = new Error("no usable address for " + host)
    for (const ip of order) {
      if (!ip) continue
      try { return await this.tcpTo(ip, port, order.filter(Boolean).length > 1 ? 2 : 5) } catch (e) { lastErr = e }
    }
    throw lastErr
  }
}

// ---- WireGuard .conf import (Route64, ProtonVPN, Mullvad, your own server...)
function parseWgConf(text) {
  const out = { addrs: [] }
  let section = "", peers = 0
  for (let line of String(text).split(/\r?\n/)) {
    line = line.replace(/[#;].*$/, "").trim()
    if (!line) continue
    const sec = /^\[(\w+)\]$/.exec(line)
    if (sec) { section = sec[1].toLowerCase(); if (section === "peer") peers++; continue }
    const kv = /^(\w+)\s*=\s*(.*)$/.exec(line)
    if (!kv) continue
    const key = kv[1].toLowerCase(), val = kv[2].trim()
    if (section === "interface") {
      if (key === "privatekey") out.priv = val
      else if (key === "address") out.addrs.push(...val.split(",").map((x) => x.trim().split("/")[0]))
      else if (key === "dns") out.dns = val.split(",").map((x) => x.trim()).find((x) => /^\d+\.\d+\.\d+\.\d+$/.test(x))
      else if (key === "mtu") out.mtu = Number(val)
    } else if (section === "peer" && peers === 1) {          // the first peer only
      if (key === "publickey") out.peerKey = val
      else if (key === "presharedkey") out.psk = val
      else if (key === "endpoint") out.endpoint = val.replace(/^\[(.*)\]:(\d+)$/, "$1:$2")
    }
  }
  out.v4 = out.addrs.find((a) => /^\d+\.\d+\.\d+\.\d+$/.test(a))
  out.v6 = out.addrs.find((a) => a.includes(":"))
  if (!out.priv || !out.peerKey || !out.endpoint || !(out.v4 || out.v6)) throw new Error("this WireGuard file needs PrivateKey, Address, and a [Peer] with PublicKey and Endpoint")
  return out
}

// A free WARP account is registered over Cloudflare's API (the call wgcf makes) and the tunnel is our UserWireGuard above.
const wgDir = path.join(stateDir, "wg")
const wgAccountFile = path.join(wgDir, "account.json")
mkdirSync(wgDir, { recursive: true })

// Plain HTTPS for setup calls, never through the gate, with a readable error.
function httpsFetch(url, { method = "GET", headers = {}, body, timeout = 30000, hops = 5 } = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, { method, headers, agent: false, timeout }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && hops > 0) {
        res.resume()
        return resolve(httpsFetch(new URL(res.headers.location, url).href, { timeout, hops: hops - 1 }))
      }
      const chunks = []
      res.on("data", (c) => chunks.push(c))
      res.on("end", () => resolve({ status: res.statusCode, ok: res.statusCode >= 200 && res.statusCode < 300, buf: Buffer.concat(chunks) }))
      res.on("error", reject)
    })
    req.on("timeout", () => req.destroy(new Error("timed out")))
    req.on("error", (e) => reject(new Error(`${new URL(url).host}: ${e.code ?? ""} ${e.message}`.trim())))
    if (body) req.write(body)
    req.end()
  })
}

async function wgRegister() {
  const { publicKey, privateKey } = generateKeyPairSync("x25519")
  const pub = publicKey.export({ format: "der", type: "spki" }).subarray(-32).toString("base64")
  const priv = privateKey.export({ format: "der", type: "pkcs8" }).subarray(-32).toString("base64")
  const r = await httpsFetch("https://api.cloudflareclient.com/v0a2158/reg", {
    method: "POST",
    headers: { "Content-Type": "application/json", "User-Agent": "okhttp/3.12.1", "CF-Client-Version": "a-6.3-2158" },
    body: JSON.stringify({ key: pub, install_id: "", fcm_token: "", tos: new Date().toISOString(), type: "Android", model: "PC", locale: "en_US" }),
    timeout: 20000,
  })
  if (!r.ok) throw new Error(`WARP registration refused (HTTP ${r.status}); try again in a few minutes`)
  const j = JSON.parse(r.buf.toString("utf8"))
  const peer = j.config?.peers?.[0]
  if (!peer?.public_key) throw new Error("WARP registration returned no peer")
  const host = String(peer.endpoint?.host ?? "engage.cloudflareclient.com:2408")
  const acc = { priv, peerKey: peer.public_key, endpoint: host.includes(":") ? host : `${host}:2408`, v4: j.config.interface.addresses.v4, v6: j.config.interface.addresses.v6 }
  writeFileSync(wgAccountFile, JSON.stringify(acc, null, 2))
  return acc
}

function wgStop() { try { wg?.stop() } catch {} wg = null }
app.on("will-quit", wgStop)

const wgFromAccount = (acc) => ({ priv: acc.priv, peerKey: acc.peerKey, endpoint: acc.endpoint, v4: acc.v4, v6: acc.v6 })
async function wgStart(opts) {
  wgStop()
  const w = new UserWireGuard(opts)
  await w.start()
  wg = w
}

// Brings the tunnel up and returns a message with the IP. "wg" = a free Cloudflare WARP account (saved, or a new one);
// "wgfile" = the WireGuard .conf the user picked (Route64, Proton, Mullvad, their own server...).
const wgFile = path.join(wgDir, "custom.json")
async function wgUp(fresh) {
  if (cfg.mode === "wgfile") {
    if (!existsSync(wgFile)) throw new Error("No WireGuard file chosen yet. Tray > Connection > Choose WireGuard file.")
    await wgStart(JSON.parse(readFileSync(wgFile, "utf8")))
    await sleep(1500)
    const ip = await traceVia(upstream()).catch(() => undefined)
    if (!ip) throw new Error("the tunnel of that WireGuard file did not answer")
    return `WireGuard file on. IP ${ip}`
  }
  let acc
  if (!fresh && existsSync(wgAccountFile)) { try { acc = JSON.parse(readFileSync(wgAccountFile, "utf8")) } catch {} }
  await wgStart(wgFromAccount(acc ?? (await wgRegister())))
  await sleep(1500)
  let ip = await traceVia(upstream()).catch(() => undefined)
  if (!ip && acc) {      // the saved account stopped working: register a new one
    log("saved WARP account did not answer, registering a new one")
    await wgStart(wgFromAccount(await wgRegister()))
    await sleep(1500)
    ip = await traceVia(upstream()).catch(() => undefined)
  }
  if (!ip) throw new Error("the WARP tunnel did not answer (is UDP 2408 blocked?)")
  return `Built-in WARP on. IP ${ip}`
}

// ---------------------------------------------------------------- free public proxies
// Public lists of open proxies. They are tested one by one through Cloudflare's trace page and the first one that answers is
// used. They are untrusted: HTTPS stays end-to-end encrypted, but the proxy sees where you connect. Many die within minutes.
const FREE_SOURCES = [
  ["socks5", "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt"],
  ["socks5", "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/socks5/data.txt"],
  ["http", "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt"],
  ["http", "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/http/data.txt"],
]
let freePool = [], freeUsed = new Set()
async function freeFetch() {
  const all = new Set()
  await Promise.all(FREE_SOURCES.map(async ([scheme, url]) => {
    try {
      const r = await httpsFetch(url, { timeout: 20000 })
      if (!r.ok) return
      for (const line of r.buf.toString("utf8").split(/\r?\n/)) {
        const m = /^(?:\w+:\/\/)?(\d{1,3}(?:\.\d{1,3}){3}:\d{2,5})\s*$/.exec(line.trim())
        if (m) all.add(`${scheme}://${m[1]}`)
      }
    } catch (e) { log("free list failed: " + why(e)) }
  }))
  freePool = [...all].sort(() => Math.random() - 0.5)
  return freePool.length
}
// First working proxy (different exit IP from the ones already used). 40 at a time, at most 90 seconds.
async function freeFind() {
  if (freePool.length < 20 && (await freeFetch()) === 0) throw new Error("could not download any public proxy list")
  const deadline = Date.now() + 90000
  let next = 0, found
  const worker = async () => {
    while (!found && Date.now() < deadline) {
      const cand = freePool[next++]
      if (!cand) return
      const ip = await traceVia(parseUp(cand)).catch(() => undefined)
      if (ip && !freeUsed.has(ip) && !found) found = { proxy: cand, ip }
    }
  }
  await Promise.all(Array.from({ length: 40 }, worker))
  freePool = freePool.slice(next)
  if (!found) throw new Error("no public proxy answered in time (try again)")
  freeUsed.add(found.ip)
  freeCurrent = found.proxy
  return found
}

const listEntries = () => cfg.list.map((x) => String(x).trim()).filter((x) => x && !x.startsWith("#") && parseUp(x))

async function newIp() {
  cfg = loadCfg()
  if (cfg.mode === "free") { const f = await freeFind(); return `New IP ${f.ip} (public proxy ${parseUp(f.proxy).host})` }
  if (cfg.mode === "wgfile") return `A WireGuard file has a fixed exit IP. ${await wgUp(false)}. Choose another file or another Connection to change it.`
  if (cfg.mode === "wg") {
    const old = wg?.session ? await traceVia(upstream()).catch(() => undefined) : undefined
    let last
    for (let i = 0; i < 3; i++) {
      if (i) await sleep(4000 * i)
      try { await wgStart(wgFromAccount(await wgRegister())); await sleep(1500); last = await traceVia(upstream()).catch(() => undefined) } catch (e) { if (i === 2) throw e; continue }
      if (last && last !== old) return `New IP ${last} (built-in WARP)`
    }
    return last ? `New WARP account, but the IP is still ${last} (WARP uses the nearest Cloudflare server)` : "The WARP tunnel did not answer"
  }
  if (cfg.mode === "list") {
    const all = listEntries()
    if (!all.length) return "Your proxy list is empty. Tray > Edit proxy list."
    const start = Math.max(0, all.indexOf(cfg.current) + 1)
    const old = cfg.current ? await traceVia(parseUp(cfg.current)).catch(() => undefined) : undefined
    for (let k = 0; k < all.length; k++) {
      const cand = all[(start + k) % all.length]
      const ip = await traceVia(parseUp(cand)).catch(() => undefined)
      if (ip && ip !== old) { cfg.current = cand; saveCfg(cfg); return `New IP ${ip} (proxy ${parseUp(cand).host})` }
    }
    return "No proxy of the list gave a different IP."
  }
  return "Direct mode has no IP to change. Pick another Connection."
}

const status = async () => {
  const ip = await traceVia(upstream()).catch(() => undefined)
  return ip ? `IP ${ip} (${{ none: "direct", wg: "built-in WARP", wgfile: "WireGuard file", free: "public proxy", list: "proxy list" }[cfg.mode]})` : "No connection through the current setting."
}

// Asks for a WireGuard .conf, checks it and keeps it for the "WireGuard file" connection.
const chooseWgFile = async () => {
  const r = await dialog.showOpenDialog({ title: "Choose a WireGuard .conf file", filters: [{ name: "WireGuard", extensions: ["conf"] }], properties: ["openFile"] })
  if (r.canceled || !r.filePaths[0]) return false
  const c = parseWgConf(readFileSync(r.filePaths[0], "utf8"))
  writeFileSync(wgFile, JSON.stringify({ priv: c.priv, peerKey: c.peerKey, psk: c.psk, endpoint: c.endpoint, v4: c.v4, v6: c.v6, dns: c.dns, mtu: c.mtu }, null, 2))
  return true
}
const useMode = (mode, pick = false) => guard(async () => {
  cfg = loadCfg(); const before = cfg.mode
  const fallback = (e) => { cfg.mode = "none"; saveCfg(cfg); wgStop(); return new Error(why(e) + " (back to direct)") }
  try {
    if (mode === "wgfile" && (pick || !existsSync(wgFile)) && !(await chooseWgFile())) { cfg.mode = before; saveCfg(cfg); return "Nothing chosen. Connection unchanged." }
    cfg.mode = mode; saveCfg(cfg)
    if (mode !== "wg" && mode !== "wgfile") wgStop()
    if (mode === "wg" || mode === "wgfile") return await wgUp(false)
    if (mode === "free") { const f = await freeFind(); return `Public proxy ${parseUp(f.proxy).host} on. IP ${f.ip}` }
  } catch (e) { throw fallback(e) }
  return mode === "list" ? "Own proxy list on. Use New IP to pick a proxy." : "Direct: OpenCode uses your normal connection."
})

const toggleAuto = () => { cfg = loadCfg(); cfg.autoRotate = !cfg.autoRotate; saveCfg(cfg); note(cfg.autoRotate ? "Auto-rotate on." : "Auto-rotate off.") }
// OpenCode's background service ("serve --service") keeps running after the app closes.
const killService = () => {
  try {
    execFileSync("powershell", ["-NoProfile", "-Command", `Get-CimInstance Win32_Process -Filter "Name='opencode-cli.exe'" | Where-Object { $_.CommandLine -match 'serve --service' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }`], { windowsHide: true, timeout: 15000 })
  } catch {}
}
const restart = () => { wgStop(); app.relaunch(); app.exit(0) }
const quit = () => { wgStop(); killService(); app.exit(0) }
const later = (what) => { writeFileSync(pendingFile, JSON.stringify(what)); wgStop(); killService(); app.relaunch(); app.exit(0) }
const clearLogin = () => {
  if (!existsSync(path.join(dataDir, "auth.json"))) return say("There is no saved login (auth.json) on this PC. Nothing to clear.")
  later(["tokens"])
}
const restoreLogin = () => {
  if (existsSync(path.join(dataDir, "auth.json"))) return say("A login already exists, so nothing was restored.")
  if (!newestBackup()) return say("There is no login backup to restore.")
  later(["restore"])
}
const clearCache = () => later(["cache"])

// ---------------------------------------------------------------- auto-rotate
// The app (patched by the installer) reports each free-limit error to the page; the page logs "__OC_LIMIT__<session>".
let lastRotation = 0, streak = 0, streakAt = 0, warnedAt = 0
async function resume(wc) {
  // The app puts the stopped message back in the prompt box; if it is empty, send "continue". Then Enter.
  const state = await wc.executeJavaScript(`(() => {
    const el = document.querySelector('[data-component=composer-editor] [contenteditable], [data-component=composer-editor][contenteditable], [contenteditable="true"]')
    if (!el) return "none"
    el.focus()
    return el.innerText.trim() ? "text" : "empty"
  })()`).catch(() => "none")
  if (state === "none") return
  wc.focus()
  if (state === "empty") wc.insertText("continue")
  await sleep(200)
  wc.sendInputEvent({ type: "keyDown", keyCode: "Enter" })
  wc.sendInputEvent({ type: "keyUp", keyCode: "Enter" })
}
async function onLimit(wc) {
  cfg = loadCfg()
  const now = Date.now()
  if (!cfg.autoRotate || busy || now - lastRotation < 15000) return
  if (cfg.mode === "none") {
    if (now - warnedAt > 600000) { warnedAt = now; note("Free limit reached. Auto-rotate needs Connection > Built-in WARP or Own proxy list.") }
    return
  }
  if (now - streakAt > 180000) streak = 0
  if (streak >= 10) return                       // 10 in a row without a free message: stop, try again in 3 minutes
  streak++; streakAt = now; lastRotation = now
  busy = true
  try {
    note("Free limit reached: changing the IP...")
    await sleep(600)
    const msg = await newIp()
    note(msg)
    if (msg.startsWith("New IP")) { await sleep(800); await resume(wc) }
  } catch (e) { note(why(e)) } finally { busy = false; lastRotation = Date.now() }
}

if (cfg.mode === "wg" || cfg.mode === "wgfile" || cfg.mode === "free") {
  setTimeout(() => (cfg.mode === "free" ? freeFind().then((f) => log(`Public proxy ${f.proxy}, IP ${f.ip}`)) : wgUp(false).then(log)).catch((e) => {
    log(`${cfg.mode}: ${why(e)} (back to direct)`); wgStop(); cfg.mode = "none"; saveCfg(cfg)
  }), 0)
}

// ---------------------------------------------------------------- tray menu
const LOGO = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AAAQAElEQVR4nOxdCXQc5X3/fTN7H9rVZd3SSrbk2MayZRsbY8fgOoBDgwMB07RpQ9ykhVASaOgr9LV9TdP2kb40pU7zkhRzhGcKSYxdkwchdcGYYGFj5BMb8C3JOr1aaQ/tvbNfv9lzdqWVVsfOCrw/v/G3s7Mzu/O/v////40UmAHUxsaFPEc3gtAlbNdCQBrYKG5F+HTCybYuCnQCtAuUnBHC5C2/6/JZTBMEU4TGbLmZB/06+xEbGcFrUAAoaC8j5FsCyDM+e+eBqZybNQPUxpoWnlf+gJ2wBQVkBBPMVwQh+Nd+V++5bD4/OQMMleU6Xv2P7NWfEUIUKGBSUEpDbNjhEfz/gNEB60SfnZgBxppSHa/Yy0zNehQwHbzttjuZxRh2ZvpARgZoTA2NHPAGk/omFDAD0DMCpVt8ju5L4x3lxntTa6xfxwNHCsSfDZAlPLjDOlP9yvGOjsOAMiPHcc+CkDIUMDsgKGf/7QBKxoTn6QwgOpNhFzuhBQXMKpg1adOZjL9AmtnnpTs6k+UBQvAwCsgJGBOalWrzQNBv70i8lzxcbtCb9Jei6lJAzkBhdTtG5wNDLnE3YYK0Jv3fFYgvAxiNtSbD3yZ3GVSGhkUKnhxn5keNAnIOSuEP+wMtPl9fd0QDeJ7cVyC+fBBpTdSqB8XXXOy/O1GArIjTnKiMls8oeXyEAmRHUMAihZIrSH++INJezG4uRwH5wnIFi4Mq8QmCpmkRtAuXQregFep5NeC1Rig0evBqHZR6E0gYCDtGILhHQT2jCNpt8Hafhaf3Ajw95yPjnAGjPdGZLZ0kWkackyAqFfQr1sG4dhMMqzZAoStiRKbgKIkQm7AKiDhyaWPyfcnn2Ea9bgwd/T8MHn4V9gsdkZgwb6A4y3I/Ft9cDEGJSg3zlj9E8Ze+BqXBxMQ6Tswo8ZFgQpIZnDitEWhkTHwusR9lDiRMCowM4spbL6C3fReEgBd5gIPozZY8isD4MN6yBWXbHoHCWJwqyUxaSVhCdIm0TyT53DiaEtcIjl1P8LjQdWAnun63EyG/G3JiTjGANxWj/NHvMVPDCnBCdJJChJhkp0k8pJJPMxwXJT+uAbHrTaRJAYcVH+59AgOn34RcmDMMULcsQeU//ZhJvXkCW840gJIMkhx/nWaWxlwnvp9Bk9hoPduO4798HAGvA7kGhzkAzXUrUPWvOyLER4wQkRGpEk7itl08icaO09jxMcSnMZtPk8SPaFL8PJrQrAQTafS6Fc3rsOGBF6EzVyPXyLsGaFfdiIq//yF4pSZrmx6XZMHlhPfSGQSHBhCwDSI4PIjA8AAIr4RSDE9jm6mpDWWL1qX5hMk1JDBqQ/vz98MxOO2+q0mRVwYoKmtQ89RuRnx1Wig5vk2Hx4PRMx1wf9gB1+n3WHyfVetN9Lu0BpQv3YiqlV9AWcvahG/AJD7C57TijZ/dDb9nBLlA/hjAYt/q7TuhaV4yVgIjrwl7HY16qMcN656nYX11J6gQwkxRVLcELZsfQjkzNdn4iDMHfowP3/kv5AJ5a7TSf/YWaJjjFSUwYcshsfU06nBH3tyLwZd+hJBjGLMF55Uz6NjxTZjrW7F86z/DWGqR+Aia6iPYWFSau+aQvDlh85e/HlV3JG07Yg42Lnl9T/0Len/23VklvhT27lNo/8mfwH7ldLQyJfl+QknCHA33nEKukBcG6NZsgNrSnJiZEulMNhalDO39OYb37UKuEWShZvuObbh69mDM1yAl2hq1dePC8V8hV8gLAwwbb49KGI1NtkRzIx6ITZ6cB/dh4IX/gFwIh/w4tPNBnH/3+aRGsn/ukV4c3P0wwkIQuUJenLDlpf2RNEOmaOfjbTdDGM39JGg8lNQsRXndCvhYCNp3/gCC/lHkErI7YVVdYyLHIzq4aNQTdXzivvvEobwRX8Rw7weRTS7IboI0S9oi5ibTDNZx8HVcS5BdA3iDKTXqkeR4RAfoOLIf1xJkZwDh+KgGjBN3IxhE2JvbdLBYZ+DrG8CZiyMbMRaB0+mYamrAqTWg7DdQvw/U52MTBheEwX62DUC42g8amvkkMB15YUA81EukjONZTl4F1bxaBK72IBfgq2uhuZVFYHp99PuRjD8SuSaiBseYxCmZpuorwFUsiAoL+43+nk54WO7J23sRNCxgNsCrNObvQkYoyyphWrMpQnyepjJBHMXaruPYAeQC6utvYEyoiXwvx2bgCoFAwYRaGWJjgI3B2JbYZ2Nin0CrLUZR5UKUNq0Er9DA5xiYMSNk1wD3sXej0U8s6pHG3aJmlN90ZyTZZmt/FbMNPkCh9ZKU7CoX5lLrB2GkHSeJ7GniWFgFXfX1qCpfhqtdHRjseX/acwXZNUC0r6brN0JpKh1b2YoxoWTVJhaKOuG+NLvhIB0ZQVHNIqioMirZjCGC9SrC1kGEBnrg7+0EdTjAewOR4xqqjowqpgFxzVAGYiPbVwsKlOjqUG5uhtX2EbuVqWtDXiZipvWbUf/w96OSn5b/l2YjR88eQ+d/PwH3lezTzpNB9EGa4iqEg374XUMTdkUQwkGlLoJeV47amrUwaiuSvzOc+nsvDryDy0OHMVXIrgEi/N0XoG9uhaaiLlmJkqp9zCdoS6tR+dmtKP7MGgg+Dzz9lzBjMIKHvE4Ifk82H4YQ8sHrHcbg1ZMYdfTAQEwoImbwTAMUYZKoWXfZOuAJTL1mkLd6gLKkAouefCXizKQ13Ylqv0G7FQMH96Dv4C74HVbkC8W6WjSVrUWpoTESS3mDDrx78TmEwgFMFXmtiBkWtmH+oz+KlA8n7G5I7/th79nPM+d3fB+untyHgNuOfECvKoFaoYcnaIcv6MJ0kPeasLqyHgv/6qfQlNUm+36opPMtpUqWXrGK7g+few/9J15HH9vy1GA1bcyJthSF3oTmh/4dpoWrMvb9ZOr3kXa+0WAAg6ffRPfRvbBeOIRPAuZUY1b5jXfAcs93oNKXJKRe2tU2mY+Q7rutl3Hx0IvoOrGXOVI/5irmXGsip9Kgct1dqP3cfdAVV0/gEyQaMEFvaMg7istHd+HcezvhHc2f486EvDGAKBRQ1loi2dFA10UIrrGOtHz551B381dgblyR0hua4hMk3XGZfERcQzpP/Rqnfvef8LgGMFcgOwN4oxn6RSugb1wMBa+O2HLq9aD3t88jnMGBGmsWov7mr6Jm5R0gYzQiex8Rn298cPAnOHXop5gLmBED+HmViNyjjc0oJ0nVaqosKFrQBn1lU0JyOcmMsu/Ya3D0fzzhNZQ6E+pWfwn1N9wLvblmAh8xnkak7tv6T2P/K9+C1zOEfGJ6DCAERVu+DFV5VVTS2A0JwzZQlzOyMgUs36PQGKDUGKFUG6HSspw75SNZSCKx2bxIGCFKtO6z/wtrf/btH5WLfw91bXegonk90yRNhnkDol3W0t5QiY8IeBx46zffQX/PkUnvV1woItYSxNeRekEgMCuLO6bFAK2FpWTXfSFpg9lN8mk5Ej5M0vYzHacY6D+Oi93TawnnVVpUttyEhmV3oGrBhgl8QmYf8dqer6G/ryPlugpLE/jKKpaJY2ZSpQRiT3WQahx8LLryeRGyWVkNo5eZUB+mimkxwNiwBJXLN0clTaCpkh1nhpC0zXx8UUWYJIgfYvZ+wPYBeoaOTnsWmQ6NoQxNbXdjQdtW6PQVaTmmDD6CHQ/5nNj9q61wuXoj1+H0BmhWrx/rS9Ice/x68bpGwGmDZ/gKvM5BphzhrH7ztBigZCalcdmd7CbnSWx5kshS255+3O2zscTV++h3iOnb2S/xiRAznk2td2HpjQ/AwBgx3rqBdI1w2rvw8u6trCrqYedzMLUy06bSJ46LPi7MpB3hMJRKHRScKoOGkcgqm66+dyFkkRuathMWU7UlxQtgMtbBrK+FUV3Ovjxa3BClxucbYUkqO1w+K8sS2uEO2CLZwkAomyzk7KFl2b1YvPKrMJkaJvURx0/swOH3tyfuT6UzR5q2RG1Nl2hCeKgYIzTKIpi0VTCoysCz96gYKjM/cXbwALvXyevbc3KNWC6wbM39aFvzF8xccBnnDQGvHc+9tBGCMPWsJseIb1CXwcwypUI4iF57dgFFXuoB+cBg71HYbRfRtOC2lOKP1EeoeC3sjk4MjUy9AMRmM/AziXd4+5nWD2Z93pxYoiQXOi/sw/vtP0xoQGpvarRG3VAj7xM6rykGiDh1/DmMOvuSnXnhVAddpMv9ujAprjkGiBAnXuP3pgJmg7yPw74mGeD3OzP0prK5hNIEOXFNPgu6tLglrTcVid5Unzc3q3Ey4ZrUgIqyJUjtTY0l8tjo9shbM5CdAca6Rcgn9Lp5UCuNiU68xBgLST1eeRkgmwmqu2Ubmj7/AHiWuQy5hnFuzw8wcOw3kBsrl30jZUac7E2NSmOf9STkhCwaUH/bN7BgyyORHiDxZtWs5tv6x9/H6m8+C325BXKhuenzaF38leSSWApJbyoiGvBRt7xCkXMGqIylaNx8vyTupomoo3T+Kqz/y5ex8NaHwClUyB0I2lq34ZabnogV9IHksySSaYlBlp11eeQtV+bcBJUsvhEcr4qtiqTJ2m7M9irYseaNf46GlXej89CL6DyyixVKZq/RSqstwW2bnkRtxapkHj8e9UhmxKIGHPrwKciNnDMg5HFF1TxGfFCaMvOME0OjL8XiTd/G4o3fQvfR3eg8umdGi+XmzVuK6qrrsaL1T6FTFyc1L9EanyzciL/jUu8BnO/dD7khSzb0hsdehrGyBZmez5OanUz2/QjeUdi6j8Pa1QFb3ykEfS4E2Bb0s5FtYj1CZ5gHvTiyrchYg8qK5Wxrw7jPBcpQKx51D+L5fffA45d3DiBCFgaoDCVY9eAzKKqYn92TrqbQ94PweJUqJB+DIGSuhInvi62ML7zxR7jqyN0jaSaCLOlo8SZ7D+9hxY0gShqWMwIokp1vUkmlEg2BpFU9ZqPjoWJSU5BKfKlZka49S1uJI2XW3vZHcGWoA/mC7AUZbXE1lt3zPZRbVmfxLDhkUdPNXKudqMvaz+rArx16DBf730Y+ITJADDnkzUAxVF93K1p//3Fo9eVJSc3aR0zS9UBjNehEt3XqdQbYZOvX7Y/C6elHnuEgepPlYyYQC5EHiLF/7XWb0bTyXpTVtI6jAZNJMpJPV4x/Ps1HSKOt0dF+vHPiSXzUJU62ZFX88SE+uJVpwAH28ibkGaZ5CzC/7V40Lv0iVAodUp6GmPARmXtBJ3rGXFfvQZzrfB2nL+3FHMPbogb8ggnMH2AOobTqOpRVL0N5FdsqW1FUVJudj4hFSVbrafQPHsPA1ZOR9hD/LPUdzToofiky4HH2u5/AHIfRVMtmtaUs3i+HTlsGraY49ogDgnA4CPvIJVZQ74Jt5Dw+MaD4m8IfcMgjxD/gwAVcnR+LzgAFyAtGc5H20WwowW9RgKwQ54DiGI3kKN1OKZ2dx38UMClEWlNCZxORpQAAAWpJREFUIitEIgzwObouMzV4GgXIBPK0z365K/Iq/pZe31hBFbSTsMwwCsgZ2OTc5xF89fG/tJ2oiLndlwcZ8XPzfN4CEmBTl+3SP3Oe9he1LRqdie4nhKxFAbMOJv1HPA7FBuBCYuEyGfMpY02pnlMeYkeaUcCsgTneix4qrIazJ6XqM7Yo7+q1hWjodnZGfpcPfppAqS0Mems68UWM2xXhd/ZcEAi3inHtOAqYEZjNPyn4gyt8ju5L4x0nE59eq9WZFS+xD30RBUwZFPRVj51sBTozLp+chAHRz7CU9X1Mjf4NhJSigMnBTA6T/Mc8jq5nMUnhgUcWCPrsJ4IqwzNKwokMaCPiKrQCxoDSyMrtn3vCoS1B55X2bM6ZMiE1xvr1PMd9mxJ6O0sG61GAaGrc7L/Xw2G63efqPjiVc2ckyTqzRfQNd7EvX0SidWUzu2IFPs2gEFfgOZios1o6/YDt/4/H2fUapon/BwAA//90xWZgAAAABklEQVQDACt6WQj9lcD4AAAAAElFTkSuQmCC"
let tray
app.whenReady().then(async () => {
  try {
    tray = new Tray(nativeImage.createFromDataURL(LOGO).resize({ width: 32, height: 32 }))
    tray.setToolTip("Slipstream")
    if (afterStart) note(afterStart)
    tray.setContextMenu(Menu.buildFromTemplate([
      { label: "New IP", click: guard(newIp) },
      { label: "Connection", submenu: [
        { label: "Direct", type: "radio", checked: cfg.mode === "none", click: useMode("none") },
        { label: "Built-in WARP", type: "radio", checked: cfg.mode === "wg", click: useMode("wg") },
        { label: "WireGuard file", type: "radio", checked: cfg.mode === "wgfile", click: useMode("wgfile") },
        { label: "Free public proxies (untrusted)", type: "radio", checked: cfg.mode === "free", click: useMode("free") },
        { label: "Own proxy list", type: "radio", checked: cfg.mode === "list", click: useMode("list") },
        { type: "separator" },
        { label: "Choose WireGuard file...", click: useMode("wgfile", true) },
      ] },
      { label: "Edit proxy list", click: () => shell.openPath(proxyFile) },
      { label: "Auto-rotate", type: "checkbox", checked: !!cfg.autoRotate, click: toggleAuto },
      { type: "separator" },
      { label: "Clear", submenu: [
        { label: "Login (keeps chats)", click: clearLogin },
        { label: "Restore login", click: restoreLogin },
        { label: "Cache and logs", click: clearCache },
      ] },
      { label: "Status", click: guard(status) },
      { type: "separator" },
      { label: "Restart OpenCode", click: restart },
      { label: "Quit", click: quit },
    ]))
  } catch (e) { log("tray failed: " + why(e)) }
})

// ---------------------------------------------------------------- remove the "subscribe to Go" popup and texts
// (the persistent "Free limit reached" tray is stopped in the app code itself by the patcher)
const stripUpsell = () => {
  window.__ocLimit = (id) => console.log("__OC_LIMIT__" + id)
  if (window.__slipstreamStrip) return
  window.__slipstreamStrip = true
  const upsell = /(subscribe to (opencode )?go|connect a provider or subscribe|\$\s?10\s?\/\s?(month|mo)|assinar o plano go|plano go|conectar um provedor ou assinar|us\$\s?10)/i
  const resetLine = /(resets? at|ser[aá] redefinid[oa]s? [aà]s|redefinid[oa]s? [aà]s)\s*\d/i
  const box = 'dialog,[role="dialog"],[role="alertdialog"],[data-component*="dialog"]'
  const hide = (el) => { if (el && el.style) el.style.setProperty("display", "none", "important") }
  const sweep = () => {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
    const hits = []
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      const t = n.nodeValue
      if (t && t.length < 600 && (upsell.test(t) || resetLine.test(t))) hits.push(n.parentElement)
    }
    for (const el of hits) {
      if (!el || el.dataset.ocHidden) continue
      el.dataset.ocHidden = "1"
      const dlg = el.closest(box)
      if (dlg) {
        document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", code: "Escape", keyCode: 27, bubbles: true }))
        hide(dlg)
        const prev = dlg.previousElementSibling
        if (prev && /overlay|backdrop/i.test(prev.getAttribute("data-component") || prev.className || "")) hide(prev)
      } else hide(el)
    }
  }
  let timer
  new MutationObserver(() => { clearTimeout(timer); timer = setTimeout(sweep, 80) }).observe(document.body, { childList: true, subtree: true, characterData: true })
  sweep()
}
app.on("web-contents-created", (_e, wc) => {
  wc.on("dom-ready", () => { wc.executeJavaScript("(" + stripUpsell.toString() + ")()").catch(() => {}) })
  wc.on("console-message", (...a) => {
    const msg = typeof a[0]?.message === "string" ? a[0].message : a[2]
    if (typeof msg === "string" && msg.startsWith("__OC_LIMIT__")) onLimit(wc)
  })
})

// ---------------------------------------------------------------- hand over to the original app
await import("./index.js")
'@

# ---------------------------------------------------------------- find the install
$dir = Find-Install
if ($download -and -not $dir) { Get-Original $version; $dir = Find-Install }
if (-not $dir) {
  Fail 'OpenCode desktop was not found.'
  Say '  Script is stopped' Red
  Say '    Use -download to install the original from GitHub, or -path <folder with OpenCode.exe>.' DarkGray
  return
}
$res     = Join-Path $dir 'resources'
$asar    = Join-Path $res 'app.asar'
$asarBak = "$asar.slipstream.bak"          # the untouched original; if it exists, OpenCode is patched
$upd     = Join-Path $res 'app-update.yml'
$updBak  = "$upd.slipstream.bak"
if (-not (Test-Path $asar)) { Fail "app.asar not found in $res"; return }

$ver = (Get-Item (Join-Path $dir $exeName)).VersionInfo.ProductVersion
Step "OpenCode $ver in $dir"

if ($status) {
  Say "  patched      : $(Test-Path $asarBak)"
  Say "  update block : $(Test-Path $updBak)"
  return
}

if ($uninstall) {
  Stop-OpenCode
  if (Test-Path $asarBak) { Move-Item $asarBak $asar -Force; Ok 'original app.asar restored' } else { Warn 'it was not patched' }
  if (Test-Path $updBak) { Move-Item $updBak $upd -Force; Ok 'auto-update restored' }
  Ok 'OpenCode is back to the original.'
  if ($start) { Start-Process (Join-Path $dir $exeName) }
  return
}

if ($block_update_off) {
  if (Test-Path $updBak) { Move-Item $updBak $upd -Force; Ok 'auto-update restored' } else { Warn 'auto-update was not blocked' }
  return
}

# ---------------------------------------------------------------- asar helpers
# asar = [u32 4][u32 headerPickleSize][u32 payloadSize][u32 jsonLen][json][pad to 4] + file data (offsets are relative to that data)
function Read-AsarHeader([string]$file) {
  $fs = [IO.File]::OpenRead($file)
  try {
    $br = New-Object IO.BinaryReader($fs)
    [void]$br.ReadUInt32()
    $pickle = $br.ReadUInt32()
    [void]$br.ReadUInt32()
    $jsonLen = $br.ReadUInt32()
    [pscustomobject]@{ Json = [Text.Encoding]::UTF8.GetString($br.ReadBytes([int]$jsonLen)); Base = [int64](8 + $pickle); Length = $fs.Length }
  } finally { $fs.Dispose() }
}

function Read-AsarFile([string]$file, [string]$inner) {
  $h = Read-AsarHeader $file
  $node = $h.Json | ConvertFrom-Json
  foreach ($part in $inner.Split('/')) { $node = $node.files.$part }
  $fs = [IO.File]::OpenRead($file)
  try {
    $fs.Position = $h.Base + [int64]$node.offset
    $buf = New-Object byte[] ([int]$node.size)
    $n = 0; while ($n -lt $buf.Length) { $r = $fs.Read($buf, $n, $buf.Length - $n); if ($r -le 0) { break }; $n += $r }
    [Text.Encoding]::UTF8.GetString($buf)
  } finally { $fs.Dispose() }
}

# The "Free limit reached" tray takes the place of the prompt box and stays until a stored time, because the app saves it on every
# free-limit error and nothing clears it. This stops that save, and reports the error to the tool (auto-rotate).
function Get-AsarPatches([string]$source) {
  $h = Read-AsarHeader $source
  $assets = ($h.Json | ConvertFrom-Json).files.out.files.renderer.files.assets.files
  $utf8 = New-Object Text.UTF8Encoding($false)
  $found = @{}
  $fs = [IO.File]::OpenRead($source)
  try {
    foreach ($p in $assets.PSObject.Properties) {
      if ($p.Name -notlike '*.js' -or $p.Value.size -lt 3000 -or $p.Value.unpacked) { continue }
      $fs.Position = $h.Base + [int64]$p.Value.offset
      $buf = New-Object byte[] ([int]$p.Value.size)
      $n = 0; while ($n -lt $buf.Length) { $r = $fs.Read($buf, $n, $buf.Length - $n); if ($r -le 0) { break }; $n += $r }
      $text = $utf8.GetString($buf)
      if (-not ($text.Contains('provider.free-limit') -and $text.Contains('resetAt'))) { continue }
      $new = [regex]::Replace($text, '([A-Za-z_$][\w$]*)\.data\.error\.type===`provider\.free-limit`&&([A-Za-z_$][\w$]*\(`resetAt`)', '$1.data.error.type===`provider.free-limit`&&(window.__ocLimit&&window.__ocLimit($1.data.sessionID),0)&&$2')
      if ($new -ne $text) { $found["out/renderer/assets/$($p.Name)"] = $utf8.GetBytes($new) }
    }
  } finally { $fs.Dispose() }
  $found
}

# New asar = the original data untouched + the changed files appended at the end, with a new header.
function Write-PatchedAsar([string]$source, [string]$dest, [string]$newPackageJson, [string]$bootJs, [hashtable]$extra) {
  $h = Read-AsarHeader $source
  $tree = $h.Json | ConvertFrom-Json
  $dataLen = $h.Length - $h.Base
  $utf8 = New-Object Text.UTF8Encoding($false)
  $pkgBytes  = $utf8.GetBytes($newPackageJson)
  $bootBytes = $utf8.GetBytes($bootJs)

  $tree.files.PSObject.Properties.Remove('package.json')
  $tree.files | Add-Member -NotePropertyName 'package.json' -NotePropertyValue ([ordered]@{ size = $pkgBytes.Length; offset = "$dataLen" })
  $mainFiles = $tree.files.out.files.main.files
  $mainFiles.PSObject.Properties.Remove('slipstream-boot.js')
  $mainFiles | Add-Member -NotePropertyName 'slipstream-boot.js' -NotePropertyValue ([ordered]@{ size = $bootBytes.Length; offset = "$($dataLen + $pkgBytes.Length)" })

  $next = $dataLen + $pkgBytes.Length + $bootBytes.Length
  $order = @($extra.Keys)
  foreach ($key in $order) {
    $node = $tree
    foreach ($part in $key.Split('/')) { $node = $node.files.$part }
    $node.size = $extra[$key].Length
    $node.offset = "$next"
    $node.PSObject.Properties.Remove('integrity')
    $next += $extra[$key].Length
  }

  $json = $utf8.GetBytes(($tree | ConvertTo-Json -Depth 100 -Compress))
  $pad = (4 - ($json.Length % 4)) % 4
  $payload = 4 + $json.Length + $pad
  $out = [IO.File]::Create($dest)
  $in = [IO.File]::OpenRead($source)
  try {
    $bw = New-Object IO.BinaryWriter($out)
    $bw.Write([uint32]4); $bw.Write([uint32]($payload + 4)); $bw.Write([uint32]$payload); $bw.Write([uint32]$json.Length)
    $bw.Write($json); if ($pad) { $bw.Write((New-Object byte[] $pad)) }
    $bw.Flush()
    $in.Position = $h.Base
    $buf = New-Object byte[] (4MB); $left = $dataLen
    while ($left -gt 0) { $n = $in.Read($buf, 0, [int][Math]::Min($buf.Length, $left)); if ($n -le 0) { throw 'short read' }; $out.Write($buf, 0, $n); $left -= $n }
    $out.Write($pkgBytes, 0, $pkgBytes.Length)
    $out.Write($bootBytes, 0, $bootBytes.Length)
    foreach ($key in $order) { $out.Write($extra[$key], 0, $extra[$key].Length) }
  } finally { $in.Dispose(); $out.Dispose() }
}

# ---------------------------------------------------------------- install
Stop-OpenCode

if (-not (Test-Path $asarBak)) {
  Step 'saving the original app.asar...'
  Copy-Item $asar $asarBak
}
$pkgText = Read-AsarFile $asarBak 'package.json'
$newPkg = [regex]::Replace($pkgText, '"main"\s*:\s*"[^"]*"', '"main": "./out/main/slipstream-boot.js"')
if ($newPkg -eq $pkgText) { Fail 'could not find "main" in package.json'; return }

Step 'Patching OpenCode...'
$tmp = "$asar.new"
try {
  $extra = Get-AsarPatches $asarBak
  if ($extra.Count) { Ok 'free-limit tray stopped in the app code' } else { Warn 'free-limit code not found in this version; the tray menu is installed without that part' }
  Write-PatchedAsar $asarBak $tmp $newPkg $BootJs $extra
  # check before replacing: the new asar must read back the new entry
  if ((Read-AsarFile $tmp 'package.json') -notmatch 'slipstream-boot\.js') { throw 'verification failed: package.json' }
  if ((Read-AsarFile $tmp 'out/main/slipstream-boot.js') -notmatch 'Slipstream') { throw 'verification failed: boot file' }
  Move-Item $tmp $asar -Force
} catch {
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  Fail "patch failed: $($_.Exception.Message) - the original was left as it was"
  return
}
Ok 'tray menu installed'

# OpenCode's updater would replace the patched app, so it is pointed at nothing (-block_update_off undoes this)
if ((Test-Path $upd) -and -not (Test-Path $updBak)) {
  Copy-Item $upd $updBak -Force
  (Get-Content $upd -Raw) -replace '(?m)^url:.*$', 'url: http://127.0.0.1:9/' | Set-Content $upd -NoNewline
  Ok 'auto-update blocked'
}

Write-Host ''
Ok 'Slipstream installation completed.'
Say '  Open OpenCode: the Slipstream menu is the tray icon next to the clock (near the date).' DarkGray
Say '  Undo: .\run.ps1 -uninstall' DarkGray
if ($start) { Start-Process (Join-Path $dir $exeName) }
