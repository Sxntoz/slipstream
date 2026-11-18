// ---- running a program through the engine (the proxy variables are already in process.env)
const toolPath = (name) => {
  const v2 = path.join(process.env.APPDATA ?? "", "npm", "node_modules", "@opencode", "cli", "bin", "opencode.exe")
  const v1 = path.join(process.env.LOCALAPPDATA ?? "", "opencode-v1", "node_modules", "opencode-windows-x64", "bin", "opencode.exe")
  if ((name === "opencode" || name === "opencode2") && existsSync(v2)) return v2
  if (name === "opencode1" && existsSync(v1)) return v1
  return name       // anything else is looked up on PATH
}
const FREE_LIMIT = /Free usage limit|FreeUsageLimitError/i

// Finds a program the way the shell would (PATH + PATHEXT), so it can be started without "shell: true".
function findOnPath(name) {
  if (path.isAbsolute(name) && existsSync(name)) return name
  const exts = name.includes(".") ? [""] : (process.env.PATHEXT ?? ".EXE;.CMD;.BAT").split(";")
  for (const dir of (process.env.PATH ?? "").split(path.delimiter)) {
    for (const ext of exts) {
      const full = path.join(dir, name + ext)
      if (existsSync(full) && statSync(full).isFile()) return full
    }
  }
  return undefined
}
// ---- the desktop app: same places the installer looks in, plus the folder it recorded during the patch
const desktopDirs = () => [
  path.join(process.env.LOCALAPPDATA ?? "", "Programs", "ai.opencode.desktop"),
  path.join(process.env.LOCALAPPDATA ?? "", "Programs", "OpenCode"),
  path.join(process.env.ProgramFiles ?? "", "OpenCode"),
  path.join(process.env["ProgramFiles(x86)"] ?? "", "OpenCode"),
]
function desktopExe() {
  if (process.env.SLIPSTREAM_DESKTOP && existsSync(process.env.SLIPSTREAM_DESKTOP)) return process.env.SLIPSTREAM_DESKTOP
  try {
    const dir = JSON.parse(readFileSync(path.join(stateDir, "desktop.json"), "utf8")).dir
    if (dir && existsSync(path.join(dir, "OpenCode.exe"))) return path.join(dir, "OpenCode.exe")
  } catch {}
  for (const dir of desktopDirs()) { const file = path.join(dir, "OpenCode.exe"); if (existsSync(file)) return file }
  return findOnPath("OpenCode.exe")
}
function runDesktop() {
  const exe = desktopExe()
  if (!exe) { print(t("noDesktop")); return process.exit(1) }
  const child = spawn(exe, [], { cwd: path.dirname(exe), detached: true, stdio: "ignore" })
  child.on("error", (e) => { print(`could not start ${exe}: ${why(e)}`); process.exit(1) })
  child.unref()
  print(t("desktopStarted"))
  process.exit(0)
}

const cmdQuote = (a) => (/[\s"&|<>^()%]/.test(a) ? `"${String(a).replace(/"/g, '""')}"` : String(a))

function runOnce(file, args, watch) {
  return new Promise((resolve) => {
    const found = toolPath(file) !== file ? toolPath(file) : findOnPath(file)
    if (!found) { print(`could not find ${file}`); return resolve({ code: 127, seen: "" }) }
    const stdio = watch ? ["inherit", "pipe", "pipe"] : "inherit"
    // .cmd / .bat files need cmd.exe; everything else (like opencode.exe) is started directly, so the arguments stay exact
    // v1 and v2 would share one database and v2's is not readable by v1, so v1 gets its own data folders
    const v1Root = path.join(process.env.LOCALAPPDATA ?? "", "opencode-v1", "xdg")
    const env = file === "opencode1" ? { ...process.env, XDG_DATA_HOME: path.join(v1Root, "data"), XDG_STATE_HOME: path.join(v1Root, "state"), XDG_CACHE_HOME: path.join(v1Root, "cache") } : process.env
    const child = /\.(cmd|bat)$/i.test(found)
      ? spawn(process.env.ComSpec ?? "cmd.exe", ["/d", "/s", "/c", `"${[found, ...args].map(cmdQuote).join(" ")}"`], { stdio, env, windowsVerbatimArguments: true })
      : spawn(found, args, { stdio, env })
    let seen = ""
    if (watch) {
      child.stdout.on("data", (d) => { process.stdout.write(d); seen = (seen + d).slice(-4000) })
      child.stderr.on("data", (d) => { process.stderr.write(d); seen = (seen + d).slice(-4000) })
    }
    child.on("error", (e) => { print(`could not start ${file}: ${why(e)}`); resolve({ code: 127, seen }) })
    child.on("close", (code) => resolve({ code: code ?? 0, seen }))
  })
}

async function runTool(args) {
  if (!args.length) return print(HELP)
  process.on("SIGINT", () => {})          // Ctrl+C belongs to the program; Slipstream leaves after it
  const attached = ATTACH_PORT > 1        // the tray's agent owns the connection: nothing to start here
  if (!attached) { startControl("session"); await bringUp() }
  const [file, ...rest] = args
  const batch = rest[0] === "run"         // "opencode run ..." has no interactive screen, so its output can be watched
  let result = await runOnce(file, rest, batch)
  for (let n = 1; batch && result.code !== 0 && FREE_LIMIT.test(result.seen) && n <= 3; n++) {
    cfg = loadCfg()
    if (!cfg.autoRotate || cfg.mode === "none") { print(t("limitWarn")); break }
    print(t("limitRotating"))
    const reply = attached ? await callControl(readState("agent.json"), "ip") : { text: await newIp(), changed: rotatedOk }
    print(reply?.text ?? "the agent did not answer")
    if (!reply?.changed) break
    result = await runOnce(file, rest, true)
  }
  wgStop()
  process.exit(result.code)
}

