<#
  Slipstream - per-app connection patcher for Windows.
  Gives one app its own route (WireGuard, proxy), a new IP on demand and safe clean-ups, without touching the rest of the PC.
  Supported apps: OpenCode desktop (more to come).

  Run:
    .\run.ps1                    install / update the patch
    .\run.ps1 -uninstall         remove it, back to the original
    .\run.ps1 -status            show what is installed
    .\run.ps1 -start             open OpenCode when done
    .\run.ps1 -download          install the ORIGINAL OpenCode from GitHub first, if it is missing
    .\run.ps1 -block_update_off  let OpenCode update itself again (updates remove the patch)
    .\run.ps1 -path <folder>     OpenCode folder, if it is not in the default place
    .\run.ps1 -lang pt-BR        installer language (default: your Windows language; the tray menu has its own Language item)

  What it adds (tray icon next to the clock):
    New IP .............. built-in WARP (our own WireGuard in JS, no .exe): new account and tunnel / next proxy of your list
    Connection .......... Direct | Built-in WARP | WireGuard file (.conf) | Free public proxies | Own proxy list
                          (only OpenCode uses it; the rest of the PC stays as it is. IPv6 first, IPv4 as fallback)
    Auto-rotate ......... when the free limit stops a chat: new IP, then the message is sent again by itself
    Clear > ............. Login (auth.json, backed up first) | Restore login | Cache and logs. Chats are never touched.
    Restart / Quit ...... restart OpenCode, or close it completely (tunnel included)
    Status .............. the IP OpenCode is using
  And it removes the "Free limit reached / subscribe to Go" tray and popup.

  How: app.asar gets a new entry file; the original is saved as app.asar.slipstream.bak. -uninstall puts it back.
  Files of the tool: %LOCALAPPDATA%\slipstream  (proxy.json = settings and proxy list, slipstream.log)
