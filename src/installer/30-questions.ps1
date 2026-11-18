# ---------------------------------------------------------------- questions (like SpotX: [Y/N]), download bar, safe update
$interactive = -not $yes
try { if ([Console]::IsInputRedirected) { $interactive = $false } } catch {}

# Asks a yes/no question. When nobody can answer (-yes, or no console) the default is used.
function Ask([string]$key, [hashtable]$vars = @{}, [bool]$default = $true) {
  if ($yes) { return $true }
  if (-not $interactive) { return $default }
  Write-Host ''
  $answer = (Read-Host ((T $key $vars) + ' [Y/N]')).Trim().ToLower()
  if (-not $answer) { return $default }
  $answer -match (T 'yes')
}

function Get-LatestTag {
  try {
    $rels = Invoke-RestMethod 'https://api.github.com/repos/anomalyco/opencode/releases?per_page=30' -Headers @{ 'User-Agent' = 'slipstream' }
    ($rels | Where-Object { $_.tag_name -match '^v\d+\.\d+\.\d+$' -and $_.assets.name -contains 'opencode-desktop-win-x64.exe' } |
      Sort-Object { [version]($_.tag_name.TrimStart('v')) } -Descending | Select-Object -First 1).tag_name
  } catch { $null }
}
$three = { param($v) [version](([string]$v) -replace '^(\d+\.\d+\.\d+).*$', '$1') }

# A download with a bar:   ################################ 100.0%
function Get-FileWithBar([string]$url, [string]$out) {
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  $req = [Net.HttpWebRequest]::Create($url); $req.UserAgent = 'slipstream'
  $res = $req.GetResponse(); $total = $res.ContentLength
  $in = $res.GetResponseStream(); $fs = [IO.File]::Create($out)
  $show = $true; try { if ([Console]::IsOutputRedirected) { $show = $false } } catch {}
  $width = 60; $buf = New-Object byte[] 131072; $read = 0L; $last = -1
  try {
    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
      $fs.Write($buf, 0, $n); $read += $n
      if ($show -and $total -gt 0) {
        $pct = [Math]::Floor(1000 * $read / $total) / 10
        if ($pct -ne $last) { $last = $pct; $fill = [int]($width * $read / $total); Write-Host ("`r  " + ('#' * $fill) + (' ' * ($width - $fill)) + (' {0,5:N1}%' -f $pct)) -NoNewline }
      }
    }
  } finally { $fs.Dispose(); $in.Dispose(); $res.Close() }
  if ($show) { Write-Host '' }
}

# Everything that is yours and lives outside the app: chats, login, settings, drafts and Slipstream's own files.
