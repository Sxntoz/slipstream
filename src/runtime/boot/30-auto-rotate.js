// ---------------------------------------------------------------- auto-rotate
// The app (patched by the installer) reports each free-limit error to the page; the page logs "__OC_LIMIT__<session>".
// boot/45-limit-log.js adds the same signal from the sidecar log, so a renderer that is still loading or running an
// older cached bundle cannot leave a chat behind.
let lastRotation = 0, streak = 0, streakAt = 0, warnedAt = 0
let rotationTimer
let rotating = false
const waiting = new Map()      // sessionID -> webContents (or null when the log reported it)
const handled = new Map()      // sessionID -> last time it was accepted, so the two signals do not rotate twice
const recovered = new Map()    // sessionID -> last automatic reload, so one slow chat is not reloaded again and again
const resumedAt = new Map()    // sessionID -> last message actually sent, so a new refusal after it is never ignored
const retries = new Map()      // sessionID -> failed resume attempts, so nobody has to babysit the app
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
// One snapshot, no timers: Chromium throttles timers of a background window, so a "wait 100ms" loop in the page used to
// stretch a single check to minutes while the connection was held busy.
function resumeInPage(sessionID) {
  const at = () => location.pathname.split("/").filter(Boolean).pop() === sessionID
  const limit = () => document.querySelector('[data-component="session-free-limit"]')
  // The prompt is contenteditable=true, but a disabled prompt is "false" and newer builds may mark it
  // plaintext-only. Take any visible editable node inside the composer, not one exact attribute value.
  const editor = () => [...document.querySelectorAll('[data-component="session-composer-dock"] [contenteditable], [data-slot="composer-face"] [contenteditable]')]
    .filter((n) => n.isConnected && n.getClientRects().length && n.isContentEditable !== false && (n.getAttribute("contenteditable") || "") !== "false")
    .at(-1)
  if (!at()) {
    const links = [...document.querySelectorAll('a[data-slot="tab-link"], a[data-titlebar-tab-link]')]
    const link = links.find((a) => (a.getAttribute("href") || "").endsWith("/session/" + sessionID))
    if (link) { link.click(); if (!at()) return "switching" }
    else {
      // The chat is not open (closed tab, a window that just started, someone away from the PC). Open it in this window
      // instead of giving up: the rotation is only useful if the failed chat can go on by itself.
      const base = (links.map((a) => a.getAttribute("href") || "").find((h) => h.includes("/session/")) ?? location.pathname).replace(/\/session\/[^/]*$/, "")
      if (!base.includes("/server/")) return "notab"
      try {
        history.pushState(null, "", base + "/session/" + sessionID)
        window.dispatchEvent(new PopStateEvent("popstate"))
        return "switching"
      } catch { return "notab" }
    }
  }
  if (limit()) return "limit"
  const el = editor()
  if (!el) return limit() ? "limit" : "none"
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
}

async function resume(wc, sessionID) {
  // Only the chat that failed may be typed into: another open tab would receive the "continue". The main process polls
  // with its own (unthrottled) timers until the chat is ready, the tab turns up, or the deadline passes.
  const deadline = Date.now() + 25000
  let target, state = "none"
  for (;;) {
    const list = [...new Set([...(wc ? [wc] : []), ...pages])]
    state = "notab"; target = undefined
    for (const w of list) {
      if (!w || w.isDestroyed() || typeof w.executeJavaScript !== "function") continue
      const s = await w.executeJavaScript(`(${resumeInPage.toString()})(${JSON.stringify(sessionID)})`).catch(() => "none")
      if (s === "text" || s === "empty" || s === "limit" || s === "draft") { target = w; state = s; break }
      if (s === "notab") continue                 // another window may still have that tab
      if (state === "notab" || s === "switching") { state = s; target = target ?? w }
    }
    if (state === "text" || state === "empty" || state === "limit" || state === "draft") break
    if (Date.now() >= deadline) break
    await sleep(400)
  }
  if (state !== "text" && state !== "empty") return { state, wc: target }
  target.focus()
  if (state === "empty") target.insertText("continue")
  await sleep(250)
  target.sendInputEvent({ type: "keyDown", keyCode: "Enter" })
  target.sendInputEvent({ type: "keyUp", keyCode: "Enter" })
  return { state: "sent", wc: target }
}

