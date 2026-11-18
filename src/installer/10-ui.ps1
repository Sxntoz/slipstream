function Say($m, $c = 'White') { Write-Host $m -ForegroundColor $c }
function Step($m) { Write-Host '  > ' -NoNewline -ForegroundColor Cyan; Write-Host $m }
function Ok($m)   { Write-Host '  + ' -NoNewline -ForegroundColor Green; Write-Host $m }
function Warn($m) { Write-Host '  ! ' -NoNewline -ForegroundColor Yellow; Write-Host $m }
function Fail($m) { Write-Host '  x ' -NoNewline -ForegroundColor Red; Write-Host $m }

# Installer messages in 12 languages (Base64 of UTF-8 JSON, so this file stays plain ASCII for any PowerShell).
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$I18N = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('@@INSTALLER_I18N@@')) | ConvertFrom-Json
$code = if ($lang) { $lang } else { (Get-Culture).Name }
$code = if ($code -like 'pt*') { 'pt-BR' } elseif ($code -like 'zh*') { 'zh-CN' } else { ($code -split '-')[0] }
if (-not $I18N.PSObject.Properties[$code]) { $code = 'en' }
function T([string]$key, [hashtable]$vars = @{}) {
  $text = $I18N.$code.$key
  if (-not $text) { $text = $I18N.en.$key }
  foreach ($k in $vars.Keys) { $text = $text.Replace('{' + $k + '}', [string]$vars[$k]) }
  $text
}

$ScriptVersion = '1.1.1'
Say @"

  +-------------------------------------+
  |  Welcome to Slipstream for Windows  |
  +-------------------------------------+
  patcher $ScriptVersion

"@ Cyan

if ($PSVersionTable.PSVersion.Major -lt 5) { Fail (T 'psOld'); Say ('  ' + (T 'stopped')) Red; return }
if ($env:OS -ne 'Windows_NT') { Fail (T 'winOnly'); Say ('  ' + (T 'stopped')) Red; return }

