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
let afterStart = null    // what the last clean-up did ({ key, vars }), shown once the app is up
function runPending() {
  try {
  if (existsSync(pendingFile)) {
    const todo = JSON.parse(readFileSync(pendingFile, "utf8"))
    rmSync(pendingFile, { force: true })
    const auth = path.join(dataDir, "auth.json")
    if (todo.includes("tokens") && existsSync(auth)) {
      const dir = path.join(backupDir, new Date().toISOString().replace(/[:.]/g, "-"))
      mkdirSync(dir, { recursive: true })
      copyFileSync(auth, path.join(dir, "auth.json"))
      if (readFileSync(auth).equals(readFileSync(path.join(dir, "auth.json")))) { rmSync(auth, { force: true }); afterStart = { key: "doneLogin" } }   // removed only after the copy is verified
      else afterStart = { key: "failVerify" }
    }
    if (todo.includes("restore")) {
      const from = newestBackup()
      if (from && !existsSync(auth)) { mkdirSync(dataDir, { recursive: true }); copyFileSync(path.join(backupDir, from, "auth.json"), auth); afterStart = { key: "doneRestore", vars: { from } } }
    }
    if (todo.includes("cache")) {
      let bytes = 0
      for (const d of [...CACHE.map((n) => path.join(userData, n)), path.join(dataDir, "log")]) { bytes += dirBytes(d); rmSync(d, { recursive: true, force: true }) }
      afterStart = { key: "doneCache", vars: { mb: (bytes / 1048576).toFixed(1) } }
    }
  }
} catch (e) { log("clean-up failed: " + why(e)); afterStart = { key: "failClean", vars: { err: why(e) } } }
}
runPending()

// The app keeps the free-limit time in its database after a limit error and shows its tray until then. Clear it before
// the app opens the database, and any time a cached/older renderer wrote it again while the app was running.
async function clearFreeLimitState() {
  // A fresh boot may still overlap a service that is closing the database; give the lock time to go away.
  for (let i = 0; i < 6; i++) {
    try {
      const { DatabaseSync } = await import("node:sqlite")
      const db = new DatabaseSync(path.join(userData, "drafts.sqlite"))
      try {
        db.exec("PRAGMA busy_timeout = 5000")
        db.prepare("update state set value = ? where name = 'opencode.global.dat' and key = 'free-limit'").run('{"resetAt":null}')
      } finally { db.close() }
      return true
    } catch (e) {
      if (i === 5) { log("free-limit state not cleared: " + why(e)); return false }
      await sleep(500 + i * 500)
    }
  }
  return false
}
await clearFreeLimitState()

