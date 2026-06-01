param(
    [string]$LoadCommand = "docker compose --profile loadtest run --rm loadtest",
    [string]$ArtifactName = "load-test",
    [string]$ArtifactDir = "artifacts/pcap",
    [string]$HealthUrl = "http://localhost:8080/health",
    [int]$HealthTimeoutSeconds = 180
)

$ErrorActionPreference = "Stop"

function Invoke-DockerCompose {
    param(
        [string[]]$Arguments
    )

    & docker compose @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
    }
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

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "docker is not available on PATH."
}

if ($LoadCommand.TrimStart().StartsWith("k6") -and -not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    throw "k6 is not available on PATH. Install k6 or pass a different -LoadCommand."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$pcapPath = Join-Path $ArtifactDir "$ArtifactName.pcap"
if (Test-Path $pcapPath) {
    Remove-Item -Force $pcapPath
}

Write-Host "Starting Docker services: mysql, redis, kafka, app"
Invoke-DockerCompose -Arguments @("up", "-d", "--build", "mysql", "redis", "kafka", "app")

Write-Host "Waiting for healthy app at $HealthUrl"
Wait-ForHealth -Url $HealthUrl -TimeoutSeconds $HealthTimeoutSeconds

Write-Host "Starting packet capture service"
Invoke-DockerCompose -Arguments @("--profile", "capture", "up", "-d", "capture")

$exitCode = 0
try {
    Write-Host "Running load command: $LoadCommand"
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $LoadCommand" -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode
}
finally {
    Write-Host "Stopping packet capture service"
    Invoke-DockerCompose -Arguments @("stop", "capture")
}

if (-not (Test-Path $pcapPath)) {
    throw "PCAP file was not created at $pcapPath"
}

$pcapInfo = Get-Item $pcapPath
if ($pcapInfo.Length -lt 1024) {
    throw "PCAP file is unexpectedly small at $($pcapInfo.Length) bytes"
}

if ($exitCode -eq 99) {
    Write-Warning "k6 thresholds were crossed, but the PCAP artifact was still generated at $pcapPath"
}
elseif ($exitCode -ne 0) {
    throw "Load command exited with code $exitCode"
}

Write-Host "PCAP generated at $pcapPath ($($pcapInfo.Length) bytes)"
