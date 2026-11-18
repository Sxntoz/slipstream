// The terminal program (slipstream.mjs) with a real agent, in a throw-away profile: nothing of the user's is touched.
// No network is needed: the connection stays "direct" and only the control port, menu, settings and log watcher are exercised.
import { test, before, after } from "node:test"
import assert from "node:assert/strict"
import { spawn, spawnSync } from "node:child_process"
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync, appendFileSync, existsSync } from "node:fs"
import { tmpdir } from "node:os"
import net from "node:net"
import path from "node:path"
import { parts } from "../build/build.mjs"

const tmp = mkdtempSync(path.join(tmpdir(), "slipstream-cli-"))
const env = {
  ...process.env,
  LOCALAPPDATA: path.join(tmp, "local"), APPDATA: path.join(tmp, "roaming"), XDG_DATA_HOME: path.join(tmp, "xdg"),
  USERPROFILE: tmp, HOME: tmp, SLIPSTREAM_ATTACH: "",
  ProgramFiles: path.join(tmp, "pf"), "ProgramFiles(x86)": path.join(tmp, "pf86"), ProgramW6432: path.join(tmp, "pf"),
}
const stateDir = path.join(env.LOCALAPPDATA, "slipstream")
const cliFile = path.join(tmp, "slipstream.mjs")
writeFileSync(cliFile, parts().cli)
writeFileSync(path.join(tmp, "package.json"), '{"type":"module"}')
const settings = () => JSON.parse(readFileSync(path.join(stateDir, "cli.json"), "utf8"))
const slipstream = (...args) => spawnSync(process.execPath, [cliFile, ...args], { env, encoding: "utf8", timeout: 60000 })
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

async function waitFor(check, ms = 15000) {
  const end = Date.now() + ms
  for (;;) {
    const v = await check()
    if (v) return v
    if (Date.now() > end) throw new Error("timed out")
    await sleep(150)
  }
}
const agentInfo = () => { try { return JSON.parse(readFileSync(path.join(stateDir, "agent.json"), "utf8")) } catch { return null } }
const control = (cmd, args = []) => new Promise((resolve, reject) => {
  const a = agentInfo()
  const c = net.connect(a.port, "127.0.0.1", () => c.write(JSON.stringify({ token: a.token, cmd, args }) + "\n"))
  let out = ""
  c.on("data", (d) => (out += d)); c.on("close", () => resolve(JSON.parse(out))); c.on("error", reject)
})

let agent
before(async () => {
  mkdirSync(path.join(env.XDG_DATA_HOME, "opencode", "log"), { recursive: true })
  writeFileSync(path.join(env.XDG_DATA_HOME, "opencode", "log", "opencode.log"), "an old line\n")
  assert.equal(slipstream("lang", "en").status, 0)                     // English, whatever language this machine speaks
  assert.equal(slipstream("mode", "direct").status, 0)
  agent = spawn(process.execPath, [cliFile, "agent"], { env, stdio: "ignore" })
  await waitFor(() => agentInfo())
})
after(() => { slipstream("stop"); try { agent.kill() } catch {} })

test("help lists the commands, including the tray ones", () => {
  const r = slipstream("help")
  assert.equal(r.status, 0)
  for (const word of ["slipstream tray", "slipstream stop", "slipstream autostart", "slipstream opencode", "slipstream cli", "slipstream ip", "slipstream clear"]) assert.ok(r.stdout.includes(word), word)
})

test("'slipstream opencode' opens the desktop app; the terminal is 'slipstream cli'", () => {
  const missing = slipstream("opencode")
  assert.equal(missing.status, 1)
  assert.match(missing.stdout, /desktop/i)
  const started = spawnSync(process.execPath, [cliFile, "opencode"], { env: { ...env, SLIPSTREAM_DESKTOP: process.execPath }, encoding: "utf8", timeout: 30000 })
  assert.equal(started.status, 0)
  assert.match(started.stdout, /OpenCode started/)
})

