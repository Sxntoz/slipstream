// ---------------------------------------------------------------- built-in WARP: our own WireGuard, no .exe, no WARP app
// ---------------------------------------------------------------- user-mode WireGuard (all JS: crypto, handshake, IPv4/TCP/UDP, DNS)
// No driver, no .exe, no admin: UDP to the WARP endpoint, and a tiny TCP/IP stack that turns the tunnel into streams.
const B2_IV = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19])
const B2_SIGMA = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15], [14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3],
  [11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4], [7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8],
  [9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13], [2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9],
  [12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11], [13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10],
  [6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5], [10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0],
]
const rotr = (x, n) => ((x >>> n) | (x << (32 - n))) >>> 0
function blake2s(input, outlen = 32, key = Buffer.alloc(0)) {
  const h = new Uint32Array(B2_IV)
  h[0] ^= 0x01010000 ^ (key.length << 8) ^ outlen
  const data = key.length ? Buffer.concat([Buffer.concat([key, Buffer.alloc(64 - key.length)]), input]) : input
  const blocks = Math.max(1, Math.ceil(data.length / 64))
  const v = new Uint32Array(16), m = new Uint32Array(16)
  for (let b = 0; b < blocks; b++) {
    const last = b === blocks - 1
    const blk = Buffer.alloc(64)
    data.copy(blk, 0, b * 64, Math.min(data.length, (b + 1) * 64))
    for (let i = 0; i < 16; i++) m[i] = blk.readUInt32LE(i * 4)
    v.set(h); v.set(B2_IV, 8)
    v[12] ^= last ? data.length : (b + 1) * 64
    if (last) v[14] = ~v[14]
    const G = (a, b2, c, d, x, y) => {
      v[a] = v[a] + v[b2] + x; v[d] = rotr(v[d] ^ v[a], 16)
      v[c] = v[c] + v[d]; v[b2] = rotr(v[b2] ^ v[c], 12)
      v[a] = v[a] + v[b2] + y; v[d] = rotr(v[d] ^ v[a], 8)
      v[c] = v[c] + v[d]; v[b2] = rotr(v[b2] ^ v[c], 7)
    }
    for (let r = 0; r < 10; r++) {
      const s = B2_SIGMA[r]
      G(0, 4, 8, 12, m[s[0]], m[s[1]]); G(1, 5, 9, 13, m[s[2]], m[s[3]]); G(2, 6, 10, 14, m[s[4]], m[s[5]]); G(3, 7, 11, 15, m[s[6]], m[s[7]])
      G(0, 5, 10, 15, m[s[8]], m[s[9]]); G(1, 6, 11, 12, m[s[10]], m[s[11]]); G(2, 7, 8, 13, m[s[12]], m[s[13]]); G(3, 4, 9, 14, m[s[14]], m[s[15]])
    }
    for (let i = 0; i < 8; i++) h[i] ^= v[i] ^ v[i + 8]
  }
  const out = Buffer.alloc(32)
  for (let i = 0; i < 8; i++) out.writeUInt32LE(h[i], i * 4)
  return out.subarray(0, outlen)
}

const wgHash = (...p) => blake2s(Buffer.concat(p))
function wgHmac(key, data) {
  const k = Buffer.concat([key.length > 64 ? wgHash(key) : key, Buffer.alloc(64)]).subarray(0, 64)
  const ik = Buffer.from(k).map((x) => x ^ 0x36), ok = Buffer.from(k).map((x) => x ^ 0x5c)
  return wgHash(ok, wgHash(ik, data))
}
const kdf1 = (key, input) => wgHmac(wgHmac(key, input), Buffer.from([1]))
function kdf2(key, input) { const t0 = wgHmac(key, input), t1 = wgHmac(t0, Buffer.from([1])); return [t1, wgHmac(t0, Buffer.concat([t1, Buffer.from([2])]))] }
function kdf3(key, input) { const [t1, t2] = kdf2(key, input), t0 = wgHmac(key, input); return [t1, t2, wgHmac(t0, Buffer.concat([t2, Buffer.from([3])]))] }

const wgNonce = (n) => { const b = Buffer.alloc(12); b.writeBigUInt64LE(BigInt(n), 4); return b }

