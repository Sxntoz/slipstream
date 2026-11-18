// ---------------------------------------------------------------- auto-rotate
// The app (patched by the installer) reports each free-limit error to the page; the page logs "__OC_LIMIT__<session>".
let lastRotation = 0, streak = 0, streakAt = 0, warnedAt = 0
async function resume(wc) {
  // The app puts the stopped message back in the prompt box; if it is empty, send "continue". Then Enter.
  const state = await wc.executeJavaScript(`(() => {
    const el = document.querySelector('[data-component=composer-editor] [contenteditable], [data-component=composer-editor][contenteditable], [contenteditable="true"]')
    if (!el) return "none"
    el.focus()
    return el.innerText.trim() ? "text" : "empty"
  })()`).catch(() => "none")
  if (state === "none") return
  wc.focus()
  if (state === "empty") wc.insertText("continue")
  await sleep(200)
  wc.sendInputEvent({ type: "keyDown", keyCode: "Enter" })
  wc.sendInputEvent({ type: "keyUp", keyCode: "Enter" })
}
async function onLimit(wc) {
  cfg = loadCfg()
  const now = Date.now()
  if (!cfg.autoRotate || busy || now - lastRotation < 15000) return
  if (cfg.mode === "none") {
    if (now - warnedAt > 600000) { warnedAt = now; note(t("limitWarn")) }
    return
  }
  if (now - streakAt > 180000) streak = 0
  if (streak >= 10) return                       // 10 in a row without a free message: stop, try again in 3 minutes
  streak++; streakAt = now; lastRotation = now
  busy = true
  try {
    note(t("limitRotating"))
    await sleep(600)
    const msg = await newIp()
    note(msg)
    if (rotatedOk) { await sleep(800); await resume(wc) }
  } catch (e) { note(why(e)) } finally { busy = false; lastRotation = Date.now() }
}

if (cfg.mode === "wg" || cfg.mode === "wgfile" || cfg.mode === "free") {
  setTimeout(() => (cfg.mode === "free" ? freeFind().then((f) => log(`Public proxy ${f.proxy}, IP ${f.ip}`)) : wgUp(false).then(log)).catch((e) => {
    log(`${cfg.mode}: ${why(e)} (back to direct)`); wgStop(); cfg.mode = "none"; saveCfg(cfg)
  }), 0)
}

