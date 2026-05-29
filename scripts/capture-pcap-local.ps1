param(
    [string]$LoadCommand = "k6 run scripts/load-test.js",
    [string]$ArtifactName = "swiftpay-250tps-1m",
    [string]$ArtifactDir = "artifacts/pcap",
    [string]$HealthUrl = "http://localhost:8080/health",
    [int]$HealthTimeoutSeconds = 120,
    [string]$CaptureFilter = "tcp port 8080 or tcp port 3306 or tcp port 6379 or tcp port 9092"
)

$ErrorActionPreference = "Stop"

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

function Find-Dumpcap {
    $candidates = @(
        "C:\Program Files\Wireshark\dumpcap.exe",
        "C:\Program Files (x86)\Wireshark\dumpcap.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    throw "dumpcap is not available. Install Wireshark and Npcap first."
}

function Find-LoopbackInterfaceId {
    param(
        [string]$DumpcapPath
    )

    $stdout = Join-Path $env:TEMP ("dumpcap-" + [guid]::NewGuid().ToString("N") + ".log")
    $stderr = Join-Path $env:TEMP ("dumpcap-" + [guid]::NewGuid().ToString("N") + ".err")

    $process = Start-Process -FilePath $DumpcapPath -ArgumentList '-D' -Wait -PassThru -NoNewWindow -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    if ($process.ExitCode -ne 0) {
        throw "dumpcap -D failed. Install Npcap and ensure capture permissions are available."
    }

    $interfaces = Get-Content $stdout
    Remove-Item -Force $stdout, $stderr -ErrorAction SilentlyContinue

    $loopbackLine = $interfaces | Where-Object {
        $_ -match 'NPF_Loopback' -or
        $_ -match 'Adapter for loopback capture' -or
        $_ -match 'Loopback'
    } | Select-Object -First 1

    if (-not $loopbackLine) {
        throw "Npcap loopback interface was not found. Install Npcap and make sure loopback capture is enabled."
    }

    if ($loopbackLine -match '^\s*(\d+)\.') {
        return [int]$Matches[1]
    }

    throw "Could not parse the loopback interface id from: $loopbackLine"
}

if ($LoadCommand.TrimStart().StartsWith("k6") -and -not (Get-Command k6 -ErrorAction SilentlyContinue)) {
    throw "k6 is not available on PATH. Install k6 or pass a different -LoadCommand."
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

New-Item -ItemType Directory -Force -Path $ArtifactDir | Out-Null

$dumpcapPath = Find-Dumpcap
$loopbackInterfaceId = Find-LoopbackInterfaceId -DumpcapPath $dumpcapPath

$pcapPath = Join-Path $ArtifactDir "$ArtifactName.pcapng"
if (Test-Path $pcapPath) {
    Remove-Item -Force $pcapPath
}

Write-Host "Waiting for healthy app at $HealthUrl"
Wait-ForHealth -Url $HealthUrl -TimeoutSeconds $HealthTimeoutSeconds

Write-Host "Starting packet capture on loopback interface $loopbackInterfaceId with filter: $CaptureFilter"
$captureProcess = Start-Process `
    -FilePath $dumpcapPath `
    -ArgumentList @(
        "-q",
        "-i", $loopbackInterfaceId,
        "-f", $CaptureFilter,
        "-w", $pcapPath
    ) `
    -PassThru `
    -WindowStyle Hidden

$exitCode = 0
try {
    Write-Host "Running load command: $LoadCommand"
    $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $LoadCommand" -Wait -PassThru -NoNewWindow
    $exitCode = $process.ExitCode
}
finally {
    Write-Host "Stopping packet capture"
    if ($captureProcess -and -not $captureProcess.HasExited) {
        Stop-Process -Id $captureProcess.Id -Force
        Start-Sleep -Seconds 2
    }
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