// ChaCha20 (RFC 8439)
const rotl = (x, n) => ((x << n) | (x >>> (32 - n))) >>> 0
function chachaBlock(key, counter, nonce) {
  const st = new Uint32Array(16)
  st[0] = 0x61707865; st[1] = 0x3320646e; st[2] = 0x79622d32; st[3] = 0x6b206574
  for (let i = 0; i < 8; i++) st[4 + i] = key.readUInt32LE(i * 4)
  st[12] = counter
  for (let i = 0; i < 3; i++) st[13 + i] = nonce.readUInt32LE(i * 4)
  const x = new Uint32Array(st)
  const qr = (a, b, c, d) => {
    x[a] += x[b]; x[d] = rotl(x[d] ^ x[a], 16); x[c] += x[d]; x[b] = rotl(x[b] ^ x[c], 12)
    x[a] += x[b]; x[d] = rotl(x[d] ^ x[a], 8); x[c] += x[d]; x[b] = rotl(x[b] ^ x[c], 7)
  }
  for (let i = 0; i < 10; i++) { qr(0, 4, 8, 12); qr(1, 5, 9, 13); qr(2, 6, 10, 14); qr(3, 7, 11, 15); qr(0, 5, 10, 15); qr(1, 6, 11, 12); qr(2, 7, 8, 13); qr(3, 4, 9, 14) }
  const out = Buffer.alloc(64)
  for (let i = 0; i < 16; i++) out.writeUInt32LE((x[i] + st[i]) >>> 0, i * 4)
  return out
}
function chachaXor(key, counter, nonce, data) {
  const out = Buffer.alloc(data.length)
  for (let off = 0; off < data.length; off += 64, counter++) {
    const ks = chachaBlock(key, counter, nonce), n = Math.min(64, data.length - off)
    for (let i = 0; i < n; i++) out[off + i] = data[off + i] ^ ks[i]
  }
  return out
}
// Poly1305 (BigInt: simple, and fast enough for tunnel-sized packets)
const P1305 = (1n << 130n) - 5n
const leBig = (b) => { let n = 0n; for (let i = b.length - 1; i >= 0; i--) n = (n << 8n) | BigInt(b[i]); return n }
function poly1305(key, msg) {
  const r = leBig(key.subarray(0, 16)) & 0x0ffffffc0ffffffc0ffffffc0fffffffn, sKey = leBig(key.subarray(16, 32))
  let acc = 0n
  for (let i = 0; i < msg.length; i += 16) {
    const chunk = msg.subarray(i, i + 16)
    acc = ((acc + leBig(chunk) + (1n << BigInt(8 * chunk.length))) * r) % P1305
  }
  const tag = Buffer.alloc(16); let t = (acc + sKey) & ((1n << 128n) - 1n)
  for (let i = 0; i < 16; i++) { tag[i] = Number(t & 255n); t >>= 8n }
  return tag
}
const pad16 = (b) => Buffer.alloc((16 - (b.length % 16)) % 16)
function aeadTag(key, nonce, aad, ct) {
  const polyKey = chachaBlock(key, 0, nonce).subarray(0, 32)
  const lens = Buffer.alloc(16); lens.writeBigUInt64LE(BigInt(aad.length), 0); lens.writeBigUInt64LE(BigInt(ct.length), 8)
  return poly1305(polyKey, Buffer.concat([aad, pad16(aad), ct, pad16(ct), lens]))
}
function aeadSeal(key, counter, plain, aad) {
  const n = wgNonce(counter), ct = chachaXor(key, 1, n, plain)
  return Buffer.concat([ct, aeadTag(key, n, aad, ct)])
}
function aeadOpen(key, counter, data, aad) {
  const n = wgNonce(counter), ct = data.subarray(0, data.length - 16)
  if (!crypto.timingSafeEqual(aeadTag(key, n, aad, ct), data.subarray(data.length - 16))) throw new Error("bad tag")
  return chachaXor(key, 1, n, ct)
}

// X25519 (RFC 7748)
const P25519 = (1n << 255n) - 19n
const mod = (a) => ((a % P25519) + P25519) % P25519
function powmod(b, e) { let r = 1n; b = mod(b); while (e > 0n) { if (e & 1n) r = (r * b) % P25519; b = (b * b) % P25519; e >>= 1n } return r }
const X_BASE = Buffer.concat([Buffer.from([9]), Buffer.alloc(31)])
function x25519(priv, pub) {
  const k = Buffer.from(priv); k[0] &= 248; k[31] &= 127; k[31] |= 64
  const kn = leBig(k), x1 = leBig(pub) & ((1n << 255n) - 1n)
  let x2 = 1n, z2 = 0n, x3 = x1, z3 = 1n, swap = 0n
  for (let t = 254; t >= 0; t--) {
    const kt = (kn >> BigInt(t)) & 1n
    swap ^= kt
    if (swap) { [x2, x3] = [x3, x2]; [z2, z3] = [z3, z2] }
    swap = kt
    const A = x2 + z2, AA = mod(A * A), B = x2 - z2, BB = mod(B * B), E = AA - BB, C = x3 + z3, D = x3 - z3
    const DA = mod(D * A), CB = mod(C * B)
    x3 = mod((DA + CB) * (DA + CB)); z3 = mod(x1 * mod((DA - CB) * (DA - CB)))
    x2 = mod(AA * BB); z2 = mod(E * (AA + 121665n * E))
  }
  if (swap) { [x2, x3] = [x3, x2]; [z2, z3] = [z3, z2] }
  let r = mod(x2 * powmod(z2, P25519 - 2n))
  const out = Buffer.alloc(32)
  for (let i = 0; i < 32; i++) { out[i] = Number(r & 255n); r >>= 8n }
  return out
}
const WG_C0 = wgHash(Buffer.from("Noise_IKpsk2_25519_ChaChaPoly_BLAKE2s"))
const WG_H0 = wgHash(WG_C0, Buffer.from("WireGuard v1 zx2c4 Jason@zx2c4.com"))
const NOTHING = Buffer.alloc(0)

function tai64n() {
  const b = Buffer.alloc(12), ms = Date.now()
  b.writeBigUInt64BE(BigInt(Math.floor(ms / 1000)) + (1n << 62n) + 10n, 0)
  b.writeUInt32BE((ms % 1000) * 1000000, 8)
  return b
}

