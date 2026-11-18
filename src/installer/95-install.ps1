# ---------------------------------------------------------------- install
$blockUpdates = Ask 'qBlock' @{} $true
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
if ($blockUpdates -and (Test-Path $upd) -and -not (Test-Path $updBak)) {
  Copy-Item $upd $updBak -Force
  (Get-Content $upd -Raw) -replace '(?m)^url:.*$', 'url: http://127.0.0.1:9/' | Set-Content $upd -NoNewline
  Ok (T 'updBlocked')
}

# the terminal version: offered once, only when Node is there and it is not installed yet
$pt = Get-CliPaths
if (-not (Test-Path $pt.Cmd) -and (Get-Command node -ErrorAction SilentlyContinue) -and (Ask 'qTerminal' @{} $false)) { Install-Terminal $false }

Write-Host ''
Ok (T 'done')
Say ('  ' + (T 'openHint')) DarkGray
Say ('  ' + (T 'undo')) DarkGray
if ($start) { Start-Process (Join-Path $dir $exeName) }
