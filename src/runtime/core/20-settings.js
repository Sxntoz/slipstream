// ---------------------------------------------------------------- settings (proxy.json)
const proxyFile = path.join(stateDir, "proxy.json")
const MODES = ["none", "wg", "wgfile", "free", "list"]
const DEFAULT_CFG = { mode: "none", language: "auto", autoRotate: true, gatePort: 0, contextLimits: { "opencode/deepseek-v4.1-flash-free": 1000000 }, current: "", list: ["# one proxy per line: http://user:pass@host:port | socks5://host:port | host:port"] }
const loadCfg = () => {
  let c = {}
  try { c = JSON.parse(readFileSync(proxyFile, "utf8")) } catch {}
  const cfg = { ...DEFAULT_CFG, ...c }
  if (!MODES.includes(cfg.mode)) cfg.mode = "none"
  return cfg
}
const saveCfg = (c) => writeFileSync(proxyFile, JSON.stringify(c, null, 2))
let cfg = loadCfg()
if (!existsSync(proxyFile)) saveCfg(cfg)

const APP_NAME = "OpenCode"
