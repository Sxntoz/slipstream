
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
  if (busy) return say(t("busy"))
  busy = true
  try { say(await fn()) } catch (e) { say(why(e)) } finally { busy = false; try { buildMenu() } catch {} }
}

