$ErrorActionPreference = "Stop"

$root   = Split-Path -Parent $PSScriptRoot
$src    = Join-Path $root "resources"
$dest   = Join-Path $PSScriptRoot "mysql-init"

$map = @(
    @{ Out = "10-schema-order.sql";  In = "db\12306-springcloud-order.sql"  },
    @{ Out = "11-schema-pay.sql";    In = "db\12306-springcloud-pay.sql"    },
    @{ Out = "12-schema-ticket.sql"; In = "db\12306-springcloud-ticket.sql" },
    @{ Out = "13-schema-user.sql";   In = "db\12306-springcloud-user.sql"   },
    @{ Out = "20-data-ticket.sql";   In = "data\12306-springcloud-ticket.sql" },
    @{ Out = "21-data-user.sql";     In = "data\12306-springcloud-user.sql"   }
)

New-Item -ItemType Directory -Force -Path $dest | Out-Null

foreach ($m in $map) {
    $inPath  = Join-Path $src  $m.In
    $outPath = Join-Path $dest $m.Out

    if (-not (Test-Path $inPath)) { throw "missing source: $inPath" }

    $body = [System.IO.File]::ReadAllText($inPath, [System.Text.UTF8Encoding]::new($false))

    # 原始 SQL 形如 "USE\r\n12306_user_0;",mysql CLI 的 use 是按行解析的客户端命令,
    # 跨行会报 "USE must be followed by a database name" 并导致后续建表全部失败。
    # 统一压成单行 "USE `db`;",并把 CRLF 归一为 LF。
    $body = $body -replace "`r`n", "`n"
    $body = [regex]::Replace($body, "(?im)^[ \t]*USE[ \t]*\n[ \t]*``?([A-Za-z0-9_]+)``?[ \t]*;", 'USE `$1`;')

    $head = "SET NAMES utf8mb4;`nSET FOREIGN_KEY_CHECKS = 0;`nSET SQL_MODE = 'NO_AUTO_VALUE_ON_ZERO';`n`n"
    $tail = "`n`nSET FOREIGN_KEY_CHECKS = 1;`n"

    [System.IO.File]::WriteAllText($outPath, $head + $body + $tail, [System.Text.UTF8Encoding]::new($false))

    "{0,-24} <- {1,-38} {2,8:N0} KB" -f $m.Out, $m.In, ((Get-Item $outPath).Length / 1KB)
}

""
"regenerate broker.conf brokerIP1..."
# 业务服务全部跑在宿主机上,且 compose 只把端口发布到 127.0.0.1,
# 因此 broker 必须向 namesrv 注册 127.0.0.1,宿主机客户端才能连回。
$ip = "127.0.0.1"

$brokerConf = Join-Path $PSScriptRoot "rocketmq\broker.conf"
$c = [System.IO.File]::ReadAllText($brokerConf)
$c = [regex]::Replace($c, "brokerIP1\s*=\s*[0-9.]+", "brokerIP1 = $ip")
[System.IO.File]::WriteAllText($brokerConf, $c, [System.Text.UTF8Encoding]::new($false))
"brokerIP1 = $ip"
