const listEntries = () => cfg.list.map((x) => String(x).trim()).filter((x) => x && !x.startsWith("#") && parseUp(x))

let rotatedOk = false
async function newIp() {
  rotatedOk = false
  cfg = loadCfg()
  if (cfg.mode === "free") { const f = await freeFind(); rotatedOk = true; return t("ipFree", { ip: f.ip, host: parseUp(f.proxy).host }) }
  if (cfg.mode === "wgfile") return t("wgfileFixed", { msg: await wgUp(false) })
  if (cfg.mode === "wg") {
    const old = wg?.session ? await traceVia(upstream()).catch(() => undefined) : undefined
    let last
    for (let i = 0; i < 3; i++) {
      if (i) await sleep(4000 * i)
      try { await wgStart(wgFromAccount(await wgRegister())); await sleep(1500); last = await traceVia(upstream()).catch(() => undefined) } catch (e) { if (i === 2) throw e; continue }
      if (last && last !== old) { rotatedOk = true; return t("ipWg", { ip: last }) }
    }
    return last ? t("sameIp", { ip: last }) : t("noAnswer")
  }
  if (cfg.mode === "list") {
    const all = listEntries()
    if (!all.length) return t("listEmpty")
    const start = Math.max(0, all.indexOf(cfg.current) + 1)
    const old = cfg.current ? await traceVia(parseUp(cfg.current)).catch(() => undefined) : undefined
    for (let k = 0; k < all.length; k++) {
      const cand = all[(start + k) % all.length]
      const ip = await traceVia(parseUp(cand)).catch(() => undefined)
      if (ip && ip !== old) { cfg.current = cand; saveCfg(cfg); rotatedOk = true; return t("ipList", { ip, host: parseUp(cand).host }) }
    }
    return t("listNone")
  }
  return t("directNoIp")
}

const status = async () => {
  const ip = await traceVia(upstream()).catch(() => undefined)
  return ip ? t("statusLine", { ip, mode: t({ none: "mDirect", wg: "mWg", wgfile: "mWgfile", free: "mFree", list: "mList" }[cfg.mode]) }) : t("statusNone")
}

// Asks for a WireGuard .conf, checks it and keeps it for the "WireGuard file" connection.
const chooseWgFile = async () => {
  const r = await dialog.showOpenDialog({ title: t("dlgChoose"), filters: [{ name: "WireGuard", extensions: ["conf"] }], properties: ["openFile"] })
  if (r.canceled || !r.filePaths[0]) return false
  const c = parseWgConf(readFileSync(r.filePaths[0], "utf8"))
  writeFileSync(wgFile, JSON.stringify({ priv: c.priv, peerKey: c.peerKey, psk: c.psk, endpoint: c.endpoint, v4: c.v4, v6: c.v6, dns: c.dns, mtu: c.mtu }, null, 2))
  return true
}
const switchMode = async (mode, pick = false) => {
  cfg = loadCfg(); const before = cfg.mode
  const fallback = (e) => { cfg.mode = "none"; saveCfg(cfg); wgStop(); return new Error(why(e) + " " + t("backDirect")) }
  try {
    if (mode === "wgfile" && (pick || !existsSync(wgFile)) && !(await chooseWgFile())) { cfg.mode = before; saveCfg(cfg); return t("noneChosen") }
    cfg.mode = mode; saveCfg(cfg)
    if (mode !== "wg" && mode !== "wgfile") wgStop()
    if (mode === "wg" || mode === "wgfile") return await wgUp(false)
    if (mode === "free") { const f = await freeFind(); return t("onFree", { host: parseUp(f.proxy).host, ip: f.ip }) }
  } catch (e) { throw fallback(e) }
  return mode === "list" ? t("onList") : t("onDirect")
}
const useMode = (mode, pick = false) => guard(() => switchMode(mode, pick))

const toggleAuto = () => { cfg = loadCfg(); cfg.autoRotate = !cfg.autoRotate; saveCfg(cfg); note(t(cfg.autoRotate ? "autoOn" : "autoOff")) }
