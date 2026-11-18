param([string]$Script)
# Loads the dictionary and the Ask function out of run.ps1 and answers the question with a fake Read-Host.
$src = Get-Content $Script -Raw
$ErrorActionPreference = 'Stop'
$lang = ''
$yes = $false
function Say($m, $c) {}
$null = $src -match "(?s)(# Installer messages in 12 languages.*?\n\})"
Invoke-Expression $Matches[1]
Invoke-Expression ([regex]::Match($src, "(?s)function Ask\(.*?\n\}\n").Value)
$interactive = $true
function Read-Host($prompt) { $script:asked = $prompt; $script:next }
$cases = @(
  @('pt-BR', 'sim', $true), @('pt-BR', 'n', $false), @('es', 'si', $true), @('es', 'n', $false), @('de', 'ja', $true),
  @('ru', 'n', $true), @('fr', 'oui', $true), @('en', 'y', $true), @('en', '', $true), @('en', '', $false), @('zh-CN', 'y', $true), @('id', 'ya', $true)
)
foreach ($case in $cases) {
  $code = $case[0]; $script:next = $case[1]
  $r = Ask 'qUpdate' @{ v = '2.3.0'; n = '2.3.2' } ([bool]$case[2])
  "{0,-6} answer='{1}' default={2} -> {3} | {4}" -f $code, $case[1], $case[2], $r, $script:asked
}
