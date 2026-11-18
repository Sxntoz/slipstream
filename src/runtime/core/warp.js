// A free WARP account is registered over Cloudflare's API (the call wgcf makes) and the tunnel is our UserWireGuard above.
const wgDir = path.join(stateDir, "wg")
const wgAccountFile = path.join(wgDir, "account.json")
mkdirSync(wgDir, { recursive: true })

// Plain HTTPS for setup calls, never through the gate, with a readable error.
function httpsFetch(url, { method = "GET", headers = {}, body, timeout = 30000, hops = 5 } = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, { method, headers, agent: false, timeout }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && hops > 0) {
        res.resume()
        return resolve(httpsFetch(new URL(res.headers.location, url).href, { timeout, hops: hops - 1 }))
      }
      const chunks = []
      res.on("data", (c) => chunks.push(c))
      res.on("end", () => resolve({ status: res.statusCode, ok: res.statusCode >= 200 && res.statusCode < 300, buf: Buffer.concat(chunks) }))
      res.on("error", reject)
    })
    req.on("timeout", () => req.destroy(new Error("timed out")))
    req.on("error", (e) => reject(new Error(`${new URL(url).host}: ${e.code ?? ""} ${e.message}`.trim())))
    if (body) req.write(body)
    req.end()
  })
}

async function wgRegister() {
  const { publicKey, privateKey } = generateKeyPairSync("x25519")
  const pub = publicKey.export({ format: "der", type: "spki" }).subarray(-32).toString("base64")
  const priv = privateKey.export({ format: "der", type: "pkcs8" }).subarray(-32).toString("base64")
  const r = await httpsFetch("https://api.cloudflareclient.com/v0a2158/reg", {
    method: "POST",
    headers: { "Content-Type": "application/json", "User-Agent": "okhttp/3.12.1", "CF-Client-Version": "a-6.3-2158" },
    body: JSON.stringify({ key: pub, install_id: "", fcm_token: "", tos: new Date().toISOString(), type: "Android", model: "PC", locale: "en_US" }),
    timeout: 20000,
  })
  if (!r.ok) throw new Error(t("eReg", { status: r.status }))
  const j = JSON.parse(r.buf.toString("utf8"))
  const peer = j.config?.peers?.[0]
  if (!peer?.public_key) throw new Error("WARP registration returned no peer")
  const host = String(peer.endpoint?.host ?? "engage.cloudflareclient.com:2408")
  const acc = { priv, peerKey: peer.public_key, endpoint: host.includes(":") ? host : `${host}:2408`, v4: j.config.interface.addresses.v4, v6: j.config.interface.addresses.v6 }
  writeFileSync(wgAccountFile, JSON.stringify(acc, null, 2))
  return acc
}

function wgStop() { try { wg?.stop() } catch {} wg = null }
app.on("will-quit", wgStop)

const wgFromAccount = (acc) => ({ priv: acc.priv, peerKey: acc.peerKey, endpoint: acc.endpoint, v4: acc.v4, v6: acc.v6 })
async function wgStart(opts) {
  wgStop()
  const w = new UserWireGuard(opts)
  await w.start()
  wg = w
}

// Brings the tunnel up and returns a message with the IP. "wg" = a free Cloudflare WARP account (saved, or a new one);
// "wgfile" = the WireGuard .conf the user picked (Route64, Proton, Mullvad, their own server...).
const wgFile = path.join(wgDir, "custom.json")
async function wgUp(fresh) {
  if (cfg.mode === "wgfile") {
    if (!existsSync(wgFile)) throw new Error(t("eNoFile"))
    await wgStart(JSON.parse(readFileSync(wgFile, "utf8")))
    await sleep(1500)
    const ip = await traceVia(upstream()).catch(() => undefined)
    if (!ip) throw new Error(t("eFileDead"))
    return t("onWgfile", { ip })
  }
  let acc
  if (!fresh && existsSync(wgAccountFile)) { try { acc = JSON.parse(readFileSync(wgAccountFile, "utf8")) } catch {} }
  await wgStart(wgFromAccount(acc ?? (await wgRegister())))
  await sleep(1500)
  let ip = await traceVia(upstream()).catch(() => undefined)
  if (!ip && acc) {      // the saved account stopped working: register a new one
    log("saved WARP account did not answer, registering a new one")
    await wgStart(wgFromAccount(await wgRegister()))
    await sleep(1500)
    ip = await traceVia(upstream()).catch(() => undefined)
  }
  if (!ip) throw new Error(t("eWarpDead"))
  return t("onWg", { ip })
}

