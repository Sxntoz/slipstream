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

// "slipstream ip | status | mode" talk to a terminal session that is already running (it owns the tunnel), if there is one.
// This runs before anything else, so a second instance never takes the proxy port of the first.
{
  const cmd = process.argv[2]
  if (["ip", "status", "mode"].includes(cmd)) {
    let ctl
    try { ctl = JSON.parse(readFileSync(path.join(process.env.LOCALAPPDATA ?? path.join(os.homedir(), ".local", "state"), "slipstream", "cli-control.json"), "utf8")) } catch {}
    if (ctl) {
      const reply = await new Promise((res) => {
        const c = net.connect(ctl.port, "127.0.0.1", () => c.write(JSON.stringify({ token: ctl.token, cmd, args: process.argv.slice(3) }) + "\n"))
        let out = ""
        c.on("data", (d) => (out += d)); c.on("close", () => res(out)); c.on("error", () => res(null))
        setTimeout(() => res(null), 120000)
      })
      if (reply) { console.log(reply.trim()); process.exit(0) }
    }
  }
}

