param(
    [string]$DataDir = "artifacts/mysql-data/local",
    [int]$Port = 3306,
    [string]$AppUser = "swiftpay",
    [string]$AppPassword = "swiftpay",
    [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = "Stop"

function Find-MySqlInstallDir {
    $candidates = @(
        "C:\Program Files\MySQL\MySQL Server 8.0",
        "C:\Program Files (x86)\MySQL\MySQL Server 8.0"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path (Join-Path $candidate "bin\mysqld.exe")) {
            return $candidate
        }
    }

    throw "MySQL Server 8.0 is not installed in the expected location."
}

function Wait-ForPort {
    param(
        [int]$Port,
        [int]$TimeoutSeconds,
        [int]$ProcessId
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $listener = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalPort -eq $Port } |
            Select-Object -First 1
        if ($listener) {
            return
        }

        if ($ProcessId -and -not (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue)) {
            throw "MySQL exited before opening port 127.0.0.1:$Port."
        }

        Start-Sleep -Milliseconds 500
    }

    throw "Timed out waiting for MySQL to listen on 127.0.0.1:$Port."
}

function Invoke-MySql {
    param(
        [string]$MysqlExe,
        [int]$Port,
        [string]$Sql,
        [string]$Password = $null
    )

    $arguments = @(
        "--protocol=tcp",
        "-h", "127.0.0.1",
        "-P", $Port.ToString(),
        "-u", "root"
    )

    if ($Password) {
        $arguments += "-p$Password"
    }

    $arguments += @("-e", $Sql)

    & $MysqlExe @arguments
    return ($LASTEXITCODE -eq 0)
}

