// ---------------------------------------------------------------- auto-rotate
// The app (patched by the installer) reports each free-limit error to the page; the page logs "__OC_LIMIT__<session>".
// boot/45-limit-log.js adds the same signal from the sidecar log, so a renderer that is still loading or running an
// older cached bundle cannot leave a chat behind.
let lastRotation = 0, streak = 0, streakAt = 0, warnedAt = 0
let rotationTimer
let rotating = false
const waiting = new Map()      // sessionID -> webContents (or null when the log reported it)
const handled = new Map()      // sessionID -> last time it was accepted, so the two signals do not rotate twice
const pages = []               // open app windows; a limit can arrive on any of them
app.on("web-contents-created", (_e, wc) => {
  if (wc.getType() !== "window") return
  pages.push(wc)
  wc.once("destroyed", () => { const i = pages.indexOf(wc); if (i >= 0) pages.splice(i, 1) })
})

function hold(ms) {
  clearTimeout(rotationTimer)
  rotationTimer = setTimeout(() => { rotationTimer = null; pump().catch((e) => log(why(e))) }, Math.max(100, ms))
}

// Runs in the page. It must be self-contained: the main process sends its source to executeJavaScript.
function resumeInPage(sessionID) {
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
  const at = () => location.pathname.split("/").filter(Boolean).pop() === sessionID
  return (async () => {
    if (!at()) {
      const link = [...document.querySelectorAll('a[data-slot="tab-link"]')].find((a) => (a.getAttribute("href") || "").endsWith("/session/" + sessionID))
      if (!link) return "notab"
      link.click()
      for (let i = 0; i < 100 && !at(); i++) await sleep(100)
      if (!at()) return "notab"
    }
    if (document.querySelector('[data-component="session-free-limit"]')) return "limit"
    let el
    for (let i = 0; i < 80; i++) {
      el = document.querySelector('[data-component="session-composer-dock"] [contenteditable="true"]')
      if (el && el.isConnected && el.getClientRects().length) break
      await sleep(100)
    }
    if (!el || !el.isConnected) return "none"
    el.focus()
    const text = (el.innerText || "").trim()
    if (!text) return "empty"
    // A draft the user was typing must not be sent by the rotation. Only the message the app handed back after the
    // refusal is safe: it matches the last message in the chat.
    const sent = [...document.querySelectorAll('[data-component="user-message"] [data-slot="user-message-text"]')]
      .map((node) => (node.innerText || "").trim())
      .filter(Boolean)
      .at(-1)
    if (!sent) return "draft"
    const same = (a, b) =>
      a === b || a.includes(b) || b.includes(a) ||
      (a.length >= 40 && b.includes(a.slice(0, 40))) || (b.length >= 40 && a.includes(b.slice(0, 40)))
    return same(text, sent) ? "text" : "draft"
  })()
}

async function resume(wc, sessionID) {
  // Only the chat that failed may be typed into: another open tab would receive the "continue". At startup the tab bar
  // is still being restored, so a missing tab is retried instead of giving up.
  let target, state = "none"
  for (let attempt = 0; attempt < 3; attempt++) {
    const list = [...new Set([...(wc ? [wc] : []), ...pages])]
    state = "none"; target = undefined
    for (const w of list) {
      if (!w || w.isDestroyed() || typeof w.executeJavaScript !== "function") continue
      const s = await w.executeJavaScript(`(${resumeInPage.toString()})(${JSON.stringify(sessionID)})`).catch(() => "error")
      if (s === "text" || s === "empty" || s === "limit" || s === "draft") { target = w; state = s; break }
      if (s === "notab") continue
      state = s
    }
    if (state !== "notab" && state !== "none") break
    if (attempt === 2 || (state === "none" && attempt > 0)) break
    await sleep(2500)
  }
  if (state !== "text" && state !== "empty") return { state, wc: target }
  target.focus()
  if (state === "empty") target.insertText("continue")
  await sleep(250)
  target.sendInputEvent({ type: "keyDown", keyCode: "Enter" })
  target.sendInputEvent({ type: "keyUp", keyCode: "Enter" })
  return { state: "sent", wc: target }
}

