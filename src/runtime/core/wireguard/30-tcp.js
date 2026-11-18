class WgTcp extends Duplex {
  constructor(wg, dstIp, dstPort, synTries = 5) {
    super({ allowHalfOpen: true })
    this.wg = wg; this.dst = dstIp; this.dport = dstPort; this.sport = wg.allocPort()
    this.local = dstIp.length === 16 ? wg.addr6 : wg.addr
    this.maxMss = wg.mtu - (dstIp.length === 16 ? 60 : 40)       // MTU minus IP and TCP headers
    this.iss = crypto.randomBytes(4).readUInt32BE(0)
    this.sndUna = this.iss; this.sndNxt = (this.iss + 1) >>> 0
    this.rcvNxt = 0; this.peerWnd = 65535; this.mss = this.maxMss
    this.state = "syn"; this.out = []; this.outBytes = 0; this.inflight = []; this.ooo = new Map(); this.finSent = false; this.ending = false
    this.drainCb = null; this.tries = 0
    wg.tcp.set(this.sport, this)
    this.sendSeg(TCP_SYN, this.iss, NOTHING, this.maxMss)
    this.synTimer = setInterval(() => {
      if (this.state !== "syn") return clearInterval(this.synTimer)
      if (++this.tries >= synTries) return this.destroy(new Error("connect timed out through the tunnel"))
      this.sendSeg(TCP_SYN, this.iss, NOTHING, this.maxMss)
    }, 1500)
    this.rtoTimer = setInterval(() => this.retransmit(), 400)
  }
  sendSeg(flags, seq, data = NOTHING, mss = 0) {
    const seg = tcpSegment(this.local, this.dst, this.sport, this.dport, seq, flags & TCP_ACK ? this.rcvNxt : 0, flags, 65535, data, mss)
    this.wg.sendIp(buildIp(6, this.local, this.dst, seg))
  }
  ackNow() { this.sendSeg(TCP_ACK, this.sndNxt) }
  _read() {}
  _write(chunk, _enc, cb) {
    this.out.push(chunk); this.outBytes += chunk.length
    this.pump()
    if (this.outBytes < 256 * 1024) cb(); else this.drainCb = cb
  }
  _final(cb) { this.ending = true; this.pump(); cb() }
  pump() {
    if (this.state !== "est" && this.state !== "closeWait") return
    const flight = () => (this.sndNxt - this.sndUna) >>> 0
    const room = () => Math.min(this.peerWnd, 48 * 1024) - flight()
    while (this.outBytes > 0 && room() > 0) {
      let want = Math.min(this.mss, room(), this.outBytes)
      const parts = []
      while (want > 0) {
        const head = this.out[0]
        if (head.length <= want) { parts.push(head); want -= head.length; this.out.shift() }
        else { parts.push(head.subarray(0, want)); this.out[0] = head.subarray(want); want = 0 }
      }
      const data = Buffer.concat(parts)
      this.outBytes -= data.length
      const seg = { seq: this.sndNxt, data, sentAt: Date.now(), tries: 0 }
      this.inflight.push(seg); this.sndNxt = (this.sndNxt + data.length) >>> 0
      this.sendSeg(TCP_ACK | TCP_PSH, seg.seq, data)
    }
    if (this.drainCb && this.outBytes < 128 * 1024) { const cb = this.drainCb; this.drainCb = null; cb() }
    if (this.ending && !this.finSent && this.outBytes === 0) {
      this.finSent = true
      this.inflight.push({ seq: this.sndNxt, data: NOTHING, fin: true, sentAt: Date.now(), tries: 0 })
      this.sendSeg(TCP_ACK | TCP_FIN, this.sndNxt)
      this.sndNxt = (this.sndNxt + 1) >>> 0
    }
  }
  retransmit() {
    const now = Date.now()
    for (const seg of this.inflight) {
      const rto = Math.min(1000 * 2 ** seg.tries, 8000)
      if (now - seg.sentAt < rto) break
      if (++seg.tries > 8) return this.destroy(new Error("tunnel stopped answering"))
      seg.sentAt = now
      this.sendSeg(TCP_ACK | (seg.fin ? TCP_FIN : TCP_PSH), seg.seq, seg.data)
      break
    }
  }
  onSegment(h, data) {
    const flags = h.flags
    if (flags & TCP_RST) return this.destroy(new Error("connection reset by the remote host"))
    if (this.state === "syn") {
      if ((flags & (TCP_SYN | TCP_ACK)) === (TCP_SYN | TCP_ACK) && h.ack === this.sndNxt) {
        this.rcvNxt = (h.seq + 1) >>> 0; this.sndUna = h.ack; this.peerWnd = h.win
        if (h.mss) this.mss = Math.min(this.maxMss, h.mss)
        this.state = "est"; clearInterval(this.synTimer)
        this.ackNow(); this.emit("tunnel-connect"); this.pump()
      }
      return
    }
    if (flags & TCP_ACK) {
      this.peerWnd = h.win
      if (seqLt(this.sndUna, h.ack) && seqLe(h.ack, this.sndNxt)) {
        this.sndUna = h.ack
        this.inflight = this.inflight.filter((s) => seqLt(h.ack, (s.seq + Math.max(1, s.data.length)) >>> 0))
      }
      this.pump()
      if (this.finSent && this.inflight.length === 0 && this.state === "closeWait") return this.close()
    }
    if (data.length || flags & TCP_FIN) {
      let seq = h.seq
      if (seqLt(seq, this.rcvNxt)) {                 // partly or fully old: keep what is new
        const skip = (this.rcvNxt - seq) >>> 0
        if (skip >= data.length && !(flags & TCP_FIN && skip === data.length)) return this.ackNow()
        data = data.subarray(Math.min(skip, data.length)); seq = this.rcvNxt
      }
      if (seq === this.rcvNxt) {
        if (data.length) { this.rcvNxt = (this.rcvNxt + data.length) >>> 0; this.push(data) }
        if (flags & TCP_FIN) this.gotFin()
        while (this.ooo.has(this.rcvNxt)) {
          const next = this.ooo.get(this.rcvNxt); this.ooo.delete(this.rcvNxt)
          this.rcvNxt = (this.rcvNxt + next.length) >>> 0; this.push(next)
        }
      } else if (this.ooo.size < 64) this.ooo.set(seq, Buffer.from(data))
      this.ackNow()
    }
  }
  gotFin() {
    if (this.state === "closeWait") return
    this.rcvNxt = (this.rcvNxt + 1) >>> 0
    this.state = "closeWait"
    this.push(null)
  }
  close() { clearInterval(this.rtoTimer); clearInterval(this.synTimer); this.wg.tcp.delete(this.sport); this.wg.ports.delete(this.sport) }
  _destroy(err, cb) {
    if (this.state !== "syn" || err) { try { this.sendSeg(TCP_RST | TCP_ACK, this.sndNxt) } catch {} }
    this.close(); cb(err)
  }
}

