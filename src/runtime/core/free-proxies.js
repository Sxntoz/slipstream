// ---------------------------------------------------------------- free public proxies
// Public lists of open proxies. They are tested one by one through Cloudflare's trace page and the first one that answers is
// used. They are untrusted: HTTPS stays end-to-end encrypted, but the proxy sees where you connect. Many die within minutes.
const FREE_SOURCES = [
  ["socks5", "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt"],
  ["socks5", "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/socks5/data.txt"],
  ["http", "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt"],
  ["http", "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/http/data.txt"],
]
let freePool = [], freeUsed = new Set()
async function freeFetch() {
  const all = new Set()
  await Promise.all(FREE_SOURCES.map(async ([scheme, url]) => {
    try {
      const r = await httpsFetch(url, { timeout: 20000 })
      if (!r.ok) return
      for (const line of r.buf.toString("utf8").split(/\r?\n/)) {
        const m = /^(?:\w+:\/\/)?(\d{1,3}(?:\.\d{1,3}){3}:\d{2,5})\s*$/.exec(line.trim())
        if (m) all.add(`${scheme}://${m[1]}`)
      }
    } catch (e) { log("free list failed: " + why(e)) }
  }))
  freePool = [...all].sort(() => Math.random() - 0.5)
  return freePool.length
}
// First working proxy (different exit IP from the ones already used). 40 at a time, at most 90 seconds.
async function freeFind() {
  if (freePool.length < 20 && (await freeFetch()) === 0) throw new Error(t("eNoList"))
  const deadline = Date.now() + 90000
  let next = 0, found
  const worker = async () => {
    while (!found && Date.now() < deadline) {
      const cand = freePool[next++]
      if (!cand) return
      const ip = await traceVia(parseUp(cand)).catch(() => undefined)
      if (ip && !freeUsed.has(ip) && !found) found = { proxy: cand, ip }
    }
  }
  await Promise.all(Array.from({ length: 40 }, worker))
  freePool = freePool.slice(next)
  if (!found) throw new Error(t("eNoProxy"))
  freeUsed.add(found.ip)
  freeCurrent = found.proxy
  return found
}

