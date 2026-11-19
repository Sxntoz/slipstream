// ---------------------------------------------------------------- second free-limit signal: the sidecar log
// The renderer only reports a free limit after its bundle has loaded and the patch is inside it. A chat that was already
// running when the app started can hit the limit before that, and an older cached bundle never reports at all. The
// sidecar writes every refusal to its log, so auto-rotate still sees it and can resume the exact chat.
const LIMIT_LOG = path.join(dataDir, "log", "opencode.log")
const LIMIT_TEXT = /Free usage limit reached/i
const LIMIT_SESSION = /sessionID=(ses_[A-Za-z0-9]+)/
let limitLogAt = 0
let limitTail = ""
try { limitLogAt = existsSync(LIMIT_LOG) ? statSync(LIMIT_LOG).size : 0 } catch {}
setInterval(() => {
  try {
    if (!existsSync(LIMIT_LOG)) return
    const size = statSync(LIMIT_LOG).size
    if (size < limitLogAt) { limitLogAt = 0; limitTail = "" }            // the log was rotated
    if (size === limitLogAt) return
    const len = Math.min(size - limitLogAt, 1_000_000)
    const buf = Buffer.alloc(len)
    const fd = openSync(LIMIT_LOG, "r")
    try { readSync(fd, buf, 0, len, limitLogAt) } finally { closeSync(fd) }
    limitLogAt += len
    const lines = (limitTail + buf.toString("utf8")).split(/\r?\n/)
    limitTail = lines.pop() ?? ""                                        // a write can end in the middle of a line
    if (limitTail.length > 65536) limitTail = limitTail.slice(-65536)
    for (const line of lines) {
      if (!LIMIT_TEXT.test(line)) continue
      const id = LIMIT_SESSION.exec(line)?.[1]
      if (id) onLimit(undefined, id)
    }
  } catch (e) { log("limit log: " + why(e)) }
}, 2000)
