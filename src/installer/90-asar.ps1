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

