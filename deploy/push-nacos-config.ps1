$ErrorActionPreference = "Stop"

$NacosAddr = "http://127.0.0.1:8848/nacos"
$User      = "nacos"
$Pass      = "nacos"

# ticket-service / aggregation-service 的 @EnableDynamicThreadPool 以 Nacos 为配置中心,
# data-id 固定为 hippo4j-nacos.yaml,缺失时线程池参数无法动态刷新。
$hippo4j = @'
executors:
  - thread-pool-id: 'select-seat-thread-pool-executor'
    alarm: false
    allow-core-thread-time-out: true
    blocking-queue: SynchronousQueue
    core-pool-size: 24
    maximum-pool-size: 36
    keep-alive-time: 60
    rejected-handler: CallerRunsPolicy
'@

$configs = @(
    @{ dataId = "hippo4j-nacos.yaml"; group = "DEFAULT_GROUP"; type = "yaml"; content = $hippo4j }
)

$login = Invoke-RestMethod -Method Post -Uri "$NacosAddr/v1/auth/login" -Body @{ username = $User; password = $Pass }
$token = $login.accessToken

foreach ($c in $configs) {
    $body = @{
        tenant      = ""
        dataId      = $c.dataId
        group       = $c.group
        type        = $c.type
        content     = $c.content
        accessToken = $token
    }
    $r = Invoke-RestMethod -Method Post -Uri "$NacosAddr/v1/cs/configs" -Body $body
    if ("$r" -eq "True" -or "$r" -eq "true") {
        "published: $($c.group)/$($c.dataId)"
    } else {
        "FAILED:    $($c.group)/$($c.dataId) -> $r"
    }
}

""
"当前 Nacos 配置列表:"
$list = Invoke-RestMethod -Uri "$NacosAddr/v1/cs/configs?search=accurate&dataId=&group=&pageNo=1&pageSize=20&accessToken=$token"
$list.pageItems | ForEach-Object { "  {0,-24} {1,-16} {2}" -f $_.dataId, $_.group, $_.type }