#>
param(
  [switch]$uninstall,
  [switch]$status,
  [switch]$start,
  [switch]$download,
  [switch]$block_update_off,
  [string]$version = '',
  [string]$path = '',
  [string]$lang = ''
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = 'SilentlyContinue'

function Say($m, $c = 'White') { Write-Host $m -ForegroundColor $c }
function Step($m) { Write-Host '  > ' -NoNewline -ForegroundColor Cyan; Write-Host $m }
function Ok($m)   { Write-Host '  + ' -NoNewline -ForegroundColor Green; Write-Host $m }
function Warn($m) { Write-Host '  ! ' -NoNewline -ForegroundColor Yellow; Write-Host $m }
function Fail($m) { Write-Host '  x ' -NoNewline -ForegroundColor Red; Write-Host $m }

# Installer messages in 12 languages (Base64 of UTF-8 JSON, so this file stays plain ASCII for any PowerShell).
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$I18N = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('eyJlbiI6eyJwc09sZCI6IlBvd2VyU2hlbGwgNS4xIG9yIGFib3ZlIGlzIHJlcXVpcmVkLiIsIndpbk9ubHkiOiJUaGlzIHBhdGNoZXIgaXMgZm9yIFdpbmRvd3MuIiwic3RvcHBlZCI6IlNjcmlwdCBpcyBzdG9wcGVkIiwiY2xvc2VkIjoiY2xvc2VkIHtufSBwcm9jZXNzKGVzKSIsIm5vdEZvdW5kIjoiT3BlbkNvZGUgZGVza3RvcCB3YXMgbm90IGZvdW5kLiIsImhpbnREb3dubG9hZCI6IlVzZSAtZG93bmxvYWQgdG8gaW5zdGFsbCB0aGUgb3JpZ2luYWwgZnJvbSBHaXRIdWIsIG9yIC1wYXRoIDxmb2xkZXIgd2l0aCBPcGVuQ29kZS5leGU+LiIsImZvdW5kIjoiT3BlbkNvZGUge3Z9IGluIHtkaXJ9IiwicmVzdG9yZWQiOiJvcmlnaW5hbCBhcHAuYXNhciByZXN0b3JlZCIsIm5vdFBhdGNoZWQiOiJpdCB3YXMgbm90IHBhdGNoZWQiLCJ1cGRSZXN0b3JlZCI6ImF1dG8tdXBkYXRlIHJlc3RvcmVkIiwib3JpZ2luYWwiOiJPcGVuQ29kZSBpcyBiYWNrIHRvIHRoZSBvcmlnaW5hbC4iLCJzYXZpbmciOiJzYXZpbmcgdGhlIG9yaWdpbmFsIGFwcC5hc2FyLi4uIiwicGF0Y2hpbmciOiJQYXRjaGluZyBPcGVuQ29kZS4uLiIsImNvZGVPayI6ImZyZWUtbGltaXQgdHJheSBzdG9wcGVkIGluIHRoZSBhcHAgY29kZSIsImNvZGVNaXNzaW5nIjoiZnJlZS1saW1pdCBjb2RlIG5vdCBmb3VuZCBpbiB0aGlzIHZlcnNpb247IHRoZSB0cmF5IG1lbnUgaXMgaW5zdGFsbGVkIHdpdGhvdXQgdGhhdCBwYXJ0IiwidHJheU9rIjoidHJheSBtZW51IGluc3RhbGxlZCIsInVwZEJsb2NrZWQiOiJhdXRvLXVwZGF0ZSBibG9ja2VkIiwiZG9uZSI6IlNsaXBzdHJlYW0gaW5zdGFsbGF0aW9uIGNvbXBsZXRlZC4iLCJvcGVuSGludCI6Ik9wZW4gT3BlbkNvZGU6IHRoZSBTbGlwc3RyZWFtIG1lbnUgaXMgdGhlIHRyYXkgaWNvbiBuZXh0IHRvIHRoZSBjbG9jayAobmVhciB0aGUgZGF0ZSkuIiwidW5kbyI6IlVuZG86IC5cXHJ1bi5wczEgLXVuaW5zdGFsbCIsImZhaWxlZCI6InBhdGNoIGZhaWxlZDoge2Vycn0gLSB0aGUgb3JpZ2luYWwgd2FzIGxlZnQgYXMgaXQgd2FzIn0sInB0LUJSIjp7InBzT2xkIjoiw4kgbmVjZXNzw6FyaW8gbyBQb3dlclNoZWxsIDUuMSBvdSBzdXBlcmlvci4iLCJ3aW5Pbmx5IjoiRXN0ZSBpbnN0YWxhZG9yIMOpIHBhcmEgV2luZG93cy4iLCJzdG9wcGVkIjoiU2NyaXB0IGludGVycm9tcGlkbyIsImNsb3NlZCI6IntufSBwcm9jZXNzbyhzKSBlbmNlcnJhZG8ocykiLCJub3RGb3VuZCI6Ik8gT3BlbkNvZGUgZGVza3RvcCBuw6NvIGZvaSBlbmNvbnRyYWRvLiIsImhpbnREb3dubG9hZCI6IlVzZSAtZG93bmxvYWQgcGFyYSBpbnN0YWxhciBvIG9yaWdpbmFsIGRvIEdpdEh1Yiwgb3UgLXBhdGggPHBhc3RhIGNvbSBPcGVuQ29kZS5leGU+LiIsImZvdW5kIjoiT3BlbkNvZGUge3Z9IGVtIHtkaXJ9IiwicmVzdG9yZWQiOiJhcHAuYXNhciBvcmlnaW5hbCByZXN0YXVyYWRvIiwibm90UGF0Y2hlZCI6ImVsZSBuw6NvIGVzdGF2YSBjb20gbyBwYXRjaCIsInVwZFJlc3RvcmVkIjoiYXR1YWxpemHDp8OjbyBhdXRvbcOhdGljYSByZXN0YXVyYWRhIiwib3JpZ2luYWwiOiJPIE9wZW5Db2RlIHZvbHRvdSBhbyBvcmlnaW5hbC4iLCJzYXZpbmciOiJzYWx2YW5kbyBvIGFwcC5hc2FyIG9yaWdpbmFsLi4uIiwicGF0Y2hpbmciOiJBcGxpY2FuZG8gbyBwYXRjaCBubyBPcGVuQ29kZS4uLiIsImNvZGVPayI6ImZhaXhhIGRvIGxpbWl0ZSBncmF0dWl0byBkZXNhdGl2YWRhIG5vIGPDs2RpZ28gZG8gYXBwIiwiY29kZU1pc3NpbmciOiJjw7NkaWdvIGRvIGxpbWl0ZSBncmF0dWl0byBuw6NvIGVuY29udHJhZG8gbmVzdGEgdmVyc8OjbzsgbyBtZW51IGRhIGJhbmRlamEgZm9pIGluc3RhbGFkbyBzZW0gZXNzYSBwYXJ0ZSIsInRyYXlPayI6Im1lbnUgZGEgYmFuZGVqYSBpbnN0YWxhZG8iLCJ1cGRCbG9ja2VkIjoiYXR1YWxpemHDp8OjbyBhdXRvbcOhdGljYSBibG9xdWVhZGEiLCJkb25lIjoiSW5zdGFsYcOnw6NvIGRvIFNsaXBzdHJlYW0gY29uY2x1w61kYS4iLCJvcGVuSGludCI6IkFicmEgbyBPcGVuQ29kZTogbyBtZW51IGRvIFNsaXBzdHJlYW0gw6kgbyDDrWNvbmUgbmEgYmFuZGVqYSwgcGVydG8gZG8gcmVsw7NnaW8gKGFvIGxhZG8gZGEgZGF0YSkuIiwidW5kbyI6IkRlc2ZhemVyOiAuXFxydW4ucHMxIC11bmluc3RhbGwiLCJmYWlsZWQiOiJmYWxoYSBubyBwYXRjaDoge2Vycn0gLSBvIG9yaWdpbmFsIGZvaSBtYW50aWRvIGNvbW8gZXN0YXZhIn0sImVzIjp7InBzT2xkIjoiU2UgcmVxdWllcmUgUG93ZXJTaGVsbCA1LjEgbyBzdXBlcmlvci4iLCJ3aW5Pbmx5IjoiRXN0ZSBpbnN0YWxhZG9yIGVzIHBhcmEgV2luZG93cy4iLCJzdG9wcGVkIjoiU2NyaXB0IGRldGVuaWRvIiwiY2xvc2VkIjoie259IHByb2Nlc28ocykgY2VycmFkbyhzKSIsIm5vdEZvdW5kIjoiTm8gc2UgZW5jb250csOzIE9wZW5Db2RlIGRlc2t0b3AuIiwiaGludERvd25sb2FkIjoiVXNhIC1kb3dubG9hZCBwYXJhIGluc3RhbGFyIGVsIG9yaWdpbmFsIGRlc2RlIEdpdEh1YiwgbyAtcGF0aCA8Y2FycGV0YSBjb24gT3BlbkNvZGUuZXhlPi4iLCJmb3VuZCI6Ik9wZW5Db2RlIHt2fSBlbiB7ZGlyfSIsInJlc3RvcmVkIjoiYXBwLmFzYXIgb3JpZ2luYWwgcmVzdGF1cmFkbyIsIm5vdFBhdGNoZWQiOiJubyB0ZW7DrWEgZWwgcGFyY2hlIiwidXBkUmVzdG9yZWQiOiJhY3R1YWxpemFjacOzbiBhdXRvbcOhdGljYSByZXN0YXVyYWRhIiwib3JpZ2luYWwiOiJPcGVuQ29kZSB2b2x2acOzIGFsIG9yaWdpbmFsLiIsInNhdmluZyI6Imd1YXJkYW5kbyBlbCBhcHAuYXNhciBvcmlnaW5hbC4uLiIsInBhdGNoaW5nIjoiQXBsaWNhbmRvIGVsIHBhcmNoZSBhIE9wZW5Db2RlLi4uIiwiY29kZU9rIjoiYmFuZGVqYSBkZWwgbMOtbWl0ZSBncmF0dWl0byBkZXNhY3RpdmFkYSBlbiBlbCBjw7NkaWdvIGRlIGxhIGFwcCIsImNvZGVNaXNzaW5nIjoibm8gc2UgZW5jb250csOzIGVsIGPDs2RpZ28gZGVsIGzDrW1pdGUgZ3JhdHVpdG8gZW4gZXN0YSB2ZXJzacOzbjsgZWwgbWVuw7ogZGUgbGEgYmFuZGVqYSBzZSBpbnN0YWzDsyBzaW4gZXNhIHBhcnRlIiwidHJheU9rIjoibWVuw7ogZGUgbGEgYmFuZGVqYSBpbnN0YWxhZG8iLCJ1cGRCbG9ja2VkIjoiYWN0dWFsaXphY2nDs24gYXV0b23DoXRpY2EgYmxvcXVlYWRhIiwiZG9uZSI6Ikluc3RhbGFjacOzbiBkZSBTbGlwc3RyZWFtIGNvbXBsZXRhZGEuIiwib3BlbkhpbnQiOiJBYnJlIE9wZW5Db2RlOiBlbCBtZW7DuiBkZSBTbGlwc3RyZWFtIGVzIGVsIGljb25vIGRlIGxhIGJhbmRlamEganVudG8gYWwgcmVsb2ogKGNlcmNhIGRlIGxhIGZlY2hhKS4iLCJ1bmRvIjoiRGVzaGFjZXI6IC5cXHJ1bi5wczEgLXVuaW5zdGFsbCIsImZhaWxlZCI6ImZhbGzDsyBlbCBwYXJjaGU6IHtlcnJ9IC0gZWwgb3JpZ2luYWwgcXVlZMOzIGNvbW8gZXN0YWJhIn0sImZyIjp7InBzT2xkIjoiUG93ZXJTaGVsbCA1LjEgb3Ugc3Vww6lyaWV1ciBlc3QgcmVxdWlzLiIsIndpbk9ubHkiOiJDZXQgaW5zdGFsbGF0ZXVyIGVzdCBwb3VyIFdpbmRvd3MuIiwic3RvcHBlZCI6IlNjcmlwdCBhcnLDqnTDqSIsImNsb3NlZCI6IntufSBwcm9jZXNzdXMgZmVybcOpKHMpIiwibm90Rm91bmQiOiJPcGVuQ29kZSBkZXNrdG9wIGVzdCBpbnRyb3V2YWJsZS4iLCJoaW50RG93bmxvYWQiOiJVdGlsaXNleiAtZG93bmxvYWQgcG91ciBpbnN0YWxsZXIgbCdvcmlnaW5hbCBkZXB1aXMgR2l0SHViLCBvdSAtcGF0aCA8ZG9zc2llciBhdmVjIE9wZW5Db2RlLmV4ZT4uIiwiZm91bmQiOiJPcGVuQ29kZSB7dn0gZGFucyB7ZGlyfSIsInJlc3RvcmVkIjoiYXBwLmFzYXIgZCdvcmlnaW5lIHJlc3RhdXLDqSIsIm5vdFBhdGNoZWQiOiJpbCBuJ8OpdGFpdCBwYXMgbW9kaWZpw6kiLCJ1cGRSZXN0b3JlZCI6Im1pc2Ugw6Agam91ciBhdXRvbWF0aXF1ZSByw6l0YWJsaWUiLCJvcmlnaW5hbCI6Ik9wZW5Db2RlIGVzdCByZXZlbnUgw6AgbCdvcmlnaW5hbC4iLCJzYXZpbmciOiJzYXV2ZWdhcmRlIGRlIGwnYXBwLmFzYXIgZCdvcmlnaW5lLi4uIiwicGF0Y2hpbmciOiJNb2RpZmljYXRpb24gZCdPcGVuQ29kZS4uLiIsImNvZGVPayI6ImJhbmRlYXUgZGUgbGltaXRlIGdyYXR1aXRlIGTDqXNhY3RpdsOpIGRhbnMgbGUgY29kZSBkZSBsJ2FwcCIsImNvZGVNaXNzaW5nIjoiY29kZSBkZSBsYSBsaW1pdGUgZ3JhdHVpdGUgaW50cm91dmFibGUgZGFucyBjZXR0ZSB2ZXJzaW9uIDsgbGUgbWVudSBkZSBsYSBiYXJyZSBkJ8OpdGF0IGVzdCBpbnN0YWxsw6kgc2FucyBjZXR0ZSBwYXJ0aWUiLCJ0cmF5T2siOiJtZW51IGRlIGxhIGJhcnJlIGQnw6l0YXQgaW5zdGFsbMOpIiwidXBkQmxvY2tlZCI6Im1pc2Ugw6Agam91ciBhdXRvbWF0aXF1ZSBibG9xdcOpZSIsImRvbmUiOiJJbnN0YWxsYXRpb24gZGUgU2xpcHN0cmVhbSB0ZXJtaW7DqWUuIiwib3BlbkhpbnQiOiJPdXZyZXogT3BlbkNvZGUgOiBsZSBtZW51IFNsaXBzdHJlYW0gZXN0IGwnaWPDtG5lIGRlIGxhIGJhcnJlIGQnw6l0YXQgcHLDqHMgZGUgbCdob3Jsb2dlICjDoCBjw7R0w6kgZGUgbGEgZGF0ZSkuIiwidW5kbyI6IkFubnVsZXIgOiAuXFxydW4ucHMxIC11bmluc3RhbGwiLCJmYWlsZWQiOiLDqWNoZWMgZGUgbGEgbW9kaWZpY2F0aW9uIDoge2Vycn0gLSBsJ29yaWdpbmFsIGEgw6l0w6kgbGFpc3PDqSB0ZWwgcXVlbCJ9LCJkZSI6eyJwc09sZCI6IlBvd2VyU2hlbGwgNS4xIG9kZXIgaMO2aGVyIGlzdCBlcmZvcmRlcmxpY2guIiwid2luT25seSI6IkRpZXNlcyBJbnN0YWxsYXRpb25zcHJvZ3JhbW0gaXN0IGbDvHIgV2luZG93cy4iLCJzdG9wcGVkIjoiU2tyaXB0IGFuZ2VoYWx0ZW4iLCJjbG9zZWQiOiJ7bn0gUHJvemVzcyhlKSBiZWVuZGV0Iiwibm90Rm91bmQiOiJPcGVuQ29kZSBEZXNrdG9wIHd1cmRlIG5pY2h0IGdlZnVuZGVuLiIsImhpbnREb3dubG9hZCI6Ik1pdCAtZG93bmxvYWQgaW5zdGFsbGllcmVuIFNpZSBkYXMgT3JpZ2luYWwgdm9uIEdpdEh1Yiwgb2RlciAtcGF0aCA8T3JkbmVyIG1pdCBPcGVuQ29kZS5leGU+LiIsImZvdW5kIjoiT3BlbkNvZGUge3Z9IGluIHtkaXJ9IiwicmVzdG9yZWQiOiJPcmlnaW5hbC1hcHAuYXNhciB3aWVkZXJoZXJnZXN0ZWxsdCIsIm5vdFBhdGNoZWQiOiJlcyB3YXIgbmljaHQgZ2VwYXRjaHQiLCJ1cGRSZXN0b3JlZCI6ImF1dG9tYXRpc2NoZXMgVXBkYXRlIHdpZWRlcmhlcmdlc3RlbGx0Iiwib3JpZ2luYWwiOiJPcGVuQ29kZSBpc3Qgd2llZGVyIGltIE9yaWdpbmFsenVzdGFuZC4iLCJzYXZpbmciOiJPcmlnaW5hbC1hcHAuYXNhciB3aXJkIGdlc2ljaGVydC4uLiIsInBhdGNoaW5nIjoiT3BlbkNvZGUgd2lyZCBnZXBhdGNodC4uLiIsImNvZGVPayI6IkdyYXRpcy1MaW1pdC1MZWlzdGUgaW0gQXBwLUNvZGUgZGVha3RpdmllcnQiLCJjb2RlTWlzc2luZyI6IkNvZGUgZsO8ciBkYXMgR3JhdGlzLUxpbWl0IGluIGRpZXNlciBWZXJzaW9uIG5pY2h0IGdlZnVuZGVuOyBkYXMgVHJheS1NZW7DvCB3dXJkZSBvaG5lIGRpZXNlbiBUZWlsIGluc3RhbGxpZXJ0IiwidHJheU9rIjoiVHJheS1NZW7DvCBpbnN0YWxsaWVydCIsInVwZEJsb2NrZWQiOiJhdXRvbWF0aXNjaGVzIFVwZGF0ZSBibG9ja2llcnQiLCJkb25lIjoiU2xpcHN0cmVhbS1JbnN0YWxsYXRpb24gYWJnZXNjaGxvc3Nlbi4iLCJvcGVuSGludCI6IsOWZmZuZW4gU2llIE9wZW5Db2RlOiBEYXMgU2xpcHN0cmVhbS1NZW7DvCBpc3QgZGFzIFRyYXktU3ltYm9sIG5lYmVuIGRlciBVaHIgKG5haGUgZGVtIERhdHVtKS4iLCJ1bmRvIjoiUsO8Y2tnw6RuZ2lnOiAuXFxydW4ucHMxIC11bmluc3RhbGwiLCJmYWlsZWQiOiJQYXRjaCBmZWhsZ2VzY2hsYWdlbjoge2Vycn0gLSBkYXMgT3JpZ2luYWwgYmxpZWIgdW52ZXLDpG5kZXJ0In0sInJ1Ijp7InBzT2xkIjoi0KLRgNC10LHRg9C10YLRgdGPIFBvd2VyU2hlbGwgNS4xINC40LvQuCDQvdC+0LLQtdC1LiIsIndpbk9ubHkiOiLQrdGC0L7RgiDRg9GB0YLQsNC90L7QstGJ0LjQuiDQv9GA0LXQtNC90LDQt9C90LDRh9C10L0g0LTQu9GPIFdpbmRvd3MuIiwic3RvcHBlZCI6ItCh0LrRgNC40L/RgiDQvtGB0YLQsNC90L7QstC70LXQvSIsImNsb3NlZCI6ItC30LDQutGA0YvRgtC+INC/0YDQvtGG0LXRgdGB0L7Qsjoge259Iiwibm90Rm91bmQiOiJPcGVuQ29kZSBkZXNrdG9wINC90LUg0L3QsNC50LTQtdC9LiIsImhpbnREb3dubG9hZCI6ItCY0YHQv9C+0LvRjNC30YPQudGC0LUgLWRvd25sb2FkLCDRh9GC0L7QsdGLINGD0YHRgtCw0L3QvtCy0LjRgtGMINC+0YDQuNCz0LjQvdCw0Lsg0YEgR2l0SHViLCDQuNC70LggLXBhdGggPNC/0LDQv9C60LAg0YEgT3BlbkNvZGUuZXhlPi4iLCJmb3VuZCI6Ik9wZW5Db2RlIHt2fSDQsiB7ZGlyfSIsInJlc3RvcmVkIjoi0L7RgNC40LPQuNC90LDQu9GM0L3Ri9C5IGFwcC5hc2FyINCy0L7RgdGB0YLQsNC90L7QstC70LXQvSIsIm5vdFBhdGNoZWQiOiLQv9Cw0YLRhyDQvdC1INCx0YvQuyDRg9GB0YLQsNC90L7QstC70LXQvSIsInVwZFJlc3RvcmVkIjoi0LDQstGC0L7QvtCx0L3QvtCy0LvQtdC90LjQtSDQstC+0YHRgdGC0LDQvdC+0LLQu9C10L3QviIsIm9yaWdpbmFsIjoiT3BlbkNvZGUg0LLQvtC30LLRgNCw0YnRkdC9INC6INC+0YDQuNCz0LjQvdCw0LvRgy4iLCJzYXZpbmciOiLRgdC+0YXRgNCw0L3Rj9GOINC+0YDQuNCz0LjQvdCw0LvRjNC90YvQuSBhcHAuYXNhci4uLiIsInBhdGNoaW5nIjoi0J/QsNGC0YfRgyBPcGVuQ29kZS4uLiIsImNvZGVPayI6ItC/0LDQvdC10LvRjCDQsdC10YHQv9C70LDRgtC90L7Qs9C+INC70LjQvNC40YLQsCDQvtGC0LrQu9GO0YfQtdC90LAg0LIg0LrQvtC00LUg0L/RgNC40LvQvtC20LXQvdC40Y8iLCJjb2RlTWlzc2luZyI6ItC60L7QtCDQsdC10YHQv9C70LDRgtC90L7Qs9C+INC70LjQvNC40YLQsCDQvdC1INC90LDQudC00LXQvSDQsiDRjdGC0L7QuSDQstC10YDRgdC40Lg7INC80LXQvdGOINCyINGC0YDQtdC1INGD0YHRgtCw0L3QvtCy0LvQtdC90L4g0LHQtdC3INGN0YLQvtC5INGH0LDRgdGC0LgiLCJ0cmF5T2siOiLQvNC10L3RjiDQsiDRgtGA0LXQtSDRg9GB0YLQsNC90L7QstC70LXQvdC+IiwidXBkQmxvY2tlZCI6ItCw0LLRgtC+0L7QsdC90L7QstC70LXQvdC40LUg0LfQsNCx0LvQvtC60LjRgNC+0LLQsNC90L4iLCJkb25lIjoi0KPRgdGC0LDQvdC+0LLQutCwIFNsaXBzdHJlYW0g0LfQsNCy0LXRgNGI0LXQvdCwLiIsIm9wZW5IaW50Ijoi0J7RgtC60YDQvtC50YLQtSBPcGVuQ29kZTog0LzQtdC90Y4gU2xpcHN0cmVhbSDigJQg0Y3RgtC+INC30L3QsNGH0L7QuiDQsiDRgtGA0LXQtSDRgNGP0LTQvtC8INGBINGH0LDRgdCw0LzQuCAo0YMg0LTQsNGC0YspLiIsInVuZG8iOiLQntGC0LzQtdC90LA6IC5cXHJ1bi5wczEgLXVuaW5zdGFsbCIsImZhaWxlZCI6ItC90LUg0YPQtNCw0LvQvtGB0Ywg0L/RgNC40LzQtdC90LjRgtGMINC/0LDRgtGHOiB7ZXJyfSAtINC+0YDQuNCz0LjQvdCw0Lsg0L7RgdGC0LDQstC70LXQvSDQsdC10Lcg0LjQt9C80LXQvdC10L3QuNC5In0sInpoLUNOIjp7InBzT2xkIjoi6ZyA6KaBIFBvd2VyU2hlbGwgNS4xIOaIluabtOmrmOeJiOacrOOAgiIsIndpbk9ubHkiOiLmraTlronoo4XnqIvluo/ku4XpgILnlKjkuo4gV2luZG93c+OAgiIsInN0b3BwZWQiOiLohJrmnKzlt7LlgZzmraIiLCJjbG9zZWQiOiLlt7LlhbPpl60ge259IOS4qui/m+eoiyIsIm5vdEZvdW5kIjoi5pyq5om+5YiwIE9wZW5Db2RlIOahjOmdoueJiOOAgiIsImhpbnREb3dubG9hZCI6IuS9v+eUqCAtZG93bmxvYWQg5LuOIEdpdEh1YiDlronoo4Xljp/niYjvvIzmiJbkvb/nlKggLXBhdGggPOWMheWQqyBPcGVuQ29kZS5leGUg55qE5paH5Lu25aS5PuOAgiIsImZvdW5kIjoiT3BlbkNvZGUge3Z977yM5L2N5LqOIHtkaXJ9IiwicmVzdG9yZWQiOiLlt7Lov5jljp/ljp/lp4sgYXBwLmFzYXIiLCJub3RQYXRjaGVkIjoi5LmL5YmN5rKh5pyJ5omT6KGl5LiBIiwidXBkUmVzdG9yZWQiOiLlt7LmgaLlpI3oh6rliqjmm7TmlrAiLCJvcmlnaW5hbCI6Ik9wZW5Db2RlIOW3suaBouWkjeS4uuWOn+eJiOOAgiIsInNhdmluZyI6Iuato+WcqOS/neWtmOWOn+WniyBhcHAuYXNhci4uLiIsInBhdGNoaW5nIjoi5q2j5Zyo57uZIE9wZW5Db2RlIOaJk+ihpeS4gS4uLiIsImNvZGVPayI6IuW3suWcqOW6lOeUqOS7o+eggeS4reWBnOeUqOWFjei0uemineW6puaPkOekuuagjyIsImNvZGVNaXNzaW5nIjoi5q2k54mI5pys5Lit5pyq5om+5Yiw5YWN6LS56aKd5bqm55u45YWz5Luj56CB77yb5omY55uY6I+c5Y2V5bey5a6J6KOF77yM5L2G5rKh5pyJ6L+Z5LiA6YOo5YiGIiwidHJheU9rIjoi5omY55uY6I+c5Y2V5bey5a6J6KOFIiwidXBkQmxvY2tlZCI6IuW3sumYu+atouiHquWKqOabtOaWsCIsImRvbmUiOiJTbGlwc3RyZWFtIOWuieijheWujOaIkOOAgiIsIm9wZW5IaW50Ijoi5omT5byAIE9wZW5Db2Rl77yaU2xpcHN0cmVhbSDoj5zljZXmmK/ml7bpkp/ml4HovrnvvIjml6XmnJ/pmYTov5HvvInnmoTmiZjnm5jlm77moIfjgIIiLCJ1bmRvIjoi5pKk6ZSA77yaLlxccnVuLnBzMSAtdW5pbnN0YWxsIiwiZmFpbGVkIjoi5omT6KGl5LiB5aSx6LSl77yae2Vycn0gLSDljp/mlofku7bkv53mjIHkuI3lj5gifSwiamEiOnsicHNPbGQiOiJQb3dlclNoZWxsIDUuMSDku6XkuIrjgYzlv4XopoHjgafjgZnjgIIiLCJ3aW5Pbmx5Ijoi44GT44Gu44Kk44Oz44K544OI44O844Op44O844GvIFdpbmRvd3Mg55So44Gn44GZ44CCIiwic3RvcHBlZCI6IuOCueOCr+ODquODl+ODiOOCkuWBnOatouOBl+OBvuOBl+OBnyIsImNsb3NlZCI6IntufSDlgIvjga7jg5fjg63jgrvjgrnjgpLntYLkuobjgZfjgb7jgZfjgZ8iLCJub3RGb3VuZCI6Ik9wZW5Db2RlIOODh+OCueOCr+ODiOODg+ODl+OBjOimi+OBpOOBi+OCiuOBvuOBm+OCk+OAgiIsImhpbnREb3dubG9hZCI6Ii1kb3dubG9hZCDjgacgR2l0SHViIOOBi+OCieWFg+OBruOCouODl+ODquOCkuOCpOODs+OCueODiOODvOODq+OBmeOCi+OBi+OAgS1wYXRoIDxPcGVuQ29kZS5leGUg44Gu44GC44KL44OV44Kp44Or44OA44O8PiDjgpLmjIflrprjgZfjgabjgY/jgaDjgZXjgYTjgIIiLCJmb3VuZCI6Ik9wZW5Db2RlIHt2fe+8iHtkaXJ977yJIiwicmVzdG9yZWQiOiLlhYPjga4gYXBwLmFzYXIg44KS5b6p5YWD44GX44G+44GX44GfIiwibm90UGF0Y2hlZCI6IuODkeODg+ODgeOBr+mBqeeUqOOBleOCjOOBpuOBhOOBvuOBm+OCk+OBp+OBl+OBnyIsInVwZFJlc3RvcmVkIjoi6Ieq5YuV5pu05paw44KS5YWD44Gr5oi744GX44G+44GX44GfIiwib3JpZ2luYWwiOiJPcGVuQ29kZSDjga/lhYPjga7nirbmhYvjgavmiLvjgorjgb7jgZfjgZ/jgIIiLCJzYXZpbmciOiLlhYPjga4gYXBwLmFzYXIg44KS5L+d5a2Y44GX44Gm44GE44G+44GZLi4uIiwicGF0Y2hpbmciOiJPcGVuQ29kZSDjgavjg5Hjg4Pjg4HjgpLpgannlKjjgZfjgabjgYTjgb7jgZkuLi4iLCJjb2RlT2siOiLjgqLjg5fjg6rjga7jgrPjg7zjg4njgafnhKHmlpnmnqDjg5Djg7zjgpLnhKHlirnjgavjgZfjgb7jgZfjgZ8iLCJjb2RlTWlzc2luZyI6IuOBk+OBruODkOODvOOCuOODp+ODs+OBp+OBr+eEoeaWmeaeoOOBruOCs+ODvOODieOBjOimi+OBpOOBi+OCiuOBvuOBm+OCk+OAguODiOODrOOCpOODoeODi+ODpeODvOOBr+OBneOBrumDqOWIhuOBquOBl+OBp+OCpOODs+OCueODiOODvOODq+OBl+OBvuOBl+OBnyIsInRyYXlPayI6IuODiOODrOOCpOODoeODi+ODpeODvOOCkuOCpOODs+OCueODiOODvOODq+OBl+OBvuOBl+OBnyIsInVwZEJsb2NrZWQiOiLoh6rli5Xmm7TmlrDjgpLjg5bjg63jg4Pjgq/jgZfjgb7jgZfjgZ8iLCJkb25lIjoiU2xpcHN0cmVhbSDjga7jgqTjg7Pjgrnjg4jjg7zjg6vjgYzlrozkuobjgZfjgb7jgZfjgZ/jgIIiLCJvcGVuSGludCI6Ik9wZW5Db2RlIOOCkumWi+OBhOOBpuOBj+OBoOOBleOBhOOAglNsaXBzdHJlYW0g44Gu44Oh44OL44Ol44O844Gv44CB5pmC6KiI77yI5pel5LuY44Gu6L+R44GP77yJ44Gu5qiq44Gr44GC44KL44OI44Os44Kk44Ki44Kk44Kz44Oz44Gn44GZ44CCIiwidW5kbyI6IuWFg+OBq+aIu+OBme+8mi5cXHJ1bi5wczEgLXVuaW5zdGFsbCIsImZhaWxlZCI6IuODkeODg+ODgeOBq+WkseaVl+OBl+OBvuOBl+OBn++8mntlcnJ9IC0g5YWD44Gu54q25oWL44Gu44G+44G+44Gn44GZIn0sImtvIjp7InBzT2xkIjoiUG93ZXJTaGVsbCA1LjEg7J207IOB7J20IO2VhOyalO2VqeuLiOuLpC4iLCJ3aW5Pbmx5Ijoi7J20IOyEpOy5mCDtlITroZzqt7jrnqjsnYAgV2luZG93c+yaqeyeheuLiOuLpC4iLCJzdG9wcGVkIjoi7Iqk7YGs66a97Yq46rCAIOykkeyngOuQmOyXiOyKteuLiOuLpCIsImNsb3NlZCI6Iu2UhOuhnOyEuOyKpCB7bn3qsJzrpbwg7KKF66OM7ZaI7Iq164uI64ukIiwibm90Rm91bmQiOiJPcGVuQ29kZSDrjbDsiqTtgazthrHsnYQg7LC+7J2EIOyImCDsl4bsirXri4jri6QuIiwiaGludERvd25sb2FkIjoiLWRvd25sb2Fk66GcIEdpdEh1YuyXkOyEnCDsm5Drs7jsnYQg7ISk7LmY7ZWY6rGw64KYIC1wYXRoIDxPcGVuQ29kZS5leGXqsIAg7J6I64qUIO2PtOuNlD7rpbwg7IKs7Jqp7ZWY7IS47JqULiIsImZvdW5kIjoiT3BlbkNvZGUge3Z9ICh7ZGlyfSkiLCJyZXN0b3JlZCI6IuybkOuzuCBhcHAuYXNhcuulvCDrs7Xsm5DtlojsirXri4jri6QiLCJub3RQYXRjaGVkIjoi7Yyo7LmY6rCAIOyggeyaqeuQmOyWtCDsnojsp4Ag7JWK7JWY7Iq164uI64ukIiwidXBkUmVzdG9yZWQiOiLsnpDrj5kg7JeF642w7J207Yq466W8IOuzteybkO2WiOyKteuLiOuLpCIsIm9yaWdpbmFsIjoiT3BlbkNvZGXqsIAg7JuQ67O47Jy866GcIOuPjOyVhOyZlOyKteuLiOuLpC4iLCJzYXZpbmciOiLsm5Drs7ggYXBwLmFzYXLrpbwg7KCA7J6l7ZWY64qUIOykkS4uLiIsInBhdGNoaW5nIjoiT3BlbkNvZGXsl5Ag7Yyo7LmY66W8IOyggeyaqe2VmOuKlCDspJEuLi4iLCJjb2RlT2siOiLslbEg7L2U65Oc7JeQ7IScIOustOujjCDtlZzrj4Qg7ZGc7Iuc7KSE7J2EIOu5hO2ZnOyEse2ZlO2WiOyKteuLiOuLpCIsImNvZGVNaXNzaW5nIjoi7J20IOuyhOyghOyXkOyEnOuKlCDrrLTro4wg7ZWc64+EIOy9lOuTnOulvCDssL7sp4Ag66q77ZaI7Iq164uI64ukLiDtirjroIjsnbQg66mU64m064qUIOq3uCDrtoDrtoQg7JeG7J20IOyEpOy5mOuQmOyXiOyKteuLiOuLpCIsInRyYXlPayI6Iu2KuOugiOydtCDrqZTribTrpbwg7ISk7LmY7ZaI7Iq164uI64ukIiwidXBkQmxvY2tlZCI6IuyekOuPmSDsl4XrjbDsnbTtirjrpbwg7LCo64uo7ZaI7Iq164uI64ukIiwiZG9uZSI6IlNsaXBzdHJlYW0g7ISk7LmY6rCAIOyZhOujjOuQmOyXiOyKteuLiOuLpC4iLCJvcGVuSGludCI6Ik9wZW5Db2Rl66W8IOyXrOyEuOyalC4gU2xpcHN0cmVhbSDrqZTribTripQg7Iuc6rOEKOuCoOynnCDqt7zsspgpIOyYhuydmCDtirjroIjsnbQg7JWE7J207L2Y7J6F64uI64ukLiIsInVuZG8iOiLrkJjrj4zrpqzquLA6IC5cXHJ1bi5wczEgLXVuaW5zdGFsbCIsImZhaWxlZCI6Iu2MqOy5mCDsi6TtjKg6IHtlcnJ9IC0g7JuQ67O47J2AIOq3uOuMgOuhnCDsnKDsp4DrkJjsl4jsirXri4jri6QifSwiaGkiOnsicHNPbGQiOiJQb3dlclNoZWxsIDUuMSDgpK/gpL4g4KSJ4KS44KS44KWHIOCkqOCkr+CkviDgpLjgpILgpLjgpY3gpJXgpLDgpKMg4KSa4KS+4KS54KS/4KSP4KWkIiwid2luT25seSI6IuCkr+CkuSDgpIfgpILgpLjgpY3gpJ/gpYngpLLgpLAgV2luZG93cyDgpJXgpYcg4KSy4KS/4KSPIOCkueCliOClpCIsInN0b3BwZWQiOiLgpLjgpY3gpJXgpY3gpLDgpL/gpKrgpY3gpJ8g4KSw4KWL4KSVIOCkpuClgCDgpJfgpIgiLCJjbG9zZWQiOiJ7bn0g4KSq4KWN4KSw4KWL4KS44KWH4KS4IOCkrOCkguCkpiDgpJXgpL/gpI8g4KSX4KSPIiwibm90Rm91bmQiOiJPcGVuQ29kZSDgpKHgpYfgpLjgpY3gpJXgpJ/gpYngpKog4KSo4KS54KWA4KSCIOCkruCkv+CksuCkvuClpCIsImhpbnREb3dubG9hZCI6IkdpdEh1YiDgpLjgpYcg4KSu4KWC4KSyIOCkkOCkqiDgpIfgpILgpLjgpY3gpJ/gpYngpLIg4KSV4KSw4KSo4KWHIOCkleClhyDgpLLgpL/gpI8gLWRvd25sb2FkLCDgpK/gpL4gLXBhdGggPE9wZW5Db2RlLmV4ZSDgpLXgpL7gpLLgpL4g4KSr4KS84KWL4KSy4KWN4KSh4KSwPiDgpIfgpLjgpY3gpKTgpYfgpK7gpL7gpLIg4KSV4KSw4KWH4KSC4KWkIiwiZm91bmQiOiJPcGVuQ29kZSB7dn0sIHtkaXJ9IOCkruClh+CkgiIsInJlc3RvcmVkIjoi4KSu4KWC4KSyIGFwcC5hc2FyIOCkrOCkueCkvuCksiDgpJXgpL/gpK/gpL4g4KSX4KSv4KS+Iiwibm90UGF0Y2hlZCI6IuCkh+CkuOCkruClh+CkgiDgpKrgpYjgpJog4KSo4KS54KWA4KSCIOCksuCkl+CkviDgpKXgpL4iLCJ1cGRSZXN0b3JlZCI6IuCkkeCkn+Cliy3gpIXgpKrgpKHgpYfgpJ8g4KSs4KS54KS+4KSyIOCkleCkv+Ckr+CkviDgpJfgpK/gpL4iLCJvcmlnaW5hbCI6Ik9wZW5Db2RlIOCkruClguCksiDgpLDgpYLgpKog4KSu4KWH4KSCIOCksuCljOCknyDgpIbgpK/gpL7gpaQiLCJzYXZpbmciOiLgpK7gpYLgpLIgYXBwLmFzYXIg4KS44KS54KWH4KSc4KS+IOCknOCkviDgpLDgpLngpL4g4KS54KWILi4uIiwicGF0Y2hpbmciOiJPcGVuQ29kZSDgpK7gpYfgpIIg4KSq4KWI4KSaIOCksuCkl+CkvuCkr+CkviDgpJzgpL4g4KSw4KS54KS+IOCkueCliC4uLiIsImNvZGVPayI6IuCkkOCkqiDgpJXgpYvgpKEg4KSu4KWH4KSCIOCkruClgeCkq+CkvOCljeCkpC3gpLjgpYDgpK7gpL4g4KS14KS+4KSy4KWAIOCkquCkn+CljeCkn+ClgCDgpKzgpILgpKYg4KSV4KWAIOCkl+CkiCIsImNvZGVNaXNzaW5nIjoi4KSH4KS4IOCkuOCkguCkuOCljeCkleCksOCkoyDgpK7gpYfgpIIg4KSu4KWB4KSr4KS84KWN4KSkLeCkuOClgOCkruCkviDgpJXgpL4g4KSV4KWL4KShIOCkqOCkueClgOCkgiDgpK7gpL/gpLLgpL47IOCkn+CljeCksOClhyDgpK7gpYfgpKjgpYIg4KSJ4KS4IOCkueCkv+CkuOCljeCkuOClhyDgpJXgpYcg4KSs4KS/4KSo4KS+IOCkh+CkguCkuOCljeCkn+ClieCksiDgpLngpYHgpIYiLCJ0cmF5T2siOiLgpJ/gpY3gpLDgpYcg4KSu4KWH4KSo4KWCIOCkh+CkguCkuOCljeCkn+ClieCksiDgpLngpYHgpIYiLCJ1cGRCbG9ja2VkIjoi4KSR4KSf4KWLLeCkheCkquCkoeClh+CknyDgpLDgpYvgpJXgpL4g4KSX4KSv4KS+IiwiZG9uZSI6IlNsaXBzdHJlYW0g4KSV4KS+IOCkh+CkguCkuOCljeCkn+ClieCksuClh+CktuCkqCDgpKrgpYLgpLDgpL4g4KS54KWB4KSG4KWkIiwib3BlbkhpbnQiOiJPcGVuQ29kZSDgpJbgpYvgpLLgpYfgpII6IFNsaXBzdHJlYW0g4KSu4KWH4KSo4KWCIOCkmOCkoeCkvOClgCAo4KSk4KS+4KSw4KWA4KSW4KS8IOCkleClhyDgpKrgpL7gpLgpIOCkleClhyDgpKzgpJfgpLIg4KSV4KS+IOCkn+CljeCksOClhyDgpIbgpIfgpJXgpKgg4KS54KWI4KWkIiwidW5kbyI6IuCkteCkvuCkquCkuCDgpJXgpLDgpYfgpII6IC5cXHJ1bi5wczEgLXVuaW5zdGFsbCIsImZhaWxlZCI6IuCkquCliOCkmiDgpLXgpL/gpKvgpLIg4KSw4KS54KS+OiB7ZXJyfSAtIOCkruClguCksiDgpJzgpYjgpLjgpL4g4KSl4KS+IOCkteCliOCkuOCkviDgpJvgpYvgpKHgpLzgpL4g4KSX4KSv4KS+In0sImFyIjp7InBzT2xkIjoi2YXYt9mE2YjYqCBQb3dlclNoZWxsIDUuMSDYo9mIINij2K3Yr9irLiIsIndpbk9ubHkiOiLZh9iw2Kcg2KfZhNmF2KvYqNmR2Kog2YXYrti12LUg2YTZhti42KfZhSBXaW5kb3dzLiIsInN0b3BwZWQiOiLYqtmFINil2YrZgtin2YEg2KfZhNio2LHZhtin2YXYrCDYp9mE2YbYtdmKIiwiY2xvc2VkIjoi2KrZhSDYpdi62YTYp9mCIHtufSDYudmF2YTZitipIiwibm90Rm91bmQiOiLZhNmFINmK2KrZhSDYp9mE2LnYq9mI2LEg2LnZhNmJIE9wZW5Db2RlINmE2LPYt9itINin2YTZhdmD2KrYqC4iLCJoaW50RG93bmxvYWQiOiLYp9iz2KrYrtiv2YUgLWRvd25sb2FkINmE2KrYq9io2YrYqiDYp9mE2YbYs9iu2Kkg2KfZhNij2LXZhNmK2Kkg2YXZhiBHaXRIdWLYjCDYo9mIIC1wYXRoIDzYp9mE2YXYrNmE2K8g2KfZhNiw2Yog2YHZitmHIE9wZW5Db2RlLmV4ZT4uIiwiZm91bmQiOiJPcGVuQ29kZSB7dn0g2YHZiiB7ZGlyfSIsInJlc3RvcmVkIjoi2KrZhdiqINin2LPYqti52KfYr9ipIGFwcC5hc2FyINin2YTYo9i12YTZiiIsIm5vdFBhdGNoZWQiOiLZhNmFINmK2YPZhiDZhdmP2LnYr9mO2ZHZhNmL2KciLCJ1cGRSZXN0b3JlZCI6Itiq2YXYqiDYp9iz2KrYudin2K/YqSDYp9mE2KrYrdiv2YrYqyDYp9mE2KrZhNmC2KfYptmKIiwib3JpZ2luYWwiOiLYudin2K8gT3BlbkNvZGUg2KXZhNmJINin2YTZhtiz2K7YqSDYp9mE2KPYtdmE2YrYqS4iLCJzYXZpbmciOiLYrNin2LHZjSDYrdmB2LggYXBwLmFzYXIg2KfZhNij2LXZhNmKLi4uIiwicGF0Y2hpbmciOiLYrNin2LHZjSDYqti52K/ZitmEIE9wZW5Db2RlLi4uIiwiY29kZU9rIjoi2KrZhSDYqti52LfZitmEINi02LHZiti3INin2YTYrdivINin2YTZhdis2KfZhtmKINmB2Yog2YPZiNivINin2YTYqti32KjZitmCIiwiY29kZU1pc3NpbmciOiLZhNmFINmK2KrZhSDYp9mE2LnYq9mI2LEg2LnZhNmJINmD2YjYryDYp9mE2K3YryDYp9mE2YXYrNin2YbZiiDZgdmKINmH2LDYpyDYp9mE2KXYtdiv2KfYsdibINiq2YUg2KrYq9io2YrYqiDZgtin2KbZhdipINi52YTYqNipINin2YTZhti42KfZhSDYqNiv2YjZhtmHIiwidHJheU9rIjoi2KrZhSDYqtir2KjZitiqINmC2KfYptmF2Kkg2LnZhNio2Kkg2KfZhNmG2LjYp9mFIiwidXBkQmxvY2tlZCI6Itiq2YUg2K3YuNixINin2YTYqtit2K/ZitirINin2YTYqtmE2YLYp9im2YoiLCJkb25lIjoi2KfZg9iq2YXZhCDYqtir2KjZitiqIFNsaXBzdHJlYW0uIiwib3BlbkhpbnQiOiLYp9mB2KrYrSBPcGVuQ29kZTog2YLYp9im2YXYqSBTbGlwc3RyZWFtINmH2Yog2KPZitmC2YjZhtipINi52YTYqNipINin2YTZhti42KfZhSDYqNis2KfZhtioINin2YTYs9in2LnYqSAo2YLYsdioINin2YTYqtin2LHZitiuKS4iLCJ1bmRvIjoi2YTZhNiq2LHYp9is2Lk6IC5cXHJ1bi5wczEgLXVuaW5zdGFsbCIsImZhaWxlZCI6ItmB2LTZhCDYp9mE2KrYudiv2YrZhDoge2Vycn0gLSDYqtmP2LHZgyDYp9mE2KPYtdmEINmD2YXYpyDZg9in2YYifSwiaWQiOnsicHNPbGQiOiJQb3dlclNoZWxsIDUuMSBhdGF1IGxlYmloIGJhcnUgZGlwZXJsdWthbi4iLCJ3aW5Pbmx5IjoiUGVtYXNhbmcgaW5pIHVudHVrIFdpbmRvd3MuIiwic3RvcHBlZCI6IlNrcmlwIGRpaGVudGlrYW4iLCJjbG9zZWQiOiJ7bn0gcHJvc2VzIGRpdHV0dXAiLCJub3RGb3VuZCI6Ik9wZW5Db2RlIGRlc2t0b3AgdGlkYWsgZGl0ZW11a2FuLiIsImhpbnREb3dubG9hZCI6Ikd1bmFrYW4gLWRvd25sb2FkIHVudHVrIG1lbWFzYW5nIHZlcnNpIGFzbGkgZGFyaSBHaXRIdWIsIGF0YXUgLXBhdGggPGZvbGRlciBiZXJpc2kgT3BlbkNvZGUuZXhlPi4iLCJmb3VuZCI6Ik9wZW5Db2RlIHt2fSBkaSB7ZGlyfSIsInJlc3RvcmVkIjoiYXBwLmFzYXIgYXNsaSBkaXB1bGloa2FuIiwibm90UGF0Y2hlZCI6ImJlbHVtIGRpLXBhdGNoIiwidXBkUmVzdG9yZWQiOiJwZW1iYXJ1YW4gb3RvbWF0aXMgZGlwdWxpaGthbiIsIm9yaWdpbmFsIjoiT3BlbkNvZGUga2VtYmFsaSBrZSB2ZXJzaSBhc2xpLiIsInNhdmluZyI6Im1lbnlpbXBhbiBhcHAuYXNhciBhc2xpLi4uIiwicGF0Y2hpbmciOiJNZW0tcGF0Y2ggT3BlbkNvZGUuLi4iLCJjb2RlT2siOiJiaWxhaCBiYXRhcyBncmF0aXMgZGlub25ha3RpZmthbiBkaSBrb2RlIGFwbGlrYXNpIiwiY29kZU1pc3NpbmciOiJrb2RlIGJhdGFzIGdyYXRpcyB0aWRhayBkaXRlbXVrYW4gZGkgdmVyc2kgaW5pOyBtZW51IGJha2kgZGlwYXNhbmcgdGFucGEgYmFnaWFuIGl0dSIsInRyYXlPayI6Im1lbnUgYmFraSB0ZXJwYXNhbmciLCJ1cGRCbG9ja2VkIjoicGVtYmFydWFuIG90b21hdGlzIGRpYmxva2lyIiwiZG9uZSI6IlBlbWFzYW5nYW4gU2xpcHN0cmVhbSBzZWxlc2FpLiIsIm9wZW5IaW50IjoiQnVrYSBPcGVuQ29kZTogbWVudSBTbGlwc3RyZWFtIGFkYWxhaCBpa29uIGRpIGJha2kgZGVrYXQgamFtIChkaSBzYW1waW5nIHRhbmdnYWwpLiIsInVuZG8iOiJVcnVuZ2thbjogLlxccnVuLnBzMSAtdW5pbnN0YWxsIiwiZmFpbGVkIjoicGF0Y2ggZ2FnYWw6IHtlcnJ9IC0gdmVyc2kgYXNsaSBkaWJpYXJrYW4gYXBhIGFkYW55YSJ9fQ==')) | ConvertFrom-Json
$code = if ($lang) { $lang } else { (Get-Culture).Name }
$code = if ($code -like 'pt*') { 'pt-BR' } elseif ($code -like 'zh*') { 'zh-CN' } else { ($code -split '-')[0] }
if (-not $I18N.PSObject.Properties[$code]) { $code = 'en' }
function T([string]$key, [hashtable]$vars = @{}) {
  $text = $I18N.$code.$key
  if (-not $text) { $text = $I18N.en.$key }
  foreach ($k in $vars.Keys) { $text = $text.Replace('{' + $k + '}', [string]$vars[$k]) }
  $text
}

$ScriptVersion = '1.0.0'
Say @"

  +-------------------------------------+
  |  Welcome to Slipstream for Windows  |
  +-------------------------------------+
  patcher $ScriptVersion

"@ Cyan

if ($PSVersionTable.PSVersion.Major -lt 5) { Fail (T 'psOld'); Say ('  ' + (T 'stopped')) Red; return }
if ($env:OS -ne 'Windows_NT') { Fail (T 'winOnly'); Say ('  ' + (T 'stopped')) Red; return }