function Write-MySqlIni {
    param(
        [string]$InstallDir,
        [string]$ResolvedDataDir,
        [string]$IniPath,
        [int]$Port
    )

    $basedirIni = $InstallDir.Replace('\', '/')
    $datadirIni = $ResolvedDataDir.Replace('\', '/')
    @"
[mysqld]
basedir=$basedirIni
datadir=$datadirIni
port=$Port
bind-address=127.0.0.1
pid-file=$datadirIni/mysqld.pid
log-error=$datadirIni/mysql.err
skip-log-bin
"@ | Set-Content -Path $IniPath -Encoding ASCII
}

function Initialize-MySqlDataDir {
    param(
        [string]$MysqlExe,
        [string]$InstallDir,
        [string]$ResolvedDataDir
    )

    Write-Host "Initializing MySQL data directory at $ResolvedDataDir"
    & $MysqlExe --no-defaults --initialize-insecure --basedir="$InstallDir" --datadir="$ResolvedDataDir" --console
    if ($LASTEXITCODE -ne 0) {
        throw "MySQL initialization failed with exit code $LASTEXITCODE."
    }
}

function Start-MySqlProcess {
    param(
        [string]$MySqlExe,
        [string]$IniPath
    )

    Write-Host "Starting MySQL with config $IniPath"
    return Start-Process -FilePath $MySqlExe -ArgumentList @("--defaults-file=`"$IniPath`"", "--console") -PassThru -WindowStyle Hidden
}

function Configure-MySqlAccounts {
    param(
        [string]$MysqlExe,
        [int]$Port,
        [string]$AppUser,
        [string]$AppPassword
    )

    $sql = @"
CREATE DATABASE IF NOT EXISTS swiftpay;
CREATE USER IF NOT EXISTS '$AppUser'@'localhost' IDENTIFIED WITH mysql_native_password BY '$AppPassword';
CREATE USER IF NOT EXISTS '$AppUser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$AppPassword';
GRANT ALL PRIVILEGES ON swiftpay.* TO '$AppUser'@'localhost';
GRANT ALL PRIVILEGES ON swiftpay.* TO '$AppUser'@'127.0.0.1';
FLUSH PRIVILEGES;
"@

    if (-not (Invoke-MySql -MysqlExe $MysqlExe -Port $Port -Sql $sql)) {
        return $false
    }

    $appGrants = & $MysqlExe --protocol=tcp -h 127.0.0.1 -P $Port -u $AppUser -p$AppPassword -Nse "SHOW GRANTS FOR CURRENT_USER();"
    if ($LASTEXITCODE -ne 0 -or ($appGrants -notmatch "GRANT ALL PRIVILEGES ON ``swiftpay``\.\* TO ``$AppUser``@``127\.0\.0\.1``")) {
        return $false
    }

    return $true
}

function Reset-MySqlDataDir {
    param([string]$ResolvedDataDir)

    if (Test-Path $ResolvedDataDir) {
        Write-Host "Removing stale MySQL data directory at $ResolvedDataDir"
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            try {
                Remove-Item -LiteralPath $ResolvedDataDir -Recurse -Force -ErrorAction Stop
                break
            }
            catch {
                if ($attempt -eq 5) {
                    throw
                }
                Start-Sleep -Seconds 1
            }
        }
    }
    New-Item -ItemType Directory -Force -Path $ResolvedDataDir | Out-Null
}

function Stop-MySqlProcess {
    param([int]$ProcessId)

    if (-not $ProcessId) {
        return
    }

    Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
    try {
        Wait-Process -Id $ProcessId -Timeout 15 -ErrorAction Stop
    }
    catch {
    }
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$installDir = Find-MySqlInstallDir
$mysqldExe = Join-Path $installDir "bin\mysqld.exe"
$mysqlExe = Join-Path $installDir "bin\mysql.exe"

if (-not (Test-Path $mysqlExe)) {
    throw "mysql.exe was not found next to mysqld.exe."
}

$resolvedDataDir = if ([System.IO.Path]::IsPathRooted($DataDir)) {
    $DataDir
}
else {
    Join-Path $repoRoot $DataDir
}
$resolvedDataDir = [System.IO.Path]::GetFullPath($resolvedDataDir)
New-Item -ItemType Directory -Force -Path $resolvedDataDir | Out-Null

$iniPath = Join-Path $resolvedDataDir "swiftpay-local-my.ini"
$readyMarker = Join-Path $resolvedDataDir ".swiftpay-local.ready"
$logPath = Join-Path $resolvedDataDir "mysql.err"
$initialized = Test-Path (Join-Path $resolvedDataDir "mysql")
$serverProcessId = $null

$listener = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -eq $Port } |
    Select-Object -First 1

if ($listener -and -not (Test-Path $readyMarker)) {
    Write-Host "MySQL is already listening on 127.0.0.1:$Port. Skipping local bootstrap because this does not look like the repo-managed instance."
    return
}

if (-not $listener) {
    if (-not $initialized) {
        Initialize-MySqlDataDir -MysqlExe $mysqldExe -InstallDir $installDir -ResolvedDataDir $resolvedDataDir
    }

    Write-MySqlIni -InstallDir $installDir -ResolvedDataDir $resolvedDataDir -IniPath $iniPath -Port $Port

    $process = Start-MySqlProcess -MySqlExe $mysqldExe -IniPath $iniPath
    $serverProcessId = $process.Id
    try {
        Wait-ForPort -Port $Port -TimeoutSeconds $TimeoutSeconds -ProcessId $process.Id
    }
    catch {
        if (Test-Path $logPath) {
            Write-Host "MySQL error log:"
            Get-Content $logPath -Tail 40
        }
        throw
    }
}
else {
    Write-Host "MySQL is already listening on 127.0.0.1:$Port"
    $serverProcessId = $listener.OwningProcess
}

if (-not (Configure-MySqlAccounts -MysqlExe $mysqlExe -Port $Port -AppUser $AppUser -AppPassword $AppPassword)) {
    Write-Host "MySQL accounts were not provisioned cleanly. Rebuilding the local data directory."
    Stop-MySqlProcess -ProcessId $serverProcessId

    Reset-MySqlDataDir -ResolvedDataDir $resolvedDataDir
    Initialize-MySqlDataDir -MysqlExe $mysqldExe -InstallDir $installDir -ResolvedDataDir $resolvedDataDir
    Write-MySqlIni -InstallDir $installDir -ResolvedDataDir $resolvedDataDir -IniPath $iniPath -Port $Port
    $process = Start-MySqlProcess -MySqlExe $mysqldExe -IniPath $iniPath
    $serverProcessId = $process.Id
    Wait-ForPort -Port $Port -TimeoutSeconds $TimeoutSeconds -ProcessId $process.Id

    if (-not (Configure-MySqlAccounts -MysqlExe $mysqlExe -Port $Port -AppUser $AppUser -AppPassword $AppPassword)) {
        throw "Unable to configure MySQL on 127.0.0.1:$Port."
    }
}

New-Item -ItemType File -Force -Path $readyMarker | Out-Null

Write-Host "MySQL is ready on 127.0.0.1:$Port"
Write-Host "Spring Boot and Workbench credentials: $AppUser / $AppPassword"