test("settings commands write the terminal's own settings file (cli.json), not the desktop's", () => {
  assert.equal(slipstream("proxy", "add", "socks5://1.2.3.4:1080").status, 0)
  assert.equal(slipstream("context", "opencode/some-model", "123456").status, 0)
  const s = settings()
  assert.ok(s.list.includes("socks5://1.2.3.4:1080"))
  assert.equal(s.contextLimits["opencode/some-model"], 123456)
  assert.ok(!existsSync(path.join(stateDir, "proxy.json")), "the desktop's proxy.json must not be created")
  assert.match(slipstream("proxy", "add", "not a proxy").stdout, /not a proxy address/)
})

test("the agent writes its control file with a port, a token and its proxy port", () => {
  const a = agentInfo()
  assert.equal(a.kind, "agent")
  assert.ok(a.port > 0 && a.gatePort > 1 && a.token.length >= 16)
})

test("the menu is a plain description the tray can draw, in the chosen language", async () => {
  const labels = async () => (await control("menu")).menu.items.filter((i) => i.label).map((i) => i.label)
  const en = await labels()
  assert.equal(en[0], "New IP")
  assert.ok(en.includes("Connection") && en.includes("Clear") && en.includes("Status") && en.includes("Language") && en.includes("Quit"))
  await control("lang", ["pt-BR"])
  assert.equal((await labels())[0], "Novo IP")
  await control("lang", ["ja"])
  assert.equal((await labels())[0], "新しい IP")
  await control("lang", ["en"])
  const { menu } = await control("menu")
  assert.equal(menu.title, "Slipstream CLI")
  const connection = menu.items.find((i) => i.label === "Connection")
  assert.equal(connection.children.filter((c) => c.radio).length, 5)
  assert.equal(connection.children.filter((c) => c.checked).length, 1, "exactly one connection is marked")
})

test("switching the connection through the control port is reflected in the menu", async () => {
  const marked = async () => (await control("menu")).menu.items.find((i) => i.label === "Connection").children.find((c) => c.checked).args[0]
  assert.equal(await marked(), "direct")
  assert.match((await control("mode", ["list"])).text, /proxy list/i)
  assert.equal(await marked(), "list")
  assert.match((await control("mode", ["direct"])).text, /Direct/)
  assert.equal(await marked(), "direct")
  assert.match((await control("mode", ["nonsense"])).text, /usage/)
})

test("auto-rotate toggles and the menu shows it", async () => {
  const flag = async () => (await control("menu")).menu.items.find((i) => i.label === "Auto-rotate").checked
  const before = await flag()
  assert.match((await control("auto")).text, before ? /off/i : /on/i)
  assert.equal(await flag(), !before)
  await control("auto")
  assert.equal(await flag(), before)
})

test("a program started with the agent running uses the agent's proxy", () => {
  const a = agentInfo()
  const r = slipstream("run", process.execPath, "-e", "console.log(process.env.HTTPS_PROXY + ' ' + process.env.HTTP_PROXY)")
  assert.equal(r.stdout.trim(), `http://127.0.0.1:${a.gatePort} http://127.0.0.1:${a.gatePort}`)
})

test("the agent reads the free-limit error from OpenCode's log and tells the tray", async () => {
  appendFileSync(path.join(env.XDG_DATA_HOME, "opencode", "log", "opencode.log"),
    'timestamp=2026-11-18T02:05:30.669Z level=ERROR message="Failed to drain Session" cause="AI.Error: Free usage limit reached. Free models work in OpenCode"\n')
  // connection is "direct", so there is no IP to change: the tray is told what to do about it
  const notice = await waitFor(async () => (await control("notices")).notices?.find((n) => /Free limit reached/.test(n)), 12000)
  assert.match(notice, /Auto-rotate needs Connection/)
  assert.deepEqual((await control("notices")).notices, [], "a notice is shown once")
})

test("old lines in the log do not trigger anything", async () => {
  await sleep(3500)
  assert.deepEqual((await control("notices")).notices, [])
})

test("'slipstream stop' closes the agent and removes its control file", async () => {
  assert.match(slipstream("stop").stdout, /stopped/)
  await waitFor(() => !agentInfo())
  assert.match(slipstream("stop").stdout, /not running/)
})