# ---------------------------------------------------------------- locate OpenCode
$exeName = 'OpenCode.exe'
$candidates = @($path, (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop'), (Join-Path $env:ProgramFiles 'OpenCode'), (Join-Path $env:LOCALAPPDATA 'Programs\OpenCode')) | Where-Object { $_ }
function Find-Install { foreach ($c in $candidates) { if (Test-Path (Join-Path $c $exeName)) { return $c } }; $null }

function Stop-OpenCode {
  $n = 0
  foreach ($p in 'OpenCode', 'opencode-cli') {
    Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object { try { $_.Kill(); $n++ } catch {} }
  }
  if ($n) { Start-Sleep 2; Step (T 'closed' @{ n = $n }) }
}

# ---------------------------------------------------------------- download the original
function Get-Original([string]$want) {
  if ($want) { $tag = "v$($want.TrimStart('v'))" }
  else {
    Step 'looking for the newest OpenCode desktop release...'
    $rels = Invoke-RestMethod 'https://api.github.com/repos/anomalyco/opencode/releases?per_page=30' -Headers @{ 'User-Agent' = 'slipstreame' }
    $tag = ($rels | Where-Object { $_.tag_name -match '^v\d+\.\d+\.\d+$' -and $_.assets.name -contains 'opencode-desktop-win-x64.exe' } |
            Sort-Object { [version]($_.tag_name.TrimStart('v')) } -Descending | Select-Object -First 1).tag_name
  }
  if (-not $tag) { throw 'no release with a Windows installer was found' }
  $out = Join-Path $env:TEMP "opencode-desktop-win-x64-$tag.exe"
  Step "downloading $tag ..."
  for ($try = 1; $try -le 3; $try++) {
    try { Invoke-WebRequest "https://github.com/anomalyco/opencode/releases/download/$tag/opencode-desktop-win-x64.exe" -OutFile $out -UseBasicParsing; break }
    catch {
      Warn "Error downloading ($($_.Exception.Message))"
      if ($try -eq 3) { throw 'Check your network settings and run the installation again' }
      Warn 'Will re-request in 5 seconds...'; Start-Sleep 5
    }
  }
  Step 'installing the original (silent)...'
  Start-Process $out -ArgumentList '/S' -Wait
  Remove-Item $out -Force -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------- the module that goes inside app.asar
$BootJs = @'
// Slipstream - slipstream-boot.js. package.json "main" points here; it sets things up and then loads the original index.js.
import { app, Tray, Menu, Notification, shell, dialog, nativeImage } from "electron"
import { execFileSync } from "node:child_process"
import dgram from "node:dgram"
import { lookup as dnsLookup } from "node:dns/promises"
import crypto, { generateKeyPairSync } from "node:crypto"
import { existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, rmSync, readdirSync, statSync } from "node:fs"
import https from "node:https"
import net from "node:net"
import os from "node:os"
import path from "node:path"
import { Duplex } from "node:stream"
import tls from "node:tls"

const home = os.homedir()
const dataDir = path.join(process.env.XDG_DATA_HOME ?? path.join(home, ".local", "share"), "opencode")
const userData = path.join(process.env.APPDATA ?? path.join(home, "AppData", "Roaming"), "ai.opencode.desktop")
const stateDir = path.join(process.env.LOCALAPPDATA ?? path.join(home, ".local", "state"), "slipstream")
mkdirSync(stateDir, { recursive: true })

const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
const log = (m) => { try { writeFileSync(path.join(stateDir, "slipstream.log"), `${new Date().toISOString()} ${m}\n`, { flag: "a" }) } catch {} }
const why = (e) => [e?.message, e?.cause?.code, e?.cause?.message].filter(Boolean).join(" - ") || String(e)
// Windows often swallows toasts of unpackaged apps, so results are also logged and shown in a message box.
const say = (body) => {
  log(body)
  try { new Notification({ title: "Slipstream", body: String(body) }).show() } catch {}
  dialog.showMessageBox({ type: "info", title: "Slipstream", message: String(body), buttons: ["OK"] }).catch(() => {})
}
const note = (body) => { log(body); try { new Notification({ title: "Slipstream", body: String(body) }).show() } catch {} }
let busy = false
const guard = (fn) => async () => {
  if (busy) return say(t("busy"))
  busy = true
  try { say(await fn()) } catch (e) { say(why(e)) } finally { busy = false; try { buildMenu() } catch {} }
}

// ---------------------------------------------------------------- before the app starts: pending clean-ups
// The Clear actions restart the app and are done here, while nothing is locked and the service cannot write auth.json back.
const pendingFile = path.join(stateDir, "pending.json")
const backupDir = path.join(stateDir, "backup")
// Caches and logs only. Chats (opencode.db), settings, drafts and the undo snapshots are never in these lists.
const CACHE = ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache", "GPUPersistentCache", "Crashpad", "logs", "Shared Dictionary"]
const dirBytes = (d) => {
  let n = 0
  try { for (const e of readdirSync(d, { withFileTypes: true })) { const f = path.join(d, e.name); n += e.isDirectory() ? dirBytes(f) : statSync(f).size } } catch {}
  return n
}
const newestBackup = () => { try { return readdirSync(backupDir).filter((n) => existsSync(path.join(backupDir, n, "auth.json"))).sort().at(-1) } catch { return undefined } }
let afterStart = null    // what the last clean-up did ({ key, vars }), shown once the app is up
try {
  if (existsSync(pendingFile)) {
    const todo = JSON.parse(readFileSync(pendingFile, "utf8"))
    rmSync(pendingFile, { force: true })
    const auth = path.join(dataDir, "auth.json")
    if (todo.includes("tokens") && existsSync(auth)) {
      const dir = path.join(backupDir, new Date().toISOString().replace(/[:.]/g, "-"))
      mkdirSync(dir, { recursive: true })
      copyFileSync(auth, path.join(dir, "auth.json"))
      if (readFileSync(auth).equals(readFileSync(path.join(dir, "auth.json")))) { rmSync(auth, { force: true }); afterStart = { key: "doneLogin" } }   // removed only after the copy is verified
      else afterStart = { key: "failVerify" }
    }
    if (todo.includes("restore")) {
      const from = newestBackup()
      if (from && !existsSync(auth)) { mkdirSync(dataDir, { recursive: true }); copyFileSync(path.join(backupDir, from, "auth.json"), auth); afterStart = { key: "doneRestore", vars: { from } } }
    }
    if (todo.includes("cache")) {
      let bytes = 0
      for (const d of [...CACHE.map((n) => path.join(userData, n)), path.join(dataDir, "log")]) { bytes += dirBytes(d); rmSync(d, { recursive: true, force: true }) }
      afterStart = { key: "doneCache", vars: { mb: (bytes / 1048576).toFixed(1) } }
    }
  }
} catch (e) { log("clean-up failed: " + why(e)); afterStart = { key: "failClean", vars: { err: why(e) } } }

// The app keeps the free-limit time in its database after a limit error and shows its tray until then. Clear it before the app opens the database.
try {
  const { DatabaseSync } = await import("node:sqlite")
  const db = new DatabaseSync(path.join(userData, "drafts.sqlite"))
  db.prepare("update state set value = ? where name = 'opencode.global.dat' and key = 'free-limit'").run('{"resetAt":null}')
  db.close()
} catch (e) { log("free-limit state not cleared: " + why(e)) }

// ---------------------------------------------------------------- settings (proxy.json)
const proxyFile = path.join(stateDir, "proxy.json")
const MODES = ["none", "wg", "wgfile", "free", "list"]
const DEFAULT_CFG = { mode: "none", language: "auto", autoRotate: true, gatePort: 0, contextLimits: { "opencode/deepseek-v4.1-flash-free": 1000000 }, current: "", list: ["# one proxy per line: http://user:pass@host:port | socks5://host:port | host:port"] }
const loadCfg = () => {
  let c = {}
  try { c = JSON.parse(readFileSync(proxyFile, "utf8")) } catch {}
  const cfg = { ...DEFAULT_CFG, ...c }
  if (!MODES.includes(cfg.mode)) cfg.mode = "none"
  return cfg
}
const saveCfg = (c) => writeFileSync(proxyFile, JSON.stringify(c, null, 2))
let cfg = loadCfg()
if (!existsSync(proxyFile)) saveCfg(cfg)

const APP_NAME = "OpenCode"
// ---------------------------------------------------------------- languages
// Menu and messages. Technical details (network and protocol errors, the log file) stay in English.
const LANGS = {
  en: { name: "English",
    m_newIp: "New IP", m_connection: "Connection", m_direct: "Direct", m_wg: "Built-in WARP", m_wgfile: "WireGuard file", m_free: "Free public proxies (untrusted)", m_list: "Own proxy list",
    m_chooseWg: "Choose WireGuard file...", m_settings: "Edit settings (proxy list, context)", m_auto: "Auto-rotate", m_clear: "Clear", m_clearLogin: "Login (keeps chats)", m_restoreLogin: "Restore login",
    m_clearCache: "Cache and logs", m_status: "Status", m_restart: "Restart {app}", m_quit: "Quit", m_language: "Language", m_langAuto: "Automatic",
    busy: "Another action is still running.", ipWg: "New IP {ip} (built-in WARP)", ipFree: "New IP {ip} (public proxy {host})", ipList: "New IP {ip} (proxy {host})",
    wgfileFixed: "A WireGuard file has a fixed exit IP. {msg}. Choose another file or another Connection to change it.",
    sameIp: "New WARP account, but the IP is still {ip} (WARP uses the nearest Cloudflare server)", noAnswer: "The WARP tunnel did not answer",
    listEmpty: "Your proxy list is empty. Tray > Edit settings.", listNone: "No proxy of the list gave a different IP.", directNoIp: "Direct mode has no IP to change. Pick another Connection.",
    onWg: "Built-in WARP on. IP {ip}", onWgfile: "WireGuard file on. IP {ip}", onFree: "Public proxy {host} on. IP {ip}", onList: "Own proxy list on. Use New IP to pick a proxy.",
    onDirect: "Direct: the app uses your normal connection.", noneChosen: "Nothing chosen. Connection unchanged.", backDirect: "(back to direct)",
    statusLine: "IP {ip} ({mode})", statusNone: "No connection through the current setting.",
    mDirect: "direct", mWg: "built-in WARP", mWgfile: "WireGuard file", mFree: "public proxy", mList: "proxy list", autoOn: "Auto-rotate on.", autoOff: "Auto-rotate off.",
    noLogin: "There is no saved login (auth.json) on this PC. Nothing to clear.", loginExists: "A login already exists, so nothing was restored.", noBackup: "There is no login backup to restore.",
    doneLogin: "Login removed (a copy is saved). Chats kept.", failVerify: "Could not verify the login backup, so the login was not removed.", doneRestore: "Login restored from {from}.",
    doneCache: "Cache and logs cleared ({mb} MB). Chats kept.", failClean: "Clean-up failed: {err}",
    limitWarn: "Free limit reached. Auto-rotate needs Connection > Built-in WARP or Own proxy list.", limitRotating: "Free limit reached: changing the IP...",
    eReg: "WARP registration refused (HTTP {status}); try again in a few minutes", eNoFile: "No WireGuard file chosen yet. Tray > Connection > Choose WireGuard file.",
    eFileDead: "The tunnel of that WireGuard file did not answer", eWarpDead: "The WARP tunnel did not answer (is UDP 2408 blocked?)",
    eNoList: "Could not download any public proxy list", eNoProxy: "No public proxy answered in time (try again)", dlgChoose: "Choose a WireGuard .conf file" },
  "pt-BR": { name: "Portugu\u00eas (Brasil)",
    m_newIp: "Novo IP", m_connection: "Conex\u00e3o", m_direct: "Direta", m_wg: "WARP embutido", m_wgfile: "Arquivo WireGuard", m_free: "Proxies p\u00fablicos gr\u00e1tis (n\u00e3o confi\u00e1veis)", m_list: "Minha lista de proxies",
    m_chooseWg: "Escolher arquivo WireGuard...", m_settings: "Editar configura\u00e7\u00f5es (proxies, contexto)", m_auto: "Rota\u00e7\u00e3o autom\u00e1tica", m_clear: "Limpar", m_clearLogin: "Login (mant\u00e9m os chats)", m_restoreLogin: "Restaurar login",
    m_clearCache: "Cache e logs", m_status: "Status", m_restart: "Reiniciar {app}", m_quit: "Sair", m_language: "Idioma", m_langAuto: "Autom\u00e1tico",
    busy: "Outra a\u00e7\u00e3o ainda est\u00e1 em andamento.", ipWg: "Novo IP {ip} (WARP embutido)", ipFree: "Novo IP {ip} (proxy p\u00fablico {host})", ipList: "Novo IP {ip} (proxy {host})",
    wgfileFixed: "Um arquivo WireGuard tem IP de sa\u00edda fixo. {msg}. Escolha outro arquivo ou outra Conex\u00e3o para mudar.",
    sameIp: "Nova conta WARP, mas o IP continua {ip} (o WARP usa o servidor da Cloudflare mais pr\u00f3ximo)", noAnswer: "O t\u00fanel WARP n\u00e3o respondeu",
    listEmpty: "Sua lista de proxies est\u00e1 vazia. Bandeja > Editar configura\u00e7\u00f5es.", listNone: "Nenhum proxy da lista deu um IP diferente.", directNoIp: "O modo direto n\u00e3o tem IP para trocar. Escolha outra Conex\u00e3o.",
    onWg: "WARP embutido ligado. IP {ip}", onWgfile: "Arquivo WireGuard ligado. IP {ip}", onFree: "Proxy p\u00fablico {host} ligado. IP {ip}", onList: "Lista de proxies ligada. Use Novo IP para escolher um proxy.",
    onDirect: "Direta: o app usa sua conex\u00e3o normal.", noneChosen: "Nada escolhido. Conex\u00e3o mantida.", backDirect: "(voltou para direta)",
    statusLine: "IP {ip} ({mode})", statusNone: "Sem conex\u00e3o com a configura\u00e7\u00e3o atual.",
    mDirect: "direta", mWg: "WARP embutido", mWgfile: "arquivo WireGuard", mFree: "proxy p\u00fablico", mList: "lista de proxies", autoOn: "Rota\u00e7\u00e3o autom\u00e1tica ligada.", autoOff: "Rota\u00e7\u00e3o autom\u00e1tica desligada.",
    noLogin: "N\u00e3o h\u00e1 login salvo (auth.json) neste PC. Nada para limpar.", loginExists: "J\u00e1 existe um login, ent\u00e3o nada foi restaurado.", noBackup: "N\u00e3o h\u00e1 backup de login para restaurar.",
    doneLogin: "Login removido (h\u00e1 uma c\u00f3pia salva). Chats mantidos.", failVerify: "N\u00e3o foi poss\u00edvel verificar o backup do login, ent\u00e3o ele n\u00e3o foi removido.", doneRestore: "Login restaurado de {from}.",
    doneCache: "Cache e logs limpos ({mb} MB). Chats mantidos.", failClean: "A limpeza falhou: {err}",
    limitWarn: "Limite gratuito atingido. A rota\u00e7\u00e3o autom\u00e1tica precisa de Conex\u00e3o > WARP embutido ou Minha lista de proxies.", limitRotating: "Limite gratuito atingido: trocando o IP...",
    eReg: "Registro WARP recusado (HTTP {status}); tente de novo em alguns minutos", eNoFile: "Nenhum arquivo WireGuard escolhido ainda. Bandeja > Conex\u00e3o > Escolher arquivo WireGuard.",
    eFileDead: "O t\u00fanel desse arquivo WireGuard n\u00e3o respondeu", eWarpDead: "O t\u00fanel WARP n\u00e3o respondeu (a porta UDP 2408 est\u00e1 bloqueada?)",
    eNoList: "N\u00e3o foi poss\u00edvel baixar nenhuma lista de proxies p\u00fablicos", eNoProxy: "Nenhum proxy p\u00fablico respondeu a tempo (tente de novo)", dlgChoose: "Escolha um arquivo WireGuard .conf" },
  es: { name: "Espa\u00f1ol",
    m_newIp: "Nueva IP", m_connection: "Conexi\u00f3n", m_direct: "Directa", m_wg: "WARP integrado", m_wgfile: "Archivo WireGuard", m_free: "Proxies p\u00fablicos gratis (no confiables)", m_list: "Mi lista de proxies",
    m_chooseWg: "Elegir archivo WireGuard...", m_settings: "Editar ajustes (proxies, contexto)", m_auto: "Rotaci\u00f3n autom\u00e1tica", m_clear: "Limpiar", m_clearLogin: "Inicio de sesi\u00f3n (conserva los chats)", m_restoreLogin: "Restaurar inicio de sesi\u00f3n",
    m_clearCache: "Cach\u00e9 y registros", m_status: "Estado", m_restart: "Reiniciar {app}", m_quit: "Salir", m_language: "Idioma", m_langAuto: "Autom\u00e1tico",
    busy: "Otra acci\u00f3n sigue en curso.", ipWg: "Nueva IP {ip} (WARP integrado)", ipFree: "Nueva IP {ip} (proxy p\u00fablico {host})", ipList: "Nueva IP {ip} (proxy {host})",
    wgfileFixed: "Un archivo WireGuard tiene una IP de salida fija. {msg}. Elige otro archivo u otra Conexi\u00f3n para cambiarla.",
    sameIp: "Cuenta WARP nueva, pero la IP sigue siendo {ip} (WARP usa el servidor de Cloudflare m\u00e1s cercano)", noAnswer: "El t\u00fanel WARP no respondi\u00f3",
    listEmpty: "Tu lista de proxies est\u00e1 vac\u00eda. Bandeja > Editar ajustes.", listNone: "Ning\u00fan proxy de la lista dio una IP distinta.", directNoIp: "El modo directo no tiene IP que cambiar. Elige otra Conexi\u00f3n.",
    onWg: "WARP integrado activado. IP {ip}", onWgfile: "Archivo WireGuard activado. IP {ip}", onFree: "Proxy p\u00fablico {host} activado. IP {ip}", onList: "Lista de proxies activada. Usa Nueva IP para elegir un proxy.",
    onDirect: "Directa: la app usa tu conexi\u00f3n normal.", noneChosen: "No se eligi\u00f3 nada. La conexi\u00f3n no cambi\u00f3.", backDirect: "(vuelve a directa)",
    statusLine: "IP {ip} ({mode})", statusNone: "Sin conexi\u00f3n con el ajuste actual.",
    mDirect: "directa", mWg: "WARP integrado", mWgfile: "archivo WireGuard", mFree: "proxy p\u00fablico", mList: "lista de proxies", autoOn: "Rotaci\u00f3n autom\u00e1tica activada.", autoOff: "Rotaci\u00f3n autom\u00e1tica desactivada.",
    noLogin: "No hay inicio de sesi\u00f3n guardado (auth.json) en este PC. Nada que limpiar.", loginExists: "Ya existe un inicio de sesi\u00f3n, as\u00ed que no se restaur\u00f3 nada.", noBackup: "No hay copia de seguridad del inicio de sesi\u00f3n para restaurar.",
    doneLogin: "Inicio de sesi\u00f3n eliminado (hay una copia guardada). Chats conservados.", failVerify: "No se pudo verificar la copia, as\u00ed que el inicio de sesi\u00f3n no se elimin\u00f3.", doneRestore: "Inicio de sesi\u00f3n restaurado desde {from}.",
    doneCache: "Cach\u00e9 y registros borrados ({mb} MB). Chats conservados.", failClean: "La limpieza fall\u00f3: {err}",
    limitWarn: "L\u00edmite gratuito alcanzado. La rotaci\u00f3n autom\u00e1tica necesita Conexi\u00f3n > WARP integrado o Mi lista de proxies.", limitRotating: "L\u00edmite gratuito alcanzado: cambiando la IP...",
    eReg: "Registro WARP rechazado (HTTP {status}); int\u00e9ntalo de nuevo en unos minutos", eNoFile: "A\u00fan no se eligi\u00f3 un archivo WireGuard. Bandeja > Conexi\u00f3n > Elegir archivo WireGuard.",
    eFileDead: "El t\u00fanel de ese archivo WireGuard no respondi\u00f3", eWarpDead: "El t\u00fanel WARP no respondi\u00f3 (\u00bfest\u00e1 bloqueado el puerto UDP 2408?)",
    eNoList: "No se pudo descargar ninguna lista de proxies p\u00fablicos", eNoProxy: "Ning\u00fan proxy p\u00fablico respondi\u00f3 a tiempo (int\u00e9ntalo de nuevo)", dlgChoose: "Elige un archivo WireGuard .conf" },
  fr: { name: "Fran\u00e7ais",
    m_newIp: "Nouvelle IP", m_connection: "Connexion", m_direct: "Directe", m_wg: "WARP int\u00e9gr\u00e9", m_wgfile: "Fichier WireGuard", m_free: "Proxys publics gratuits (non fiables)", m_list: "Ma liste de proxys",
    m_chooseWg: "Choisir un fichier WireGuard...", m_settings: "Modifier les r\u00e9glages (proxys, contexte)", m_auto: "Rotation automatique", m_clear: "Nettoyer", m_clearLogin: "Connexion (garde les chats)", m_restoreLogin: "Restaurer la connexion",
    m_clearCache: "Cache et journaux", m_status: "\u00c9tat", m_restart: "Red\u00e9marrer {app}", m_quit: "Quitter", m_language: "Langue", m_langAuto: "Automatique",
    busy: "Une autre action est encore en cours.", ipWg: "Nouvelle IP {ip} (WARP int\u00e9gr\u00e9)", ipFree: "Nouvelle IP {ip} (proxy public {host})", ipList: "Nouvelle IP {ip} (proxy {host})",
    wgfileFixed: "Un fichier WireGuard a une IP de sortie fixe. {msg}. Choisissez un autre fichier ou une autre Connexion pour la changer.",
    sameIp: "Nouveau compte WARP, mais l'IP reste {ip} (WARP utilise le serveur Cloudflare le plus proche)", noAnswer: "Le tunnel WARP n'a pas r\u00e9pondu",
    listEmpty: "Votre liste de proxys est vide. Barre d'\u00e9tat > Modifier les r\u00e9glages.", listNone: "Aucun proxy de la liste n'a donn\u00e9 une IP diff\u00e9rente.", directNoIp: "Le mode direct n'a pas d'IP \u00e0 changer. Choisissez une autre Connexion.",
    onWg: "WARP int\u00e9gr\u00e9 activ\u00e9. IP {ip}", onWgfile: "Fichier WireGuard activ\u00e9. IP {ip}", onFree: "Proxy public {host} activ\u00e9. IP {ip}", onList: "Liste de proxys activ\u00e9e. Utilisez Nouvelle IP pour choisir un proxy.",
    onDirect: "Directe : l'app utilise votre connexion normale.", noneChosen: "Rien de choisi. Connexion inchang\u00e9e.", backDirect: "(retour en direct)",
    statusLine: "IP {ip} ({mode})", statusNone: "Aucune connexion avec le r\u00e9glage actuel.",
    mDirect: "directe", mWg: "WARP int\u00e9gr\u00e9", mWgfile: "fichier WireGuard", mFree: "proxy public", mList: "liste de proxys", autoOn: "Rotation automatique activ\u00e9e.", autoOff: "Rotation automatique d\u00e9sactiv\u00e9e.",
    noLogin: "Aucune connexion enregistr\u00e9e (auth.json) sur ce PC. Rien \u00e0 nettoyer.", loginExists: "Une connexion existe d\u00e9j\u00e0, rien n'a \u00e9t\u00e9 restaur\u00e9.", noBackup: "Aucune sauvegarde de connexion \u00e0 restaurer.",
    doneLogin: "Connexion supprim\u00e9e (une copie est conserv\u00e9e). Chats gard\u00e9s.", failVerify: "Impossible de v\u00e9rifier la sauvegarde, la connexion n'a donc pas \u00e9t\u00e9 supprim\u00e9e.", doneRestore: "Connexion restaur\u00e9e depuis {from}.",
    doneCache: "Cache et journaux nettoy\u00e9s ({mb} Mo). Chats gard\u00e9s.", failClean: "\u00c9chec du nettoyage : {err}",
    limitWarn: "Limite gratuite atteinte. La rotation automatique requiert Connexion > WARP int\u00e9gr\u00e9 ou Ma liste de proxys.", limitRotating: "Limite gratuite atteinte : changement d'IP...",
    eReg: "Inscription WARP refus\u00e9e (HTTP {status}) ; r\u00e9essayez dans quelques minutes", eNoFile: "Aucun fichier WireGuard choisi. Barre d'\u00e9tat > Connexion > Choisir un fichier WireGuard.",
    eFileDead: "Le tunnel de ce fichier WireGuard n'a pas r\u00e9pondu", eWarpDead: "Le tunnel WARP n'a pas r\u00e9pondu (le port UDP 2408 est-il bloqu\u00e9 ?)",
    eNoList: "Impossible de t\u00e9l\u00e9charger une liste de proxys publics", eNoProxy: "Aucun proxy public n'a r\u00e9pondu \u00e0 temps (r\u00e9essayez)", dlgChoose: "Choisissez un fichier WireGuard .conf" },
  de: { name: "Deutsch",
    m_newIp: "Neue IP", m_connection: "Verbindung", m_direct: "Direkt", m_wg: "Integriertes WARP", m_wgfile: "WireGuard-Datei", m_free: "Kostenlose \u00f6ffentliche Proxys (nicht vertrauensw\u00fcrdig)", m_list: "Eigene Proxy-Liste",
    m_chooseWg: "WireGuard-Datei w\u00e4hlen...", m_settings: "Einstellungen bearbeiten (Proxys, Kontext)", m_auto: "Automatisch wechseln", m_clear: "Bereinigen", m_clearLogin: "Anmeldung (Chats bleiben)", m_restoreLogin: "Anmeldung wiederherstellen",
    m_clearCache: "Cache und Protokolle", m_status: "Status", m_restart: "{app} neu starten", m_quit: "Beenden", m_language: "Sprache", m_langAuto: "Automatisch",
    busy: "Eine andere Aktion l\u00e4uft noch.", ipWg: "Neue IP {ip} (integriertes WARP)", ipFree: "Neue IP {ip} (\u00f6ffentlicher Proxy {host})", ipList: "Neue IP {ip} (Proxy {host})",
    wgfileFixed: "Eine WireGuard-Datei hat eine feste Ausgangs-IP. {msg}. W\u00e4hlen Sie eine andere Datei oder Verbindung, um sie zu \u00e4ndern.",
    sameIp: "Neues WARP-Konto, aber die IP ist weiterhin {ip} (WARP nutzt den n\u00e4chsten Cloudflare-Server)", noAnswer: "Der WARP-Tunnel hat nicht geantwortet",
    listEmpty: "Ihre Proxy-Liste ist leer. Tray > Einstellungen bearbeiten.", listNone: "Kein Proxy der Liste lieferte eine andere IP.", directNoIp: "Im direkten Modus gibt es keine IP zu \u00e4ndern. W\u00e4hlen Sie eine andere Verbindung.",
    onWg: "Integriertes WARP an. IP {ip}", onWgfile: "WireGuard-Datei an. IP {ip}", onFree: "\u00d6ffentlicher Proxy {host} an. IP {ip}", onList: "Eigene Proxy-Liste an. Mit Neue IP w\u00e4hlen Sie einen Proxy.",
    onDirect: "Direkt: die App nutzt Ihre normale Verbindung.", noneChosen: "Nichts gew\u00e4hlt. Verbindung unver\u00e4ndert.", backDirect: "(zur\u00fcck auf direkt)",
    statusLine: "IP {ip} ({mode})", statusNone: "Keine Verbindung mit der aktuellen Einstellung.",
    mDirect: "direkt", mWg: "integriertes WARP", mWgfile: "WireGuard-Datei", mFree: "\u00f6ffentlicher Proxy", mList: "Proxy-Liste", autoOn: "Automatischer Wechsel an.", autoOff: "Automatischer Wechsel aus.",
    noLogin: "Auf diesem PC ist keine Anmeldung (auth.json) gespeichert. Nichts zu bereinigen.", loginExists: "Es gibt bereits eine Anmeldung, daher wurde nichts wiederhergestellt.", noBackup: "Keine Anmeldungssicherung zum Wiederherstellen.",
    doneLogin: "Anmeldung entfernt (eine Kopie ist gesichert). Chats bleiben.", failVerify: "Die Sicherung lie\u00df sich nicht pr\u00fcfen, daher wurde die Anmeldung nicht entfernt.", doneRestore: "Anmeldung aus {from} wiederhergestellt.",
    doneCache: "Cache und Protokolle gel\u00f6scht ({mb} MB). Chats bleiben.", failClean: "Bereinigung fehlgeschlagen: {err}",
    limitWarn: "Gratis-Limit erreicht. Der automatische Wechsel braucht Verbindung > Integriertes WARP oder Eigene Proxy-Liste.", limitRotating: "Gratis-Limit erreicht: IP wird gewechselt...",
    eReg: "WARP-Registrierung abgelehnt (HTTP {status}); versuchen Sie es in einigen Minuten erneut", eNoFile: "Noch keine WireGuard-Datei gew\u00e4hlt. Tray > Verbindung > WireGuard-Datei w\u00e4hlen.",
    eFileDead: "Der Tunnel dieser WireGuard-Datei hat nicht geantwortet", eWarpDead: "Der WARP-Tunnel hat nicht geantwortet (ist UDP 2408 blockiert?)",
    eNoList: "Keine \u00f6ffentliche Proxy-Liste konnte geladen werden", eNoProxy: "Kein \u00f6ffentlicher Proxy antwortete rechtzeitig (erneut versuchen)", dlgChoose: "WireGuard-.conf-Datei w\u00e4hlen" },
  ru: { name: "\u0420\u0443\u0441\u0441\u043a\u0438\u0439",
    m_newIp: "\u041d\u043e\u0432\u044b\u0439 IP", m_connection: "\u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435", m_direct: "\u041d\u0430\u043f\u0440\u044f\u043c\u0443\u044e", m_wg: "\u0412\u0441\u0442\u0440\u043e\u0435\u043d\u043d\u044b\u0439 WARP", m_wgfile: "\u0424\u0430\u0439\u043b WireGuard", m_free: "\u0411\u0435\u0441\u043f\u043b\u0430\u0442\u043d\u044b\u0435 \u043f\u0443\u0431\u043b\u0438\u0447\u043d\u044b\u0435 \u043f\u0440\u043e\u043a\u0441\u0438 (\u043d\u0435\u043d\u0430\u0434\u0451\u0436\u043d\u044b\u0435)", m_list: "\u0421\u0432\u043e\u0439 \u0441\u043f\u0438\u0441\u043e\u043a \u043f\u0440\u043e\u043a\u0441\u0438",
    m_chooseWg: "\u0412\u044b\u0431\u0440\u0430\u0442\u044c \u0444\u0430\u0439\u043b WireGuard...", m_settings: "\u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438 (\u043f\u0440\u043e\u043a\u0441\u0438, \u043a\u043e\u043d\u0442\u0435\u043a\u0441\u0442)", m_auto: "\u0410\u0432\u0442\u043e\u0441\u043c\u0435\u043d\u0430 IP", m_clear: "\u041e\u0447\u0438\u0441\u0442\u043a\u0430", m_clearLogin: "\u0412\u0445\u043e\u0434 (\u0447\u0430\u0442\u044b \u0441\u043e\u0445\u0440\u0430\u043d\u044f\u044e\u0442\u0441\u044f)", m_restoreLogin: "\u0412\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u0438\u0442\u044c \u0432\u0445\u043e\u0434",
    m_clearCache: "\u041a\u044d\u0448 \u0438 \u043b\u043e\u0433\u0438", m_status: "\u0421\u043e\u0441\u0442\u043e\u044f\u043d\u0438\u0435", m_restart: "\u041f\u0435\u0440\u0435\u0437\u0430\u043f\u0443\u0441\u0442\u0438\u0442\u044c {app}", m_quit: "\u0412\u044b\u0445\u043e\u0434", m_language: "\u042f\u0437\u044b\u043a", m_langAuto: "\u0410\u0432\u0442\u043e\u043c\u0430\u0442\u0438\u0447\u0435\u0441\u043a\u0438",
    busy: "\u0414\u0440\u0443\u0433\u043e\u0435 \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u0435 \u0435\u0449\u0451 \u0432\u044b\u043f\u043e\u043b\u043d\u044f\u0435\u0442\u0441\u044f.", ipWg: "\u041d\u043e\u0432\u044b\u0439 IP {ip} (\u0432\u0441\u0442\u0440\u043e\u0435\u043d\u043d\u044b\u0439 WARP)", ipFree: "\u041d\u043e\u0432\u044b\u0439 IP {ip} (\u043f\u0443\u0431\u043b\u0438\u0447\u043d\u044b\u0439 \u043f\u0440\u043e\u043a\u0441\u0438 {host})", ipList: "\u041d\u043e\u0432\u044b\u0439 IP {ip} (\u043f\u0440\u043e\u043a\u0441\u0438 {host})",
    wgfileFixed: "\u0423 \u0444\u0430\u0439\u043b\u0430 WireGuard \u0444\u0438\u043a\u0441\u0438\u0440\u043e\u0432\u0430\u043d\u043d\u044b\u0439 \u0432\u044b\u0445\u043e\u0434\u043d\u043e\u0439 IP. {msg}. \u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u0434\u0440\u0443\u0433\u043e\u0439 \u0444\u0430\u0439\u043b \u0438\u043b\u0438 \u0434\u0440\u0443\u0433\u043e\u0435 \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435, \u0447\u0442\u043e\u0431\u044b \u0441\u043c\u0435\u043d\u0438\u0442\u044c \u0435\u0433\u043e.",
    sameIp: "\u041d\u043e\u0432\u0430\u044f \u0443\u0447\u0451\u0442\u043d\u0430\u044f \u0437\u0430\u043f\u0438\u0441\u044c WARP, \u043d\u043e IP \u043e\u0441\u0442\u0430\u043b\u0441\u044f {ip} (WARP \u0438\u0441\u043f\u043e\u043b\u044c\u0437\u0443\u0435\u0442 \u0431\u043b\u0438\u0436\u0430\u0439\u0448\u0438\u0439 \u0441\u0435\u0440\u0432\u0435\u0440 Cloudflare)", noAnswer: "\u0422\u0443\u043d\u043d\u0435\u043b\u044c WARP \u043d\u0435 \u043e\u0442\u0432\u0435\u0442\u0438\u043b",
    listEmpty: "\u0412\u0430\u0448 \u0441\u043f\u0438\u0441\u043e\u043a \u043f\u0440\u043e\u043a\u0441\u0438 \u043f\u0443\u0441\u0442. \u0422\u0440\u0435\u0439 > \u041d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0438.", listNone: "\u041d\u0438 \u043e\u0434\u0438\u043d \u043f\u0440\u043e\u043a\u0441\u0438 \u0438\u0437 \u0441\u043f\u0438\u0441\u043a\u0430 \u043d\u0435 \u0434\u0430\u043b \u0434\u0440\u0443\u0433\u043e\u0439 IP.", directNoIp: "\u0412 \u043f\u0440\u044f\u043c\u043e\u043c \u0440\u0435\u0436\u0438\u043c\u0435 \u043d\u0435\u0442 IP \u0434\u043b\u044f \u0441\u043c\u0435\u043d\u044b. \u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u0434\u0440\u0443\u0433\u043e\u0435 \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435.",
    onWg: "\u0412\u0441\u0442\u0440\u043e\u0435\u043d\u043d\u044b\u0439 WARP \u0432\u043a\u043b\u044e\u0447\u0451\u043d. IP {ip}", onWgfile: "\u0424\u0430\u0439\u043b WireGuard \u0432\u043a\u043b\u044e\u0447\u0451\u043d. IP {ip}", onFree: "\u041f\u0443\u0431\u043b\u0438\u0447\u043d\u044b\u0439 \u043f\u0440\u043e\u043a\u0441\u0438 {host} \u0432\u043a\u043b\u044e\u0447\u0451\u043d. IP {ip}", onList: "\u0421\u043f\u0438\u0441\u043e\u043a \u043f\u0440\u043e\u043a\u0441\u0438 \u0432\u043a\u043b\u044e\u0447\u0451\u043d. \u041d\u0430\u0436\u043c\u0438\u0442\u0435 \u00ab\u041d\u043e\u0432\u044b\u0439 IP\u00bb, \u0447\u0442\u043e\u0431\u044b \u0432\u044b\u0431\u0440\u0430\u0442\u044c \u043f\u0440\u043e\u043a\u0441\u0438.",
    onDirect: "\u041d\u0430\u043f\u0440\u044f\u043c\u0443\u044e: \u043f\u0440\u0438\u043b\u043e\u0436\u0435\u043d\u0438\u0435 \u0438\u0441\u043f\u043e\u043b\u044c\u0437\u0443\u0435\u0442 \u043e\u0431\u044b\u0447\u043d\u043e\u0435 \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435.", noneChosen: "\u041d\u0438\u0447\u0435\u0433\u043e \u043d\u0435 \u0432\u044b\u0431\u0440\u0430\u043d\u043e. \u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435 \u043d\u0435 \u0438\u0437\u043c\u0435\u043d\u0435\u043d\u043e.", backDirect: "(\u0432\u043e\u0437\u0432\u0440\u0430\u0442 \u043a \u043f\u0440\u044f\u043c\u043e\u043c\u0443)",
    statusLine: "IP {ip} ({mode})", statusNone: "\u041d\u0435\u0442 \u0441\u043e\u0435\u0434\u0438\u043d\u0435\u043d\u0438\u044f \u043f\u0440\u0438 \u0442\u0435\u043a\u0443\u0449\u0438\u0445 \u043d\u0430\u0441\u0442\u0440\u043e\u0439\u043a\u0430\u0445.",
    mDirect: "\u043d\u0430\u043f\u0440\u044f\u043c\u0443\u044e", mWg: "\u0432\u0441\u0442\u0440\u043e\u0435\u043d\u043d\u044b\u0439 WARP", mWgfile: "\u0444\u0430\u0439\u043b WireGuard", mFree: "\u043f\u0443\u0431\u043b\u0438\u0447\u043d\u044b\u0439 \u043f\u0440\u043e\u043a\u0441\u0438", mList: "\u0441\u043f\u0438\u0441\u043e\u043a \u043f\u0440\u043e\u043a\u0441\u0438", autoOn: "\u0410\u0432\u0442\u043e\u0441\u043c\u0435\u043d\u0430 IP \u0432\u043a\u043b\u044e\u0447\u0435\u043d\u0430.", autoOff: "\u0410\u0432\u0442\u043e\u0441\u043c\u0435\u043d\u0430 IP \u0432\u044b\u043a\u043b\u044e\u0447\u0435\u043d\u0430.",
    noLogin: "\u041d\u0430 \u044d\u0442\u043e\u043c \u041f\u041a \u043d\u0435\u0442 \u0441\u043e\u0445\u0440\u0430\u043d\u0451\u043d\u043d\u043e\u0433\u043e \u0432\u0445\u043e\u0434\u0430 (auth.json). \u041d\u0435\u0447\u0435\u0433\u043e \u043e\u0447\u0438\u0449\u0430\u0442\u044c.", loginExists: "\u0412\u0445\u043e\u0434 \u0443\u0436\u0435 \u0441\u0443\u0449\u0435\u0441\u0442\u0432\u0443\u0435\u0442, \u043f\u043e\u044d\u0442\u043e\u043c\u0443 \u043d\u0438\u0447\u0435\u0433\u043e \u043d\u0435 \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u043e.", noBackup: "\u041d\u0435\u0442 \u0440\u0435\u0437\u0435\u0440\u0432\u043d\u043e\u0439 \u043a\u043e\u043f\u0438\u0438 \u0432\u0445\u043e\u0434\u0430 \u0434\u043b\u044f \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d\u0438\u044f.",
    doneLogin: "\u0412\u0445\u043e\u0434 \u0443\u0434\u0430\u043b\u0451\u043d (\u043a\u043e\u043f\u0438\u044f \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u0430). \u0427\u0430\u0442\u044b \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u044b.", failVerify: "\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043f\u0440\u043e\u0432\u0435\u0440\u0438\u0442\u044c \u043a\u043e\u043f\u0438\u044e \u0432\u0445\u043e\u0434\u0430, \u043f\u043e\u044d\u0442\u043e\u043c\u0443 \u0432\u0445\u043e\u0434 \u043d\u0435 \u0443\u0434\u0430\u043b\u0451\u043d.", doneRestore: "\u0412\u0445\u043e\u0434 \u0432\u043e\u0441\u0441\u0442\u0430\u043d\u043e\u0432\u043b\u0435\u043d \u0438\u0437 {from}.",
    doneCache: "\u041a\u044d\u0448 \u0438 \u043b\u043e\u0433\u0438 \u043e\u0447\u0438\u0449\u0435\u043d\u044b ({mb} \u041c\u0411). \u0427\u0430\u0442\u044b \u0441\u043e\u0445\u0440\u0430\u043d\u0435\u043d\u044b.", failClean: "\u041e\u0447\u0438\u0441\u0442\u043a\u0430 \u043d\u0435 \u0443\u0434\u0430\u043b\u0430\u0441\u044c: {err}",
    limitWarn: "\u0411\u0435\u0441\u043f\u043b\u0430\u0442\u043d\u044b\u0439 \u043b\u0438\u043c\u0438\u0442 \u0438\u0441\u0447\u0435\u0440\u043f\u0430\u043d. \u0414\u043b\u044f \u0430\u0432\u0442\u043e\u0441\u043c\u0435\u043d\u044b \u043d\u0443\u0436\u043d\u043e \u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435 > \u0412\u0441\u0442\u0440\u043e\u0435\u043d\u043d\u044b\u0439 WARP \u0438\u043b\u0438 \u0421\u0432\u043e\u0439 \u0441\u043f\u0438\u0441\u043e\u043a \u043f\u0440\u043e\u043a\u0441\u0438.", limitRotating: "\u0411\u0435\u0441\u043f\u043b\u0430\u0442\u043d\u044b\u0439 \u043b\u0438\u043c\u0438\u0442 \u0438\u0441\u0447\u0435\u0440\u043f\u0430\u043d: \u043c\u0435\u043d\u044f\u044e IP...",
    eReg: "\u0420\u0435\u0433\u0438\u0441\u0442\u0440\u0430\u0446\u0438\u044f WARP \u043e\u0442\u043a\u043b\u043e\u043d\u0435\u043d\u0430 (HTTP {status}); \u043f\u043e\u0432\u0442\u043e\u0440\u0438\u0442\u0435 \u0447\u0435\u0440\u0435\u0437 \u043d\u0435\u0441\u043a\u043e\u043b\u044c\u043a\u043e \u043c\u0438\u043d\u0443\u0442", eNoFile: "\u0424\u0430\u0439\u043b WireGuard \u0435\u0449\u0451 \u043d\u0435 \u0432\u044b\u0431\u0440\u0430\u043d. \u0422\u0440\u0435\u0439 > \u041f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u0435 > \u0412\u044b\u0431\u0440\u0430\u0442\u044c \u0444\u0430\u0439\u043b WireGuard.",
    eFileDead: "\u0422\u0443\u043d\u043d\u0435\u043b\u044c \u044d\u0442\u043e\u0433\u043e \u0444\u0430\u0439\u043b\u0430 WireGuard \u043d\u0435 \u043e\u0442\u0432\u0435\u0442\u0438\u043b", eWarpDead: "\u0422\u0443\u043d\u043d\u0435\u043b\u044c WARP \u043d\u0435 \u043e\u0442\u0432\u0435\u0442\u0438\u043b (UDP-\u043f\u043e\u0440\u0442 2408 \u0437\u0430\u0431\u043b\u043e\u043a\u0438\u0440\u043e\u0432\u0430\u043d?)",
    eNoList: "\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0437\u0430\u0433\u0440\u0443\u0437\u0438\u0442\u044c \u043d\u0438 \u043e\u0434\u0438\u043d \u0441\u043f\u0438\u0441\u043e\u043a \u043f\u0443\u0431\u043b\u0438\u0447\u043d\u044b\u0445 \u043f\u0440\u043e\u043a\u0441\u0438", eNoProxy: "\u041d\u0438 \u043e\u0434\u0438\u043d \u043f\u0443\u0431\u043b\u0438\u0447\u043d\u044b\u0439 \u043f\u0440\u043e\u043a\u0441\u0438 \u043d\u0435 \u043e\u0442\u0432\u0435\u0442\u0438\u043b \u0432\u043e\u0432\u0440\u0435\u043c\u044f (\u043f\u043e\u0432\u0442\u043e\u0440\u0438\u0442\u0435)", dlgChoose: "\u0412\u044b\u0431\u0435\u0440\u0438\u0442\u0435 \u0444\u0430\u0439\u043b WireGuard .conf" },
  "zh-CN": { name: "\u7b80\u4f53\u4e2d\u6587",
    m_newIp: "\u66f4\u6362 IP", m_connection: "\u8fde\u63a5\u65b9\u5f0f", m_direct: "\u76f4\u8fde", m_wg: "\u5185\u7f6e WARP", m_wgfile: "WireGuard \u6587\u4ef6", m_free: "\u514d\u8d39\u516c\u5171\u4ee3\u7406\uff08\u4e0d\u53ef\u4fe1\uff09", m_list: "\u6211\u7684\u4ee3\u7406\u5217\u8868",
    m_chooseWg: "\u9009\u62e9 WireGuard \u6587\u4ef6...", m_settings: "\u7f16\u8f91\u8bbe\u7f6e\uff08\u4ee3\u7406\u5217\u8868\u3001\u4e0a\u4e0b\u6587\uff09", m_auto: "\u81ea\u52a8\u8f6e\u6362", m_clear: "\u6e05\u7406", m_clearLogin: "\u767b\u5f55\u4fe1\u606f\uff08\u4fdd\u7559\u804a\u5929\uff09", m_restoreLogin: "\u6062\u590d\u767b\u5f55\u4fe1\u606f",
    m_clearCache: "\u7f13\u5b58\u548c\u65e5\u5fd7", m_status: "\u72b6\u6001", m_restart: "\u91cd\u542f {app}", m_quit: "\u9000\u51fa", m_language: "\u8bed\u8a00", m_langAuto: "\u81ea\u52a8",
    busy: "\u53e6\u4e00\u4e2a\u64cd\u4f5c\u4ecd\u5728\u8fdb\u884c\u3002", ipWg: "\u65b0 IP {ip}\uff08\u5185\u7f6e WARP\uff09", ipFree: "\u65b0 IP {ip}\uff08\u516c\u5171\u4ee3\u7406 {host}\uff09", ipList: "\u65b0 IP {ip}\uff08\u4ee3\u7406 {host}\uff09",
    wgfileFixed: "WireGuard \u6587\u4ef6\u7684\u51fa\u53e3 IP \u662f\u56fa\u5b9a\u7684\u3002{msg}\u3002\u8bf7\u9009\u62e9\u5176\u4ed6\u6587\u4ef6\u6216\u5176\u4ed6\u8fde\u63a5\u65b9\u5f0f\u6765\u66f4\u6362\u3002",
    sameIp: "\u5df2\u521b\u5efa\u65b0\u7684 WARP \u8d26\u6237\uff0c\u4f46 IP \u4ecd\u662f {ip}\uff08WARP \u4f7f\u7528\u6700\u8fd1\u7684 Cloudflare \u670d\u52a1\u5668\uff09", noAnswer: "WARP \u96a7\u9053\u6ca1\u6709\u54cd\u5e94",
    listEmpty: "\u4f60\u7684\u4ee3\u7406\u5217\u8868\u4e3a\u7a7a\u3002\u6258\u76d8 > \u7f16\u8f91\u8bbe\u7f6e\u3002", listNone: "\u5217\u8868\u4e2d\u6ca1\u6709\u4ee3\u7406\u7ed9\u51fa\u4e0d\u540c\u7684 IP\u3002", directNoIp: "\u76f4\u8fde\u6a21\u5f0f\u6ca1\u6709\u53ef\u66f4\u6362\u7684 IP\u3002\u8bf7\u9009\u62e9\u5176\u4ed6\u8fde\u63a5\u65b9\u5f0f\u3002",
    onWg: "\u5185\u7f6e WARP \u5df2\u5f00\u542f\u3002IP {ip}", onWgfile: "WireGuard \u6587\u4ef6\u5df2\u5f00\u542f\u3002IP {ip}", onFree: "\u516c\u5171\u4ee3\u7406 {host} \u5df2\u5f00\u542f\u3002IP {ip}", onList: "\u4ee3\u7406\u5217\u8868\u5df2\u5f00\u542f\u3002\u70b9\u51fb\u201c\u66f4\u6362 IP\u201d\u6765\u9009\u62e9\u4ee3\u7406\u3002",
    onDirect: "\u76f4\u8fde\uff1a\u5e94\u7528\u4f7f\u7528\u4f60\u7684\u6b63\u5e38\u7f51\u7edc\u3002", noneChosen: "\u672a\u9009\u62e9\u4efb\u4f55\u5185\u5bb9\u3002\u8fde\u63a5\u4fdd\u6301\u4e0d\u53d8\u3002", backDirect: "\uff08\u5df2\u56de\u5230\u76f4\u8fde\uff09",
    statusLine: "IP {ip}\uff08{mode}\uff09", statusNone: "\u5f53\u524d\u8bbe\u7f6e\u4e0b\u6ca1\u6709\u8fde\u63a5\u3002",
    mDirect: "\u76f4\u8fde", mWg: "\u5185\u7f6e WARP", mWgfile: "WireGuard \u6587\u4ef6", mFree: "\u516c\u5171\u4ee3\u7406", mList: "\u4ee3\u7406\u5217\u8868", autoOn: "\u81ea\u52a8\u8f6e\u6362\u5df2\u5f00\u542f\u3002", autoOff: "\u81ea\u52a8\u8f6e\u6362\u5df2\u5173\u95ed\u3002",
    noLogin: "\u6b64\u7535\u8111\u4e0a\u6ca1\u6709\u5df2\u4fdd\u5b58\u7684\u767b\u5f55\u4fe1\u606f (auth.json)\u3002\u65e0\u9700\u6e05\u7406\u3002", loginExists: "\u5df2\u5b58\u5728\u767b\u5f55\u4fe1\u606f\uff0c\u56e0\u6b64\u672a\u6062\u590d\u4efb\u4f55\u5185\u5bb9\u3002", noBackup: "\u6ca1\u6709\u53ef\u6062\u590d\u7684\u767b\u5f55\u5907\u4efd\u3002",
    doneLogin: "\u767b\u5f55\u4fe1\u606f\u5df2\u79fb\u9664\uff08\u5df2\u4fdd\u5b58\u526f\u672c\uff09\u3002\u804a\u5929\u5df2\u4fdd\u7559\u3002", failVerify: "\u65e0\u6cd5\u9a8c\u8bc1\u767b\u5f55\u5907\u4efd\uff0c\u56e0\u6b64\u672a\u79fb\u9664\u767b\u5f55\u4fe1\u606f\u3002", doneRestore: "\u5df2\u4ece {from} \u6062\u590d\u767b\u5f55\u4fe1\u606f\u3002",
    doneCache: "\u7f13\u5b58\u548c\u65e5\u5fd7\u5df2\u6e05\u7406\uff08{mb} MB\uff09\u3002\u804a\u5929\u5df2\u4fdd\u7559\u3002", failClean: "\u6e05\u7406\u5931\u8d25\uff1a{err}",
    limitWarn: "\u5df2\u8fbe\u5230\u514d\u8d39\u989d\u5ea6\u3002\u81ea\u52a8\u8f6e\u6362\u9700\u8981\u201c\u8fde\u63a5\u65b9\u5f0f > \u5185\u7f6e WARP\u201d\u6216\u201c\u6211\u7684\u4ee3\u7406\u5217\u8868\u201d\u3002", limitRotating: "\u5df2\u8fbe\u5230\u514d\u8d39\u989d\u5ea6\uff1a\u6b63\u5728\u66f4\u6362 IP...",
    eReg: "WARP \u6ce8\u518c\u88ab\u62d2\u7edd\uff08HTTP {status}\uff09\uff1b\u8bf7\u51e0\u5206\u949f\u540e\u91cd\u8bd5", eNoFile: "\u5c1a\u672a\u9009\u62e9 WireGuard \u6587\u4ef6\u3002\u6258\u76d8 > \u8fde\u63a5\u65b9\u5f0f > \u9009\u62e9 WireGuard \u6587\u4ef6\u3002",
    eFileDead: "\u8be5 WireGuard \u6587\u4ef6\u7684\u96a7\u9053\u6ca1\u6709\u54cd\u5e94", eWarpDead: "WARP \u96a7\u9053\u6ca1\u6709\u54cd\u5e94\uff08UDP 2408 \u7aef\u53e3\u662f\u5426\u88ab\u5c01\u9501\uff1f\uff09",
    eNoList: "\u65e0\u6cd5\u4e0b\u8f7d\u4efb\u4f55\u516c\u5171\u4ee3\u7406\u5217\u8868", eNoProxy: "\u6ca1\u6709\u516c\u5171\u4ee3\u7406\u53ca\u65f6\u54cd\u5e94\uff08\u8bf7\u91cd\u8bd5\uff09", dlgChoose: "\u9009\u62e9 WireGuard .conf \u6587\u4ef6" },
  ja: { name: "\u65e5\u672c\u8a9e",
    m_newIp: "\u65b0\u3057\u3044 IP", m_connection: "\u63a5\u7d9a", m_direct: "\u76f4\u63a5", m_wg: "\u5185\u8535 WARP", m_wgfile: "WireGuard \u30d5\u30a1\u30a4\u30eb", m_free: "\u7121\u6599\u306e\u516c\u958b\u30d7\u30ed\u30ad\u30b7\uff08\u4fe1\u983c\u4e0d\u53ef\uff09", m_list: "\u81ea\u5206\u306e\u30d7\u30ed\u30ad\u30b7\u4e00\u89a7",
    m_chooseWg: "WireGuard \u30d5\u30a1\u30a4\u30eb\u3092\u9078\u629e...", m_settings: "\u8a2d\u5b9a\u3092\u7de8\u96c6\uff08\u30d7\u30ed\u30ad\u30b7\u3001\u30b3\u30f3\u30c6\u30ad\u30b9\u30c8\uff09", m_auto: "\u81ea\u52d5\u30ed\u30fc\u30c6\u30fc\u30b7\u30e7\u30f3", m_clear: "\u30af\u30ea\u30a2", m_clearLogin: "\u30ed\u30b0\u30a4\u30f3\uff08\u30c1\u30e3\u30c3\u30c8\u306f\u4fdd\u6301\uff09", m_restoreLogin: "\u30ed\u30b0\u30a4\u30f3\u3092\u5fa9\u5143",
    m_clearCache: "\u30ad\u30e3\u30c3\u30b7\u30e5\u3068\u30ed\u30b0", m_status: "\u72b6\u614b", m_restart: "{app} \u3092\u518d\u8d77\u52d5", m_quit: "\u7d42\u4e86", m_language: "\u8a00\u8a9e", m_langAuto: "\u81ea\u52d5",
    busy: "\u5225\u306e\u64cd\u4f5c\u304c\u307e\u3060\u5b9f\u884c\u4e2d\u3067\u3059\u3002", ipWg: "\u65b0\u3057\u3044 IP {ip}\uff08\u5185\u8535 WARP\uff09", ipFree: "\u65b0\u3057\u3044 IP {ip}\uff08\u516c\u958b\u30d7\u30ed\u30ad\u30b7 {host}\uff09", ipList: "\u65b0\u3057\u3044 IP {ip}\uff08\u30d7\u30ed\u30ad\u30b7 {host}\uff09",
    wgfileFixed: "WireGuard \u30d5\u30a1\u30a4\u30eb\u306e\u51fa\u53e3 IP \u306f\u56fa\u5b9a\u3067\u3059\u3002{msg}\u3002\u5909\u66f4\u3059\u308b\u306b\u306f\u5225\u306e\u30d5\u30a1\u30a4\u30eb\u304b\u5225\u306e\u63a5\u7d9a\u3092\u9078\u3093\u3067\u304f\u3060\u3055\u3044\u3002",
    sameIp: "\u65b0\u3057\u3044 WARP \u30a2\u30ab\u30a6\u30f3\u30c8\u3067\u3059\u304c\u3001IP \u306f {ip} \u306e\u307e\u307e\u3067\u3059\uff08WARP \u306f\u6700\u5bc4\u308a\u306e Cloudflare \u30b5\u30fc\u30d0\u30fc\u3092\u4f7f\u3044\u307e\u3059\uff09", noAnswer: "WARP \u30c8\u30f3\u30cd\u30eb\u304c\u5fdc\u7b54\u3057\u307e\u305b\u3093\u3067\u3057\u305f",
    listEmpty: "\u30d7\u30ed\u30ad\u30b7\u4e00\u89a7\u304c\u7a7a\u3067\u3059\u3002\u30c8\u30ec\u30a4 > \u8a2d\u5b9a\u3092\u7de8\u96c6\u3002", listNone: "\u4e00\u89a7\u306e\u3069\u306e\u30d7\u30ed\u30ad\u30b7\u3082\u5225\u306e IP \u3092\u8fd4\u3057\u307e\u305b\u3093\u3067\u3057\u305f\u3002", directNoIp: "\u76f4\u63a5\u30e2\u30fc\u30c9\u306b\u306f\u5909\u66f4\u3067\u304d\u308b IP \u304c\u3042\u308a\u307e\u305b\u3093\u3002\u5225\u306e\u63a5\u7d9a\u3092\u9078\u3093\u3067\u304f\u3060\u3055\u3044\u3002",
    onWg: "\u5185\u8535 WARP \u3092\u30aa\u30f3\u306b\u3057\u307e\u3057\u305f\u3002IP {ip}", onWgfile: "WireGuard \u30d5\u30a1\u30a4\u30eb\u3092\u30aa\u30f3\u306b\u3057\u307e\u3057\u305f\u3002IP {ip}", onFree: "\u516c\u958b\u30d7\u30ed\u30ad\u30b7 {host} \u3092\u30aa\u30f3\u306b\u3057\u307e\u3057\u305f\u3002IP {ip}", onList: "\u30d7\u30ed\u30ad\u30b7\u4e00\u89a7\u3092\u30aa\u30f3\u306b\u3057\u307e\u3057\u305f\u3002\u300c\u65b0\u3057\u3044 IP\u300d\u3067\u30d7\u30ed\u30ad\u30b7\u3092\u9078\u3073\u307e\u3059\u3002",
    onDirect: "\u76f4\u63a5\uff1a\u30a2\u30d7\u30ea\u306f\u901a\u5e38\u306e\u63a5\u7d9a\u3092\u4f7f\u3044\u307e\u3059\u3002", noneChosen: "\u4f55\u3082\u9078\u3070\u308c\u307e\u305b\u3093\u3067\u3057\u305f\u3002\u63a5\u7d9a\u306f\u5909\u308f\u308a\u307e\u305b\u3093\u3002", backDirect: "\uff08\u76f4\u63a5\u306b\u623b\u308a\u307e\u3057\u305f\uff09",
    statusLine: "IP {ip}\uff08{mode}\uff09", statusNone: "\u73fe\u5728\u306e\u8a2d\u5b9a\u3067\u306f\u63a5\u7d9a\u3067\u304d\u307e\u305b\u3093\u3002",
    mDirect: "\u76f4\u63a5", mWg: "\u5185\u8535 WARP", mWgfile: "WireGuard \u30d5\u30a1\u30a4\u30eb", mFree: "\u516c\u958b\u30d7\u30ed\u30ad\u30b7", mList: "\u30d7\u30ed\u30ad\u30b7\u4e00\u89a7", autoOn: "\u81ea\u52d5\u30ed\u30fc\u30c6\u30fc\u30b7\u30e7\u30f3\u3092\u30aa\u30f3\u306b\u3057\u307e\u3057\u305f\u3002", autoOff: "\u81ea\u52d5\u30ed\u30fc\u30c6\u30fc\u30b7\u30e7\u30f3\u3092\u30aa\u30d5\u306b\u3057\u307e\u3057\u305f\u3002",
    noLogin: "\u3053\u306e PC \u306b\u4fdd\u5b58\u3055\u308c\u305f\u30ed\u30b0\u30a4\u30f3 (auth.json) \u306f\u3042\u308a\u307e\u305b\u3093\u3002\u6d88\u53bb\u3059\u308b\u3082\u306e\u306f\u3042\u308a\u307e\u305b\u3093\u3002", loginExists: "\u3059\u3067\u306b\u30ed\u30b0\u30a4\u30f3\u304c\u3042\u308b\u305f\u3081\u3001\u4f55\u3082\u5fa9\u5143\u3057\u307e\u305b\u3093\u3067\u3057\u305f\u3002", noBackup: "\u5fa9\u5143\u3067\u304d\u308b\u30ed\u30b0\u30a4\u30f3\u306e\u30d0\u30c3\u30af\u30a2\u30c3\u30d7\u304c\u3042\u308a\u307e\u305b\u3093\u3002",
    doneLogin: "\u30ed\u30b0\u30a4\u30f3\u3092\u524a\u9664\u3057\u307e\u3057\u305f\uff08\u30b3\u30d4\u30fc\u306f\u4fdd\u5b58\u6e08\u307f\uff09\u3002\u30c1\u30e3\u30c3\u30c8\u306f\u4fdd\u6301\u3055\u308c\u307e\u3059\u3002", failVerify: "\u30d0\u30c3\u30af\u30a2\u30c3\u30d7\u3092\u78ba\u8a8d\u3067\u304d\u306a\u304b\u3063\u305f\u305f\u3081\u3001\u30ed\u30b0\u30a4\u30f3\u306f\u524a\u9664\u3057\u307e\u305b\u3093\u3067\u3057\u305f\u3002", doneRestore: "{from} \u304b\u3089\u30ed\u30b0\u30a4\u30f3\u3092\u5fa9\u5143\u3057\u307e\u3057\u305f\u3002",
    doneCache: "\u30ad\u30e3\u30c3\u30b7\u30e5\u3068\u30ed\u30b0\u3092\u6d88\u53bb\u3057\u307e\u3057\u305f\uff08{mb} MB\uff09\u3002\u30c1\u30e3\u30c3\u30c8\u306f\u4fdd\u6301\u3055\u308c\u307e\u3059\u3002", failClean: "\u30af\u30ea\u30a2\u306b\u5931\u6557\u3057\u307e\u3057\u305f\uff1a{err}",
    limitWarn: "\u7121\u6599\u67a0\u306e\u4e0a\u9650\u306b\u9054\u3057\u307e\u3057\u305f\u3002\u81ea\u52d5\u30ed\u30fc\u30c6\u30fc\u30b7\u30e7\u30f3\u306b\u306f\u300c\u63a5\u7d9a > \u5185\u8535 WARP\u300d\u307e\u305f\u306f\u300c\u81ea\u5206\u306e\u30d7\u30ed\u30ad\u30b7\u4e00\u89a7\u300d\u304c\u5fc5\u8981\u3067\u3059\u3002", limitRotating: "\u7121\u6599\u67a0\u306e\u4e0a\u9650\u306b\u9054\u3057\u307e\u3057\u305f\uff1aIP \u3092\u5909\u66f4\u3057\u3066\u3044\u307e\u3059...",
    eReg: "WARP \u306e\u767b\u9332\u304c\u62d2\u5426\u3055\u308c\u307e\u3057\u305f\uff08HTTP {status}\uff09\u3002\u6570\u5206\u5f8c\u306b\u3082\u3046\u4e00\u5ea6\u304a\u8a66\u3057\u304f\u3060\u3055\u3044", eNoFile: "WireGuard \u30d5\u30a1\u30a4\u30eb\u304c\u307e\u3060\u9078\u3070\u308c\u3066\u3044\u307e\u305b\u3093\u3002\u30c8\u30ec\u30a4 > \u63a5\u7d9a > WireGuard \u30d5\u30a1\u30a4\u30eb\u3092\u9078\u629e\u3002",
    eFileDead: "\u305d\u306e WireGuard \u30d5\u30a1\u30a4\u30eb\u306e\u30c8\u30f3\u30cd\u30eb\u304c\u5fdc\u7b54\u3057\u307e\u305b\u3093\u3067\u3057\u305f", eWarpDead: "WARP \u30c8\u30f3\u30cd\u30eb\u304c\u5fdc\u7b54\u3057\u307e\u305b\u3093\u3067\u3057\u305f\uff08UDP 2408 \u304c\u30d6\u30ed\u30c3\u30af\u3055\u308c\u3066\u3044\u307e\u305b\u3093\u304b\uff1f\uff09",
    eNoList: "\u516c\u958b\u30d7\u30ed\u30ad\u30b7\u4e00\u89a7\u3092\u30c0\u30a6\u30f3\u30ed\u30fc\u30c9\u3067\u304d\u307e\u305b\u3093\u3067\u3057\u305f", eNoProxy: "\u6642\u9593\u5185\u306b\u5fdc\u7b54\u3057\u305f\u516c\u958b\u30d7\u30ed\u30ad\u30b7\u304c\u3042\u308a\u307e\u305b\u3093\uff08\u3082\u3046\u4e00\u5ea6\u304a\u8a66\u3057\u304f\u3060\u3055\u3044\uff09", dlgChoose: "WireGuard \u306e .conf \u30d5\u30a1\u30a4\u30eb\u3092\u9078\u629e" },
  ko: { name: "\ud55c\uad6d\uc5b4",
    m_newIp: "\uc0c8 IP", m_connection: "\uc5f0\uacb0", m_direct: "\uc9c1\uc811", m_wg: "\ub0b4\uc7a5 WARP", m_wgfile: "WireGuard \ud30c\uc77c", m_free: "\ubb34\ub8cc \uacf5\uac1c \ud504\ub85d\uc2dc (\uc2e0\ub8b0 \ubd88\uac00)", m_list: "\ub0b4 \ud504\ub85d\uc2dc \ubaa9\ub85d",
    m_chooseWg: "WireGuard \ud30c\uc77c \uc120\ud0dd...", m_settings: "\uc124\uc815 \ud3b8\uc9d1 (\ud504\ub85d\uc2dc, \ucee8\ud14d\uc2a4\ud2b8)", m_auto: "\uc790\ub3d9 \uad50\uccb4", m_clear: "\uc815\ub9ac", m_clearLogin: "\ub85c\uadf8\uc778 (\ucc44\ud305 \uc720\uc9c0)", m_restoreLogin: "\ub85c\uadf8\uc778 \ubcf5\uc6d0",
    m_clearCache: "\uce90\uc2dc \ubc0f \ub85c\uadf8", m_status: "\uc0c1\ud0dc", m_restart: "{app} \ub2e4\uc2dc \uc2dc\uc791", m_quit: "\uc885\ub8cc", m_language: "\uc5b8\uc5b4", m_langAuto: "\uc790\ub3d9",
    busy: "\ub2e4\ub978 \uc791\uc5c5\uc774 \uc544\uc9c1 \uc9c4\ud589 \uc911\uc785\ub2c8\ub2e4.", ipWg: "\uc0c8 IP {ip} (\ub0b4\uc7a5 WARP)", ipFree: "\uc0c8 IP {ip} (\uacf5\uac1c \ud504\ub85d\uc2dc {host})", ipList: "\uc0c8 IP {ip} (\ud504\ub85d\uc2dc {host})",
    wgfileFixed: "WireGuard \ud30c\uc77c\uc740 \ucd9c\uad6c IP\uac00 \uace0\uc815\uc785\ub2c8\ub2e4. {msg}. \ubc14\uafb8\ub824\uba74 \ub2e4\ub978 \ud30c\uc77c\uc774\ub098 \ub2e4\ub978 \uc5f0\uacb0\uc744 \uc120\ud0dd\ud558\uc138\uc694.",
    sameIp: "\uc0c8 WARP \uacc4\uc815\uc774\uc9c0\ub9cc IP\ub294 \uc5ec\uc804\ud788 {ip}\uc785\ub2c8\ub2e4 (WARP\ub294 \uac00\uc7a5 \uac00\uae4c\uc6b4 Cloudflare \uc11c\ubc84\ub97c \uc0ac\uc6a9\ud569\ub2c8\ub2e4)", noAnswer: "WARP \ud130\ub110\uc774 \uc751\ub2f5\ud558\uc9c0 \uc54a\uc558\uc2b5\ub2c8\ub2e4",
    listEmpty: "\ud504\ub85d\uc2dc \ubaa9\ub85d\uc774 \ube44\uc5b4 \uc788\uc2b5\ub2c8\ub2e4. \ud2b8\ub808\uc774 > \uc124\uc815 \ud3b8\uc9d1.", listNone: "\ubaa9\ub85d\uc758 \uc5b4\ub5a4 \ud504\ub85d\uc2dc\ub3c4 \ub2e4\ub978 IP\ub97c \uc8fc\uc9c0 \uc54a\uc558\uc2b5\ub2c8\ub2e4.", directNoIp: "\uc9c1\uc811 \ubaa8\ub4dc\uc5d0\ub294 \ubc14\uafc0 IP\uac00 \uc5c6\uc2b5\ub2c8\ub2e4. \ub2e4\ub978 \uc5f0\uacb0\uc744 \uc120\ud0dd\ud558\uc138\uc694.",
    onWg: "\ub0b4\uc7a5 WARP \ucf1c\uc9d0. IP {ip}", onWgfile: "WireGuard \ud30c\uc77c \ucf1c\uc9d0. IP {ip}", onFree: "\uacf5\uac1c \ud504\ub85d\uc2dc {host} \ucf1c\uc9d0. IP {ip}", onList: "\ud504\ub85d\uc2dc \ubaa9\ub85d \ucf1c\uc9d0. '\uc0c8 IP'\ub85c \ud504\ub85d\uc2dc\ub97c \uace0\ub974\uc138\uc694.",
    onDirect: "\uc9c1\uc811: \uc571\uc774 \uc77c\ubc18 \uc5f0\uacb0\uc744 \uc0ac\uc6a9\ud569\ub2c8\ub2e4.", noneChosen: "\uc120\ud0dd\ud55c \uac83\uc774 \uc5c6\uc2b5\ub2c8\ub2e4. \uc5f0\uacb0\uc740 \uadf8\ub300\ub85c\uc785\ub2c8\ub2e4.", backDirect: "(\uc9c1\uc811\uc73c\ub85c \ub3cc\uc544\uac10)",
    statusLine: "IP {ip} ({mode})", statusNone: "\ud604\uc7ac \uc124\uc815\uc73c\ub85c\ub294 \uc5f0\uacb0\ub418\uc9c0 \uc54a\uc2b5\ub2c8\ub2e4.",
    mDirect: "\uc9c1\uc811", mWg: "\ub0b4\uc7a5 WARP", mWgfile: "WireGuard \ud30c\uc77c", mFree: "\uacf5\uac1c \ud504\ub85d\uc2dc", mList: "\ud504\ub85d\uc2dc \ubaa9\ub85d", autoOn: "\uc790\ub3d9 \uad50\uccb4\uac00 \ucf1c\uc84c\uc2b5\ub2c8\ub2e4.", autoOff: "\uc790\ub3d9 \uad50\uccb4\uac00 \uaebc\uc84c\uc2b5\ub2c8\ub2e4.",
    noLogin: "\uc774 PC\uc5d0 \uc800\uc7a5\ub41c \ub85c\uadf8\uc778(auth.json)\uc774 \uc5c6\uc2b5\ub2c8\ub2e4. \uc815\ub9ac\ud560 \uac83\uc774 \uc5c6\uc2b5\ub2c8\ub2e4.", loginExists: "\uc774\ubbf8 \ub85c\uadf8\uc778\uc774 \uc788\uc5b4\uc11c \uc544\ubb34\uac83\ub3c4 \ubcf5\uc6d0\ud558\uc9c0 \uc54a\uc558\uc2b5\ub2c8\ub2e4.", noBackup: "\ubcf5\uc6d0\ud560 \ub85c\uadf8\uc778 \ubc31\uc5c5\uc774 \uc5c6\uc2b5\ub2c8\ub2e4.",
    doneLogin: "\ub85c\uadf8\uc778\uc744 \uc81c\uac70\ud588\uc2b5\ub2c8\ub2e4 (\uc0ac\ubcf8 \uc800\uc7a5\ub428). \ucc44\ud305\uc740 \uc720\uc9c0\ub429\ub2c8\ub2e4.", failVerify: "\ub85c\uadf8\uc778 \ubc31\uc5c5\uc744 \ud655\uc778\ud558\uc9c0 \ubabb\ud574 \ub85c\uadf8\uc778\uc744 \uc81c\uac70\ud558\uc9c0 \uc54a\uc558\uc2b5\ub2c8\ub2e4.", doneRestore: "{from}\uc5d0\uc11c \ub85c\uadf8\uc778\uc744 \ubcf5\uc6d0\ud588\uc2b5\ub2c8\ub2e4.",
    doneCache: "\uce90\uc2dc\uc640 \ub85c\uadf8\ub97c \uc815\ub9ac\ud588\uc2b5\ub2c8\ub2e4 ({mb} MB). \ucc44\ud305\uc740 \uc720\uc9c0\ub429\ub2c8\ub2e4.", failClean: "\uc815\ub9ac \uc2e4\ud328: {err}",
    limitWarn: "\ubb34\ub8cc \ud55c\ub3c4\uc5d0 \ub3c4\ub2ec\ud588\uc2b5\ub2c8\ub2e4. \uc790\ub3d9 \uad50\uccb4\uc5d0\ub294 \uc5f0\uacb0 > \ub0b4\uc7a5 WARP \ub610\ub294 \ub0b4 \ud504\ub85d\uc2dc \ubaa9\ub85d\uc774 \ud544\uc694\ud569\ub2c8\ub2e4.", limitRotating: "\ubb34\ub8cc \ud55c\ub3c4\uc5d0 \ub3c4\ub2ec\ud588\uc2b5\ub2c8\ub2e4: IP\ub97c \ubc14\uafb8\ub294 \uc911...",
    eReg: "WARP \ub4f1\ub85d\uc774 \uac70\ubd80\ub418\uc5c8\uc2b5\ub2c8\ub2e4 (HTTP {status}). \uba87 \ubd84 \ub4a4 \ub2e4\uc2dc \uc2dc\ub3c4\ud558\uc138\uc694", eNoFile: "\uc544\uc9c1 WireGuard \ud30c\uc77c\uc744 \uc120\ud0dd\ud558\uc9c0 \uc54a\uc558\uc2b5\ub2c8\ub2e4. \ud2b8\ub808\uc774 > \uc5f0\uacb0 > WireGuard \ud30c\uc77c \uc120\ud0dd.",
    eFileDead: "\ud574\ub2f9 WireGuard \ud30c\uc77c\uc758 \ud130\ub110\uc774 \uc751\ub2f5\ud558\uc9c0 \uc54a\uc558\uc2b5\ub2c8\ub2e4", eWarpDead: "WARP \ud130\ub110\uc774 \uc751\ub2f5\ud558\uc9c0 \uc54a\uc558\uc2b5\ub2c8\ub2e4 (UDP 2408\uc774 \ucc28\ub2e8\ub418\uc5c8\ub098\uc694?)",
    eNoList: "\uacf5\uac1c \ud504\ub85d\uc2dc \ubaa9\ub85d\uc744 \ub0b4\ub824\ubc1b\uc9c0 \ubabb\ud588\uc2b5\ub2c8\ub2e4", eNoProxy: "\uc81c\uc2dc\uac04\uc5d0 \uc751\ub2f5\ud55c \uacf5\uac1c \ud504\ub85d\uc2dc\uac00 \uc5c6\uc2b5\ub2c8\ub2e4 (\ub2e4\uc2dc \uc2dc\ub3c4\ud558\uc138\uc694)", dlgChoose: "WireGuard .conf \ud30c\uc77c \uc120\ud0dd" },
  hi: { name: "\u0939\u093f\u0928\u094d\u0926\u0940",
    m_newIp: "\u0928\u092f\u093e IP", m_connection: "\u0915\u0928\u0947\u0915\u094d\u0936\u0928", m_direct: "\u0938\u0940\u0927\u093e", m_wg: "\u092c\u093f\u0932\u094d\u091f-\u0907\u0928 WARP", m_wgfile: "WireGuard \u092b\u093c\u093e\u0907\u0932", m_free: "\u092e\u0941\u092b\u093c\u094d\u0924 \u0938\u093e\u0930\u094d\u0935\u091c\u0928\u093f\u0915 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 (\u0905\u0935\u093f\u0936\u094d\u0935\u0938\u0928\u0940\u092f)", m_list: "\u092e\u0947\u0930\u0940 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 \u0938\u0942\u091a\u0940",
    m_chooseWg: "WireGuard \u092b\u093c\u093e\u0907\u0932 \u091a\u0941\u0928\u0947\u0902...", m_settings: "\u0938\u0947\u091f\u093f\u0902\u0917 \u092c\u0926\u0932\u0947\u0902 (\u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940, \u0938\u0902\u0926\u0930\u094d\u092d)", m_auto: "\u0911\u091f\u094b-\u0930\u094b\u091f\u0947\u091f", m_clear: "\u0938\u093e\u092b\u093c \u0915\u0930\u0947\u0902", m_clearLogin: "\u0932\u0949\u0917\u093f\u0928 (\u091a\u0948\u091f \u092c\u0928\u0947 \u0930\u0939\u0947\u0902\u0917\u0947)", m_restoreLogin: "\u0932\u0949\u0917\u093f\u0928 \u092c\u0939\u093e\u0932 \u0915\u0930\u0947\u0902",
    m_clearCache: "\u0915\u0948\u0936 \u0914\u0930 \u0932\u0949\u0917", m_status: "\u0938\u094d\u0925\u093f\u0924\u093f", m_restart: "{app} \u092b\u093f\u0930 \u0936\u0941\u0930\u0942 \u0915\u0930\u0947\u0902", m_quit: "\u092c\u093e\u0939\u0930 \u0928\u093f\u0915\u0932\u0947\u0902", m_language: "\u092d\u093e\u0937\u093e", m_langAuto: "\u0938\u094d\u0935\u091a\u093e\u0932\u093f\u0924",
    busy: "\u0915\u094b\u0908 \u0926\u0942\u0938\u0930\u0940 \u0915\u093e\u0930\u094d\u0930\u0935\u093e\u0908 \u0905\u092d\u0940 \u091a\u0932 \u0930\u0939\u0940 \u0939\u0948\u0964", ipWg: "\u0928\u092f\u093e IP {ip} (\u092c\u093f\u0932\u094d\u091f-\u0907\u0928 WARP)", ipFree: "\u0928\u092f\u093e IP {ip} (\u0938\u093e\u0930\u094d\u0935\u091c\u0928\u093f\u0915 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 {host})", ipList: "\u0928\u092f\u093e IP {ip} (\u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 {host})",
    wgfileFixed: "WireGuard \u092b\u093c\u093e\u0907\u0932 \u0915\u093e \u090f\u0917\u094d\u091c\u093c\u093f\u091f IP \u0924\u092f \u0939\u094b\u0924\u093e \u0939\u0948\u0964 {msg}\u0964 \u092c\u0926\u0932\u0928\u0947 \u0915\u0947 \u0932\u093f\u090f \u0926\u0942\u0938\u0930\u0940 \u092b\u093c\u093e\u0907\u0932 \u092f\u093e \u0926\u0942\u0938\u0930\u093e \u0915\u0928\u0947\u0915\u094d\u0936\u0928 \u091a\u0941\u0928\u0947\u0902\u0964",
    sameIp: "\u0928\u092f\u093e WARP \u0916\u093e\u0924\u093e \u092c\u0928\u093e, \u0932\u0947\u0915\u093f\u0928 IP \u0905\u092c \u092d\u0940 {ip} \u0939\u0948 (WARP \u0938\u092c\u0938\u0947 \u0928\u091c\u093c\u0926\u0940\u0915\u0940 Cloudflare \u0938\u0930\u094d\u0935\u0930 \u0907\u0938\u094d\u0924\u0947\u092e\u093e\u0932 \u0915\u0930\u0924\u093e \u0939\u0948)", noAnswer: "WARP \u091f\u0928\u0932 \u0928\u0947 \u091c\u0935\u093e\u092c \u0928\u0939\u0940\u0902 \u0926\u093f\u092f\u093e",
    listEmpty: "\u0906\u092a\u0915\u0940 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 \u0938\u0942\u091a\u0940 \u0916\u093e\u0932\u0940 \u0939\u0948\u0964 \u091f\u094d\u0930\u0947 > \u0938\u0947\u091f\u093f\u0902\u0917 \u092c\u0926\u0932\u0947\u0902\u0964", listNone: "\u0938\u0942\u091a\u0940 \u0915\u0947 \u0915\u093f\u0938\u0940 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 \u0928\u0947 \u0905\u0932\u0917 IP \u0928\u0939\u0940\u0902 \u0926\u093f\u092f\u093e\u0964", directNoIp: "\u0938\u0940\u0927\u0947 \u092e\u094b\u0921 \u092e\u0947\u0902 \u092c\u0926\u0932\u0928\u0947 \u0915\u0947 \u0932\u093f\u090f \u0915\u094b\u0908 IP \u0928\u0939\u0940\u0902 \u0939\u0948\u0964 \u0926\u0942\u0938\u0930\u093e \u0915\u0928\u0947\u0915\u094d\u0936\u0928 \u091a\u0941\u0928\u0947\u0902\u0964",
    onWg: "\u092c\u093f\u0932\u094d\u091f-\u0907\u0928 WARP \u091a\u093e\u0932\u0942\u0964 IP {ip}", onWgfile: "WireGuard \u092b\u093c\u093e\u0907\u0932 \u091a\u093e\u0932\u0942\u0964 IP {ip}", onFree: "\u0938\u093e\u0930\u094d\u0935\u091c\u0928\u093f\u0915 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 {host} \u091a\u093e\u0932\u0942\u0964 IP {ip}", onList: "\u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 \u0938\u0942\u091a\u0940 \u091a\u093e\u0932\u0942\u0964 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 \u091a\u0941\u0928\u0928\u0947 \u0915\u0947 \u0932\u093f\u090f '\u0928\u092f\u093e IP' \u0926\u092c\u093e\u090f\u0901\u0964",
    onDirect: "\u0938\u0940\u0927\u093e: \u0910\u092a \u0906\u092a\u0915\u093e \u0938\u093e\u092e\u093e\u0928\u094d\u092f \u0915\u0928\u0947\u0915\u094d\u0936\u0928 \u0907\u0938\u094d\u0924\u0947\u092e\u093e\u0932 \u0915\u0930\u0924\u093e \u0939\u0948\u0964", noneChosen: "\u0915\u0941\u091b \u0928\u0939\u0940\u0902 \u091a\u0941\u0928\u093e \u0917\u092f\u093e\u0964 \u0915\u0928\u0947\u0915\u094d\u0936\u0928 \u0935\u0948\u0938\u093e \u0939\u0940 \u0939\u0948\u0964", backDirect: "(\u0938\u0940\u0927\u0947 \u092a\u0930 \u0932\u094c\u091f\u093e)",
    statusLine: "IP {ip} ({mode})", statusNone: "\u092e\u094c\u091c\u0942\u0926\u093e \u0938\u0947\u091f\u093f\u0902\u0917 \u0938\u0947 \u0915\u094b\u0908 \u0915\u0928\u0947\u0915\u094d\u0936\u0928 \u0928\u0939\u0940\u0902 \u0939\u0948\u0964",
    mDirect: "\u0938\u0940\u0927\u093e", mWg: "\u092c\u093f\u0932\u094d\u091f-\u0907\u0928 WARP", mWgfile: "WireGuard \u092b\u093c\u093e\u0907\u0932", mFree: "\u0938\u093e\u0930\u094d\u0935\u091c\u0928\u093f\u0915 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940", mList: "\u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 \u0938\u0942\u091a\u0940", autoOn: "\u0911\u091f\u094b-\u0930\u094b\u091f\u0947\u091f \u091a\u093e\u0932\u0942\u0964", autoOff: "\u0911\u091f\u094b-\u0930\u094b\u091f\u0947\u091f \u092c\u0902\u0926\u0964",
    noLogin: "\u0907\u0938 PC \u092a\u0930 \u0915\u094b\u0908 \u0938\u0939\u0947\u091c\u093e \u0939\u0941\u0906 \u0932\u0949\u0917\u093f\u0928 (auth.json) \u0928\u0939\u0940\u0902 \u0939\u0948\u0964 \u0938\u093e\u092b\u093c \u0915\u0930\u0928\u0947 \u0915\u094b \u0915\u0941\u091b \u0928\u0939\u0940\u0902\u0964", loginExists: "\u0932\u0949\u0917\u093f\u0928 \u092a\u0939\u0932\u0947 \u0938\u0947 \u092e\u094c\u091c\u0942\u0926 \u0939\u0948, \u0907\u0938\u0932\u093f\u090f \u0915\u0941\u091b \u092c\u0939\u093e\u0932 \u0928\u0939\u0940\u0902 \u0915\u093f\u092f\u093e \u0917\u092f\u093e\u0964", noBackup: "\u092c\u0939\u093e\u0932 \u0915\u0930\u0928\u0947 \u0915\u0947 \u0932\u093f\u090f \u0915\u094b\u0908 \u0932\u0949\u0917\u093f\u0928 \u092c\u0948\u0915\u0905\u092a \u0928\u0939\u0940\u0902 \u0939\u0948\u0964",
    doneLogin: "\u0932\u0949\u0917\u093f\u0928 \u0939\u091f\u093e \u0926\u093f\u092f\u093e \u0917\u092f\u093e (\u090f\u0915 \u092a\u094d\u0930\u0924\u093f \u0938\u0941\u0930\u0915\u094d\u0937\u093f\u0924 \u0939\u0948)\u0964 \u091a\u0948\u091f \u092c\u0928\u0947 \u0930\u0939\u0947\u0902\u0917\u0947\u0964", failVerify: "\u0932\u0949\u0917\u093f\u0928 \u092c\u0948\u0915\u0905\u092a \u091c\u093e\u0901\u091a\u093e \u0928\u0939\u0940\u0902 \u091c\u093e \u0938\u0915\u093e, \u0907\u0938\u0932\u093f\u090f \u0932\u0949\u0917\u093f\u0928 \u0928\u0939\u0940\u0902 \u0939\u091f\u093e\u092f\u093e \u0917\u092f\u093e\u0964", doneRestore: "{from} \u0938\u0947 \u0932\u0949\u0917\u093f\u0928 \u092c\u0939\u093e\u0932 \u0915\u093f\u092f\u093e \u0917\u092f\u093e\u0964",
    doneCache: "\u0915\u0948\u0936 \u0914\u0930 \u0932\u0949\u0917 \u0938\u093e\u092b\u093c \u0939\u094b \u0917\u090f ({mb} MB)\u0964 \u091a\u0948\u091f \u092c\u0928\u0947 \u0930\u0939\u0947\u0902\u0917\u0947\u0964", failClean: "\u0938\u092b\u093c\u093e\u0908 \u0935\u093f\u092b\u0932 \u0930\u0939\u0940: {err}",
    limitWarn: "\u092e\u0941\u092b\u093c\u094d\u0924 \u0938\u0940\u092e\u093e \u092a\u0942\u0930\u0940 \u0939\u094b \u0917\u0908\u0964 \u0911\u091f\u094b-\u0930\u094b\u091f\u0947\u091f \u0915\u0947 \u0932\u093f\u090f \u0915\u0928\u0947\u0915\u094d\u0936\u0928 > \u092c\u093f\u0932\u094d\u091f-\u0907\u0928 WARP \u092f\u093e \u092e\u0947\u0930\u0940 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 \u0938\u0942\u091a\u0940 \u091a\u093e\u0939\u093f\u090f\u0964", limitRotating: "\u092e\u0941\u092b\u093c\u094d\u0924 \u0938\u0940\u092e\u093e \u092a\u0942\u0930\u0940 \u0939\u0941\u0908: IP \u092c\u0926\u0932\u093e \u091c\u093e \u0930\u0939\u093e \u0939\u0948...",
    eReg: "WARP \u092a\u0902\u091c\u0940\u0915\u0930\u0923 \u0905\u0938\u094d\u0935\u0940\u0915\u093e\u0930 \u0939\u0941\u0906 (HTTP {status}); \u0915\u0941\u091b \u092e\u093f\u0928\u091f \u092c\u093e\u0926 \u092b\u093f\u0930 \u0915\u094b\u0936\u093f\u0936 \u0915\u0930\u0947\u0902", eNoFile: "\u0905\u092d\u0940 \u0924\u0915 \u0915\u094b\u0908 WireGuard \u092b\u093c\u093e\u0907\u0932 \u0928\u0939\u0940\u0902 \u091a\u0941\u0928\u0940 \u0917\u0908\u0964 \u091f\u094d\u0930\u0947 > \u0915\u0928\u0947\u0915\u094d\u0936\u0928 > WireGuard \u092b\u093c\u093e\u0907\u0932 \u091a\u0941\u0928\u0947\u0902\u0964",
    eFileDead: "\u0909\u0938 WireGuard \u092b\u093c\u093e\u0907\u0932 \u0915\u0940 \u091f\u0928\u0932 \u0928\u0947 \u091c\u0935\u093e\u092c \u0928\u0939\u0940\u0902 \u0926\u093f\u092f\u093e", eWarpDead: "WARP \u091f\u0928\u0932 \u0928\u0947 \u091c\u0935\u093e\u092c \u0928\u0939\u0940\u0902 \u0926\u093f\u092f\u093e (\u0915\u094d\u092f\u093e UDP 2408 \u092c\u0902\u0926 \u0939\u0948?)",
    eNoList: "\u0915\u094b\u0908 \u092d\u0940 \u0938\u093e\u0930\u094d\u0935\u091c\u0928\u093f\u0915 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 \u0938\u0942\u091a\u0940 \u0921\u093e\u0909\u0928\u0932\u094b\u0921 \u0928\u0939\u0940\u0902 \u0939\u094b \u0938\u0915\u0940", eNoProxy: "\u0938\u092e\u092f \u092a\u0930 \u0915\u094b\u0908 \u0938\u093e\u0930\u094d\u0935\u091c\u0928\u093f\u0915 \u092a\u094d\u0930\u0949\u0915\u094d\u0938\u0940 \u0928\u0939\u0940\u0902 \u091a\u0932\u093e (\u092b\u093f\u0930 \u0915\u094b\u0936\u093f\u0936 \u0915\u0930\u0947\u0902)", dlgChoose: "WireGuard .conf \u092b\u093c\u093e\u0907\u0932 \u091a\u0941\u0928\u0947\u0902" },
  ar: { name: "\u0627\u0644\u0639\u0631\u0628\u064a\u0629",
    m_newIp: "\u0639\u0646\u0648\u0627\u0646 IP \u062c\u062f\u064a\u062f", m_connection: "\u0627\u0644\u0627\u062a\u0635\u0627\u0644", m_direct: "\u0645\u0628\u0627\u0634\u0631", m_wg: "WARP \u0627\u0644\u0645\u062f\u0645\u062c", m_wgfile: "\u0645\u0644\u0641 WireGuard", m_free: "\u0648\u0643\u0644\u0627\u0621 \u0639\u0627\u0645\u0648\u0646 \u0645\u062c\u0627\u0646\u064a\u0648\u0646 (\u063a\u064a\u0631 \u0645\u0648\u062b\u0648\u0642\u064a\u0646)", m_list: "\u0642\u0627\u0626\u0645\u0629 \u0648\u0643\u0644\u0627\u0626\u064a",
    m_chooseWg: "\u0627\u062e\u062a\u064a\u0627\u0631 \u0645\u0644\u0641 WireGuard...", m_settings: "\u062a\u0639\u062f\u064a\u0644 \u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a (\u0627\u0644\u0648\u0643\u0644\u0627\u0621\u060c \u0627\u0644\u0633\u064a\u0627\u0642)", m_auto: "\u0627\u0644\u062a\u0628\u062f\u064a\u0644 \u0627\u0644\u062a\u0644\u0642\u0627\u0626\u064a", m_clear: "\u062a\u0646\u0638\u064a\u0641", m_clearLogin: "\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 (\u062a\u0628\u0642\u0649 \u0627\u0644\u0645\u062d\u0627\u062f\u062b\u0627\u062a)", m_restoreLogin: "\u0627\u0633\u062a\u0639\u0627\u062f\u0629 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644",
    m_clearCache: "\u0627\u0644\u0630\u0627\u0643\u0631\u0629 \u0627\u0644\u0645\u0624\u0642\u062a\u0629 \u0648\u0627\u0644\u0633\u062c\u0644\u0627\u062a", m_status: "\u0627\u0644\u062d\u0627\u0644\u0629", m_restart: "\u0625\u0639\u0627\u062f\u0629 \u062a\u0634\u063a\u064a\u0644 {app}", m_quit: "\u0625\u0646\u0647\u0627\u0621", m_language: "\u0627\u0644\u0644\u063a\u0629", m_langAuto: "\u062a\u0644\u0642\u0627\u0626\u064a",
    busy: "\u0625\u062c\u0631\u0627\u0621 \u0622\u062e\u0631 \u0645\u0627 \u0632\u0627\u0644 \u0642\u064a\u062f \u0627\u0644\u062a\u0646\u0641\u064a\u0630.", ipWg: "\u0639\u0646\u0648\u0627\u0646 IP \u062c\u062f\u064a\u062f {ip} (WARP \u0627\u0644\u0645\u062f\u0645\u062c)", ipFree: "\u0639\u0646\u0648\u0627\u0646 IP \u062c\u062f\u064a\u062f {ip} (\u0648\u0643\u064a\u0644 \u0639\u0627\u0645 {host})", ipList: "\u0639\u0646\u0648\u0627\u0646 IP \u062c\u062f\u064a\u062f {ip} (\u0648\u0643\u064a\u0644 {host})",
    wgfileFixed: "\u0645\u0644\u0641 WireGuard \u0644\u0647 \u0639\u0646\u0648\u0627\u0646 IP \u062e\u0631\u0648\u062c \u062b\u0627\u0628\u062a. {msg}. \u0627\u062e\u062a\u0631 \u0645\u0644\u0641\u064b\u0627 \u0622\u062e\u0631 \u0623\u0648 \u0627\u062a\u0635\u0627\u0644\u064b\u0627 \u0622\u062e\u0631 \u0644\u062a\u063a\u064a\u064a\u0631\u0647.",
    sameIp: "\u062d\u0633\u0627\u0628 WARP \u062c\u062f\u064a\u062f\u060c \u0644\u0643\u0646 \u0639\u0646\u0648\u0627\u0646 IP \u0645\u0627 \u0632\u0627\u0644 {ip} (\u064a\u0633\u062a\u062e\u062f\u0645 WARP \u0623\u0642\u0631\u0628 \u062e\u0627\u062f\u0645 Cloudflare)", noAnswer: "\u0644\u0645 \u064a\u0633\u062a\u062c\u0628 \u0646\u0641\u0642 WARP",
    listEmpty: "\u0642\u0627\u0626\u0645\u0629 \u0627\u0644\u0648\u0643\u0644\u0627\u0621 \u0641\u0627\u0631\u063a\u0629. \u0639\u0644\u0628\u0629 \u0627\u0644\u0646\u0638\u0627\u0645 > \u062a\u0639\u062f\u064a\u0644 \u0627\u0644\u0625\u0639\u062f\u0627\u062f\u0627\u062a.", listNone: "\u0644\u0645 \u064a\u0639\u0637\u0650 \u0623\u064a \u0648\u0643\u064a\u0644 \u0641\u064a \u0627\u0644\u0642\u0627\u0626\u0645\u0629 \u0639\u0646\u0648\u0627\u0646 IP \u0645\u062e\u062a\u0644\u0641\u064b\u0627.", directNoIp: "\u0627\u0644\u0648\u0636\u0639 \u0627\u0644\u0645\u0628\u0627\u0634\u0631 \u0644\u064a\u0633 \u0641\u064a\u0647 \u0639\u0646\u0648\u0627\u0646 IP \u0644\u062a\u063a\u064a\u064a\u0631\u0647. \u0627\u062e\u062a\u0631 \u0627\u062a\u0635\u0627\u0644\u064b\u0627 \u0622\u062e\u0631.",
    onWg: "\u062a\u0645 \u062a\u0634\u063a\u064a\u0644 WARP \u0627\u0644\u0645\u062f\u0645\u062c. IP {ip}", onWgfile: "\u062a\u0645 \u062a\u0634\u063a\u064a\u0644 \u0645\u0644\u0641 WireGuard. IP {ip}", onFree: "\u062a\u0645 \u062a\u0634\u063a\u064a\u0644 \u0627\u0644\u0648\u0643\u064a\u0644 \u0627\u0644\u0639\u0627\u0645 {host}. IP {ip}", onList: "\u062a\u0645 \u062a\u0634\u063a\u064a\u0644 \u0642\u0627\u0626\u0645\u0629 \u0627\u0644\u0648\u0643\u0644\u0627\u0621. \u0627\u0633\u062a\u062e\u062f\u0645 \u00ab\u0639\u0646\u0648\u0627\u0646 IP \u062c\u062f\u064a\u062f\u00bb \u0644\u0627\u062e\u062a\u064a\u0627\u0631 \u0648\u0643\u064a\u0644.",
    onDirect: "\u0645\u0628\u0627\u0634\u0631: \u064a\u0633\u062a\u062e\u062f\u0645 \u0627\u0644\u062a\u0637\u0628\u064a\u0642 \u0627\u062a\u0635\u0627\u0644\u0643 \u0627\u0644\u0639\u0627\u062f\u064a.", noneChosen: "\u0644\u0645 \u064a\u062a\u0645 \u0627\u062e\u062a\u064a\u0627\u0631 \u0634\u064a\u0621. \u0627\u0644\u0627\u062a\u0635\u0627\u0644 \u0644\u0645 \u064a\u062a\u063a\u064a\u0631.", backDirect: "(\u0639\u0627\u062f \u0625\u0644\u0649 \u0627\u0644\u0645\u0628\u0627\u0634\u0631)",
    statusLine: "IP {ip} ({mode})", statusNone: "\u0644\u0627 \u064a\u0648\u062c\u062f \u0627\u062a\u0635\u0627\u0644 \u0628\u0627\u0644\u0625\u0639\u062f\u0627\u062f \u0627\u0644\u062d\u0627\u0644\u064a.",
    mDirect: "\u0645\u0628\u0627\u0634\u0631", mWg: "WARP \u0627\u0644\u0645\u062f\u0645\u062c", mWgfile: "\u0645\u0644\u0641 WireGuard", mFree: "\u0648\u0643\u064a\u0644 \u0639\u0627\u0645", mList: "\u0642\u0627\u0626\u0645\u0629 \u0627\u0644\u0648\u0643\u0644\u0627\u0621", autoOn: "\u062a\u0645 \u062a\u0634\u063a\u064a\u0644 \u0627\u0644\u062a\u0628\u062f\u064a\u0644 \u0627\u0644\u062a\u0644\u0642\u0627\u0626\u064a.", autoOff: "\u062a\u0645 \u0625\u064a\u0642\u0627\u0641 \u0627\u0644\u062a\u0628\u062f\u064a\u0644 \u0627\u0644\u062a\u0644\u0642\u0627\u0626\u064a.",
    noLogin: "\u0644\u0627 \u064a\u0648\u062c\u062f \u062a\u0633\u062c\u064a\u0644 \u062f\u062e\u0648\u0644 \u0645\u062d\u0641\u0648\u0638 (auth.json) \u0639\u0644\u0649 \u0647\u0630\u0627 \u0627\u0644\u062c\u0647\u0627\u0632. \u0644\u0627 \u0634\u064a\u0621 \u0644\u062a\u0646\u0638\u064a\u0641\u0647.", loginExists: "\u064a\u0648\u062c\u062f \u062a\u0633\u062c\u064a\u0644 \u062f\u062e\u0648\u0644 \u0628\u0627\u0644\u0641\u0639\u0644\u060c \u0644\u0630\u0644\u0643 \u0644\u0645 \u062a\u062a\u0645 \u0627\u0633\u062a\u0639\u0627\u062f\u0629 \u0623\u064a \u0634\u064a\u0621.", noBackup: "\u0644\u0627 \u062a\u0648\u062c\u062f \u0646\u0633\u062e\u0629 \u0627\u062d\u062a\u064a\u0627\u0637\u064a\u0629 \u0644\u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 \u0644\u0627\u0633\u062a\u0639\u0627\u062f\u062a\u0647\u0627.",
    doneLogin: "\u062a\u0645\u062a \u0625\u0632\u0627\u0644\u0629 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 (\u062a\u0645 \u062d\u0641\u0638 \u0646\u0633\u062e\u0629). \u0627\u0644\u0645\u062d\u0627\u062f\u062b\u0627\u062a \u0628\u0627\u0642\u064a\u0629.", failVerify: "\u062a\u0639\u0630\u0631 \u0627\u0644\u062a\u062d\u0642\u0642 \u0645\u0646 \u0627\u0644\u0646\u0633\u062e\u0629 \u0627\u0644\u0627\u062d\u062a\u064a\u0627\u0637\u064a\u0629\u060c \u0644\u0630\u0644\u0643 \u0644\u0645 \u062a\u062a\u0645 \u0625\u0632\u0627\u0644\u0629 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644.", doneRestore: "\u062a\u0645\u062a \u0627\u0633\u062a\u0639\u0627\u062f\u0629 \u062a\u0633\u062c\u064a\u0644 \u0627\u0644\u062f\u062e\u0648\u0644 \u0645\u0646 {from}.",
    doneCache: "\u062a\u0645 \u0645\u0633\u062d \u0627\u0644\u0630\u0627\u0643\u0631\u0629 \u0627\u0644\u0645\u0624\u0642\u062a\u0629 \u0648\u0627\u0644\u0633\u062c\u0644\u0627\u062a ({mb} \u0645.\u0628). \u0627\u0644\u0645\u062d\u0627\u062f\u062b\u0627\u062a \u0628\u0627\u0642\u064a\u0629.", failClean: "\u0641\u0634\u0644 \u0627\u0644\u062a\u0646\u0638\u064a\u0641: {err}",
    limitWarn: "\u062a\u0645 \u0628\u0644\u0648\u063a \u0627\u0644\u062d\u062f \u0627\u0644\u0645\u062c\u0627\u0646\u064a. \u064a\u062d\u062a\u0627\u062c \u0627\u0644\u062a\u0628\u062f\u064a\u0644 \u0627\u0644\u062a\u0644\u0642\u0627\u0626\u064a \u0625\u0644\u0649 \u0627\u0644\u0627\u062a\u0635\u0627\u0644 > WARP \u0627\u0644\u0645\u062f\u0645\u062c \u0623\u0648 \u0642\u0627\u0626\u0645\u0629 \u0648\u0643\u0644\u0627\u0626\u064a.", limitRotating: "\u062a\u0645 \u0628\u0644\u0648\u063a \u0627\u0644\u062d\u062f \u0627\u0644\u0645\u062c\u0627\u0646\u064a: \u062c\u0627\u0631\u064d \u062a\u063a\u064a\u064a\u0631 \u0639\u0646\u0648\u0627\u0646 IP...",
    eReg: "\u062a\u0645 \u0631\u0641\u0636 \u062a\u0633\u062c\u064a\u0644 WARP (HTTP {status})\u061b \u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649 \u0628\u0639\u062f \u062f\u0642\u0627\u0626\u0642", eNoFile: "\u0644\u0645 \u064a\u062a\u0645 \u0627\u062e\u062a\u064a\u0627\u0631 \u0645\u0644\u0641 WireGuard \u0628\u0639\u062f. \u0639\u0644\u0628\u0629 \u0627\u0644\u0646\u0638\u0627\u0645 > \u0627\u0644\u0627\u062a\u0635\u0627\u0644 > \u0627\u062e\u062a\u064a\u0627\u0631 \u0645\u0644\u0641 WireGuard.",
    eFileDead: "\u0644\u0645 \u064a\u0633\u062a\u062c\u0628 \u0646\u0641\u0642 \u0645\u0644\u0641 WireGuard \u0647\u0630\u0627", eWarpDead: "\u0644\u0645 \u064a\u0633\u062a\u062c\u0628 \u0646\u0641\u0642 WARP (\u0647\u0644 \u0627\u0644\u0645\u0646\u0641\u0630 UDP 2408 \u0645\u062d\u0638\u0648\u0631\u061f)",
    eNoList: "\u062a\u0639\u0630\u0631 \u062a\u0646\u0632\u064a\u0644 \u0623\u064a \u0642\u0627\u0626\u0645\u0629 \u0648\u0643\u0644\u0627\u0621 \u0639\u0627\u0645\u064a\u0646", eNoProxy: "\u0644\u0645 \u064a\u0633\u062a\u062c\u0628 \u0623\u064a \u0648\u0643\u064a\u0644 \u0639\u0627\u0645 \u0641\u064a \u0627\u0644\u0648\u0642\u062a \u0627\u0644\u0645\u0646\u0627\u0633\u0628 (\u062d\u0627\u0648\u0644 \u0645\u0631\u0629 \u0623\u062e\u0631\u0649)", dlgChoose: "\u0627\u062e\u062a\u0631 \u0645\u0644\u0641 WireGuard \u0628\u0635\u064a\u063a\u0629 .conf" },
  id: { name: "Bahasa Indonesia",
    m_newIp: "IP baru", m_connection: "Koneksi", m_direct: "Langsung", m_wg: "WARP bawaan", m_wgfile: "Berkas WireGuard", m_free: "Proxy publik gratis (tidak tepercaya)", m_list: "Daftar proxy saya",
    m_chooseWg: "Pilih berkas WireGuard...", m_settings: "Ubah pengaturan (proxy, konteks)", m_auto: "Rotasi otomatis", m_clear: "Bersihkan", m_clearLogin: "Login (obrolan tetap ada)", m_restoreLogin: "Pulihkan login",
    m_clearCache: "Cache dan log", m_status: "Status", m_restart: "Mulai ulang {app}", m_quit: "Keluar", m_language: "Bahasa", m_langAuto: "Otomatis",
    busy: "Tindakan lain masih berjalan.", ipWg: "IP baru {ip} (WARP bawaan)", ipFree: "IP baru {ip} (proxy publik {host})", ipList: "IP baru {ip} (proxy {host})",
    wgfileFixed: "Berkas WireGuard punya IP keluar yang tetap. {msg}. Pilih berkas atau Koneksi lain untuk mengubahnya.",
    sameIp: "Akun WARP baru, tetapi IP tetap {ip} (WARP memakai server Cloudflare terdekat)", noAnswer: "Terowongan WARP tidak merespons",
    listEmpty: "Daftar proxy Anda kosong. Baki > Ubah pengaturan.", listNone: "Tidak ada proxy di daftar yang memberi IP berbeda.", directNoIp: "Mode langsung tidak punya IP untuk diganti. Pilih Koneksi lain.",
    onWg: "WARP bawaan aktif. IP {ip}", onWgfile: "Berkas WireGuard aktif. IP {ip}", onFree: "Proxy publik {host} aktif. IP {ip}", onList: "Daftar proxy aktif. Gunakan IP baru untuk memilih proxy.",
    onDirect: "Langsung: aplikasi memakai koneksi normal Anda.", noneChosen: "Tidak ada yang dipilih. Koneksi tidak berubah.", backDirect: "(kembali ke langsung)",
    statusLine: "IP {ip} ({mode})", statusNone: "Tidak ada koneksi dengan pengaturan saat ini.",
    mDirect: "langsung", mWg: "WARP bawaan", mWgfile: "berkas WireGuard", mFree: "proxy publik", mList: "daftar proxy", autoOn: "Rotasi otomatis aktif.", autoOff: "Rotasi otomatis nonaktif.",
    noLogin: "Tidak ada login tersimpan (auth.json) di PC ini. Tidak ada yang dibersihkan.", loginExists: "Login sudah ada, jadi tidak ada yang dipulihkan.", noBackup: "Tidak ada cadangan login untuk dipulihkan.",
    doneLogin: "Login dihapus (salinan tersimpan). Obrolan tetap ada.", failVerify: "Cadangan login tidak dapat diverifikasi, jadi login tidak dihapus.", doneRestore: "Login dipulihkan dari {from}.",
    doneCache: "Cache dan log dibersihkan ({mb} MB). Obrolan tetap ada.", failClean: "Pembersihan gagal: {err}",
    limitWarn: "Batas gratis tercapai. Rotasi otomatis butuh Koneksi > WARP bawaan atau Daftar proxy saya.", limitRotating: "Batas gratis tercapai: mengganti IP...",
    eReg: "Pendaftaran WARP ditolak (HTTP {status}); coba lagi beberapa menit lagi", eNoFile: "Belum ada berkas WireGuard yang dipilih. Baki > Koneksi > Pilih berkas WireGuard.",
    eFileDead: "Terowongan berkas WireGuard itu tidak merespons", eWarpDead: "Terowongan WARP tidak merespons (apakah UDP 2408 diblokir?)",
    eNoList: "Tidak bisa mengunduh daftar proxy publik mana pun", eNoProxy: "Tidak ada proxy publik yang merespons tepat waktu (coba lagi)", dlgChoose: "Pilih berkas WireGuard .conf" },
}
// "xx-YY" or "xx" from the system -> one of the languages above (English if there is none)
const pickLang = (code) => {
  const c = String(code || "").toLowerCase()
  if (cfg.language && cfg.language !== "auto" && LANGS[cfg.language]) return cfg.language
  if (c.startsWith("pt")) return "pt-BR"
  if (c.startsWith("zh")) return "zh-CN"
  const base = c.split(/[-_]/)[0]
  return Object.keys(LANGS).find((k) => k.toLowerCase() === base) ?? "en"
}
let langCode = "en"
const t = (key, vars = {}) => (LANGS[langCode]?.[key] ?? LANGS.en[key] ?? key).replace(/\{(\w+)\}/g, (_, n) => String(vars[n] ?? ""))
langCode = pickLang(Intl.DateTimeFormat().resolvedOptions().locale)

// ---------------------------------------------------------------- local gate: the only proxy OpenCode talks to
// 127.0.0.1:<port> forwards to the current upstream (built-in WARP, a proxy of the list, or direct). Changing the upstream is instant.
function parseUp(s) {
  const m = /^(?:(\w+):\/\/)?(?:([^:@\/]*):([^@\/]*)@)?([^:\/\s]+):(\d+)/.exec(String(s).trim())
  if (!m) return undefined
  return { kind: (m[1] ?? "http").toLowerCase().startsWith("socks") ? "socks" : "http", user: m[2], pass: m[3], host: m[4], port: Number(m[5]) }
}
let wg = null          // the WireGuard tunnel (see UserWireGuard)
let freeCurrent = ""   // the public proxy in use while the mode is "free"
const DEAD = { kind: "http", host: "127.0.0.1", port: 1 }
const upstream = () =>
  cfg.mode === "list" ? parseUp(cfg.current)
  : cfg.mode === "wg" || cfg.mode === "wgfile" ? (wg?.session ? { kind: "wg" } : DEAD)   // tunnel down = no connection, never the real IP
  : cfg.mode === "free" ? (freeCurrent ? parseUp(freeCurrent) : DEAD)
  : undefined

const readUntil = (sock, test) => new Promise((resolve, reject) => {
  let buf = Buffer.alloc(0)
  const on = (d) => { buf = Buffer.concat([buf, d]); const n = test(buf); if (n >= 0) { cleanup(); resolve({ buf, n }) } }
  const bad = (e) => { cleanup(); reject(e ?? new Error("closed")) }
  const cleanup = () => { sock.off("data", on); sock.off("error", bad); sock.off("close", bad) }
  sock.on("data", on); sock.once("error", bad); sock.once("close", bad)
})

// A tunnel to host:port through the upstream (undefined = direct).
async function dial(up, host, port, timeout = 15000) {
  const open = (h, p) => new Promise((res, rej) => {
    const s = net.connect({ host: h, port: p }, () => res(s))
    s.once("error", rej); s.setTimeout(timeout, () => s.destroy(new Error("timeout")))
  })
  if (up?.kind === "wg") return await wg.connect(host, port)
  if (!up) { const s = await open(host, port); s.setTimeout(0); return s }
  const s = await open(up.host, up.port)
  try {
    if (up.kind === "http") {
      const auth = up.user ? `Proxy-Authorization: Basic ${Buffer.from(`${up.user}:${up.pass}`).toString("base64")}\r\n` : ""
      s.write(`CONNECT ${host}:${port} HTTP/1.1\r\nHost: ${host}:${port}\r\n${auth}\r\n`)
      const { buf, n } = await readUntil(s, (b) => b.indexOf("\r\n\r\n"))
      if (!/^HTTP\/1\.[01] 200/.test(buf.toString("latin1", 0, 20))) throw new Error("proxy refused: " + buf.toString("latin1", 0, 40).split("\r\n")[0])
      const rest = buf.subarray(n + 4); if (rest.length) s.unshift(rest)
    } else {
      s.write(up.user ? Buffer.from([5, 2, 0, 2]) : Buffer.from([5, 1, 0]))
      let r = await readUntil(s, (b) => (b.length >= 2 ? 2 : -1))
      if (r.buf[0] !== 5 || r.buf[1] === 0xff) throw new Error("socks: no acceptable auth")
      if (r.buf[1] === 2) {
        const u = Buffer.from(up.user ?? ""), p = Buffer.from(up.pass ?? "")
        s.write(Buffer.concat([Buffer.from([1, u.length]), u, Buffer.from([p.length]), p]))
        r = await readUntil(s, (b) => (b.length >= 2 ? 2 : -1))
        if (r.buf[1] !== 0) throw new Error("socks: bad login")
      }
      const h = Buffer.from(host)
      s.write(Buffer.concat([Buffer.from([5, 1, 0, 3, h.length]), h, Buffer.from([port >> 8, port & 255])]))
      r = await readUntil(s, (b) => { if (b.length < 5) return -1; const need = b[3] === 1 ? 10 : b[3] === 4 ? 22 : 7 + b[4]; return b.length >= need ? need : -1 })
      if (r.buf[1] !== 0) throw new Error("socks: connect failed (" + r.buf[1] + ")")
      const rest = r.buf.subarray(r.n); if (rest.length) s.unshift(rest)
    }
  } catch (e) { s.destroy(); throw e }
  s.setTimeout(0)
  return s
}

const isLocal = (h) => /^(localhost|127\.\d+\.\d+\.\d+|::1|\[::1\])$/i.test(h)   // OpenCode's own service is always reached directly
const gate = net.createServer((client) => {
  client.on("error", () => {})
  let buf = Buffer.alloc(0)
  const onData = async (d) => {
    buf = Buffer.concat([buf, d])
    const end = buf.indexOf("\r\n\r\n"); if (end < 0) { if (buf.length > 65536) client.destroy(); return }
    client.off("data", onData); client.pause()
    const head = buf.toString("latin1", 0, end), rest = buf.subarray(end + 4)
    const [method, target, ver] = head.split("\r\n")[0].split(" ")
    try {
      if (method === "CONNECT") {
        const i = target.lastIndexOf(":"), host = target.slice(0, i).replace(/^\[|\]$/g, "")
        const out = await dial(isLocal(host) ? undefined : upstream(), host, Number(target.slice(i + 1)))
        out.on("error", () => client.destroy()); client.write("HTTP/1.1 200 Connection Established\r\n\r\n")
        if (rest.length) out.write(rest); client.pipe(out); out.pipe(client); client.resume()
      } else {
        const u = new URL(target), out = await dial(isLocal(u.hostname) ? undefined : upstream(), u.hostname, Number(u.port || 80))
        out.on("error", () => client.destroy())
        out.write(Buffer.concat([Buffer.from(`${method} ${u.pathname}${u.search} ${ver}\r\n${head.split("\r\n").slice(1).filter((l) => !/^proxy-/i.test(l)).join("\r\n")}\r\n\r\n`, "latin1"), rest]))
        client.pipe(out); out.pipe(client); client.resume()
      }
    } catch { client.end("HTTP/1.1 502 Bad Gateway\r\n\r\n") }
  }
  client.on("data", onData)
})
// The same port every time: OpenCode's background service outlives the app and keeps the proxy address it was started with.
gate.on("error", () => {})
const listenOn = (port) => new Promise((res) => { const fail = () => res(0); gate.once("error", fail); gate.listen(port, "127.0.0.1", () => { gate.off("error", fail); res(gate.address().port) }) })
let gatePort = cfg.gatePort ? await listenOn(cfg.gatePort) : 0
if (!gatePort) { gatePort = await listenOn(0); cfg.gatePort = gatePort; saveCfg(cfg) }
const gateUrl = `http://127.0.0.1:${gatePort}`
// Only this process and the OpenCode service it starts are pointed at the gate.
for (const k of ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"]) process.env[k] = gateUrl
process.env.NO_PROXY = process.env.no_proxy = "localhost,127.0.0.1,::1"
// Context window the app believes a model has ("provider/model": tokens). The app compacts the chat by that number, so a model
// that really accepts more than it declares gets compacted too early. Raising it past what the server accepts gives errors.
function applyContextLimits() {
  const providers = {}
  for (const [id, tokens] of Object.entries(cfg.contextLimits ?? {})) {
    const [prov, ...rest] = id.split("/"), model = rest.join("/")
    if (prov && model && tokens > 0) (providers[prov] ??= {})[model] = { limit: { context: Math.floor(tokens) } }
  }
  if (!Object.keys(providers).length) return
  let base = {}
  try { base = JSON.parse(process.env.OPENCODE_CONFIG_CONTENT || "{}") } catch {}
  base.providers = { ...(base.providers ?? {}) }
  for (const [prov, models] of Object.entries(providers)) base.providers[prov] = { ...(base.providers[prov] ?? {}), models: { ...(base.providers[prov]?.models ?? {}), ...models } }
  process.env.OPENCODE_CONFIG_CONTENT = JSON.stringify(base)
}
applyContextLimits()
app.commandLine.appendSwitch("proxy-server", gateUrl)
app.commandLine.appendSwitch("proxy-bypass-list", "localhost;127.0.0.1;[::1]")

// The IP the internet sees through an upstream.
async function traceVia(up) {
  const t = tls.connect({ socket: await dial(up, "www.cloudflare.com", 443, 8000), servername: "www.cloudflare.com" })
  t.write("GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\n\r\n")
  const chunks = []
  await new Promise((res, rej) => { t.on("data", (c) => chunks.push(c)); t.on("end", res); t.on("error", rej); setTimeout(() => rej(new Error("timeout")), 8000) })
  t.destroy()
  return /^ip=(.*)$/m.exec(Buffer.concat(chunks).toString())?.[1]?.trim()
}

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

// A free WARP account is registered over Cloudflare's API (the call wgcf makes) and the tunnel is our UserWireGuard above.
const wgDir = path.join(stateDir, "wg")
const wgAccountFile = path.join(wgDir, "account.json")
mkdirSync(wgDir, { recursive: true })

// Plain HTTPS for setup calls, never through the gate, with a readable error.
function httpsFetch(url, { method = "GET", headers = {}, body, timeout = 30000, hops = 5 } = {}) {
  return new Promise((resolve, reject) => {
    const req = https.request(url, { method, headers, agent: false, timeout }, (res) => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location && hops > 0) {
        res.resume()
        return resolve(httpsFetch(new URL(res.headers.location, url).href, { timeout, hops: hops - 1 }))
      }
      const chunks = []
      res.on("data", (c) => chunks.push(c))
      res.on("end", () => resolve({ status: res.statusCode, ok: res.statusCode >= 200 && res.statusCode < 300, buf: Buffer.concat(chunks) }))
      res.on("error", reject)
    })
    req.on("timeout", () => req.destroy(new Error("timed out")))
    req.on("error", (e) => reject(new Error(`${new URL(url).host}: ${e.code ?? ""} ${e.message}`.trim())))
    if (body) req.write(body)
    req.end()
  })
}

async function wgRegister() {
  const { publicKey, privateKey } = generateKeyPairSync("x25519")
  const pub = publicKey.export({ format: "der", type: "spki" }).subarray(-32).toString("base64")
  const priv = privateKey.export({ format: "der", type: "pkcs8" }).subarray(-32).toString("base64")
  const r = await httpsFetch("https://api.cloudflareclient.com/v0a2158/reg", {
    method: "POST",
    headers: { "Content-Type": "application/json", "User-Agent": "okhttp/3.12.1", "CF-Client-Version": "a-6.3-2158" },
    body: JSON.stringify({ key: pub, install_id: "", fcm_token: "", tos: new Date().toISOString(), type: "Android", model: "PC", locale: "en_US" }),
    timeout: 20000,
  })
  if (!r.ok) throw new Error(t("eReg", { status: r.status }))
  const j = JSON.parse(r.buf.toString("utf8"))
  const peer = j.config?.peers?.[0]
  if (!peer?.public_key) throw new Error("WARP registration returned no peer")
  const host = String(peer.endpoint?.host ?? "engage.cloudflareclient.com:2408")
  const acc = { priv, peerKey: peer.public_key, endpoint: host.includes(":") ? host : `${host}:2408`, v4: j.config.interface.addresses.v4, v6: j.config.interface.addresses.v6 }
  writeFileSync(wgAccountFile, JSON.stringify(acc, null, 2))
  return acc
}

function wgStop() { try { wg?.stop() } catch {} wg = null }
app.on("will-quit", wgStop)

const wgFromAccount = (acc) => ({ priv: acc.priv, peerKey: acc.peerKey, endpoint: acc.endpoint, v4: acc.v4, v6: acc.v6 })
async function wgStart(opts) {
  wgStop()
  const w = new UserWireGuard(opts)
  await w.start()
  wg = w
}

// Brings the tunnel up and returns a message with the IP. "wg" = a free Cloudflare WARP account (saved, or a new one);
// "wgfile" = the WireGuard .conf the user picked (Route64, Proton, Mullvad, their own server...).
const wgFile = path.join(wgDir, "custom.json")
async function wgUp(fresh) {
  if (cfg.mode === "wgfile") {
    if (!existsSync(wgFile)) throw new Error(t("eNoFile"))
    await wgStart(JSON.parse(readFileSync(wgFile, "utf8")))
    await sleep(1500)
    const ip = await traceVia(upstream()).catch(() => undefined)
    if (!ip) throw new Error(t("eFileDead"))
    return t("onWgfile", { ip })
  }
  let acc
  if (!fresh && existsSync(wgAccountFile)) { try { acc = JSON.parse(readFileSync(wgAccountFile, "utf8")) } catch {} }
  await wgStart(wgFromAccount(acc ?? (await wgRegister())))
  await sleep(1500)
  let ip = await traceVia(upstream()).catch(() => undefined)
  if (!ip && acc) {      // the saved account stopped working: register a new one
    log("saved WARP account did not answer, registering a new one")
    await wgStart(wgFromAccount(await wgRegister()))
    await sleep(1500)
    ip = await traceVia(upstream()).catch(() => undefined)
  }
  if (!ip) throw new Error(t("eWarpDead"))
  return t("onWg", { ip })
}

// ---------------------------------------------------------------- free public proxies
// Public lists of open proxies. They are tested one by one through Cloudflare's trace page and the first one that answers is
// used. They are untrusted: HTTPS stays end-to-end encrypted, but the proxy sees where you connect. Many die within minutes.
const FREE_SOURCES = [
  ["socks5", "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/socks5.txt"],
  ["socks5", "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/socks5/data.txt"],
  ["http", "https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt"],
  ["http", "https://raw.githubusercontent.com/proxifly/free-proxy-list/main/proxies/protocols/http/data.txt"],
]
let freePool = [], freeUsed = new Set()
async function freeFetch() {
  const all = new Set()
  await Promise.all(FREE_SOURCES.map(async ([scheme, url]) => {
    try {
      const r = await httpsFetch(url, { timeout: 20000 })
      if (!r.ok) return
      for (const line of r.buf.toString("utf8").split(/\r?\n/)) {
        const m = /^(?:\w+:\/\/)?(\d{1,3}(?:\.\d{1,3}){3}:\d{2,5})\s*$/.exec(line.trim())
        if (m) all.add(`${scheme}://${m[1]}`)
      }
    } catch (e) { log("free list failed: " + why(e)) }
  }))
  freePool = [...all].sort(() => Math.random() - 0.5)
  return freePool.length
}
// First working proxy (different exit IP from the ones already used). 40 at a time, at most 90 seconds.
async function freeFind() {
  if (freePool.length < 20 && (await freeFetch()) === 0) throw new Error(t("eNoList"))
  const deadline = Date.now() + 90000
  let next = 0, found
  const worker = async () => {
    while (!found && Date.now() < deadline) {
      const cand = freePool[next++]
      if (!cand) return
      const ip = await traceVia(parseUp(cand)).catch(() => undefined)
      if (ip && !freeUsed.has(ip) && !found) found = { proxy: cand, ip }
    }
  }
  await Promise.all(Array.from({ length: 40 }, worker))
  freePool = freePool.slice(next)
  if (!found) throw new Error(t("eNoProxy"))
  freeUsed.add(found.ip)
  freeCurrent = found.proxy
  return found
}

const listEntries = () => cfg.list.map((x) => String(x).trim()).filter((x) => x && !x.startsWith("#") && parseUp(x))

let rotatedOk = false
async function newIp() {
  rotatedOk = false
  cfg = loadCfg()
  if (cfg.mode === "free") { const f = await freeFind(); rotatedOk = true; return t("ipFree", { ip: f.ip, host: parseUp(f.proxy).host }) }
  if (cfg.mode === "wgfile") return t("wgfileFixed", { msg: await wgUp(false) })
  if (cfg.mode === "wg") {
    const old = wg?.session ? await traceVia(upstream()).catch(() => undefined) : undefined
    let last
    for (let i = 0; i < 3; i++) {
      if (i) await sleep(4000 * i)
      try { await wgStart(wgFromAccount(await wgRegister())); await sleep(1500); last = await traceVia(upstream()).catch(() => undefined) } catch (e) { if (i === 2) throw e; continue }
      if (last && last !== old) { rotatedOk = true; return t("ipWg", { ip: last }) }
    }
    return last ? t("sameIp", { ip: last }) : t("noAnswer")
  }
  if (cfg.mode === "list") {
    const all = listEntries()
    if (!all.length) return t("listEmpty")
    const start = Math.max(0, all.indexOf(cfg.current) + 1)
    const old = cfg.current ? await traceVia(parseUp(cfg.current)).catch(() => undefined) : undefined
    for (let k = 0; k < all.length; k++) {
      const cand = all[(start + k) % all.length]
      const ip = await traceVia(parseUp(cand)).catch(() => undefined)
      if (ip && ip !== old) { cfg.current = cand; saveCfg(cfg); rotatedOk = true; return t("ipList", { ip, host: parseUp(cand).host }) }
    }
    return t("listNone")
  }
  return t("directNoIp")
}

const status = async () => {
  const ip = await traceVia(upstream()).catch(() => undefined)
  return ip ? t("statusLine", { ip, mode: t({ none: "mDirect", wg: "mWg", wgfile: "mWgfile", free: "mFree", list: "mList" }[cfg.mode]) }) : t("statusNone")
}

// Asks for a WireGuard .conf, checks it and keeps it for the "WireGuard file" connection.
const chooseWgFile = async () => {
  const r = await dialog.showOpenDialog({ title: t("dlgChoose"), filters: [{ name: "WireGuard", extensions: ["conf"] }], properties: ["openFile"] })
  if (r.canceled || !r.filePaths[0]) return false
  const c = parseWgConf(readFileSync(r.filePaths[0], "utf8"))
  writeFileSync(wgFile, JSON.stringify({ priv: c.priv, peerKey: c.peerKey, psk: c.psk, endpoint: c.endpoint, v4: c.v4, v6: c.v6, dns: c.dns, mtu: c.mtu }, null, 2))
  return true
}
const useMode = (mode, pick = false) => guard(async () => {
  cfg = loadCfg(); const before = cfg.mode
  const fallback = (e) => { cfg.mode = "none"; saveCfg(cfg); wgStop(); return new Error(why(e) + " " + t("backDirect")) }
  try {
    if (mode === "wgfile" && (pick || !existsSync(wgFile)) && !(await chooseWgFile())) { cfg.mode = before; saveCfg(cfg); return t("noneChosen") }
    cfg.mode = mode; saveCfg(cfg)
    if (mode !== "wg" && mode !== "wgfile") wgStop()
    if (mode === "wg" || mode === "wgfile") return await wgUp(false)
    if (mode === "free") { const f = await freeFind(); return t("onFree", { host: parseUp(f.proxy).host, ip: f.ip }) }
  } catch (e) { throw fallback(e) }
  return mode === "list" ? t("onList") : t("onDirect")
})

const toggleAuto = () => { cfg = loadCfg(); cfg.autoRotate = !cfg.autoRotate; saveCfg(cfg); note(t(cfg.autoRotate ? "autoOn" : "autoOff")) }
// OpenCode's background service ("serve --service") keeps running after the app closes.
const killService = () => {
  try {
    execFileSync("powershell", ["-NoProfile", "-Command", `Get-CimInstance Win32_Process -Filter "Name='opencode-cli.exe'" | Where-Object { $_.CommandLine -match 'serve --service' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }`], { windowsHide: true, timeout: 15000 })
  } catch {}
}
const restart = () => { wgStop(); killService(); app.relaunch(); app.exit(0) }
const quit = () => { wgStop(); killService(); app.exit(0) }
const later = (what) => { writeFileSync(pendingFile, JSON.stringify(what)); wgStop(); killService(); app.relaunch(); app.exit(0) }
const clearLogin = () => {
  if (!existsSync(path.join(dataDir, "auth.json"))) return say(t("noLogin"))
  later(["tokens"])
}
const restoreLogin = () => {
  if (existsSync(path.join(dataDir, "auth.json"))) return say(t("loginExists"))
  if (!newestBackup()) return say(t("noBackup"))
  later(["restore"])
}
const clearCache = () => later(["cache"])

// ---------------------------------------------------------------- auto-rotate
// The app (patched by the installer) reports each free-limit error to the page; the page logs "__OC_LIMIT__<session>".
let lastRotation = 0, streak = 0, streakAt = 0, warnedAt = 0
async function resume(wc) {
  // The app puts the stopped message back in the prompt box; if it is empty, send "continue". Then Enter.
  const state = await wc.executeJavaScript(`(() => {
    const el = document.querySelector('[data-component=composer-editor] [contenteditable], [data-component=composer-editor][contenteditable], [contenteditable="true"]')
    if (!el) return "none"
    el.focus()
    return el.innerText.trim() ? "text" : "empty"
  })()`).catch(() => "none")
  if (state === "none") return
  wc.focus()
  if (state === "empty") wc.insertText("continue")
  await sleep(200)
  wc.sendInputEvent({ type: "keyDown", keyCode: "Enter" })
  wc.sendInputEvent({ type: "keyUp", keyCode: "Enter" })
}
async function onLimit(wc) {
  cfg = loadCfg()
  const now = Date.now()
  if (!cfg.autoRotate || busy || now - lastRotation < 15000) return
  if (cfg.mode === "none") {
    if (now - warnedAt > 600000) { warnedAt = now; note(t("limitWarn")) }
    return
  }
  if (now - streakAt > 180000) streak = 0
  if (streak >= 10) return                       // 10 in a row without a free message: stop, try again in 3 minutes
  streak++; streakAt = now; lastRotation = now
  busy = true
  try {
    note(t("limitRotating"))
    await sleep(600)
    const msg = await newIp()
    note(msg)
    if (rotatedOk) { await sleep(800); await resume(wc) }
  } catch (e) { note(why(e)) } finally { busy = false; lastRotation = Date.now() }
}

if (cfg.mode === "wg" || cfg.mode === "wgfile" || cfg.mode === "free") {
  setTimeout(() => (cfg.mode === "free" ? freeFind().then((f) => log(`Public proxy ${f.proxy}, IP ${f.ip}`)) : wgUp(false).then(log)).catch((e) => {
    log(`${cfg.mode}: ${why(e)} (back to direct)`); wgStop(); cfg.mode = "none"; saveCfg(cfg)
  }), 0)
}

// ---------------------------------------------------------------- tray menu
const LOGO = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGAAAABgCAYAAADimHc4AAAQAElEQVR4nOxdCXQc5X3/fTN7H9rVZd3SSrbk2MayZRsbY8fgOoBDgwMB07RpQ9ykhVASaOgr9LV9TdP2kb40pU7zkhRzhGcKSYxdkwchdcGYYGFj5BMb8C3JOr1aaQ/tvbNfv9lzdqWVVsfOCrw/v/G3s7Mzu/O/v////40UmAHUxsaFPEc3gtAlbNdCQBrYKG5F+HTCybYuCnQCtAuUnBHC5C2/6/JZTBMEU4TGbLmZB/06+xEbGcFrUAAoaC8j5FsCyDM+e+eBqZybNQPUxpoWnlf+gJ2wBQVkBBPMVwQh+Nd+V++5bD4/OQMMleU6Xv2P7NWfEUIUKGBSUEpDbNjhEfz/gNEB60SfnZgBxppSHa/Yy0zNehQwHbzttjuZxRh2ZvpARgZoTA2NHPAGk/omFDAD0DMCpVt8ju5L4x3lxntTa6xfxwNHCsSfDZAlPLjDOlP9yvGOjsOAMiPHcc+CkDIUMDsgKGf/7QBKxoTn6QwgOpNhFzuhBQXMKpg1adOZjL9AmtnnpTs6k+UBQvAwCsgJGBOalWrzQNBv70i8lzxcbtCb9Jei6lJAzkBhdTtG5wNDLnE3YYK0Jv3fFYgvAxiNtSbD3yZ3GVSGhkUKnhxn5keNAnIOSuEP+wMtPl9fd0QDeJ7cVyC+fBBpTdSqB8XXXOy/O1GArIjTnKiMls8oeXyEAmRHUMAihZIrSH++INJezG4uRwH5wnIFi4Mq8QmCpmkRtAuXQregFep5NeC1Rig0evBqHZR6E0gYCDtGILhHQT2jCNpt8Hafhaf3Ajw95yPjnAGjPdGZLZ0kWkackyAqFfQr1sG4dhMMqzZAoStiRKbgKIkQm7AKiDhyaWPyfcnn2Ea9bgwd/T8MHn4V9gsdkZgwb6A4y3I/Ft9cDEGJSg3zlj9E8Ze+BqXBxMQ6Tswo8ZFgQpIZnDitEWhkTHwusR9lDiRMCowM4spbL6C3fReEgBd5gIPozZY8isD4MN6yBWXbHoHCWJwqyUxaSVhCdIm0TyT53DiaEtcIjl1P8LjQdWAnun63EyG/G3JiTjGANxWj/NHvMVPDCnBCdJJChJhkp0k8pJJPMxwXJT+uAbHrTaRJAYcVH+59AgOn34RcmDMMULcsQeU//ZhJvXkCW840gJIMkhx/nWaWxlwnvp9Bk9hoPduO4798HAGvA7kGhzkAzXUrUPWvOyLER4wQkRGpEk7itl08icaO09jxMcSnMZtPk8SPaFL8PJrQrAQTafS6Fc3rsOGBF6EzVyPXyLsGaFfdiIq//yF4pSZrmx6XZMHlhPfSGQSHBhCwDSI4PIjA8AAIr4RSDE9jm6mpDWWL1qX5hMk1JDBqQ/vz98MxOO2+q0mRVwYoKmtQ89RuRnx1Wig5vk2Hx4PRMx1wf9gB1+n3WHyfVetN9Lu0BpQv3YiqlV9AWcvahG/AJD7C57TijZ/dDb9nBLlA/hjAYt/q7TuhaV4yVgIjrwl7HY16qMcN656nYX11J6gQwkxRVLcELZsfQjkzNdn4iDMHfowP3/kv5AJ5a7TSf/YWaJjjFSUwYcshsfU06nBH3tyLwZd+hJBjGLMF55Uz6NjxTZjrW7F86z/DWGqR+Aia6iPYWFSau+aQvDlh85e/HlV3JG07Yg42Lnl9T/0Len/23VklvhT27lNo/8mfwH7ldLQyJfl+QknCHA33nEKukBcG6NZsgNrSnJiZEulMNhalDO39OYb37UKuEWShZvuObbh69mDM1yAl2hq1dePC8V8hV8gLAwwbb49KGI1NtkRzIx6ITZ6cB/dh4IX/gFwIh/w4tPNBnH/3+aRGsn/ukV4c3P0wwkIQuUJenLDlpf2RNEOmaOfjbTdDGM39JGg8lNQsRXndCvhYCNp3/gCC/lHkErI7YVVdYyLHIzq4aNQTdXzivvvEobwRX8Rw7weRTS7IboI0S9oi5ibTDNZx8HVcS5BdA3iDKTXqkeR4RAfoOLIf1xJkZwDh+KgGjBN3IxhE2JvbdLBYZ+DrG8CZiyMbMRaB0+mYamrAqTWg7DdQvw/U52MTBheEwX62DUC42g8amvkkMB15YUA81EukjONZTl4F1bxaBK72IBfgq2uhuZVFYHp99PuRjD8SuSaiBseYxCmZpuorwFUsiAoL+43+nk54WO7J23sRNCxgNsCrNObvQkYoyyphWrMpQnyepjJBHMXaruPYAeQC6utvYEyoiXwvx2bgCoFAwYRaGWJjgI3B2JbYZ2Nin0CrLUZR5UKUNq0Er9DA5xiYMSNk1wD3sXej0U8s6pHG3aJmlN90ZyTZZmt/FbMNPkCh9ZKU7CoX5lLrB2GkHSeJ7GniWFgFXfX1qCpfhqtdHRjseX/acwXZNUC0r6brN0JpKh1b2YoxoWTVJhaKOuG+NLvhIB0ZQVHNIqioMirZjCGC9SrC1kGEBnrg7+0EdTjAewOR4xqqjowqpgFxzVAGYiPbVwsKlOjqUG5uhtX2EbuVqWtDXiZipvWbUf/w96OSn5b/l2YjR88eQ+d/PwH3lezTzpNB9EGa4iqEg374XUMTdkUQwkGlLoJeV47amrUwaiuSvzOc+nsvDryDy0OHMVXIrgEi/N0XoG9uhaaiLlmJkqp9zCdoS6tR+dmtKP7MGgg+Dzz9lzBjMIKHvE4Ifk82H4YQ8sHrHcbg1ZMYdfTAQEwoImbwTAMUYZKoWXfZOuAJTL1mkLd6gLKkAouefCXizKQ13Ylqv0G7FQMH96Dv4C74HVbkC8W6WjSVrUWpoTESS3mDDrx78TmEwgFMFXmtiBkWtmH+oz+KlA8n7G5I7/th79nPM+d3fB+untyHgNuOfECvKoFaoYcnaIcv6MJ0kPeasLqyHgv/6qfQlNUm+36opPMtpUqWXrGK7g+few/9J15HH9vy1GA1bcyJthSF3oTmh/4dpoWrMvb9ZOr3kXa+0WAAg6ffRPfRvbBeOIRPAuZUY1b5jXfAcs93oNKXJKRe2tU2mY+Q7rutl3Hx0IvoOrGXOVI/5irmXGsip9Kgct1dqP3cfdAVV0/gEyQaMEFvaMg7istHd+HcezvhHc2f486EvDGAKBRQ1loi2dFA10UIrrGOtHz551B381dgblyR0hua4hMk3XGZfERcQzpP/Rqnfvef8LgGMFcgOwN4oxn6RSugb1wMBa+O2HLq9aD3t88jnMGBGmsWov7mr6Jm5R0gYzQiex8Rn298cPAnOHXop5gLmBED+HmViNyjjc0oJ0nVaqosKFrQBn1lU0JyOcmMsu/Ya3D0fzzhNZQ6E+pWfwn1N9wLvblmAh8xnkak7tv6T2P/K9+C1zOEfGJ6DCAERVu+DFV5VVTS2A0JwzZQlzOyMgUs36PQGKDUGKFUG6HSspw75SNZSCKx2bxIGCFKtO6z/wtrf/btH5WLfw91bXegonk90yRNhnkDol3W0t5QiY8IeBx46zffQX/PkUnvV1woItYSxNeRekEgMCuLO6bFAK2FpWTXfSFpg9lN8mk5Ej5M0vYzHacY6D+Oi93TawnnVVpUttyEhmV3oGrBhgl8QmYf8dqer6G/ryPlugpLE/jKKpaJY2ZSpQRiT3WQahx8LLryeRGyWVkNo5eZUB+mimkxwNiwBJXLN0clTaCpkh1nhpC0zXx8UUWYJIgfYvZ+wPYBeoaOTnsWmQ6NoQxNbXdjQdtW6PQVaTmmDD6CHQ/5nNj9q61wuXoj1+H0BmhWrx/rS9Ice/x68bpGwGmDZ/gKvM5BphzhrH7ztBigZCalcdmd7CbnSWx5kshS255+3O2zscTV++h3iOnb2S/xiRAznk2td2HpjQ/AwBgx3rqBdI1w2rvw8u6trCrqYedzMLUy06bSJ46LPi7MpB3hMJRKHRScKoOGkcgqm66+dyFkkRuathMWU7UlxQtgMtbBrK+FUV3Ovjxa3BClxucbYUkqO1w+K8sS2uEO2CLZwkAomyzk7KFl2b1YvPKrMJkaJvURx0/swOH3tyfuT6UzR5q2RG1Nl2hCeKgYIzTKIpi0VTCoysCz96gYKjM/cXbwALvXyevbc3KNWC6wbM39aFvzF8xccBnnDQGvHc+9tBGCMPWsJseIb1CXwcwypUI4iF57dgFFXuoB+cBg71HYbRfRtOC2lOKP1EeoeC3sjk4MjUy9AMRmM/AziXd4+5nWD2Z93pxYoiQXOi/sw/vtP0xoQGpvarRG3VAj7xM6rykGiDh1/DmMOvuSnXnhVAddpMv9ujAprjkGiBAnXuP3pgJmg7yPw74mGeD3OzP0prK5hNIEOXFNPgu6tLglrTcVid5Unzc3q3Ey4ZrUgIqyJUjtTY0l8tjo9shbM5CdAca6Rcgn9Lp5UCuNiU68xBgLST1eeRkgmwmqu2Ubmj7/AHiWuQy5hnFuzw8wcOw3kBsrl30jZUac7E2NSmOf9STkhCwaUH/bN7BgyyORHiDxZtWs5tv6x9/H6m8+C325BXKhuenzaF38leSSWApJbyoiGvBRt7xCkXMGqIylaNx8vyTupomoo3T+Kqz/y5ex8NaHwClUyB0I2lq34ZabnogV9IHksySSaYlBlp11eeQtV+bcBJUsvhEcr4qtiqTJ2m7M9irYseaNf46GlXej89CL6DyyixVKZq/RSqstwW2bnkRtxapkHj8e9UhmxKIGHPrwKciNnDMg5HFF1TxGfFCaMvOME0OjL8XiTd/G4o3fQvfR3eg8umdGi+XmzVuK6qrrsaL1T6FTFyc1L9EanyzciL/jUu8BnO/dD7khSzb0hsdehrGyBZmez5OanUz2/QjeUdi6j8Pa1QFb3ykEfS4E2Bb0s5FtYj1CZ5gHvTiyrchYg8qK5Wxrw7jPBcpQKx51D+L5fffA45d3DiBCFgaoDCVY9eAzKKqYn92TrqbQ94PweJUqJB+DIGSuhInvi62ML7zxR7jqyN0jaSaCLOlo8SZ7D+9hxY0gShqWMwIokp1vUkmlEg2BpFU9ZqPjoWJSU5BKfKlZka49S1uJI2XW3vZHcGWoA/mC7AUZbXE1lt3zPZRbVmfxLDhkUdPNXKudqMvaz+rArx16DBf730Y+ITJADDnkzUAxVF93K1p//3Fo9eVJSc3aR0zS9UBjNehEt3XqdQbYZOvX7Y/C6elHnuEgepPlYyYQC5EHiLF/7XWb0bTyXpTVtI6jAZNJMpJPV4x/Ps1HSKOt0dF+vHPiSXzUJU62ZFX88SE+uJVpwAH28ibkGaZ5CzC/7V40Lv0iVAodUp6GmPARmXtBJ3rGXFfvQZzrfB2nL+3FHMPbogb8ggnMH2AOobTqOpRVL0N5FdsqW1FUVJudj4hFSVbrafQPHsPA1ZOR9hD/LPUdzToofiky4HH2u5/AHIfRVMtmtaUs3i+HTlsGraY49ogDgnA4CPvIJVZQ74Jt5Dw+MaD4m8IfcMgjxD/gwAVcnR+LzgAFyAtGc5H20WwowW9RgKwQ54DiGI3kKN1OKZ2dx38UMClEWlNCZxORpQAAAWpJREFUIitEIgzwObouMzV4GgXIBPK0z365K/Iq/pZe31hBFbSTsMwwCsgZ2OTc5xF89fG/tJ2oiLndlwcZ8XPzfN4CEmBTl+3SP3Oe9he1LRqdie4nhKxFAbMOJv1HPA7FBuBCYuEyGfMpY02pnlMeYkeaUcCsgTneix4qrIazJ6XqM7Yo7+q1hWjodnZGfpcPfppAqS0Mems68UWM2xXhd/ZcEAi3inHtOAqYEZjNPyn4gyt8ju5L4x0nE59eq9WZFS+xD30RBUwZFPRVj51sBTozLp+chAHRz7CU9X1Mjf4NhJSigMnBTA6T/Mc8jq5nMUnhgUcWCPrsJ4IqwzNKwokMaCPiKrQCxoDSyMrtn3vCoS1B55X2bM6ZMiE1xvr1PMd9mxJ6O0sG61GAaGrc7L/Xw2G63efqPjiVc2ckyTqzRfQNd7EvX0SidWUzu2IFPs2gEFfgOZios1o6/YDt/4/H2fUapon/BwAA//90xWZgAAAABklEQVQDACt6WQj9lcD4AAAAAElFTkSuQmCC"
let tray
function buildMenu() {
  if (!tray) return
  cfg = loadCfg()
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: t("m_newIp"), click: guard(newIp) },
    { label: t("m_connection"), submenu: [
      { label: t("m_direct"), type: "radio", checked: cfg.mode === "none", click: useMode("none") },
      { label: t("m_wg"), type: "radio", checked: cfg.mode === "wg", click: useMode("wg") },
      { label: t("m_wgfile"), type: "radio", checked: cfg.mode === "wgfile", click: useMode("wgfile") },
      { label: t("m_free"), type: "radio", checked: cfg.mode === "free", click: useMode("free") },
      { label: t("m_list"), type: "radio", checked: cfg.mode === "list", click: useMode("list") },
      { type: "separator" },
      { label: t("m_chooseWg"), click: useMode("wgfile", true) },
    ] },
    { label: t("m_settings"), click: () => shell.openPath(proxyFile) },
    { label: t("m_auto"), type: "checkbox", checked: !!cfg.autoRotate, click: toggleAuto },
    { type: "separator" },
    { label: t("m_clear"), submenu: [
      { label: t("m_clearLogin"), click: clearLogin },
      { label: t("m_restoreLogin"), click: restoreLogin },
      { label: t("m_clearCache"), click: clearCache },
    ] },
    { label: t("m_status"), click: guard(status) },
    { type: "separator" },
    { label: t("m_language"), submenu: [
      { label: t("m_langAuto"), type: "radio", checked: !cfg.language || cfg.language === "auto", click: () => setLanguage("auto") },
      ...Object.entries(LANGS).map(([code, l]) => ({ label: l.name, type: "radio", checked: cfg.language === code, click: () => setLanguage(code) })),
    ] },
    { label: t("m_restart", { app: APP_NAME }), click: restart },
    { label: t("m_quit"), click: quit },
  ]))
}
function setLanguage(code) {
  cfg = loadCfg(); cfg.language = code; saveCfg(cfg)
  langCode = pickLang(app.getLocale())
  buildMenu()
}
app.whenReady().then(async () => {
  try {
    tray = new Tray(nativeImage.createFromDataURL(LOGO).resize({ width: 32, height: 32 }))
    tray.setToolTip("Slipstream")
    langCode = pickLang(app.getLocale())
    if (afterStart) note(t(afterStart.key, afterStart.vars))
    buildMenu()
  } catch (e) { log("tray failed: " + why(e)) }
})

