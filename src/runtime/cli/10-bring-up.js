// ---- the connection that was saved last time
async function bringUp(quiet = false) {
  if (ATTACH_PORT) return                          // attached: the agent already has the connection
  cfg = loadCfg()
  const say2 = quiet ? () => {} : print
  try {
    if (cfg.mode === "wg" || cfg.mode === "wgfile") say2(await serial(() => wgUp(false)))
    else if (cfg.mode === "free") { const f = await serial(() => freeFind()); say2(t("onFree", { host: parseUp(f.proxy).host, ip: f.ip })) }
  } catch (e) { print(why(e) + " " + t("backDirect")); wgStop(); cfg.mode = "none"; saveCfg(cfg) }
}
