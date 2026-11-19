// The page function that decides whether a chat can be resumed after a free limit. It must act on the chat that
// failed (not whichever tab is open) and it must never send a draft the user was typing.
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import path from "node:path"
import vm from "node:vm"
import { SRC } from "./helpers/load.mjs"

const source = readFileSync(path.join(SRC, "runtime/boot/30-auto-rotate.js"), "utf8")
const start = source.indexOf("function resumeInPage(")
const end = source.indexOf("\n}\n\nasync function resume", start)
const fnSource = source.slice(start, end + 2)

const page = ({ session = "ses_a", composer = "text", panel = false, tab = true, last = "the original message" } = {}) => {
  const location = { pathname: "/server/x/session/" + session }
  const editor = {
    isConnected: true,
    innerText: composer === "none" ? "" : composer,
    getClientRects: () => [{ width: 1 }],
    focus() { this.focused = true },
  }
  const link = {
    getAttribute: () => "/server/x/session/ses_b",
    click() { location.pathname = "/server/x/session/ses_b" },
  }
  const document = {
    querySelectorAll: (selector) => {
      if (selector.includes("tab-link")) return tab ? [link] : []
      if (selector.includes("user-message-text")) return [{ innerText: last }]
      return []
    },
    querySelector: (selector) => {
      if (selector.includes("session-free-limit")) return panel ? {} : null
      if (selector.includes("contenteditable")) return composer === "none" ? null : editor
      return null
    },
  }
  return { location, document, editor }
}

const run = async (options, session) => {
  const p = page(options)
  const context = vm.createContext({ location: p.location, document: p.document, setTimeout: (fn) => setTimeout(fn, 0) })
  const result = await vm.runInContext(`(${fnSource})`, context)(session)
  return { result, page: p }
}

test("the failed chat is the one that gets the message, even when another tab is open", async () => {
  const { result, page } = await run({ session: "ses_a", composer: "the original message" }, "ses_b")
  assert.equal(result, "text")
  assert.equal(page.location.pathname, "/server/x/session/ses_b")
  assert.ok(page.editor.focused)
})

test("an empty composer gets 'continue', a draft is never sent", async () => {
  assert.equal((await run({ session: "ses_a", composer: "" }, "ses_a")).result, "empty")
  assert.equal((await run({ session: "ses_a", composer: "unrelated draft" }, "ses_a")).result, "draft")
})

test("a free-limit panel blocks the composer and asks for the cache clean-up", async () => {
  assert.equal((await run({ session: "ses_a", panel: true }, "ses_a")).result, "limit")
})

test("a chat whose tab is not open is reported instead of typing somewhere else", async () => {
  assert.equal((await run({ session: "ses_a", tab: false }, "ses_b")).result, "notab")
})
