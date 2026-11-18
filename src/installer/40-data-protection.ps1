function Get-DataFiles {
  $d = Join-Path $env:USERPROFILE '.local\share\opencode'
  $a = Join-Path $env:APPDATA 'ai.opencode.desktop'
  $s = Join-Path $env:LOCALAPPDATA 'slipstream'
  @("$d\opencode.db", "$d\opencode.db-wal", "$d\opencode.db-shm", "$d\auth.json",
    "$a\opencode.settings", "$a\drafts.sqlite", "$a\drafts.sqlite-wal", "$a\drafts.sqlite-shm",
    "$s\proxy.json", "$s\cli.json", "$s\wg\account.json", "$s\wg\account-cli.json", "$s\wg\custom.json")
}
function Protect-Data {
  $dir = Join-Path $env:LOCALAPPDATA ('slipstream\backup\update-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
  New-Item -ItemType Directory -Force $dir | Out-Null
  $items = @(); $i = 0
  foreach ($f in Get-DataFiles) {
    if (-not (Test-Path -LiteralPath $f)) { continue }
    $copy = Join-Path $dir ('{0:D2}.bak' -f $i++)
    Copy-Item -LiteralPath $f $copy -Force
    $items += [pscustomobject]@{ Path = $f; Copy = $copy; Hash = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash }
  }
  # keep the 3 newest backups of this kind
  Get-ChildItem (Split-Path $dir) -Directory -Filter 'update-*' -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -Skip 3 | ForEach-Object { Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue }
  $items
}
# After the update every file must still be there and byte for byte the same; if not, it is put back from the backup.
function Test-Data($items) {
  $changed = @($items | Where-Object { -not (Test-Path -LiteralPath $_.Path) -or (Get-FileHash -LiteralPath $_.Path -Algorithm SHA256).Hash -ne $_.Hash })
  foreach ($c in $changed) { Copy-Item -LiteralPath $c.Copy $c.Path -Force }
  $changed.Count -eq 0
}

