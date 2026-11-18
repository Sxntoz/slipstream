// The WireGuard crypto is written in plain JavaScript (the app's Electron has no ChaCha20-Poly1305 in OpenSSL), so it is checked
// against Node's own OpenSSL and against the published test vectors.
import { test } from "node:test"
import assert from "node:assert/strict"
import crypto from "node:crypto"
import { loadFragments } from "./helpers/load.mjs"

const lib = await loadFragments(["runtime/core/wireguard/10-crypto.js"], ["blake2s", "wgHmac", "aeadSeal", "aeadOpen", "x25519", "X_BASE", "kdf2"])
const hex = (b) => Buffer.from(b).toString("hex")

test("BLAKE2s-256 matches the RFC 7693 vector", () => {
  assert.equal(hex(lib.blake2s(Buffer.from("abc"))), "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982")
})

test("BLAKE2s matches OpenSSL for every block boundary", () => {
  for (const n of [0, 1, 31, 32, 63, 64, 65, 127, 128, 129, 1000]) {
    const d = crypto.randomBytes(n)
    assert.equal(hex(lib.blake2s(d)), crypto.createHash("blake2s256").update(d).digest("hex"), `length ${n}`)
  }
})

test("HMAC-BLAKE2s matches OpenSSL", () => {
  for (const kl of [16, 32, 64, 100]) {
    const key = crypto.randomBytes(kl), data = crypto.randomBytes(77)
    assert.equal(hex(lib.wgHmac(key, data)), crypto.createHmac("blake2s256", key).update(data).digest("hex"), `key ${kl}`)
  }
})

test("keyed BLAKE2s-128 (WireGuard's MAC) is the 16-byte keyed hash", () => {
  // a keyed hash is not the plain hash of the same bytes
  const key = crypto.randomBytes(32), data = crypto.randomBytes(100)
  const mac = lib.blake2s(data, 16, key)
  assert.equal(mac.length, 16)
  assert.notEqual(hex(mac), hex(lib.blake2s(data, 16)))
})

test("ChaCha20-Poly1305 matches OpenSSL, both directions", () => {
  for (const n of [0, 1, 15, 16, 17, 63, 64, 65, 1280]) {
    const key = crypto.randomBytes(32), plain = crypto.randomBytes(n), aad = crypto.randomBytes(n % 9), counter = 7000 + n
    const nonce = Buffer.alloc(12); nonce.writeBigUInt64LE(BigInt(counter), 4)
    const c = crypto.createCipheriv("chacha20-poly1305", key, nonce, { authTagLength: 16 })
    c.setAAD(aad, { plaintextLength: n })
    const reference = Buffer.concat([c.update(plain), c.final(), c.getAuthTag()])
    assert.equal(hex(lib.aeadSeal(key, counter, plain, aad)), hex(reference), `seal ${n}`)
    assert.equal(hex(lib.aeadOpen(key, counter, reference, aad)), hex(plain), `open ${n}`)
  }
})

test("a changed byte or a wrong key is rejected", () => {
  const key = crypto.randomBytes(32), sealed = lib.aeadSeal(key, 1, Buffer.from("secret"), Buffer.alloc(0))
  const bent = Buffer.from(sealed); bent[0] ^= 1
  assert.throws(() => lib.aeadOpen(key, 1, bent, Buffer.alloc(0)))
  assert.throws(() => lib.aeadOpen(crypto.randomBytes(32), 1, sealed, Buffer.alloc(0)))
  assert.throws(() => lib.aeadOpen(key, 2, sealed, Buffer.alloc(0)))     // a different counter is a different nonce
})

test("X25519 matches the RFC 7748 vectors", () => {
  const alice = Buffer.from("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a", "hex")
  const bob = Buffer.from("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb", "hex")
  const alicePub = lib.x25519(alice, lib.X_BASE), bobPub = lib.x25519(bob, lib.X_BASE)
  assert.equal(hex(alicePub), "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
  assert.equal(hex(bobPub), "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
  const shared = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
  assert.equal(hex(lib.x25519(alice, bobPub)), shared)
  assert.equal(hex(lib.x25519(bob, alicePub)), shared)
})

test("X25519 agrees with OpenSSL on random keys", () => {
  const a = crypto.generateKeyPairSync("x25519"), b = crypto.generateKeyPairSync("x25519")
  const raw = (k, type) => k.export({ format: "der", type }).subarray(-32)
  const reference = crypto.diffieHellman({ privateKey: a.privateKey, publicKey: b.publicKey })
  assert.equal(hex(lib.x25519(raw(a.privateKey, "pkcs8"), raw(b.publicKey, "spki"))), hex(reference))
})
