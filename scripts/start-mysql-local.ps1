param(
    [string]$DataDir = "artifacts/mysql-data/local",
    [int]$Port = 3306,
    [string]$RootPassword = "Bhanu@454",
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

$listener = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPort -eq $Port } |
    Select-Object -First 1

if ($listener -and -not (Test-Path $readyMarker)) {
    Write-Host "MySQL is already listening on 127.0.0.1:$Port. Skipping local bootstrap because this does not look like the repo-managed instance."
    return
}

if (-not $listener) {
    if (-not $initialized) {
        Write-Host "Initializing MySQL data directory at $resolvedDataDir"
        & $mysqldExe --no-defaults --initialize-insecure --basedir="$installDir" --datadir="$resolvedDataDir" --console
        if ($LASTEXITCODE -ne 0) {
            throw "MySQL initialization failed with exit code $LASTEXITCODE."
        }
    }

    $basedirIni = $installDir.Replace('\', '/')
    $datadirIni = $resolvedDataDir.Replace('\', '/')
    @"
[mysqld]
basedir=$basedirIni
datadir=$datadirIni
port=$Port
bind-address=127.0.0.1
pid-file=$datadirIni/mysqld.pid
log-error=$datadirIni/mysql.err
skip-log-bin
"@ | Set-Content -Path $iniPath -Encoding ASCII

    Write-Host "Starting MySQL on 127.0.0.1:$Port"
    $process = Start-Process -FilePath $mysqldExe -ArgumentList @("--defaults-file=`"$iniPath`"", "--console") -PassThru -WindowStyle Hidden
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
}

$sql = @"
CREATE DATABASE IF NOT EXISTS swiftpay;
CREATE USER IF NOT EXISTS 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$RootPassword';
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$RootPassword';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$RootPassword';
ALTER USER 'root'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$RootPassword';
GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
CREATE USER IF NOT EXISTS '$AppUser'@'localhost' IDENTIFIED WITH mysql_native_password BY '$AppPassword';
CREATE USER IF NOT EXISTS '$AppUser'@'127.0.0.1' IDENTIFIED WITH mysql_native_password BY '$AppPassword';
GRANT ALL PRIVILEGES ON swiftpay.* TO '$AppUser'@'localhost';
GRANT ALL PRIVILEGES ON swiftpay.* TO '$AppUser'@'127.0.0.1';
FLUSH PRIVILEGES;
"@

if (-not (Invoke-MySql -MysqlExe $mysqlExe -Port $Port -Sql $sql)) {
    if (-not (Invoke-MySql -MysqlExe $mysqlExe -Port $Port -Sql $sql -Password $RootPassword)) {
        throw "Unable to configure MySQL on 127.0.0.1:$Port."
    }
}

$adminGrants = & $mysqlExe --protocol=tcp -h 127.0.0.1 -P $Port -u root -p$RootPassword -Nse "SHOW GRANTS FOR CURRENT_USER();"
if ($LASTEXITCODE -ne 0 -or ($adminGrants -notmatch "GRANT ALL PRIVILEGES ON \*\.\* TO ``root``@``127\.0\.0\.1`` WITH GRANT OPTION")) {
    throw "MySQL root admin grants were not verified for 127.0.0.1:$Port. If this data directory was bootstrapped before the latest script update, remove '$resolvedDataDir' and rerun scripts/start-mysql-local.ps1."
}

New-Item -ItemType File -Force -Path $readyMarker | Out-Null

Write-Host "MySQL is ready on 127.0.0.1:$Port"
Write-Host "Spring Boot default credentials: $AppUser / $AppPassword"
Write-Host "Administrative root credentials also available: root / $RootPassword"
