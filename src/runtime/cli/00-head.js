
// ================================================================ terminal commands
import { spawn } from "node:child_process"
import { openSync, readSync, closeSync } from "node:fs"

const argv = process.argv.slice(2)
const print = (m) => console.log(m)

const HELP = `Slipstream CLI

  slipstream tray                the tray icon (next to the clock) and the agent that keeps the connection for every terminal
  slipstream stop                close the agent and the tray
  slipstream autostart on|off    start the tray with Windows

  slipstream opencode            the OpenCode desktop app
  slipstream cli [args]          OpenCode v2 in this terminal, through Slipstream  (also: opencode cli, opencode2)
  slipstream opencode1 [args]    OpenCode v1 in this terminal
  slipstream run <program> ...   run any program through it
  slipstream ip                  new IP
  slipstream status              the IP in use
  slipstream mode <name>         direct | wg | wgfile | free | list
  slipstream auto                turn auto-rotate on / off
  slipstream wgfile <file.conf>  use a WireGuard file (Route64, Proton, Mullvad, your server...)
  slipstream proxy add <url>     add to your proxy list (http://user:pass@host:port, socks5://host:port)
  slipstream proxy list          show the list and the file
  slipstream context <provider/model> <tokens>   e.g. opencode/deepseek-v4.1-flash-free 1000000
  slipstream lang <code|auto>    ${Object.keys(LANGS).join(", ")}
  slipstream clear login|restore|cache    login (auth.json, backed up first), put it back, cache and logs. Chats are kept.

  With the tray running, all terminals share its connection, and a free-limit error written in OpenCode's log changes the IP by itself.
  Without it, "opencode run ..." does the same for that one run; in the interactive screen use "slipstream ip" from another terminal.`
