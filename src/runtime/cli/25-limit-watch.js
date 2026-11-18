// ---- the agent watches OpenCode's own log for the free-limit error, so the IP changes even on the interactive screen,
// where nothing else can see the error (the traffic is encrypted). v2 writes ~/.local/share/opencode/log/opencode.log,
// and opencode1 the same under its own data folder.
const LIMIT_LINE = /Free usage limit reached/i
const limitLogs = () => [
  path.join(dataDir, "log", "opencode.log"),
  path.join(process.env.LOCALAPPDATA ?? "", "opencode-v1", "xdg", "data", "opencode", "log", "opencode.log"),
]
let lastLimit = 0, limitStreak = 0, limitStreakAt = 0

async function onFreeLimit() {
  cfg = loadCfg()
  langCode = pickLang(app.getLocale())
  const now = Date.now()
  if (!cfg.autoRotate || busy || now - lastLimit < 20000) return
  lastLimit = now
  if (cfg.mode === "none") { notices.push(t("limitWarn")); return }
  if (now - limitStreakAt > 180000) limitStreak = 0
  if (limitStreak >= 10) return                         // 10 in a row without a free message: stop for 3 minutes
  limitStreak++; limitStreakAt = now
  busy = true
  try {
    notices.push(t("limitRotating"))
    const text = await newIp()
    notices.push(rotatedOk ? `${text}\n${t("sendAgain")}` : text)
  } catch (e) { notices.push(why(e)) } finally { busy = false }
}

function startLimitWatch() {
  const offsets = new Map(limitLogs().map((f) => [f, existsSync(f) ? statSync(f).size : 0]))      // only what is written from now on
  setInterval(async () => {
    for (const f of limitLogs()) {
      try {
        if (!existsSync(f)) continue
        const size = statSync(f).size
        let from = offsets.get(f) ?? size
        if (size < from) from = 0                                                              // the log was rotated
        if (size === from) { offsets.set(f, size); continue }
        const buf = Buffer.alloc(Math.min(size - from, 1_000_000))
        const fd = openSync(f, "r")
        try { readSync(fd, buf, 0, buf.length, from) } finally { closeSync(fd) }
        offsets.set(f, from + buf.length)
        if (LIMIT_LINE.test(buf.toString("utf8"))) await onFreeLimit()
      } catch (e) { log("limit watch: " + why(e)) }
    }
  }, 3000)
}
