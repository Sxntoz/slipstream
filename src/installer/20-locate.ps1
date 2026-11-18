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

