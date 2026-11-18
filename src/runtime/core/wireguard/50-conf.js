// ---- WireGuard .conf import (Route64, ProtonVPN, Mullvad, your own server...)
function parseWgConf(text) {
  const out = { addrs: [] }
  let section = "", peers = 0
  for (let line of String(text).split(/\r?\n/)) {
    line = line.replace(/[#;].*$/, "").trim()
    if (!line) continue
    const sec = /^\[(\w+)\]$/.exec(line)
    if (sec) { section = sec[1].toLowerCase(); if (section === "peer") peers++; continue }
    const kv = /^(\w+)\s*=\s*(.*)$/.exec(line)
    if (!kv) continue
    const key = kv[1].toLowerCase(), val = kv[2].trim()
    if (section === "interface") {
      if (key === "privatekey") out.priv = val
      else if (key === "address") out.addrs.push(...val.split(",").map((x) => x.trim().split("/")[0]))
      else if (key === "dns") out.dns = val.split(",").map((x) => x.trim()).find((x) => /^\d+\.\d+\.\d+\.\d+$/.test(x))
      else if (key === "mtu") out.mtu = Number(val)
    } else if (section === "peer" && peers === 1) {          // the first peer only
      if (key === "publickey") out.peerKey = val
      else if (key === "presharedkey") out.psk = val
      else if (key === "endpoint") out.endpoint = val.replace(/^\[(.*)\]:(\d+)$/, "$1:$2")
    }
  }
  out.v4 = out.addrs.find((a) => /^\d+\.\d+\.\d+\.\d+$/.test(a))
  out.v6 = out.addrs.find((a) => a.includes(":"))
  if (!out.priv || !out.peerKey || !out.endpoint || !(out.v4 || out.v6)) throw new Error("this WireGuard file needs PrivateKey, Address, and a [Peer] with PublicKey and Endpoint")
  return out
}

