// ---- what the tray draws. A plain description with the labels already in the user's language, so the tray script only has to show it.
const notices = []                                 // messages for the tray to show (the free limit was hit, the IP changed...)
function buildCliMenu() {
  cfg = loadCfg()
  langCode = pickLang(app.getLocale())
  const connection = (id, label) => ({ label, radio: true, checked: cfg.mode === id, cmd: "mode", args: [id === "none" ? "direct" : id] })
  const language = (code, label) => ({ label, radio: true, checked: (cfg.language ?? "auto") === code, cmd: "lang", args: [code] })
  return {
    title: "Slipstream CLI",
    settingsPath: proxyFile,
    items: [
      { label: t("m_newIp"), cmd: "ip" },
      { label: t("m_connection"), children: [
        connection("none", t("m_direct")), connection("wg", t("m_wg")), connection("wgfile", t("m_wgfile")),
        connection("free", t("m_free")), connection("list", t("m_list")),
        { separator: true }, { label: t("m_chooseWg"), action: "choose-wg" },
      ] },
      { label: t("m_settings"), action: "open", path: proxyFile },
      { label: t("m_auto"), checked: !!cfg.autoRotate, cmd: "auto" },
      { label: t("m_autostart"), checked: autostartOn(), cmd: "autostart" },
      { separator: true },
      { label: t("m_clear"), children: [
        { label: t("m_clearLogin"), cmd: "clear", args: ["login"] },
        { label: t("m_restoreLogin"), cmd: "clear", args: ["restore"] },
        { label: t("m_clearCache"), cmd: "clear", args: ["cache"] },
      ] },
      { label: t("m_status"), cmd: "status" },
      { separator: true },
      { label: t("m_language"), children: [language("auto", t("m_langAuto")), ...Object.entries(LANGS).map(([code, l]) => language(code, l.name))] },
      { label: t("m_quit"), cmd: "quit", action: "quit" },
    ],
  }
}
