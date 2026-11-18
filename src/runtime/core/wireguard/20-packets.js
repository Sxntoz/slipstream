// ---- IPv4 / IPv6 / TCP / UDP packets
const ip4 = (s) => Buffer.from(s.split(".").map(Number))
function ip6(s) {
  s = s.split("%")[0]
  const [head, tail = ""] = s.split("::")
  const h = head ? head.split(":") : [], t = tail ? tail.split(":") : []
  const groups = s.includes("::") ? [...h, ...Array(8 - h.length - t.length).fill("0"), ...t] : h
  const b = Buffer.alloc(16)
  groups.forEach((g, i) => b.writeUInt16BE(parseInt(g || "0", 16), i * 2))
  return b
}
const ipText = (b) => (b.length === 4 ? [...b].join(".") : Array.from({ length: 8 }, (_, i) => b.readUInt16BE(i * 2).toString(16)).join(":"))
function checksum(buf, init = 0) {
  let sum = init
  for (let i = 0; i + 1 < buf.length; i += 2) sum += buf.readUInt16BE(i)
  if (buf.length & 1) sum += buf[buf.length - 1] << 8
  while (sum > 0xffff) sum = (sum & 0xffff) + (sum >>> 16)
  return ~sum & 0xffff
}
let ipId = 1
function buildIp(proto, src, dst, payload) {
  if (src.length === 16) {
    const h = Buffer.alloc(40)
    h[0] = 0x60; h.writeUInt16BE(payload.length, 4); h[6] = proto; h[7] = 64
    src.copy(h, 8); dst.copy(h, 24)
    return Buffer.concat([h, payload])
  }
  const h = Buffer.alloc(20)
  h[0] = 0x45; h.writeUInt16BE(20 + payload.length, 2); h.writeUInt16BE(ipId++ & 0xffff, 4); h.writeUInt16BE(0x4000, 6); h[8] = 64; h[9] = proto
  src.copy(h, 12); dst.copy(h, 16); h.writeUInt16BE(checksum(h), 10)
  return Buffer.concat([h, payload])
}
function pseudo(src, dst, proto, len) {
  if (src.length === 16) { const p = Buffer.alloc(40); src.copy(p, 0); dst.copy(p, 16); p.writeUInt32BE(len, 32); p[39] = proto; return p }
  const p = Buffer.alloc(12); src.copy(p, 0); dst.copy(p, 4); p[9] = proto; p.writeUInt16BE(len, 10); return p
}
function tcpSegment(src, dst, sport, dport, seq, ack, flags, win, data = NOTHING, mss = 0) {
  const opt = mss ? Buffer.from([2, 4, mss >> 8, mss & 255]) : NOTHING
  const h = Buffer.alloc(20 + opt.length + data.length)
  h.writeUInt16BE(sport, 0); h.writeUInt16BE(dport, 2); h.writeUInt32BE(seq >>> 0, 4); h.writeUInt32BE(ack >>> 0, 8)
  h[12] = ((20 + opt.length) / 4) << 4; h[13] = flags; h.writeUInt16BE(win, 14)
  opt.copy(h, 20); data.copy(h, 20 + opt.length)
  h.writeUInt16BE(checksum(h, ~checksum(pseudo(src, dst, 6, h.length)) & 0xffff), 16)
  return h
}
function udpDatagram(src, dst, sport, dport, data) {
  const h = Buffer.alloc(8 + data.length)
  h.writeUInt16BE(sport, 0); h.writeUInt16BE(dport, 2); h.writeUInt16BE(h.length, 4); data.copy(h, 8)
  const c = checksum(h, ~checksum(pseudo(src, dst, 17, h.length)) & 0xffff)
  h.writeUInt16BE(c || 0xffff, 6)
  return h
}

const TCP_FIN = 1, TCP_SYN = 2, TCP_RST = 4, TCP_PSH = 8, TCP_ACK = 16
const seqLt = (a, b) => ((a - b) | 0) < 0
const seqLe = (a, b) => ((a - b) | 0) <= 0

