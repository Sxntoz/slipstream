# Slipstream CLI tray. It has no logic of its own: it draws the menu the agent describes (labels already in the user's language)
# and sends the clicks back to the agent. Needs nothing installed: Windows PowerShell and WinForms.
param([string]$AgentFile)
$ErrorActionPreference = 'Stop'
$logFile = Join-Path $env:LOCALAPPDATA 'slipstream\tray.log'
trap { try { Add-Content -LiteralPath $logFile -Value ("{0} {1}" -f (Get-Date -Format s), $_) } catch {}; continue }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

function Write-Log([string]$m) { try { Add-Content -LiteralPath $logFile -Value ('{0} [{1}] {2}' -f (Get-Date -Format s), $PID, $m) } catch {} }
Write-Log 'tray starting'

# one tray at a time
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\SlipstreamCliTray', [ref]$created)
if (-not $created) { Write-Log 'another tray is already running'; return }

# ---------------------------------------------------------------- the agent's control port
function Read-Agent([string]$file) {
  try {
    $j = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
    if (Get-Process -Id $j.pid -ErrorAction SilentlyContinue) { return $j }
  } catch {}
  $null
}
function Invoke-Agent([string]$file, [string]$cmd, $arguments = @(), [int]$timeoutMs = 130000) {
  $agent = Read-Agent $file
  if (-not $agent) { return $null }
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $client.Connect('127.0.0.1', [int]$agent.port)
    $stream = $client.GetStream(); $stream.ReadTimeout = $timeoutMs
    $json = [pscustomobject]@{ token = $agent.token; cmd = $cmd; args = @($arguments) } | ConvertTo-Json -Compress -Depth 5
    $bytes = [Text.Encoding]::UTF8.GetBytes($json + "`n")
    $stream.Write($bytes, 0, $bytes.Length)
    $ms = New-Object IO.MemoryStream; $buf = New-Object byte[] 8192
    while (($n = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $ms.Write($buf, 0, $n) }
    return [Text.Encoding]::UTF8.GetString($ms.ToArray()) | ConvertFrom-Json
  } catch { return $null } finally { $client.Close() }
}
# the same two functions, as text, for the background runspaces that run the slow actions (a new IP takes seconds)
$agentFunctions = "function Read-Agent { $((Get-Command Read-Agent).ScriptBlock) }`nfunction Invoke-Agent { $((Get-Command Invoke-Agent).ScriptBlock) }"

# ---------------------------------------------------------------- messages: a result is shown in a message box (toasts are often swallowed)
function Show-Result([string]$text) {
  if (-not $text) { return }
  $owner = New-Object System.Windows.Forms.Form
  $owner.TopMost = $true; $owner.ShowInTaskbar = $false; $owner.StartPosition = 'Manual'
  $owner.Location = New-Object System.Drawing.Point(-2000, -2000); $owner.Size = New-Object System.Drawing.Size(1, 1)
  $owner.Show()
  [void][System.Windows.Forms.MessageBox]::Show($owner, $text, 'Slipstream CLI', 'OK', 'Information')
  $owner.Close()
}

# ---------------------------------------------------------------- actions run in the background, the tray stays responsive
$script:jobs = New-Object System.Collections.ArrayList
function Start-Action([string]$cmd, $arguments = @()) {
  $rs = [runspacefactory]::CreateRunspace(); $rs.Open()
  $rs.SessionStateProxy.SetVariable('file', $AgentFile)
  $rs.SessionStateProxy.SetVariable('cmd', $cmd)
  $rs.SessionStateProxy.SetVariable('arguments', @($arguments))
  $ps = [powershell]::Create(); $ps.Runspace = $rs
  [void]$ps.AddScript($agentFunctions + "`nInvoke-Agent `$file `$cmd `$arguments")
  [void]$script:jobs.Add([pscustomobject]@{ Ps = $ps; Rs = $rs; Handle = $ps.BeginInvoke(); Cmd = $cmd })
}

