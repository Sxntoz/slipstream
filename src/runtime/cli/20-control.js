// ---- a small local control port, so "slipstream ip" in another terminal changes the IP of the running session
function startControl() {
  const token = crypto.randomBytes(16).toString("hex")
  const srv = net.createServer((c) => {
    let buf = ""
    c.on("error", () => {})
    c.on("data", async (d) => {
      buf += d
      if (!buf.includes("\n")) return
      let req
      try { req = JSON.parse(buf) } catch { return c.end() }
      if (req.token !== token) return c.end("denied\n")
      cfg = loadCfg()
      let out
      try {
        if (req.cmd === "ip") out = await newIp()
        else if (req.cmd === "status") out = await status()
        else if (req.cmd === "mode") out = await switchMode(req.args?.[0])
        else out = "unknown command"
      } catch (e) { out = why(e) }
      c.end(String(out) + "\n")
    })
  })
  srv.listen(0, "127.0.0.1", () => writeFileSync(ctlFile, JSON.stringify({ port: srv.address().port, token, pid: process.pid })))
  process.on("exit", () => { try { rmSync(ctlFile, { force: true }) } catch {} })
}

