class UserWireGuard {
  // opts: { priv, peerKey (base64), psk? (base64), endpoint "host:port", v4?, v6?, dns? ("1.1.1.1"), mtu? (1280), preferV6? (true) }
  constructor(opts) {
    this.opts = opts
    this.sPriv = Buffer.from(opts.priv, "base64"); this.sPub = x25519(this.sPriv, X_BASE)
    this.rPub = Buffer.from(opts.peerKey, "base64")
    this.psk = opts.psk ? Buffer.from(opts.psk, "base64") : Buffer.alloc(32)
    this.addr = opts.v4 ? ip4(opts.v4) : null
    this.addr6 = opts.v6 ? ip6(opts.v6) : null
    this.mtu = opts.mtu || 1280
    this.dns = ip4(opts.dns || "1.1.1.1")
    this.preferV6 = opts.preferV6 !== false
    this.tcp = new Map(); this.udp = new Map(); this.ports = new Set()
    this.session = null; this.prev = null; this.pending = null; this.dnsCache = new Map()
  }
  allocPort() { for (;;) { const p = 20000 + crypto.randomInt(40000); if (!this.ports.has(p) && !this.tcp.has(p) && !this.udp.has(p)) { this.ports.add(p); return p } } }
  async start() {
    const [host, port] = this.opts.endpoint.split(":")
    const { address } = await dnsLookup(host, { family: 4 })
    this.remote = { address, port: Number(port || 2408) }
    this.sock = dgram.createSocket("udp4")
    this.sock.on("message", (m) => { try { this.onUdp(m) } catch {} })
    this.sock.on("error", () => {})
    await new Promise((res) => this.sock.bind(0, res))
    let lastErr = new Error("no handshake answer")
    for (let attempt = 0; attempt < 4 && !this.session; attempt++) {
      await this.handshake().catch((e) => (lastErr = e))
    }
    if (!this.session) { this.stop(); throw new Error("WireGuard handshake failed: " + lastErr.message + " (is UDP " + this.remote.port + " blocked?)") }
    this.keep = setInterval(() => this.send(NOTHING), 20000)                       // keep-alive
    this.rekey = setInterval(() => this.handshake().catch(() => {}), 100000)        // WireGuard replaces keys every 2 minutes
  }
  stop() {
    clearInterval(this.keep); clearInterval(this.rekey)
    for (const t of [...this.tcp.values()]) t.destroy()
    try { this.sock?.close() } catch {}
    this.session = null
  }
  handshake() {
    return new Promise((resolve, reject) => {
      const index = crypto.randomBytes(4).readUInt32LE(0)
      let C = WG_C0, H = wgHash(WG_H0, this.rPub)
      const ePriv = crypto.randomBytes(32), ePub = x25519(ePriv, X_BASE)
      C = kdf1(C, ePub); H = wgHash(H, ePub)
      let k; [C, k] = kdf2(C, x25519(ePriv, this.rPub))
      const encS = aeadSeal(k, 0, this.sPub, H); H = wgHash(H, encS);
      [C, k] = kdf2(C, x25519(this.sPriv, this.rPub))
      const encT = aeadSeal(k, 0, tai64n(), H); H = wgHash(H, encT)
      const msg = Buffer.alloc(148)
      msg[0] = 1; msg.writeUInt32LE(index, 4); ePub.copy(msg, 8); encS.copy(msg, 40); encT.copy(msg, 88)
      blake2s(msg.subarray(0, 116), 16, wgHash(Buffer.from("mac1----"), this.rPub)).copy(msg, 116)
      const done = (err) => { clearTimeout(timer); this.pending = null; err ? reject(err) : resolve() }
      const timer = setTimeout(() => done(new Error("no answer from the WireGuard server")), 5000)
      this.pending = { index, C, H, ePriv, done }
      this.sock.send(msg, this.remote.port, this.remote.address)
    })
  }
  onUdp(m) {
    const type = m[0]
    if (type === 2 && m.length === 92 && this.pending && m.readUInt32LE(8) === this.pending.index) {
      const p = this.pending
      let { C, H } = p
      const er = m.subarray(12, 44)
      C = kdf1(C, er); H = wgHash(H, er)
      C = kdf1(C, x25519(p.ePriv, er)); C = kdf1(C, x25519(this.sPriv, er))
      const [c3, tau, k] = kdf3(C, this.psk); C = c3
      H = wgHash(H, tau)
      try { aeadOpen(k, 0, m.subarray(44, 60), H) } catch { return p.done(new Error("handshake answer failed its check")) }
      const [send, recv] = kdf2(C, NOTHING)
      this.prev = this.session
      this.session = { send, recv, counter: 0, theirIndex: m.readUInt32LE(4), at: Date.now() }
      p.done()
      this.send(NOTHING)
    } else if (type === 4 && m.length >= 32) {
      const counter = Number(m.readBigUInt64LE(8)), body = m.subarray(16)
      let pt
      for (const s of [this.session, this.prev]) {
        if (!s) continue
        try { pt = aeadOpen(s.recv, counter, body, NOTHING); break } catch {}
      }
      if (!pt || pt.length < 20) return
      const len = (pt[0] >> 4) === 6 ? 40 + pt.readUInt16BE(4) : pt.readUInt16BE(2)
      this.onIp(pt.subarray(0, Math.min(pt.length, len)))
    }
  }
  send(plain) {
    const s = this.session
    if (!s) return
    const padded = Buffer.alloc(Math.ceil(plain.length / 16) * 16); plain.copy(padded)
    const hdr = Buffer.alloc(16); hdr[0] = 4; hdr.writeUInt32LE(s.theirIndex, 4); hdr.writeBigUInt64LE(BigInt(s.counter), 8)
    this.sock.send(Buffer.concat([hdr, aeadSeal(s.send, s.counter++, padded, NOTHING)]), this.remote.port, this.remote.address)
  }
  sendIp(pkt) { this.send(pkt) }
  onIp(p) {
    const ver = p[0] >> 4
    let proto, pl
    if (ver === 4) { proto = p[9]; pl = p.subarray((p[0] & 15) * 4) }
    else if (ver === 6) { proto = p[6]; pl = p.subarray(40) }       // extension headers are not used by the servers we talk to
    else return
    if (proto === 6 && pl.length >= 20) {
      const conn = this.tcp.get(pl.readUInt16BE(2))
      if (!conn) return
      const off = (pl[12] >> 4) * 4
      let mss = 0
      for (let i = 20; i + 3 < off;) { const kind = pl[i]; if (kind === 0) break; if (kind === 1) { i++; continue } if (kind === 2) mss = pl.readUInt16BE(i + 2); i += pl[i + 1] || 1 }
      conn.onSegment({ seq: pl.readUInt32BE(4), ack: pl.readUInt32BE(8), flags: pl[13], win: pl.readUInt16BE(14), mss }, pl.subarray(off))
    } else if (proto === 17 && pl.length >= 8) {
      const h = this.udp.get(pl.readUInt16BE(2))
      if (h) h(pl.subarray(8))
    }
  }
  // One DNS question through the tunnel (over IPv4 UDP to the tunnel's DNS server); returns the raw answers of that type.
  async dnsQuery(name, qtype) {
    if (!this.addr) throw new Error("this tunnel has no IPv4 address for DNS")
    const sport = this.allocPort(), id = crypto.randomBytes(2)
    const labels = name.split(".").map((l) => Buffer.concat([Buffer.from([l.length]), Buffer.from(l)]))
    const q = Buffer.concat([id, Buffer.from([1, 0, 0, 1, 0, 0, 0, 0, 0, 0]), ...labels, Buffer.from([0, qtype >> 8, qtype & 255, 0, 1])])
    const answer = await new Promise((resolve, reject) => {
      let tries = 0, timer
      const fire = () => {
        if (++tries > 3) { this.udp.delete(sport); this.ports.delete(sport); return reject(new Error("DNS through the tunnel timed out for " + name)) }
        this.sendIp(buildIp(17, this.addr, this.dns, udpDatagram(this.addr, this.dns, sport, 53, q)))
        timer = setTimeout(fire, 2000)
      }
      this.udp.set(sport, (data) => { if (data.subarray(0, 2).equals(id)) { clearTimeout(timer); this.udp.delete(sport); this.ports.delete(sport); resolve(data) } })
      fire()
    })
    let pos = 12
    for (let i = 0; i < answer.readUInt16BE(4); i++) { while (answer[pos] !== 0) pos += (answer[pos] & 0xc0) === 0xc0 ? 1 : answer[pos] + 1; pos += 5 }
    const found = []
    for (let i = 0; i < answer.readUInt16BE(6); i++) {
      while (answer[pos] !== 0 && (answer[pos] & 0xc0) !== 0xc0) pos += answer[pos] + 1
      pos += (answer[pos] & 0xc0) === 0xc0 ? 2 : 1
      const type = answer.readUInt16BE(pos), len = answer.readUInt16BE(pos + 8)
      if (type === qtype) found.push(Buffer.from(answer.subarray(pos + 10, pos + 10 + len)))
      pos += 10 + len
    }
    return found
  }
  // { v4, v6 } addresses (Buffers) of a name; literal addresses are returned as they are.
  async resolve(name) {
    if (/^\d+\.\d+\.\d+\.\d+$/.test(name)) return { v4: ip4(name) }
    if (name.includes(":")) return { v6: ip6(name) }
    const hit = this.dnsCache.get(name)
    if (hit && hit.until > Date.now()) return hit.r
    const [a, aaaa] = await Promise.all([this.dnsQuery(name, 1).catch(() => []), this.addr6 ? this.dnsQuery(name, 28).catch(() => []) : []])
    const r = { v4: a.find((x) => x.length === 4), v6: aaaa.find((x) => x.length === 16) }
    if (!r.v4 && !r.v6) throw new Error("no address for " + name)
    this.dnsCache.set(name, { r, until: Date.now() + 60000 })
    return r
  }
  tcpTo(ip, port, synTries) {
    const t = new WgTcp(this, ip, port, synTries)
    return new Promise((res, rej) => { t.once("tunnel-connect", () => res(t)); t.once("error", rej); t.once("close", () => rej(new Error("closed"))) })
  }
  // A TCP stream through the tunnel. IPv6 first when the host has it and the tunnel does (then IPv4 as a fallback).
  async connect(host, port) {
    if (!this.session) throw new Error("the WireGuard tunnel is down")
    const r = await this.resolve(host)
    const v6 = this.addr6 && r.v6, v4 = this.addr && r.v4
    const order = this.preferV6 ? [v6, v4] : [v4, v6]
    let lastErr = new Error("no usable address for " + host)
    for (const ip of order) {
      if (!ip) continue
      try { return await this.tcpTo(ip, port, order.filter(Boolean).length > 1 ? 2 : 5) } catch (e) { lastErr = e }
    }
    throw lastErr
  }
}

