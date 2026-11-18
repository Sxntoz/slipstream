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
let gatePort = ATTACH_PORT
if (!gatePort) gatePort = cfg.gatePort ? await listenOn(cfg.gatePort) : 0
if (!gatePort) { gatePort = await listenOn(0); cfg.gatePort = gatePort; saveCfg(cfg) }
const gateUrl = `http://127.0.0.1:${gatePort}`
// Only this process and the OpenCode service it starts are pointed at the gate.
for (const k of ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"]) process.env[k] = gateUrl
process.env.NO_PROXY = process.env.no_proxy = "localhost,127.0.0.1,::1"
// Context window the app believes a model has ("provider/model": tokens). The app compacts the chat by that number, so a model
// that really accepts more than it declares gets compacted too early. Raising it past what the server accepts gives errors.
function applyContextLimits() {
  const providers = {}
  for (const [id, tokens] of Object.entries(cfg.contextLimits ?? {})) {
    const [prov, ...rest] = id.split("/"), model = rest.join("/")
    if (prov && model && tokens > 0) (providers[prov] ??= {})[model] = { limit: { context: Math.floor(tokens) } }
  }
  if (!Object.keys(providers).length) return
  let base = {}
  try { base = JSON.parse(process.env.OPENCODE_CONFIG_CONTENT || "{}") } catch {}
  base.providers = { ...(base.providers ?? {}) }
  for (const [prov, models] of Object.entries(providers)) base.providers[prov] = { ...(base.providers[prov] ?? {}), models: { ...(base.providers[prov]?.models ?? {}), ...models } }
  process.env.OPENCODE_CONFIG_CONTENT = JSON.stringify(base)
}
applyContextLimits()
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

