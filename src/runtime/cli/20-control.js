// ---- control port: the tray (and "slipstream ip" typed in another terminal) talk to the process that owns the tunnel
const MODE_ALIASES = { direct: "none", none: "none", wg: "wg", warp: "wg", wgfile: "wgfile", free: "free", list: "list" }

let trayChild = null                              // the tray's PowerShell, a child of the agent so that both live and end together
function startTray() {
  if (trayChild && trayChild.exitCode === null) return false
  const script = path.join(path.dirname(cliFile), "slipstream-tray.ps1")
  trayChild = spawn("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-STA", "-File", script, "-AgentFile", path.join(stateDir, "agent.json")], { stdio: "ignore", windowsHide: true })
  trayChild.on("exit", () => { trayChild = null })
  trayChild.on("error", (e) => { log("tray: " + why(e)); trayChild = null })
  return true
}

const locked = async (fn) => {                    // one change at a time (a new IP takes seconds)
  if (busy) return { text: t("busy") }
  busy = true
  try { return await fn() } catch (e) { return { text: why(e) } } finally { busy = false }
}

function importWgFile(file) {
  const c = parseWgConf(readFileSync(file, "utf8"))
  writeFileSync(wgFile, JSON.stringify({ priv: c.priv, peerKey: c.peerKey, psk: c.psk, endpoint: c.endpoint, v4: c.v4, v6: c.v6, dns: c.dns, mtu: c.mtu }, null, 2))
}

async function controlHandle(req) {
  cfg = loadCfg()
  langCode = pickLang(app.getLocale())
  const args = req.args ?? []
  switch (req.cmd) {
    case "menu": return { menu: buildCliMenu() }
    case "notices": return { notices: notices.splice(0) }
    case "status": return { text: await status() }
    case "ip": return await locked(async () => { const text = await newIp(); return { text, changed: rotatedOk } })
    case "mode": {
      const m = MODE_ALIASES[String(args[0] ?? "").toLowerCase()]
      if (!m) return { text: "usage: mode direct|wg|wgfile|free|list" }
      return await locked(async () => ({ text: await switchMode(m) }))
    }
    case "auto": cfg.autoRotate = !cfg.autoRotate; saveCfg(cfg); return { text: t(cfg.autoRotate ? "autoOn" : "autoOff") }
    case "lang": {
      const code = args[0] === "auto" ? "auto" : Object.keys(LANGS).find((k) => k.toLowerCase() === String(args[0]).toLowerCase())
      if (!code) return { text: "languages: auto, " + Object.keys(LANGS).join(", ") }
      cfg.language = code; saveCfg(cfg); langCode = pickLang(app.getLocale())
      return { text: "ok" }
    }
    case "clear": {
      const what = { login: ["tokens"], restore: ["restore"], cache: ["cache"] }[args[0]]
      if (!what) return { text: "usage: clear login|restore|cache" }
      const auth = path.join(dataDir, "auth.json")
      if (args[0] === "login" && !existsSync(auth)) return { text: t("noLogin") }
      if (args[0] === "restore" && existsSync(auth)) return { text: t("loginExists") }
      if (args[0] === "restore" && !newestBackup()) return { text: t("noBackup") }
      writeFileSync(pendingFile, JSON.stringify(what)); runPending()
      return { text: afterStart ? t(afterStart.key, afterStart.vars) : "done" }
    }
    case "wgfile":
      if (!args[0] || !existsSync(args[0])) return { text: "usage: wgfile <file.conf>" }
      importWgFile(args[0])
      return await locked(async () => ({ text: await switchMode("wgfile") }))
    case "autostart": { const on = !autostartOn(); setAutostart(on); return { text: `${t("m_autostart")}: ${on ? "on" : "off"}` } }
    case "tray": return { text: startTray() ? "tray started" : "tray already running" }
    case "quit": setTimeout(() => process.exit(0), 150); return { text: "bye" }       // the exit handler closes the tunnel
    default: return { text: "unknown command" }
  }
}

// kind: "agent" (the tray's background process, lives until "quit") or "session" (one program started by "slipstream opencode")
function startControl(kind = "session") {
  const token = crypto.randomBytes(16).toString("hex")
  const file = path.join(stateDir, kind === "agent" ? "agent.json" : "cli-control.json")
  const srv = net.createServer((c) => {
    let buf = ""
    c.on("error", () => {})
    c.on("data", async (d) => {
      buf += d
      if (!buf.includes("\n")) return
      let req
      try { req = JSON.parse(buf) } catch { return c.end() }
      if (req.token !== token) return c.end(JSON.stringify({ text: "denied" }) + "\n")
      let out
      try { out = await controlHandle(req) } catch (e) { out = { text: why(e) } }
      c.end(JSON.stringify(out) + "\n")
    })
  })
  srv.listen(0, "127.0.0.1", () => writeFileSync(file, JSON.stringify({ port: srv.address().port, token, pid: process.pid, gatePort, kind })))
  process.on("exit", () => { try { rmSync(file, { force: true }) } catch {} })
}