function canRecover(sessionID) {
  const now = Date.now()
  if (now - (recovered.get(sessionID) ?? 0) < 60000) return false
  recovered.set(sessionID, now)
  if (recovered.size > 100) for (const [id, at] of recovered) if (now - at > 600000) recovered.delete(id)
  return true
}

// The "clear cache and restart" workaround without a restart: drop the stored free-limit time and the cached renderer
// bundle, then reload the window. Used by auto-rotate and by the tray's "Resume chat".
async function refreshChat(wc) {
  if (!wc || wc.isDestroyed()) return
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
}

async function recoverLimit(wc, sessionID) {
  if (!wc || wc.isDestroyed()) return "none"
  log("chat has no usable composer; clearing the state and the renderer cache, then reloading")
  await refreshChat(wc)
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
  let delay = 1500
  try {
    note(t("limitRotating"))
    await sleep(400)
    const msg = await newIp()
    note(msg)
    lastRotation = Date.now()
    streak++
    streakAt = lastRotation
    // The tunnel is up; the tray works again while the chats are resumed and reloaded.
    busy = false
    try { buildMenu() } catch {}
    const todo = [...waiting]
    waiting.clear()
    for (const [id, wc] of todo) {
      let r = await resume(wc, id)
      // "none" is the same dead end as the limit panel: the chat is open but there is no usable composer. Reload it
      // the way the user would, instead of logging a failure and leaving the chat stuck.
      if ((r.state === "limit" || r.state === "none") && canRecover(id)) r = { state: await recoverLimit(r.wc, id), wc: r.wc }
      if (r.state === "sent") { retries.delete(id); resumedAt.set(id, Date.now()); continue }
      log(`could not resume ${id}: ${r.state}`)
      // Nobody may be watching: keep trying a few times instead of leaving the chat dead until the next refusal.
      // A draft is the one case to leave alone, since sending it would put words in the user's mouth.
      const tries = retries.get(id) ?? 0
      if (r.state !== "draft" && tries < 3) { retries.set(id, tries + 1); waiting.set(id, r.wc ?? wc); delay = 45000 }
      else { retries.delete(id); log(`giving up on ${id} after ${tries + 1} attempts`) }
    }
  } catch (e) { note(why(e)) } finally {
    busy = false
    rotating = false
    if (waiting.size) hold(delay)
  }
}

function onLimit(wc, sessionID) {
  cfg = loadCfg()
  if (!cfg.autoRotate) return
  const id = /^ses_[A-Za-z0-9]+$/.test(String(sessionID ?? "")) ? String(sessionID) : "?"
  if (id === "?") return
  const now = Date.now()
  // The renderer event and the sidecar log line describe the same refusal; a refusal that arrives after a message was
  // actually sent is a NEW refusal and must rotate again, even inside that 20s window.
  const last = handled.get(id) ?? 0
  if (now - last < 20000 && last > (resumedAt.get(id) ?? 0)) return
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
      const failed = cfg.mode
      log(`${failed}: ${why(e)} (back to direct)`)
      wgStop(); cfg.mode = "none"; saveCfg(cfg)
      // One dead tunnel must not leave auto-rotate stuck on Direct for the rest of the day. Try the saved connection
      // once more, unless the user picked something else in the meantime.
      setTimeout(() => {
        if (loadCfg().mode !== "none") return
        log("trying the saved connection again")
        serial(() => switchModeNow(failed)).then(log).catch((err) => log(why(err)))
      }, 60000)
    })
    .finally(() => { busy = false; pump().catch((e) => log(why(e))) })
}