// ---------------------------------------------------------------- remove the "subscribe to Go" popup and texts
// (the persistent "Free limit reached" tray is stopped in the app code itself by the patcher)
const stripUpsell = () => {
  window.__ocLimit = (id) => console.log("__OC_LIMIT__" + id)
  if (window.__slipstreamStrip) return
  window.__slipstreamStrip = true
  const upsell = /(subscribe to (opencode )?go|connect a provider or subscribe|\$\s?10\s?\/\s?(month|mo)|assinar o plano go|plano go|conectar um provedor ou assinar|us\$\s?10)/i
  const resetLine = /(resets? at|ser[a\u00e1] redefinid[oa]s? [a\u00e0]s|redefinid[oa]s? [a\u00e0]s)\s*\d/i
  const box = 'dialog,[role="dialog"],[role="alertdialog"],[data-component*="dialog"]'
  const hide = (el) => { if (el && el.style) el.style.setProperty("display", "none", "important") }
  const sweep = () => {
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT)
    const hits = []
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      const t = n.nodeValue
      if (t && t.length < 600 && (upsell.test(t) || resetLine.test(t))) hits.push(n.parentElement)
    }
    for (const el of hits) {
      if (!el || el.dataset.ocHidden) continue
      el.dataset.ocHidden = "1"
      const dlg = el.closest(box)
      if (dlg) {
        document.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", code: "Escape", keyCode: 27, bubbles: true }))
        hide(dlg)
        const prev = dlg.previousElementSibling
        if (prev && /overlay|backdrop/i.test(prev.getAttribute("data-component") || prev.className || "")) hide(prev)
      } else hide(el)
    }
  }
  let timer
  new MutationObserver(() => { clearTimeout(timer); timer = setTimeout(sweep, 80) }).observe(document.body, { childList: true, subtree: true, characterData: true })
  sweep()
}
app.on("web-contents-created", (_e, wc) => {
  wc.on("dom-ready", () => { wc.executeJavaScript("(" + stripUpsell.toString() + ")()").catch(() => {}) })
  wc.on("console-message", (...a) => {
    const msg = typeof a[0]?.message === "string" ? a[0].message : a[2]
    if (typeof msg === "string" && msg.startsWith("__OC_LIMIT__")) onLimit(wc)
  })
})

