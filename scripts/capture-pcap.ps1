param(
    [string]$LoadCommand = "k6 run scripts/load-test.js",
    [string]$ArtifactName = "load-test",
    [string]$ArtifactDir = "artifacts/pcap",
    [string]$HealthUrl = "http://localhost:8080/health",
    [int]$HealthTimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"

$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent()
)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an elevated PowerShell session."
}

if (-not (Get-Command pktmon -ErrorAction SilentlyContinue)) {
    throw "pktmon is not available on PATH."
}

if ($LoadCommand.TrimStart().StartsWith("k6") -and -not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    throw "k6 is not available on PATH. Install k6 or pass a different -LoadCommand."
}

function Wait-ForHealth {
    param(
        [string]$Url,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        try {
            $statusCode = & curl.exe --silent --show-error --max-time 5 --output NUL --write-out "%{http_code}" $Url
            if ($LASTEXITCODE -eq 0 -and $statusCode -match '^\d{3}$' -and [int]$statusCode -ge 200 -and [int]$statusCode -lt 300) {
                return
            }
        }
        catch {
            Start-Sleep -Seconds 2
        }
    }

    throw "Timed out waiting for $Url after $TimeoutSeconds seconds."
}

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$etlPath = Join-Path $ArtifactDir "$ArtifactName.etl"
$pcapngPath = Join-Path $ArtifactDir "$ArtifactName.pcapng"

if (Test-Path $etlPath) { Remove-Item -Force $etlPath }
if (Test-Path $pcapngPath) { Remove-Item -Force $pcapngPath }

Write-Host "Waiting for healthy app at $HealthUrl"
Wait-ForHealth -Url $HealthUrl -TimeoutSeconds $HealthTimeoutSeconds

Write-Host "Starting packet capture: $etlPath"
& pktmon reset | Out-Null
& pktmon filter add SwiftPayHttp -t TCP -p 8080 | Out-Null
& pktmon filter add SwiftPayMysql -t TCP -p 3306 | Out-Null
& pktmon filter add SwiftPayRedis -t TCP -p 6379 | Out-Null
& pktmon filter add SwiftPayKafka -t TCP -p 9092 | Out-Null
& pktmon start --capture --comp all --pkt-size 0 --file-name $etlPath | Out-Null

$exitCode = 0
try {
    Write-Host "Running load command: $LoadCommand"
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $LoadCommand" -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode
}
finally {
    Write-Host "Stopping packet capture"
    & pktmon stop | Out-Null
}

Write-Host "Converting ETL to PCAPNG: $pcapngPath"
& pktmon etl2pcap $etlPath --out $pcapngPath | Out-Null

$pcapInfo = Get-Item $pcapngPath
if ($pcapInfo.Length -lt 1024) {
    Write-Warning "Standard PCAPNG was empty or too small; regenerating with drop-only events."
    & pktmon etl2pcap $etlPath --drop-only --out $pcapngPath | Out-Null
    $pcapInfo = Get-Item $pcapngPath
}

& pktmon filter remove | Out-Null

if ($exitCode -eq 99) {
    Write-Warning "k6 thresholds were crossed, but the PCAP artifact was still generated at $pcapngPath"
}
elseif ($exitCode -ne 0) {
    throw "Load command exited with code $exitCode"
}

Write-Host "PCAP generated at $pcapngPath ($($pcapInfo.Length) bytes)"
