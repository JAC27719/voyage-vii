[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ApiImage
)

$ErrorActionPreference = "Stop"

$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$composeFile = Join-Path $root "compose.yaml"
$imagePattern = '^[^:]+(?:/[^:]+)*:[^@\s]+@sha256:[0-9a-f]{64}$'
$apiVersionPattern = ':0\.1\.0@sha256:'

if ($ApiImage -notmatch $imagePattern) {
    throw "ApiImage must be an exact tag+digest pin: name:tag@sha256:<64 lowercase hex chars>."
}
if ($ApiImage -notmatch $apiVersionPattern) {
    throw "ApiImage must use the frozen Voyage VII API tag 0.1.0."
}

$env:VOYAGE_VII_API_IMAGE = $ApiImage
$script:appToken = $null
$script:supervisorToken = $null
$script:apiUrl = $null

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]] $Args)
    & docker compose --file $composeFile @Args
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($Args -join ' ') failed with exit code $LASTEXITCODE."
    }
}

function Redact-Line {
    param([string] $Line)

    $redacted = $Line -replace 'VOYAGE_VII_HANDSHAKE\s+\{.*\}', 'VOYAGE_VII_HANDSHAKE [redacted]'
    $redacted = $redacted -replace '(Authorization:\s*Bearer\s+)[A-Za-z0-9_-]+', '$1[redacted]'
    if ($script:appToken) {
        $redacted = $redacted.Replace($script:appToken, "[redacted-app-token]")
    }
    if ($script:supervisorToken) {
        $redacted = $redacted.Replace($script:supervisorToken, "[redacted-supervisor-token]")
    }
    return $redacted
}

function Wait-ApiReady {
    if (-not $script:appToken -or -not $script:apiUrl) {
        throw "Cannot run authenticated checks before the API handshake is captured."
    }

    $deadline = (Get-Date).AddSeconds(60)
    $headers = @{ Authorization = "Bearer $script:appToken"; Origin = "http://localhost:1420" }
    do {
        try {
            $ready = Invoke-WebRequest -Uri "$($script:apiUrl)/health/ready" -Method Get -UseBasicParsing -TimeoutSec 10
            if ($ready.StatusCode -eq 200) {
                $status = Invoke-RestMethod -Uri "$($script:apiUrl)/api/v1/system/status" -Method Get -Headers $headers -TimeoutSec 10
                Invoke-AuthenticatedRetryCheck -Headers $headers
                Write-Host ("API ready. overallState={0}; retry check passed" -f $status.overallState)
                return
            }
        } catch {
            Start-Sleep -Seconds 1
        }
    } while ((Get-Date) -lt $deadline)

    throw "API did not report ready within 60 seconds."
}

function Invoke-AuthenticatedRetryCheck {
    param([hashtable] $Headers)

    $retry = Invoke-RestMethod -Uri "$($script:apiUrl)/api/v1/system/retry" -Method Post -Headers $Headers -TimeoutSec 10
    if ($null -eq $retry -or $retry.accepted -ne $false) {
        throw "Authenticated retry check returned an unexpected response."
    }
    if (-not $retry.targets -or $retry.targets.Count -ne 2) {
        throw "Authenticated retry check did not return both component targets."
    }
    if ([string] $retry.targets[0] -ne "sqlite" -or [string] $retry.targets[1] -ne "tigerbeetle") {
        throw "Authenticated retry check returned unexpected component order."
    }
}

function Start-AttachedApi {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "docker"
    foreach ($arg in @("compose", "--file", $composeFile, "up", "--no-log-prefix", "--attach", "api", "api")) {
        [void] $psi.ArgumentList.Add($arg)
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $root
    $psi.Environment["VOYAGE_VII_API_IMAGE"] = $ApiImage

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $psi
    $handshakeSeen = [System.Threading.ManualResetEventSlim]::new($false)

    $onOutput = [System.Diagnostics.DataReceivedEventHandler] {
        param($sender, $event)
        if ($null -eq $event.Data) { return }
        $line = $event.Data
        if ($line.StartsWith("VOYAGE_VII_HANDSHAKE ")) {
            $jsonText = $line.Substring("VOYAGE_VII_HANDSHAKE ".Length)
            try {
                $handshake = $jsonText | ConvertFrom-Json
                if ($handshake.protocolVersion -ne 1) {
                    throw "Unsupported handshake protocol version."
                }
                $script:apiUrl = [string] $handshake.apiUrl
                $script:appToken = [string] $handshake.appToken
                $script:supervisorToken = [string] $handshake.supervisorToken
                if ($script:appToken -eq $script:supervisorToken) {
                    throw "API returned identical app and supervisor tokens."
                }
                [void] $handshakeSeen.Set()
            } catch {
                Write-Error "Failed to parse API handshake: $($_.Exception.Message)"
            }
        }
        Write-Host (Redact-Line $line)
    }

    $onError = [System.Diagnostics.DataReceivedEventHandler] {
        param($sender, $event)
        if ($null -eq $event.Data) { return }
        Write-Host (Redact-Line $event.Data)
    }

    $process.add_OutputDataReceived($onOutput)
    $process.add_ErrorDataReceived($onError)
    [void] $process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    if (-not $handshakeSeen.Wait([TimeSpan]::FromSeconds(15))) {
        if (-not $process.HasExited) {
            $process.Kill($true)
        }
        throw "API handshake was not observed within 15 seconds."
    }

    Wait-ApiReady
    Write-Host "Compose is attached. Press Ctrl+C to stop containers without removing volumes."

    try {
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw "Attached docker compose exited with code $($process.ExitCode)."
        }
    } finally {
        $process.remove_OutputDataReceived($onOutput)
        $process.remove_ErrorDataReceived($onError)
    }
}

try {
    Invoke-Compose config --quiet
    Invoke-Compose up --detach tigerbeetle
    Start-AttachedApi
} finally {
    $script:appToken = $null
    $script:supervisorToken = $null
    Invoke-Compose stop --timeout 20
}