// ---------------------------------------------------------------- hand over to the original app
await import("./index.js")
'@

# ---------------------------------------------------------------- find the install
$dir = Find-Install
if ($download -and -not $dir) { Get-Original $version; $dir = Find-Install }
if (-not $dir) {
  Fail (T 'notFound')
  Say ('  ' + (T 'stopped')) Red
  Say ('    ' + (T 'hintDownload')) DarkGray
  return
}
$res     = Join-Path $dir 'resources'
$asar    = Join-Path $res 'app.asar'
$asarBak = "$asar.slipstream.bak"          # the untouched original; if it exists, OpenCode is patched
$upd     = Join-Path $res 'app-update.yml'
$updBak  = "$upd.slipstream.bak"
if (-not (Test-Path $asar)) { Fail "app.asar not found in $res"; return }

$ver = (Get-Item (Join-Path $dir $exeName)).VersionInfo.ProductVersion
Step (T 'found' @{ v = $ver; dir = $dir })

if ($status) {
  Say "  patched      : $(Test-Path $asarBak)"
  Say "  update block : $(Test-Path $updBak)"
  return
}

if ($uninstall) {
  Stop-OpenCode
  if (Test-Path $asarBak) { Move-Item $asarBak $asar -Force; Ok (T 'restored') } else { Warn (T 'notPatched') }
  if (Test-Path $updBak) { Move-Item $updBak $upd -Force; Ok (T 'updRestored') }
  Ok (T 'original')
  if ($start) { Start-Process (Join-Path $dir $exeName) }
  return
}

