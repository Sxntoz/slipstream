// ---- the agent: what "slipstream tray" starts in the background. It owns the tunnel for every terminal and for the tray.
let staying = false
async function runAgent() {
  staying = true
  startControl("agent")
  await bringUp(true)
  startLimitWatch()
  log("Slipstream CLI agent ready")
  setInterval(() => {}, 60000)                       // keep the process alive until "quit"
}

// ---- commands that only change settings (the connection starts with the next run)
async function main() {
  const [cmd, ...rest] = argv
  cfg = loadCfg()
  if (!cmd || cmd === "help" || cmd === "-h" || cmd === "--help") return print(HELP)
  if (cmd === "agent") return runAgent()
  if (cmd === "run") return runTool(rest)
  if (cmd === "opencode") return ["cli", "terminal"].includes(String(rest[0] ?? "").toLowerCase()) ? runTool(["opencode", ...rest.slice(1)]) : runDesktop()
  if (cmd === "cli") return runTool(["opencode", ...rest])
  if (cmd === "opencode1" || cmd === "opencode2") return runTool(argv)

  if (cmd === "ip") { print(await newIp()); process.exit(0) }
  if (cmd === "status") { await bringUp(true); print(await status()); process.exit(0) }
  if (cmd === "auto") { cfg.autoRotate = !cfg.autoRotate; saveCfg(cfg); print(t(cfg.autoRotate ? "autoOn" : "autoOff")); process.exit(0) }
  if (cmd === "mode") {
    const m = MODE_ALIASES[String(rest[0] ?? "").toLowerCase()]
    if (!m) return print("usage: slipstream mode direct|wg|wgfile|free|list")
    cfg.mode = m; saveCfg(cfg)
    return print(`Connection set to ${rest[0]}. It starts with the next "slipstream cli".`)
  }
  if (cmd === "wgfile") {
    if (!rest[0] || !existsSync(rest[0])) return print("usage: slipstream wgfile <file.conf>")
    const c = parseWgConf(readFileSync(rest[0], "utf8"))
    writeFileSync(wgFile, JSON.stringify({ priv: c.priv, peerKey: c.peerKey, psk: c.psk, endpoint: c.endpoint, v4: c.v4, v6: c.v6, dns: c.dns, mtu: c.mtu }, null, 2))
    cfg.mode = "wgfile"; saveCfg(cfg)
    return print("WireGuard file saved and selected.")
  }
  if (cmd === "proxy") {
    if (rest[0] === "add" && rest[1]) {
      if (!parseUp(rest[1])) return print("not a proxy address: use http://user:pass@host:port, socks5://host:port or host:port")
      cfg.list = [...cfg.list, rest[1]]; saveCfg(cfg)
      return print("added. Use: slipstream mode list")
    }
    return print(`${proxyFile}\n` + listEntries().map((x) => "  " + x).join("\n"))
  }
  if (cmd === "context") {
    const tokens = Number(rest[1])
    if (!rest[0] || !rest[0].includes("/") || !(tokens > 0)) return print("usage: slipstream context <provider/model> <tokens>")
    cfg.contextLimits = { ...(cfg.contextLimits ?? {}), [rest[0]]: tokens }; saveCfg(cfg)
    return print(`${rest[0]} -> ${tokens} tokens (applies to the next run). Raising it above what the server accepts gives errors.`)
  }
  if (cmd === "lang") {
    const code = rest[0] === "auto" ? "auto" : Object.keys(LANGS).find((k) => k.toLowerCase() === String(rest[0]).toLowerCase())
    if (!code) return print("languages: auto, " + Object.keys(LANGS).join(", "))
    cfg.language = code; saveCfg(cfg)
    return print("ok")
  }
  if (cmd === "clear") {
    const what = { login: ["tokens"], restore: ["restore"], cache: ["cache"] }[rest[0]]
    if (!what) return print("usage: slipstream clear login|restore|cache")
    const auth = path.join(dataDir, "auth.json")
    if (rest[0] === "login" && !existsSync(auth)) return print(t("noLogin"))
    if (rest[0] === "restore" && existsSync(auth)) return print(t("loginExists"))
    if (rest[0] === "restore" && !newestBackup()) return print(t("noBackup"))
    writeFileSync(pendingFile, JSON.stringify(what)); runPending()
    return print(afterStart ? t(afterStart.key, afterStart.vars) : "done")
  }
  print(`unknown command: ${cmd}\n`); print(HELP)
}
await main()
if (!staying) process.exit(0)

