# ---------------------------------------------------------------- find the install
$dir = Find-Install
if (-not $dir -and ($download -or (Ask 'qDownload' @{} $false))) { Get-Original $version; $dir = Find-Install }
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

# Is there a newer official version? (-update means yes, without asking)
$doUpdate = [bool]$update
$latestTag = $null
if (-not ($status -or $uninstall -or $block_update_off)) {
  $latestTag = Get-LatestTag
  if ($latestTag -and -not $doUpdate) {
    $have = & $three $ver; $new = & $three $latestTag.TrimStart('v')
    if ($new -gt $have) { $doUpdate = Ask 'qUpdate' @{ v = $have.ToString(); n = $new.ToString() } $false }
    else { Step (T 'sUpToDate' @{ v = $have.ToString() }) }
  }
}

if ($doUpdate) {
  Step (T 'updating')
  Stop-OpenCode
  Step (T 'sBackup')
  $saved = Protect-Data
  # the official installer replaces the app, so the original files go back first and the patch is rebuilt on the new version
  if (Test-Path $asarBak) { Move-Item $asarBak $asar -Force }
  if (Test-Path $updBak) { Move-Item $updBak $upd -Force }
  Get-Original $(if ($version) { $version } else { $latestTag })
  $dir = Find-Install
  $ver = (Get-Item (Join-Path $dir $exeName)).VersionInfo.ProductVersion
  Ok (T 'updated' @{ v = $ver })
  if (Test-Data $saved) { Ok (T 'sIntact') } else { Warn (T 'sRestored') }
}

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