if ($block_update_off) {
  if (Test-Path $updBak) { Move-Item $updBak $upd -Force; Ok (T 'updRestored') } else { Warn (T 'notPatched') }
  return
}

# ---------------------------------------------------------------- asar helpers
# asar = [u32 4][u32 headerPickleSize][u32 payloadSize][u32 jsonLen][json][pad to 4] + file data (offsets are relative to that data)
function Read-AsarHeader([string]$file) {
  $fs = [IO.File]::OpenRead($file)
  try {
    $br = New-Object IO.BinaryReader($fs)
    [void]$br.ReadUInt32()
    $pickle = $br.ReadUInt32()
    [void]$br.ReadUInt32()
    $jsonLen = $br.ReadUInt32()
    [pscustomobject]@{ Json = [Text.Encoding]::UTF8.GetString($br.ReadBytes([int]$jsonLen)); Base = [int64](8 + $pickle); Length = $fs.Length }
  } finally { $fs.Dispose() }
}

function Read-AsarFile([string]$file, [string]$inner) {
  $h = Read-AsarHeader $file
  $node = $h.Json | ConvertFrom-Json
  foreach ($part in $inner.Split('/')) { $node = $node.files.$part }
  $fs = [IO.File]::OpenRead($file)
  try {
    $fs.Position = $h.Base + [int64]$node.offset
    $buf = New-Object byte[] ([int]$node.size)
    $n = 0; while ($n -lt $buf.Length) { $r = $fs.Read($buf, $n, $buf.Length - $n); if ($r -le 0) { break }; $n += $r }
    [Text.Encoding]::UTF8.GetString($buf)
  } finally { $fs.Dispose() }
}