async function recoverLimit(wc, sessionID) {
  // A stored free-limit time from an older run (or an older renderer) replaces the composer. Drop it, drop the cached
  // bundle, reload and try once more: the "clear cache and restart" workaround, done automatically.
  log("free-limit panel is blocking the composer; clearing it and reloading")
  if (typeof clearFreeLimitState === "function") await clearFreeLimitState()   // absent in the terminal build
  try { await wc.session.clearCache() } catch {}
  try { if (wc.session.clearCodeCaches) await wc.session.clearCodeCaches({}) } catch {}
  const loaded = new Promise((resolve) => {
    let done = false
    const finish = () => { if (done) return; done = true; try { wc.off("did-finish-load", finish) } catch {}; resolve() }
    wc.once("did-finish-load", finish)
    setTimeout(finish, 15000)
  })
  wc.reload()
  await loaded
  await sleep(1500)
  return (await resume(wc, sessionID)).state
}

async function pump() {
  if (rotating || !waiting.size) return
  cfg = loadCfg()
  if (!cfg.autoRotate) { waiting.clear(); return }
  const now = Date.now()
  if (cfg.mode === "none") {
    if (now - warnedAt > 600000) { warnedAt = now; note(t("limitWarn")) }
    waiting.clear()
    return
  }
  if (busy) return hold(1200)
  if (now - lastRotation < 15000) return hold(15000 - (now - lastRotation))
  if (now - streakAt > 180000) streak = 0
  if (streak >= 10) return hold(60000)
  rotating = true
  busy = true
  try {
    note(t("limitRotating"))
    await sleep(400)
    const msg = await newIp()
    note(msg)
    lastRotation = Date.now()
    streak++
    streakAt = lastRotation
    const todo = [...waiting]
    waiting.clear()
    for (const [id, wc] of todo) {
      let r = await resume(wc, id)
      if (r.state === "limit") r = { state: await recoverLimit(r.wc, id), wc: r.wc }
      if (r.state !== "sent") log(`could not resume ${id}: ${r.state}`)
    }
  } catch (e) { note(why(e)) } finally {
    busy = false
    rotating = false
    if (waiting.size) hold(1500)
  }
}

function onLimit(wc, sessionID) {
  cfg = loadCfg()
  if (!cfg.autoRotate) return
  const id = /^ses_[A-Za-z0-9]+$/.test(String(sessionID ?? "")) ? String(sessionID) : "?"
  if (id === "?") return
  const now = Date.now()
  // The renderer event and the sidecar log line describe the same refusal; a real new refusal after the rotation
  // comes later and must still be accepted.
  if (now - (handled.get(id) ?? 0) < 20000) return
  if (cfg.mode === "none") {
    if (now - warnedAt > 600000) { warnedAt = now; note(t("limitWarn")) }
    waiting.clear()
    return
  }
  handled.set(id, now)
  if (handled.size > 200) for (const [key, at] of handled) if (now - at > 600000) handled.delete(key)
  if (!waiting.has(id) || (!waiting.get(id) && wc)) waiting.set(id, wc ?? null)
  pump().catch((e) => log(why(e)))
}

if (cfg.mode === "wg" || cfg.mode === "wgfile" || cfg.mode === "free") {
  // Serialized with New IP and Connection: a rotation must never restart the tunnel while it is still coming up.
  busy = true
  serial(() => (cfg.mode === "free" ? freeFind().then((f) => log(`Public proxy ${f.proxy}, IP ${f.ip}`)) : wgUp(false).then(log)))
    .catch((e) => {
      log(`${cfg.mode}: ${why(e)} (back to direct)`)
      wgStop(); cfg.mode = "none"; saveCfg(cfg)
    })
    .finally(() => { busy = false; pump().catch((e) => log(why(e))) })
}
