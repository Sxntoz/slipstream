// run.ps1 is generated. These tests make sure what is committed is what the sources give, and that it is sound.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync, existsSync } from "node:fs"
import path from "node:path"
import { parts } from "../build/build.mjs"
import { ROOT, SRC, syntaxError, pwsh } from "./helpers/load.mjs"
import { spawnSync } from "node:child_process"

const built = parts()

test("run.ps1 on disk is exactly what src/ builds (run: npm run build)", () => {
  assert.equal(readFileSync(path.join(ROOT, "run.ps1"), "utf8"), built.ps)
})

test("run.ps1 is plain ASCII and has no leftover placeholders", () => {
  assert.ok(!/[^\x00-\x7f]/.test(built.ps), "non-ASCII character (Windows PowerShell 5.1 reads BOM-less UTF-8 as ANSI)")
  assert.ok(!built.ps.includes("@@"), "an @@placeholder@@ was not filled")
  assert.ok(!built.ps.includes("\r"), "line ends must be LF")
})

test("every file named in the manifest exists, and every source file is in the manifest", () => {
  const m = JSON.parse(readFileSync(path.join(SRC, "manifest.json"), "utf8"))
  const listed = [...m.installer, ...m.boot, ...m.cliShim, ...m.cliMain]
  for (const f of listed) assert.ok(existsSync(path.join(SRC, f)), `missing ${f}`)
  assert.equal(new Set(listed).size, listed.length, "a file is listed twice")
  for (const code of m.languages) {
    assert.ok(existsSync(path.join(SRC, "i18n", "app", `${code}.js`)), `app language ${code}`)
    assert.ok(existsSync(path.join(SRC, "i18n", "installer", `${code}.json`)), `installer language ${code}`)
  }
})

test("the desktop patch (boot) is valid JavaScript", () => {
  assert.equal(syntaxError(built.boot, "boot.mjs"), null)
})

test("the terminal parts (shim, main) are valid JavaScript", () => {
  assert.equal(syntaxError(built.shim, "shim.mjs"), null)
  assert.equal(syntaxError(built.main, "main.mjs"), null)
})

test("run.ps1 parses as PowerShell", { skip: !pwsh && "pwsh is not installed" }, () => {
  const script = `$e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile('${path.join(ROOT, "run.ps1")}',[ref]$null,[ref]$e); $e.Count`
  const r = spawnSync("pwsh", ["-NoProfile", "-Command", script], { encoding: "utf8" })
  assert.equal(r.stdout.trim(), "0", r.stdout + r.stderr)
})
