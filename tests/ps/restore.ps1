param([string]$Script)
$src = Get-Content $Script -Raw
Invoke-Expression ([regex]::Match($src, "(?s)function Test-Data.*?\n\}\n").Value)
$d = Join-Path $env:TEMP 'restore-test'; Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue; New-Item -ItemType Directory $d | Out-Null
$a = Join-Path $d 'chats.db'; $b = Join-Path $d 'auth.json'
Set-Content $a 'conversa importante' -NoNewline; Set-Content $b '{"key":"segredo"}' -NoNewline
$items = foreach ($f in $a, $b) { $c = "$f.bak"; Copy-Item $f $c; [pscustomobject]@{ Path = $f; Copy = $c; Hash = (Get-FileHash $f -Algorithm SHA256).Hash } }
"1) nada mudou           -> Test-Data = $(Test-Data $items)"
Set-Content $a 'corrompido pela atualizacao' -NoNewline; Remove-Item $b
"2) um mudou, outro sumiu -> Test-Data = $(Test-Data $items)"
"   chats.db restaurado : $(Get-Content $a -Raw)"
"   auth.json restaurado: $(Get-Content $b -Raw)"
Remove-Item $d -Recurse -Force
