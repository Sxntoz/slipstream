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
  startControl()
  await bringUp()
  const [file, ...rest] = args
  const batch = rest[0] === "run"         // "opencode run ..." has no interactive screen, so its output can be watched
  let result = await runOnce(file, rest, batch)
  for (let n = 1; batch && result.code !== 0 && FREE_LIMIT.test(result.seen) && n <= 3; n++) {
    cfg = loadCfg()
    if (!cfg.autoRotate || cfg.mode === "none") { print(t("limitWarn")); break }
    print(t("limitRotating"))
    print(await newIp())
    if (!rotatedOk) break
    result = await runOnce(file, rest, true)
  }
  wgStop()
  process.exit(result.code)
}

