
// ================================================================ terminal commands
import { spawn } from "node:child_process"

const argv = process.argv.slice(2)
const ctlFile = path.join(stateDir, "cli-control.json")      // { port, token } of the running session, for "slipstream ip" from another terminal
const print = (m) => console.log(m)

const HELP = `Slipstream for the terminal

  slipstream opencode [args]     run OpenCode through Slipstream   (also: opencode1 = v1, opencode2 = v2)
  slipstream run <program> ...   run any program through it
  slipstream ip                  new IP (use it from a second terminal while a session is running)
  slipstream status              the IP in use
  slipstream mode <name>         direct | wg | wgfile | free | list
  slipstream wgfile <file.conf>  use a WireGuard file (Route64, Proton, Mullvad, your server...)
  slipstream proxy add <url>     add to your proxy list (http://user:pass@host:port, socks5://host:port)
  slipstream proxy list          show the list and the file
  slipstream context <provider/model> <tokens>   e.g. opencode/deepseek-v4.1-flash-free 1000000
  slipstream lang <code|auto>    ${Object.keys(LANGS).join(", ")}
  slipstream clear login|restore|cache    login (auth.json, backed up first), put it back, cache and logs. Chats are kept.

  With "opencode run ..." (not the interactive screen) a free-limit error changes the IP by itself and runs it again.
  In the interactive screen run "slipstream ip" in another terminal when the limit stops you, then send your message again.`

