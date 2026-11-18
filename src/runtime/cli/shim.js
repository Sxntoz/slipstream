// ---- terminal build: there is no Electron here. These stand-ins print instead of opening windows or trays.
class Notification { constructor(o) { this.o = o } show() { console.log(this.o.body) } }
const dialog = { showMessageBox: async () => ({}), showOpenDialog: async () => ({ canceled: true }) }
const shell = { openPath: (f) => { try { execFileSync("cmd", ["/c", "start", "", f], { windowsHide: true }) } catch {} } }
const app = {
  commandLine: { appendSwitch() {} },
  on(ev, fn) { if (ev === "will-quit") process.on("exit", fn) },
  relaunch() {}, exit(code) { process.exit(code) }, getLocale: () => Intl.DateTimeFormat().resolvedOptions().locale,
}
const Tray = null, Menu = null, nativeImage = null

// ---- Slipstream CLI: the agent (a background process that owns the tunnel) and the tray that controls it.
// Everything below runs BEFORE the engine starts, so a second process never takes the proxy port of the first.
import { fileURLToPath } from "node:url"

const cliFile = fileURLToPath(import.meta.url)
const cliStateDir = path.join(process.env.LOCALAPPDATA ?? path.join(os.homedir(), ".local", "state"), "slipstream")
// the control file of a running agent / session (undefined when it is not running any more)
const readState = (name) => {
  try {
    const j = JSON.parse(readFileSync(path.join(cliStateDir, name), "utf8"))
    process.kill(j.pid, 0)
    return j
  } catch { return undefined }
}
// one request to a control port. The reply is a JSON object ({ text, ... }), or null when nobody answers.
const callControl = (ctl, cmd, args = [], timeout = 120000) => new Promise((resolve) => {
  if (!ctl) return resolve(null)
  const c = net.connect(ctl.port, "127.0.0.1", () => c.write(JSON.stringify({ token: ctl.token, cmd, args }) + "\n"))
  let out = ""
  c.on("data", (d) => (out += d))
  c.on("close", () => { try { resolve(JSON.parse(out)) } catch { resolve(null) } })
  c.on("error", () => resolve(null))
  setTimeout(() => { c.destroy(); resolve(null) }, timeout)
})
const detached = (file, args) => spawn(file, args, { detached: true, stdio: "ignore", windowsHide: true }).unref()
async function ensureAgent() {
  if (readState("agent.json")) return true
  detached(process.execPath, [cliFile, "agent"])
  for (let i = 0; i < 120; i++) { await new Promise((r) => setTimeout(r, 250)); if (readState("agent.json")) return true }
  return false
}

// Start with Windows: a small .vbs in the Startup folder runs "slipstream tray" without a console window.
const startupFile = () => path.join(process.env.APPDATA ?? path.join(os.homedir(), "AppData", "Roaming"), "Microsoft", "Windows", "Start Menu", "Programs", "Startup", "Slipstream CLI.vbs")
const autostartOn = () => existsSync(startupFile())
function setAutostart(on) {
  if (!on) { try { rmSync(startupFile(), { force: true }) } catch {} return false }
  mkdirSync(path.dirname(startupFile()), { recursive: true })
  const q = (s) => `""${s}""`                                    // a double quote inside a VBScript string is written twice
  writeFileSync(startupFile(), `CreateObject("WScript.Shell").Run "${q(process.execPath)} ${q(cliFile)} tray", 0, False\r\n`)
  return true
}

{
  const [cmd, ...rest] = process.argv.slice(2)

  // commands that need no engine at all
  if (cmd === "tray") {
    if (!(await ensureAgent())) { console.log("could not start the Slipstream CLI agent (see slipstream.log)"); process.exit(1) }
    // the agent starts the tray itself: it outlives this process, and PowerShell cannot be "detached" (it needs a console)
    await callControl(readState("agent.json"), "tray", [], 15000)
    console.log("Slipstream CLI tray started: the icon is next to the clock.")
    process.exit(0)
  }
  if (cmd === "stop") {
    console.log((await callControl(readState("agent.json"), "quit", [], 5000)) ? "Slipstream CLI stopped." : "Slipstream CLI is not running.")
    process.exit(0)
  }
  if (cmd === "autostart") {
    if (rest[0] === "on" || rest[0] === "off") setAutostart(rest[0] === "on")
    console.log(`Start with Windows: ${autostartOn() ? "on" : "off"}`)
    process.exit(0)
  }

  // talk to what is already running (the agent from the tray, or another session) instead of starting a second engine
  if (["ip", "status", "mode", "auto"].includes(cmd)) {
    const reply = await callControl(readState("agent.json") ?? readState("cli-control.json"), cmd, rest)
    if (reply?.text) { console.log(reply.text); process.exit(0) }
  }

  // programs started through the agent use its connection; commands that only change settings need no connection
  const agent = readState("agent.json")
  const terminal = cmd === "cli" || ["opencode1", "opencode2", "run"].includes(cmd) ||
    (cmd === "opencode" && ["cli", "terminal"].includes(String(rest[0] ?? "").toLowerCase()))
  if (agent && terminal) process.env.SLIPSTREAM_ATTACH = String(agent.gatePort)
  else if ([undefined, "help", "-h", "--help", "wgfile", "proxy", "context", "lang", "clear"].includes(cmd)) process.env.SLIPSTREAM_ATTACH = "1"
}
