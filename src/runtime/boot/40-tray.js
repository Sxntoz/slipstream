// ---------------------------------------------------------------- tray menu
const LOGO = "data:image/png;base64,@@TRAY_ICON_B64@@"
let tray
function buildMenu() {
  if (!tray) return
  cfg = loadCfg()
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: t("m_newIp"), click: guard(newIp) },
    { label: t("m_connection"), submenu: [
      { label: t("m_direct"), type: "radio", checked: cfg.mode === "none", click: useMode("none") },
      { label: t("m_wg"), type: "radio", checked: cfg.mode === "wg", click: useMode("wg") },
      { label: t("m_wgfile"), type: "radio", checked: cfg.mode === "wgfile", click: useMode("wgfile") },
      { label: t("m_free"), type: "radio", checked: cfg.mode === "free", click: useMode("free") },
      { label: t("m_list"), type: "radio", checked: cfg.mode === "list", click: useMode("list") },
      { type: "separator" },
      { label: t("m_chooseWg"), click: useMode("wgfile", true) },
    ] },
    { label: t("m_settings"), click: () => shell.openPath(proxyFile) },
    { label: t("m_auto"), type: "checkbox", checked: !!cfg.autoRotate, click: toggleAuto },
    { type: "separator" },
    { label: t("m_clear"), submenu: [
      { label: t("m_clearLogin"), click: clearLogin },
      { label: t("m_restoreLogin"), click: restoreLogin },
      { label: t("m_clearCache"), click: clearCache },
    ] },
    { label: t("m_status"), click: guard(status) },
    { type: "separator" },
    { label: t("m_language"), submenu: [
      { label: t("m_langAuto"), type: "radio", checked: !cfg.language || cfg.language === "auto", click: () => setLanguage("auto") },
      ...Object.entries(LANGS).map(([code, l]) => ({ label: l.name, type: "radio", checked: cfg.language === code, click: () => setLanguage(code) })),
    ] },
    { label: t("m_restart", { app: APP_NAME }), click: restart },
    { label: t("m_quit"), click: quit },
  ]))
}
function setLanguage(code) {
  cfg = loadCfg(); cfg.language = code; saveCfg(cfg)
  langCode = pickLang(app.getLocale())
  buildMenu()
}
app.whenReady().then(async () => {
  try {
    tray = new Tray(nativeImage.createFromDataURL(LOGO).resize({ width: 32, height: 32 }))
    tray.setToolTip("Slipstream")
    langCode = pickLang(app.getLocale())
    if (afterStart) note(t(afterStart.key, afterStart.vars))
    buildMenu()
  } catch (e) { log("tray failed: " + why(e)) }
})