function Invoke-MenuItem($item) {
  if ($item.action -eq 'open') { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + [string]$item.path + '"'); return }
  if ($item.action -eq 'choose-wg') {
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Filter = 'WireGuard (*.conf)|*.conf|All files (*.*)|*.*'
    if ($dialog.ShowDialog() -eq 'OK') { Start-Action 'wgfile' @($dialog.FileName) }
    return
  }
  if ($item.cmd) { Start-Action ([string]$item.cmd) @($item.args) }
}

# ---------------------------------------------------------------- the menu
$bytes = [Convert]::FromBase64String('@@CLI_ICON_B64@@')
$bitmap = New-Object System.Drawing.Bitmap (New-Object System.IO.MemoryStream (, $bytes))
$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Icon = [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
$notify.Text = 'Slipstream CLI'
$notify.Visible = $true
$menu = New-Object System.Windows.Forms.ContextMenuStrip
$notify.ContextMenuStrip = $menu

function Add-Items($collection, $items) {
  foreach ($item in $items) {
    if ($item.separator) { [void]$collection.Add((New-Object System.Windows.Forms.ToolStripSeparator)); continue }
    $entry = New-Object System.Windows.Forms.ToolStripMenuItem ([string]$item.label)
    if ($item.checked) { $entry.Checked = $true }
    if ($item.children) { Add-Items $entry.DropDownItems $item.children }
    else { $entry.Tag = $item; $entry.Add_Click({ param($sender, $e) Invoke-MenuItem $sender.Tag }) }
    [void]$collection.Add($entry)
  }
}
function Update-Menu {
  $reply = Invoke-Agent $AgentFile 'menu' @() 8000
  $menu.Items.Clear()
  if (-not $reply -or -not $reply.menu) { [void]$menu.Items.Add('(Slipstream CLI is not running)'); return }
  Add-Items $menu.Items $reply.menu.items
}
$menu.Add_Opening({ param($sender, $e) Update-Menu })
# a left click opens the same menu (a right click does it by itself)
$notify.Add_MouseClick({
  param($sender, $e)
  if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
    Update-Menu
    [System.Windows.Forms.NotifyIcon].GetMethod('ShowContextMenu', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($notify, $null)
  }
})

# ---------------------------------------------------------------- once a second: finished actions, messages from the agent, is it still there?
$script:ticks = 0; $script:misses = 0; $script:showing = $false
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
  $script:ticks++
  foreach ($job in @($script:jobs)) {
    if (-not $job.Handle.IsCompleted) { continue }
    [void]$script:jobs.Remove($job)
    $reply = $null
    try { $reply = $job.Ps.EndInvoke($job.Handle) | Select-Object -First 1 } catch {}
    $job.Ps.Dispose(); $job.Rs.Dispose()
    if ($job.Cmd -eq 'quit') { [System.Windows.Forms.Application]::Exit(); return }
    if ($reply -and $reply.text) { Show-Result ([string]$reply.text) }
  }
  # the agent is gone (slipstream stop, a reinstall, a crash): leave, so a new tray can start
  if (-not (Read-Agent $AgentFile)) { if (++$script:misses -ge 2) { Write-Log 'the agent is gone: leaving'; [System.Windows.Forms.Application]::Exit() }; return }
  $script:misses = 0
  if ($script:ticks % 3 -ne 0 -or $script:showing) { return }
  $reply = Invoke-Agent $AgentFile 'notices' @() 5000
  if (-not $reply) { return }
  if ($reply.notices) {
    $script:showing = $true
    try { Show-Result ((@($reply.notices) | ForEach-Object { [string]$_ }) -join "`n`n") } finally { $script:showing = $false }
  }
})
$timer.Start()

Write-Log 'tray ready'
[System.Windows.Forms.Application]::Run()
Write-Log 'tray closed'
$timer.Stop(); $notify.Visible = $false; $notify.Dispose()
try { $mutex.ReleaseMutex() } catch {}
