// Every language must say the same things as English: same messages, same {placeholders}, nothing empty.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import path from "node:path"
import { parts } from "../build/build.mjs"
import { SRC, tempFile } from "./helpers/load.mjs"
import { pathToFileURL } from "node:url"

const manifest = JSON.parse(readFileSync(path.join(SRC, "manifest.json"), "utf8"))
const placeholders = (s) => [...String(s).matchAll(/\{(\w+)\}/g)].map((m) => m[1]).sort().join(",")

function compare(label, en, others) {
  const keys = Object.keys(en)
  for (const [code, dict] of Object.entries(others)) {
    assert.deepEqual(keys.filter((k) => !(k in dict)), [], `${label} ${code}: missing messages`)
    assert.deepEqual(Object.keys(dict).filter((k) => !(k in en)), [], `${label} ${code}: messages that English does not have`)
    for (const k of keys) {
      assert.ok(String(dict[k]).trim().length > 0, `${label} ${code}.${k} is empty`)
      assert.equal(placeholders(dict[k]), placeholders(en[k]), `${label} ${code}.${k}: placeholders differ from English`)
    }
  }
}

test("the installer messages are complete in every language", () => {
  const all = Object.fromEntries(manifest.languages.map((c) => [c, JSON.parse(readFileSync(path.join(SRC, "i18n", "installer", `${c}.json`), "utf8"))]))
  const { en, ...others } = all
  compare("installer", en, others)
  assert.equal(Object.keys(others).length, 11)
})

test("the yes-answer of every language is a valid regular expression that accepts y and rejects n", () => {
  for (const c of manifest.languages) {
    const { yes } = JSON.parse(readFileSync(path.join(SRC, "i18n", "installer", `${c}.json`), "utf8"))
    const re = new RegExp(yes)
    assert.ok(re.test("y"), `${c} accepts y`)
    assert.ok(!re.test("n"), `${c} rejects n`)
  }
})

test("the app's menu and messages are complete in every language", async () => {
  // the built boot script holds the dictionary; evaluate just that block
  const boot = parts().boot
  const block = boot.slice(boot.indexOf("const LANGS = {"), boot.indexOf("let langCode"))
  const file = tempFile("langs.mjs", `const cfg = { language: "auto" }\n${block}\nexport { LANGS, pickLang }`)
  const { LANGS, pickLang } = await import(pathToFileURL(file).href)
  assert.deepEqual(Object.keys(LANGS), manifest.languages)
  const strip = ({ name, ...messages }) => messages          // the language's own name is the one entry that differs
  const { en, ...others } = LANGS
  compare("app", strip(en), Object.fromEntries(Object.entries(others).map(([c, d]) => [c, strip(d)])))
  for (const [code, l] of Object.entries(LANGS)) assert.ok(l.name, `${code} has a name`)

  // system language -> one of ours
  const want = { "pt-BR": "pt-BR", "pt-PT": "pt-BR", "en-US": "en", "zh-TW": "zh-CN", "es-419": "es", "fr-CA": "fr", "ar-SA": "ar", "hi-IN": "hi", "xx": "en", "it-IT": "en", "": "en" }
  for (const [locale, code] of Object.entries(want)) assert.equal(pickLang(locale), code, locale)
})

test("a message's placeholders are the ones the code passes", () => {
  // the code asks for these variables; a typo in a language file would leave a hole in the sentence
  const known = new Set(["ip", "host", "msg", "mb", "from", "err", "status", "mode", "app"])
  const en = JSON.parse(readFileSync(path.join(SRC, "i18n", "installer", "en.json"), "utf8"))
  for (const v of Object.values(en)) for (const name of placeholders(v).split(",").filter(Boolean)) assert.ok(new Set([...known, "n", "v", "dir", "v2", "v1"]).has(name), name)
})
