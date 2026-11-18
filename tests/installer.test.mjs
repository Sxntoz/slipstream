// The installer's own logic, run in PowerShell: the [Y/N] questions and "update without losing anything".
import { test } from "node:test"
import assert from "node:assert/strict"
import path from "node:path"
import { spawnSync } from "node:child_process"
import { ROOT, pwsh } from "./helpers/load.mjs"

const skip = !pwsh && "pwsh is not installed"
const run = (file) => spawnSync("pwsh", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(ROOT, "tests", "ps", file), "-Script", path.join(ROOT, "run.ps1")], { encoding: "utf8" })

test("Ask: understands yes in each language, uses the default on Enter", { skip }, () => {
  const r = run("ask.ps1")
  assert.equal(r.status, 0, r.stdout + r.stderr)
  const rows = r.stdout.split("\n").filter((l) => l.includes("answer="))
  assert.ok(rows.length >= 8)
  for (const row of rows) {
    const m = /answer='(.*?)' default=(\w+) -> (\w+)/.exec(row)
    const [, answer, def, result] = m
    const wantNo = answer === "n" || (answer === "" && def === "False")
    assert.equal(result, wantNo ? "False" : "True", row)
  }
})

test("update safety: a changed or missing file is put back from the backup", { skip }, () => {
  const r = run("restore.ps1")
  assert.equal(r.status, 0, r.stdout + r.stderr)
  assert.match(r.stdout, /nada mudou\s+-> Test-Data = True/)
  assert.match(r.stdout, /um mudou, outro sumiu -> Test-Data = False/)
  assert.match(r.stdout, /chats\.db restaurado : conversa importante/)
  assert.match(r.stdout, /auth\.json restaurado: \{"key":"segredo"\}/)
})
