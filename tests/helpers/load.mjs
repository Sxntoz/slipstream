// Test helpers. The sources in src/runtime are fragments of one big script, not ES modules, so a test joins the ones it needs,
// adds the imports they expect, and loads the result as a module.
import { mkdtempSync, writeFileSync, readFileSync } from "node:fs"
import { spawnSync } from "node:child_process"
import { tmpdir } from "node:os"
import path from "node:path"
import { pathToFileURL, fileURLToPath } from "node:url"

export const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..")
export const SRC = path.join(ROOT, "src")

const IMPORTS = `import crypto from "node:crypto"
import { Duplex } from "node:stream"
import dgram from "node:dgram"
import { lookup as dnsLookup } from "node:dns/promises"
`

export const tempFile = (name, text) => {
  const file = path.join(mkdtempSync(path.join(tmpdir(), "slipstream-test-")), name)
  writeFileSync(file, text)
  return file
}

/** Joins source fragments, loads them as a module and returns the names asked for. */
export async function loadFragments(files, names) {
  const text = files.map((f) => readFileSync(path.join(SRC, f), "utf8")).join("\n")
  const file = tempFile("fragments.mjs", `${IMPORTS}\n${text}\nexport { ${names.join(", ")} }\n`)
  return import(pathToFileURL(file).href)
}

/** `node --check` on some text; returns null when it parses, otherwise the error text. */
export function syntaxError(text, name = "check.mjs") {
  const r = spawnSync(process.execPath, ["--check", tempFile(name, text)], { encoding: "utf8" })
  return r.status === 0 ? null : r.stderr
}

/** PowerShell 7 if it is installed (tests that need it are skipped otherwise). */
export const pwsh = (() => {
  const r = spawnSync("pwsh", ["-NoProfile", "-Command", "$PSVersionTable.PSVersion.Major"], { encoding: "utf8" })
  return r.status === 0 ? "pwsh" : null
})()
