param(
    [string]$LoadCommand = "k6 run scripts/load-test.js",
    [string]$ArtifactName = "swiftpay-250tps-1m",
    [string]$ArtifactDir = "artifacts/pcap"
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

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$etlPath = Join-Path $ArtifactDir "$ArtifactName.etl"
$pcapngPath = Join-Path $ArtifactDir "$ArtifactName.pcapng"

if (Test-Path $etlPath) { Remove-Item -Force $etlPath }
if (Test-Path $pcapngPath) { Remove-Item -Force $pcapngPath }

Write-Host "Starting packet capture: $etlPath"
& pktmon reset | Out-Null
& pktmon start --capture --comp nics --pkt-size 0 --file-name $etlPath | Out-Null

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

if ($exitCode -ne 0) {
    throw "Load command exited with code $exitCode"
}

Write-Host "PCAP generated at $pcapngPath"
