// ---------------------------------------------------------------- remove the "subscribe to Go" popup and texts
// (the persistent "Free limit reached" tray is stopped in the app code itself by the patcher)
const stripUpsell = () => {
  window.__ocLimit = (id) => console.log("__OC_LIMIT__" + id)
  if (window.__slipstreamStrip) return
  window.__slipstreamStrip = true
  const upsell = /(subscribe to (opencode )?go|connect a provider or subscribe|\$\s?10\s?\/\s?(month|mo)|assinar o plano go|plano go|conectar um provedor ou assinar|us\$\s?10)/i
  const resetLine = /(resets? at|ser[aá] redefinid[oa]s? [aà]s|redefinid[oa]s? [aà]s)\s*\d/i
  const box = 'dialog,[role="dialog"],[role="alertdialog"],[data-component*="dialog"]'
  const hide = (el) => { if (el && el.style) el.style.setProperty("display", "none", "important") }
  const sweep = () => {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
    const hits = []
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      const t = n.nodeValue
      if (t && t.length < 600 && (upsell.test(t) || resetLine.test(t))) hits.push(n.parentElement)
    }
    for (const el of hits) {
      if (!el || el.dataset.ocHidden) continue
      el.dataset.ocHidden = "1"
      const dlg = el.closest(box)
      if (dlg) {
        document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", code: "Escape", keyCode: 27, bubbles: true }))
        hide(dlg)
        const prev = dlg.previousElementSibling
        if (prev && /overlay|backdrop/i.test(prev.getAttribute("data-component") || prev.className || "")) hide(prev)
      } else hide(el)
    }
  }
  let timer
  new MutationObserver(() => { clearTimeout(timer); timer = setTimeout(sweep, 80) }).observe(document.body, { childList: true, subtree: true, characterData: true })
  sweep()
}
app.on("web-contents-created", (_e, wc) => {
  wc.on("dom-ready", () => { wc.executeJavaScript("(" + stripUpsell.toString() + ")()").catch(() => {}) })
  wc.on("console-message", (...a) => {
    const msg = typeof a[0]?.message === "string" ? a[0].message : a[2]
    if (typeof msg === "string" && msg.startsWith("__OC_LIMIT__")) onLimit(wc)
  })
})

