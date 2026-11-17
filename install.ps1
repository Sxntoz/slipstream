param
(
    [Alias("m")]
    [switch]$mirror
)

# Tiny loader (same idea as SpotX): downloads the real run.ps1 with retries and runs it with your parameters.
#   iex "& { $(iwr -useb 'https://raw.githubusercontent.com/Sxntoz/driftwire/main/install.ps1') } -start"
# Every parameter of run.ps1 can be added after it: -uninstall, -status, -start, -download, -block_update_off, -path <folder>

function Run-DriftWire {

    param(
        [string]$params
    )

    $maxRetryCount = 3
    $retryInterval = 5

    if ($mirror) {
        $url = 'https://cdn.jsdelivr.net/gh/Sxntoz/driftwire@main/run.ps1'
    }
    else {
        $url = 'https://raw.githubusercontent.com/Sxntoz/driftwire/main/run.ps1'
    }

    for ($retry = 1; $retry -le $maxRetryCount; $retry++) {
        try {
            $response = iwr -useb $url
            $StatusCode = $response.StatusCode
        }
        catch {
            $StatusCode = $_.Exception.Response.StatusCode.value__
        }

        if ($StatusCode -eq 200) {
            iex "& {$($response)} $params"
            return
        }
        else {
            Write-Host ("Attempt $($retry): HTTP status code: $($StatusCode). Retrying in $($retryInterval) seconds...")
            Start-Sleep -Seconds $retryInterval
        }
    }

    Write-Host
    Write-Warning "Failed to make the request after $maxRetryCount attempts, script terminated."
    Write-Host $Error[0].Exception.Message
    exit
}

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12;
Run-DriftWire -params $args
