# ---------------------------------------------------------------- download the original
function Get-Original([string]$want) {
  if ($want) { $tag = "v$($want.TrimStart('v'))" } else { $tag = Get-LatestTag }
  if (-not $tag) { throw 'no release with a Windows installer was found' }
  $out = Join-Path $env:TEMP "opencode-desktop-win-x64-$tag.exe"
  Step (T 'sDownload' @{ v = $tag.TrimStart('v') })
  for ($try = 1; $try -le 3; $try++) {
    try { Get-FileWithBar "https://github.com/anomalyco/opencode/releases/download/$tag/opencode-desktop-win-x64.exe" $out; break }
    catch {
      Warn "Error downloading ($($_.Exception.Message))"
      if ($try -eq 3) { throw 'Check your network settings and run the installation again' }
      Warn 'Will re-request in 5 seconds...'; Start-Sleep 5
    }
  }
  Step (T 'sInstall')
  Start-Process $out -ArgumentList '/S' -Wait
  Remove-Item $out -Force -ErrorAction SilentlyContinue
}

