param(
    [string[]]$Only,
    [switch]$Stop,
    [switch]$Prepare
)

$ErrorActionPreference = "Stop"

$Root    = Split-Path -Parent $PSScriptRoot
$LogDir  = Join-Path $Root "logs"
$PidDir  = Join-Path $LogDir "pid"
$JavaHome = $env:JAVA_HOME
if (-not $JavaHome) { $JavaHome = "C:\Program Files\jdk" }
$Java = Join-Path $JavaHome "bin\java.exe"

New-Item -ItemType Directory -Force -Path $LogDir, $PidDir | Out-Null

# name, 模块目录, 主类, 端口, 额外 JVM/Spring 参数
$Services = @(
    @{ Name = "user-service";    Dir = "services\user-service";    Main = "org.opengoofy.index12306.biz.userservice.UserServiceApplication";       Port = 9001; Extra = @() },
    @{ Name = "ticket-service";  Dir = "services\ticket-service";  Main = "org.opengoofy.index12306.biz.ticketservice.TicketServiceApplication";   Port = 9002; Extra = @() },
    @{ Name = "order-service";   Dir = "services\order-service";   Main = "org.opengoofy.index12306.biz.orderservice.OrderServiceApplication";     Port = 9003; Extra = @() },
    @{ Name = "pay-service";     Dir = "services\pay-service";     Main = "org.opengoofy.index12306.biz.payservice.PayServiceApplication";         Port = 9004; Extra = @() },
    # gateway 默认 profile 是 aggregation(路由到单体服务),拆分版必须切到 dev
    @{ Name = "gateway-service"; Dir = "services\gateway-service"; Main = "org.opengoofy.index12306.biz.gatewayservice.GatewayServiceApplication"; Port = 9000; Extra = @("-Dspring.profiles.active=dev") }
)

if ($Only) { $Services = $Services | Where-Object { $Only -contains $_.Name } }

function Stop-Service($svc) {
    $pidFile = Join-Path $PidDir "$($svc.Name).pid"
    if (Test-Path $pidFile) {
        $procId = (Get-Content $pidFile -Raw).Trim()
        $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
        if ($proc) {
            # spring-boot 应用是 java 进程,直接杀进程树
            taskkill /PID $procId /T /F 2>&1 | Out-Null
            "stopped  $($svc.Name) (pid $procId)"
        } else {
            "not running: $($svc.Name)"
        }
        Remove-Item $pidFile -Force
    } else {
        "no pid file: $($svc.Name)"
    }
}

# 生成 target\cp.txt 与 java @argfile,规避 Windows CreateProcess 32KB 命令行上限
function Prepare-Service($svc) {
    $modDir   = Join-Path $Root $svc.Dir
    $cpFile   = Join-Path $modDir "target\cp.txt"
    $argFile  = Join-Path $modDir "target\java-args.txt"

    Push-Location $modDir
    try {
        & mvn -B -ntp dependency:build-classpath "-Dmdep.outputFile=$cpFile" "-Dmdep.includeScope=runtime" -q 2>&1 |
            Where-Object { $_ -match "ERROR" } | ForEach-Object { throw $_ }
    } finally { Pop-Location }

    if (-not (Test-Path $cpFile)) { throw "classpath 生成失败: $cpFile" }

    # java @argfile 中双引号内反斜杠是转义符,统一换成正斜杠
    $deps    = ([System.IO.File]::ReadAllText($cpFile)).Trim() -replace "\\", "/"
    $classes = ((Join-Path $modDir "target\classes") -replace "\\", "/")

    $lines = @(
        "-Dfile.encoding=UTF-8"
        "-Duser.timezone=Asia/Shanghai"
        "-Xms512m"
        "-Xmx1024m"
        '-cp "' + $classes + ";" + $deps + '"'
    )
    $lines += $svc.Extra

    [System.IO.File]::WriteAllText($argFile, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
    "prepared $($svc.Name)"
}

function Start-Service($svc) {
    $modDir  = Join-Path $Root $svc.Dir
    $argFile = Join-Path $modDir "target\java-args.txt"
    $log     = Join-Path $LogDir "$($svc.Name).log"

    if (-not (Test-Path $argFile)) { Prepare-Service $svc | Out-Null }

    Remove-Item $log -ErrorAction SilentlyContinue

    $proc = Start-Process -FilePath $Java `
        -ArgumentList "@`"$argFile`"", $svc.Main `
        -WorkingDirectory $modDir `
        -RedirectStandardOutput $log `
        -RedirectStandardError  (Join-Path $LogDir "$($svc.Name).err.log") `
        -PassThru -NoNewWindow

    $proc.Id | Set-Content (Join-Path $PidDir "$($svc.Name).pid") -NoNewline
    "started  $($svc.Name) pid=$($proc.Id) port=$($svc.Port)"
}

function Wait-Port($svc, [int]$TimeoutSec = 180) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $TimeoutSec) {
        $pidFile = Join-Path $PidDir "$($svc.Name).pid"
        if ((Test-Path $pidFile) -and -not (Get-Process -Id (Get-Content $pidFile -Raw).Trim() -ErrorAction SilentlyContinue)) {
            return "CRASHED"
        }
        if (Test-NetConnection -ComputerName 127.0.0.1 -Port $svc.Port -WarningAction SilentlyContinue -InformationLevel Quiet) {
            return "UP"
        }
        Start-Sleep -Seconds 3
    }
    return "TIMEOUT"
}

if ($Stop) {
    foreach ($s in $Services) { Stop-Service $s }
    return
}

if ($Prepare) {
    foreach ($s in $Services) { Prepare-Service $s }
    return
}

foreach ($s in $Services) { Stop-Service $s | Out-Null }
foreach ($s in $Services) { Start-Service $s; Start-Sleep -Seconds 2 }

""
"等待端口就绪..."
foreach ($s in $Services) {
    $r = Wait-Port $s
    "{0,-18} {1,-6} {2}" -f $s.Name, $s.Port, $r
}
