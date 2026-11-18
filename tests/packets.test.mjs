// The tunnel carries its own IPv4/IPv6/TCP/UDP packets, so their headers and checksums have to be exactly right.
import { test } from "node:test"
import assert from "node:assert/strict"
import { loadFragments } from "./helpers/load.mjs"

const lib = await loadFragments(
  ["runtime/core/wireguard/10-crypto.js", "runtime/core/wireguard/20-packets.js", "runtime/core/wireguard/50-conf.js"],
  ["ip4", "ip6", "ipText", "checksum", "buildIp", "tcpSegment", "udpDatagram", "pseudo", "seqLt", "seqLe", "parseWgConf"],
)
const hex = (b) => Buffer.from(b).toString("hex")

test("IPv6 text is parsed with :: in any place", () => {
  assert.equal(hex(lib.ip6("::1")), "00000000000000000000000000000001")
  assert.equal(hex(lib.ip6("fe80::")), "fe800000000000000000000000000000")
  assert.equal(hex(lib.ip6("2606:4700:110:81ee:2f4f:bae7:4719:92ff")), "26064700011081ee2f4fbae7471992ff")
  assert.equal(hex(lib.ip6("2001:db8::8:800:200c:417a")), "20010db80000000000080800200c417a")
  assert.equal(hex(lib.ip6("fe80::1%12")), "fe800000000000000000000000000001")        // a zone id is ignored
})

test("addresses go to text and back", () => {
  assert.equal(lib.ipText(lib.ip4("172.16.0.2")), "172.16.0.2")
  assert.equal(hex(lib.ip4("1.2.3.4")), "01020304")
  assert.equal(lib.ipText(lib.ip6("2606:4700::1111")), "2606:4700:0:0:0:0:0:1111")
})

test("the Internet checksum matches the RFC 1071 / textbook IPv4 header", () => {
  const header = Buffer.from("450000730000400040110000c0a80001c0a800c7", "hex")      // checksum field zeroed
  assert.equal(lib.checksum(header), 0xb861)
})

test("an IPv4 packet has a valid header checksum and the right length", () => {
  const payload = Buffer.from("hello")
  const pkt = lib.buildIp(17, lib.ip4("172.16.0.2"), lib.ip4("1.1.1.1"), payload)
  assert.equal(pkt[0], 0x45)
  assert.equal(pkt.readUInt16BE(2), 20 + payload.length)
  assert.equal(pkt[9], 17)
  assert.equal(lib.checksum(pkt.subarray(0, 20)), 0, "a header with its checksum sums to zero")
})

test("an IPv6 packet has version 6, the payload length and both addresses", () => {
  const src = lib.ip6("2606:4700:110:81ee::2"), dst = lib.ip6("2606:4700::6810:7b60"), payload = Buffer.from("data!")
  const pkt = lib.buildIp(6, src, dst, payload)
  assert.equal(pkt[0] >> 4, 6)
  assert.equal(pkt.readUInt16BE(4), payload.length)
  assert.equal(pkt[6], 6)
  assert.equal(hex(pkt.subarray(8, 24)), hex(src))
  assert.equal(hex(pkt.subarray(24, 40)), hex(dst))
})

const verifies = (src, dst, proto, segment) => {
  // the checksum of pseudo-header + segment (with its checksum in place) must be zero
  const sum = Buffer.concat([lib.pseudo(src, dst, proto, segment.length), segment])
  return lib.checksum(sum) === 0
}

test("TCP checksums verify over IPv4 and IPv6, with and without data and options", () => {
  for (const [src, dst] of [[lib.ip4("172.16.0.2"), lib.ip4("104.16.124.96")], [lib.ip6("2606:4700:110:81ee::2"), lib.ip6("2606:4700::6810:7b60")]]) {
    const syn = lib.tcpSegment(src, dst, 40000, 443, 123456, 0, 2, 65535, Buffer.alloc(0), 1240)
    assert.equal(syn.length, 24, "SYN carries the MSS option")
    assert.ok(verifies(src, dst, 6, syn), "SYN")
    const data = lib.tcpSegment(src, dst, 40000, 443, 1, 2, 24, 65535, Buffer.from("odd length payload"))
    assert.ok(verifies(src, dst, 6, data), "data")
  }
})

test("UDP checksums verify (mandatory over IPv6)", () => {
  for (const [src, dst] of [[lib.ip4("172.16.0.2"), lib.ip4("1.1.1.1")], [lib.ip6("2606:4700:110:81ee::2"), lib.ip6("2606:4700:4700::1111")]]) {
    assert.ok(verifies(src, dst, 17, lib.udpDatagram(src, dst, 50000, 53, Buffer.from("dns query bytes"))))
  }
})

test("TCP sequence numbers compare across the 32-bit wrap", () => {
  assert.ok(lib.seqLt(0xfffffff0, 5))
  assert.ok(!lib.seqLt(5, 0xfffffff0))
  assert.ok(lib.seqLe(7, 7))
})

test("a WireGuard .conf is read: addresses, DNS, MTU, preshared key, first peer only", () => {
  const conf = `
[Interface]
PrivateKey = cHJpdmF0ZQ==   # a comment
Address = 10.0.0.2/32, fd00::2/128
DNS = 9.9.9.9, 2620:fe::fe
MTU = 1380
[Peer]
PublicKey = cGVlcg==
PresharedKey = cHNr
Endpoint = vpn.example.net:51820
AllowedIPs = 0.0.0.0/0
[Peer]
PublicKey = c2Vjb25k
Endpoint = other.example:1`
  const c = lib.parseWgConf(conf)
  assert.equal(c.v4, "10.0.0.2")
  assert.equal(c.v6, "fd00::2")
  assert.equal(c.dns, "9.9.9.9")
  assert.equal(c.mtu, 1380)
  assert.equal(c.psk, "cHNr")
  assert.equal(c.endpoint, "vpn.example.net:51820")
  assert.equal(c.peerKey, "cGVlcg==")
  assert.throws(() => lib.parseWgConf("[Interface]\nAddress = 10.0.0.2/32"), /PrivateKey/)
})
