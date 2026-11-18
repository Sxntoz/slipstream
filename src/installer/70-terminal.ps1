# ---------------------------------------------------------------- the terminal version (Node, no Electron)
$CliShim = @'
@@CLI_SHIM@@
'@

$CliMain = @'
@@CLI_MAIN@@
'@

# Same engine as the tray version, cut before the tray, with stand-ins for Electron and its own settings, account and proxy port
# (a second session must not share them: two clients with one WireGuard key kick each other out).
function Get-CliSource {
  $mark = '// ---------------------------------------------------------------- tray menu'
  $head = $BootJs.Substring(0, $BootJs.IndexOf($mark))
  $head = $head.Replace('import { app, Tray, Menu, Notification, shell, dialog, nativeImage } from "electron"', $CliShim)
  $a = $head.IndexOf('// The app keeps the free-limit time')
  $b = $head.IndexOf('// ---------------------------------------------------------------- settings (proxy.json)')
  if ($a -ge 0 -and $b -gt $a) { $head = $head.Remove($a, $b - $a) }          # that part is for the desktop app's database
  $head = $head.Replace('"proxy.json"', '"cli.json"').Replace('cfg.gatePort', 'cfg.cliGatePort').Replace('"account.json"', '"account-cli.json"')
  $c = $head.LastIndexOf('if (cfg.mode === "wg" || cfg.mode === "wgfile" || cfg.mode === "free") {')
  if ($c -ge 0) { $head = $head.Substring(0, $c) }                            # the terminal brings the connection up itself, before it starts the program
  $head + $CliMain
}

function Get-CliPaths {
  $npmPrefix = ''
  try { $npmPrefix = (npm config get prefix 2>$null | Select-Object -First 1).Trim() } catch {}
  if (-not $npmPrefix -or -not (Test-Path $npmPrefix)) { $npmPrefix = Join-Path $env:APPDATA 'npm' }
  @{ Dir = (Join-Path $env:LOCALAPPDATA 'slipstream\cli'); Prefix = $npmPrefix; Cmd = (Join-Path $npmPrefix 'slipstream.cmd'); V1 = (Join-Path $env:LOCALAPPDATA 'opencode-v1') }
}

function Install-Terminal([bool]$withUpdate) {
  $pt = Get-CliPaths
  $cliDir = $pt.Dir; $npmPrefix = $pt.Prefix; $cliCmd = $pt.Cmd; $v1Dir = $pt.V1
  $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
  $nodeOk = $false
  if ($nodeCmd) { try { $nodeOk = ([version](& node --version).TrimStart('v')).Major -ge 20 } catch {} }
  if (-not $nodeOk) { Fail (T 'cliNode'); Say ('  ' + (T 'stopped')) Red; return }

  if ($withUpdate) {
    # OpenCode v2 (@opencode/cli: the commands opencode and opencode2) and v1 (opencode-ai, kept apart as opencode1)
    Step (T 'updating')
    & npm install -g '@opencode/cli@latest' 2>&1 | Out-Null
    New-Item -ItemType Directory -Force $v1Dir | Out-Null
    & npm install --prefix $v1Dir 'opencode-ai@latest' --no-fund --no-audit 2>&1 | Out-Null
    $v1Cmd = Join-Path $v1Dir 'node_modules\.bin\opencode.cmd'
    $v1Xdg = Join-Path $v1Dir 'xdg'
    Set-Content -Path (Join-Path $npmPrefix 'opencode1.cmd') -Value ("@ECHO off`r`nSET `"XDG_DATA_HOME=$v1Xdg\data`"`r`nSET `"XDG_STATE_HOME=$v1Xdg\state`"`r`nSET `"XDG_CACHE_HOME=$v1Xdg\cache`"`r`n`"$v1Cmd`" %*") -Encoding ascii
    $v2 = try { (& opencode2 --version 2>&1 | Select-Object -First 1) -replace '^\D*', '' } catch { '?' }
    $v1 = try { (& $v1Cmd --version 2>&1 | Select-Object -First 1) } catch { '?' }
    # the same for Git Bash / WSL-style shells
    [IO.File]::WriteAllText((Join-Path $npmPrefix 'opencode1'), ("#!/bin/sh`nexport XDG_DATA_HOME=`"`$LOCALAPPDATA/opencode-v1/xdg/data`" XDG_STATE_HOME=`"`$LOCALAPPDATA/opencode-v1/xdg/state`" XDG_CACHE_HOME=`"`$LOCALAPPDATA/opencode-v1/xdg/cache`"`nexec `"`$LOCALAPPDATA/opencode-v1/node_modules/opencode-windows-x64/bin/opencode.exe`" `"`$@`"`n"), (New-Object Text.UTF8Encoding($false)))
    Ok (T 'cliUpd' @{ v2 = $v2; v1 = $v1 })
  }

  New-Item -ItemType Directory -Force $cliDir | Out-Null
  $utf8 = New-Object Text.UTF8Encoding($false)
  [IO.File]::WriteAllText((Join-Path $cliDir 'slipstream.mjs'), (Get-CliSource), $utf8)
  [IO.File]::WriteAllText((Join-Path $cliDir 'package.json'), '{"type":"module"}', $utf8)
  Set-Content -Path $cliCmd -Value ("@ECHO off`r`nnode `"%LOCALAPPDATA%\slipstream\cli\slipstream.mjs`" %*") -Encoding ascii
  # the same command for Git Bash / WSL-style shells (no extension, LF line ends)
  [IO.File]::WriteAllText((Join-Path $npmPrefix 'slipstream'), ("#!/bin/sh`nexec node `"`$LOCALAPPDATA/slipstream/cli/slipstream.mjs`" `"`$@`"`n"), $utf8)
  Ok (T 'cliOk')
}

if ($terminal) {
  $pt = Get-CliPaths
  if ($status) {
    Say "  slipstream (terminal) : $(Test-Path $pt.Cmd)"
    foreach ($n in 'opencode', 'opencode1', 'opencode2') { $v = try { (& $n --version 2>&1 | Select-Object -First 1) } catch { '-' }; Say ("  {0,-10} : {1}" -f $n, $v) }
    return
  }
  if ($uninstall) {
    if (Test-Path $pt.Cmd) { Remove-Item $pt.Cmd -Force }
    $cliSh = Join-Path $pt.Prefix 'slipstream'; if (Test-Path $cliSh) { Remove-Item $cliSh -Force }
    if (Test-Path $pt.Dir) { Remove-Item $pt.Dir -Recurse -Force }
    Ok (T 'cliGone')
    return
  }
  Install-Terminal $update
  return
}

