#!/usr/bin/env node
// Builds run.ps1 (the single file the one-line installer downloads) from the modules in src/.
//
//   node build/build.mjs            write run.ps1
//   node build/build.mjs --check    fail if run.ps1 is not what the sources give (CI uses this)
//   node build/build.mjs --out f    write somewhere else
//
// Order and grouping of the files is in src/manifest.json. A few placeholders are filled here:
//   @@BOOT_JS@@  @@CLI_SOURCE@@  @@CLI_TRAY@@  the desktop patch, the finished terminal program and its tray script, embedded in the PowerShell script
//   @@INSTALLER_I18N@@                        installer messages, Base64 of one JSON (keeps run.ps1 plain ASCII)
//   @@APP_LANGS@@                             the app's language entries (src/i18n/app/<code>.js)
//   @@TRAY_ICON_B64@@                         assets/tray-icon.png      (the desktop tray)
//   @@CLI_ICON_B64@@                          assets/tray-icon-cli.png  (the terminal tray)
import { readFileSync, writeFileSync, existsSync } from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const SRC = path.join(ROOT, "src")

// a file is its text plus one final newline; joining files puts one newline between them
const read = (rel) => {
  const text = readFileSync(path.join(SRC, rel), "utf8").replace(/\r\n/g, "\n")      // a checkout with CRLF must build the same file
  return text.endsWith("\n") ? text.slice(0, -1) : text
}
const join = (files) => files.map(read).join("\n")
// non-ASCII characters become \uXXXX so run.ps1 stays plain ASCII: Windows PowerShell 5.1 misreads UTF-8 files without a BOM
const ascii = (text) => text.replace(/[^\x00-\x7f]/g, (c) => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"))
// String.replace would read "$&" in the replacement; a function never does
const fill = (text, marker, value) => {
  if (!text.includes(marker)) throw new Error(`placeholder ${marker} not found`)
  return text.replace(marker, () => value)
}

// The terminal version is the same engine as the tray version, cut before the tray, with stand-ins for Electron and its own settings,
// WARP account and proxy port (two clients with one WireGuard key kick each other out).
export function cliSource(boot, shim, main) {
  const mark = "// ---------------------------------------------------------------- tray menu"
  let head = boot.slice(0, boot.indexOf(mark))
  head = head.replace('import { app, Tray, Menu, Notification, shell, dialog, nativeImage } from "electron"', () => shim)
  const a = head.indexOf("// The app keeps the free-limit time")
  const b = head.indexOf("// ---------------------------------------------------------------- settings (proxy.json)")
  if (a >= 0 && b > a) head = head.slice(0, a) + head.slice(b)                    // that part is for the desktop app's database
  head = head.replaceAll('"proxy.json"', '"cli.json"').replaceAll("cfg.gatePort", "cfg.cliGatePort").replaceAll('"account.json"', '"account-cli.json"')
  const c = head.lastIndexOf('if (cfg.mode === "wg" || cfg.mode === "wgfile" || cfg.mode === "free") {')
  if (c >= 0) head = head.slice(0, c)                                              // the terminal brings the connection up itself
  return head + main
}

// every piece of the result: the JavaScript parts (boot = the desktop patch, shim + main = the terminal) and the whole PowerShell script
export function parts() {
  const manifest = JSON.parse(readFileSync(path.join(SRC, "manifest.json"), "utf8"))

  // the app's languages
  const appLangs = manifest.languages.map((code) => read(`i18n/app/${code}.js`)).join("\n")
  let boot = join(manifest.boot)
  boot = fill(boot, "@@APP_LANGS@@", appLangs)
  const trayIcon = readFileSync(path.join(ROOT, "assets", "tray-icon.png")).toString("base64")
  const cliIcon = readFileSync(path.join(ROOT, "assets", "tray-icon-cli.png")).toString("base64")
  boot = fill(boot, "@@TRAY_ICON_B64@@", trayIcon)
  boot = ascii(boot)

  const shim = ascii(join(manifest.cliShim))
  const main = ascii(join(manifest.cliMain))
  const cli = cliSource(boot, shim, main)
  const tray = fill(read(manifest.cliTray), "@@CLI_ICON_B64@@", cliIcon)

  // the installer's languages
  const installerMessages = {}
  for (const code of manifest.languages) installerMessages[code] = JSON.parse(readFileSync(path.join(SRC, "i18n", "installer", `${code}.json`), "utf8"))
  const b64 = Buffer.from(JSON.stringify(installerMessages), "utf8").toString("base64")

  let out = manifest.installer.map(read).join("\n")
  out = fill(out, "@@INSTALLER_I18N@@", b64)
  out = fill(out, "@@BOOT_JS@@", boot)
  out = fill(out, "@@CLI_SOURCE@@", cli)
  out = fill(out, "@@CLI_TRAY@@", tray)
  out += "\n"
  if (/[^\x00-\x7f]/.test(out)) throw new Error("run.ps1 must be plain ASCII")
  return { boot, shim, main, cli, tray, ps: out }
}

export const build = () => parts().ps

// ---- command line
const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (isMain) {
  const args = process.argv.slice(2)
  const out = build()
  const target = args.includes("--out") ? path.resolve(args[args.indexOf("--out") + 1]) : path.join(ROOT, "run.ps1")
  if (args.includes("--check")) {
    const current = existsSync(target) ? readFileSync(target, "utf8") : ""
    if (current !== out) {
      console.error("run.ps1 is out of date with src/. Run: npm run build")
      process.exit(1)
    }
    console.log(`run.ps1 is up to date (${out.length} bytes)`)
  } else {
    writeFileSync(target, out, { encoding: "ascii" })
    console.log(`wrote ${path.relative(ROOT, target)} (${out.length} bytes, ${out.split("\n").length - 1} lines)`)
  }
}