# The "Free limit reached" tray takes the place of the prompt box and stays until a stored time, because the app saves it on every
# free-limit error and nothing clears it. This stops that save, and reports the error to the tool (auto-rotate).
function Get-AsarPatches([string]$source) {
  $h = Read-AsarHeader $source
  $assets = ($h.Json | ConvertFrom-Json).files.out.files.renderer.files.assets.files
  $utf8 = New-Object Text.UTF8Encoding($false)
  $found = @{}
  $fs = [IO.File]::OpenRead($source)
  try {
    foreach ($p in $assets.PSObject.Properties) {
      if ($p.Name -notlike '*.js' -or $p.Value.size -lt 3000 -or $p.Value.unpacked) { continue }
      $fs.Position = $h.Base + [int64]$p.Value.offset
      $buf = New-Object byte[] ([int]$p.Value.size)
      $n = 0; while ($n -lt $buf.Length) { $r = $fs.Read($buf, $n, $buf.Length - $n); if ($r -le 0) { break }; $n += $r }
      $text = $utf8.GetString($buf)
      if (-not ($text.Contains('provider.free-limit') -and $text.Contains('resetAt'))) { continue }
      $new = [regex]::Replace($text, '([A-Za-z_$][\w$]*)\.data\.error\.type===`provider\.free-limit`&&([A-Za-z_$][\w$]*\(`resetAt`)', '$1.data.error.type===`provider.free-limit`&&(window.__ocLimit&&window.__ocLimit($1.data.sessionID),0)&&$2')
      if ($new -ne $text) { $found["out/renderer/assets/$($p.Name)"] = $utf8.GetBytes($new) }
    }
  } finally { $fs.Dispose() }
  $found
}

