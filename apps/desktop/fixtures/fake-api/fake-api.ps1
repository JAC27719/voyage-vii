#requires -Version 7.0

[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet(
    "valid",
    "delayed",
    "malformed",
    "duplicate",
    "missing",
    "crash",
    "grandchild",
    "exit7",
    "ignore-shutdown",
    "env-check",
    "record-shutdown-token"
  )]
  [string]$Mode,
  [string]$MarkerPath,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ApiArgs
)

$ErrorActionPreference = "Stop"
$appToken = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE"
$supervisorToken = "AgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgI"

function Write-Handshake([int]$Port) {
  [Console]::Out.WriteLine("VOYAGE_VII_HANDSHAKE {`"protocolVersion`":1,`"apiUrl`":`"http://127.0.0.1:$Port`",`"appToken`":`"$appToken`",`"supervisorToken`":`"$supervisorToken`"}")
  [Console]::Out.Flush()
}

function Write-HttpResponse($Stream, [string]$Status, [string]$Body) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $header = "HTTP/1.1 $Status`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
  $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($header)
  $Stream.Write($headerBytes, 0, $headerBytes.Length)
  $Stream.Write($bytes, 0, $bytes.Length)
  $Stream.Flush()
}

if ($Mode -eq "delayed") {
  Start-Sleep -Seconds 3
}

if ($Mode -eq "malformed") {
  [Console]::Out.WriteLine("VOYAGE_VII_HANDSHAKE {bad json")
  Start-Sleep -Seconds 10
  exit 0
}

if ($Mode -eq "missing") {
  Start-Sleep -Seconds 10
  exit 0
}

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port

if ($Mode -eq "env-check" -and $env:VOYAGE_VII_SHOULD_NOT_LEAK) {
  exit 42
}

Write-Handshake $port
if ($Mode -eq "duplicate") {
  Write-Handshake $port
}

if ($Mode -eq "crash") {
  exit 1
}

if ($Mode -eq "grandchild") {
  Start-Process -WindowStyle Hidden -FilePath "pwsh.exe" -ArgumentList @("-NoProfile", "-Command", "Start-Sleep -Seconds 60") | Out-Null
}

try {
  while ($true) {
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII, $false, 1024, $true)
      $requestLine = $reader.ReadLine()
      $headers = @{}
      while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq "") { break }
        $parts = $line.Split(":", 2)
        if ($parts.Count -eq 2) {
          $headers[$parts[0].Trim().ToLowerInvariant()] = $parts[1].Trim()
        }
      }

      if ($requestLine -like "POST /api/v1/system/shutdown *") {
        $auth = $headers["authorization"]
        $token = ""
        if ($auth -like "Bearer *") {
          $token = $auth.Substring(7)
        }
        if ($Mode -eq "record-shutdown-token" -and $MarkerPath) {
          Set-Content -LiteralPath $MarkerPath -Value $token -Encoding ascii
        }
        Write-HttpResponse $stream "202 Accepted" "{`"requestId`":`"fake`",`"accepted`":true}"
        if ($Mode -eq "ignore-shutdown") {
          Start-Sleep -Seconds 60
        } elseif ($Mode -eq "exit7") {
          exit 7
        } else {
          exit 0
        }
      } else {
        Write-HttpResponse $stream "404 Not Found" "{}"
      }
    } finally {
      $client.Dispose()
    }
  }
} finally {
  $listener.Stop()
}
