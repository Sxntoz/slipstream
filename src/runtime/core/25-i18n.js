// ---------------------------------------------------------------- languages
// Menu and messages. Technical details (network and protocol errors, the log file) stay in English.
const LANGS = {
@@APP_LANGS@@
}
// "xx-YY" or "xx" from the system -> one of the languages above (English if there is none)
const pickLang = (code) => {
  const c = String(code || "").toLowerCase()
  if (cfg.language && cfg.language !== "auto" && LANGS[cfg.language]) return cfg.language
  if (c.startsWith("pt")) return "pt-BR"
  if (c.startsWith("zh")) return "zh-CN"
  const base = c.split(/[-_]/)[0]
  return Object.keys(LANGS).find((k) => k.toLowerCase() === base) ?? "en"
}
let langCode = "en"
const t = (key, vars = {}) => (LANGS[langCode]?.[key] ?? LANGS.en[key] ?? key).replace(/\{(\w+)\}/g, (_, n) => String(vars[n] ?? ""))
langCode = pickLang(Intl.DateTimeFormat().resolvedOptions().locale)