# New asar = the original data untouched + the changed files appended at the end, with a new header.
function Write-PatchedAsar([string]$source, [string]$dest, [string]$newPackageJson, [string]$bootJs, [hashtable]$extra) {
  $h = Read-AsarHeader $source
  $tree = $h.Json | ConvertFrom-Json
  $dataLen = $h.Length - $h.Base
  $utf8 = New-Object Text.UTF8Encoding($false)
  $pkgBytes  = $utf8.GetBytes($newPackageJson)
  $bootBytes = $utf8.GetBytes($bootJs)

  $tree.files.PSObject.Properties.Remove('package.json')
  $tree.files | Add-Member -NotePropertyName 'package.json' -NotePropertyValue ([ordered]@{ size = $pkgBytes.Length; offset = "$dataLen" })
  $mainFiles = $tree.files.out.files.main.files
  $mainFiles.PSObject.Properties.Remove('slipstream-boot.js')
  $mainFiles | Add-Member -NotePropertyName 'slipstream-boot.js' -NotePropertyValue ([ordered]@{ size = $bootBytes.Length; offset = "$($dataLen + $pkgBytes.Length)" })

  $next = $dataLen + $pkgBytes.Length + $bootBytes.Length
  $order = @($extra.Keys)
  foreach ($key in $order) {
    $node = $tree
    foreach ($part in $key.Split('/')) { $node = $node.files.$part }
    $node.size = $extra[$key].Length
    $node.offset = "$next"
    $node.PSObject.Properties.Remove('integrity')
    $next += $extra[$key].Length
  }

  $json = $utf8.GetBytes(($tree | ConvertTo-Json -Depth 100 -Compress))
  $pad = (4 - ($json.Length % 4)) % 4
  $payload = 4 + $json.Length + $pad
  $out = [IO.File]::Create($dest)
  $in = [IO.File]::OpenRead($source)
  try {
    $bw = New-Object IO.BinaryWriter($out)
    $bw.Write([uint32]4); $bw.Write([uint32]($payload + 4)); $bw.Write([uint32]$payload); $bw.Write([uint32]$json.Length)
    $bw.Write($json); if ($pad) { $bw.Write((New-Object byte[] $pad)) }
    $bw.Flush()
    $in.Position = $h.Base
    $buf = New-Object byte[] (4MB); $left = $dataLen
    while ($left -gt 0) { $n = $in.Read($buf, 0, [int][Math]::Min($buf.Length, $left)); if ($n -le 0) { throw 'short read' }; $out.Write($buf, 0, $n); $left -= $n }
    $out.Write($pkgBytes, 0, $pkgBytes.Length)
    $out.Write($bootBytes, 0, $bootBytes.Length)
    foreach ($key in $order) { $out.Write($extra[$key], 0, $extra[$key].Length) }
  } finally { $in.Dispose(); $out.Dispose() }
}

# ---------------------------------------------------------------- install
Stop-OpenCode

if (-not (Test-Path $asarBak)) {
  Step (T 'saving')
  Copy-Item $asar $asarBak
}
$pkgText = Read-AsarFile $asarBak 'package.json'
$newPkg = [regex]::Replace($pkgText, '"main"\s*:\s*"[^"]*"', '"main": "./out/main/slipstream-boot.js"')
if ($newPkg -eq $pkgText) { Fail 'could not find "main" in package.json'; return }

Step (T 'patching')
$tmp = "$asar.new"
try {
  $extra = Get-AsarPatches $asarBak
  if ($extra.Count) { Ok (T 'codeOk') } else { Warn (T 'codeMissing') }
  Write-PatchedAsar $asarBak $tmp $newPkg $BootJs $extra
  # check before replacing: the new asar must read back the new entry
  if ((Read-AsarFile $tmp 'package.json') -notmatch 'slipstream-boot\.js') { throw 'verification failed: package.json' }
  if ((Read-AsarFile $tmp 'out/main/slipstream-boot.js') -notmatch 'Slipstream') { throw 'verification failed: boot file' }
  Move-Item $tmp $asar -Force
} catch {
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  Fail (T 'failed' @{ err = $_.Exception.Message })
  return
}
Ok (T 'trayOk')

# OpenCode's updater would replace the patched app, so it is pointed at nothing (-block_update_off undoes this)
if ((Test-Path $upd) -and -not (Test-Path $updBak)) {
  Copy-Item $upd $updBak -Force
  (Get-Content $upd -Raw) -replace '(?m)^url:.*$', 'url: http://127.0.0.1:9/' | Set-Content $upd -NoNewline
  Ok (T 'updBlocked')
}

Write-Host ''
Ok (T 'done')
Say ('  ' + (T 'openHint')) DarkGray
Say ('  ' + (T 'undo')) DarkGray
if ($start) { Start-Process (Join-Path $dir $exeName) }
