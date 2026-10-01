# 本地运行环境(微服务拆分版)

Windows + JDK 21 + Docker Desktop 下跑通 `nageoffer/12306` 微服务版的完整配置。

## 目录

| 文件 | 作用 |
|---|---|
| `docker-compose.yml` | MySQL / Redis / Nacos / RocketMQ / Sentinel 一键起 |
| `gen-init.ps1` | 从 `resources/` 生成 MySQL 初始化脚本 |
| `push-nacos-config.ps1` | 向 Nacos 发布 hippo4j 动态线程池配置 |
| `start-services.ps1` | 启动/停止 5 个业务服务 |
| `mysql-init/` | MySQL 首次启动自动执行(建库+建表+种子数据) |
| `rocketmq/broker.conf` | broker 配置 |

## 中间件

| 组件 | 版本 | 宿主机地址 | 账号 |
|---|---|---|---|
| MySQL | 8.0 | `127.0.0.1:13306` | root / root |
| Redis | 7 | `127.0.0.1:6379` | 密码 `123456` |
| Nacos | 2.2.3 | `127.0.0.1:8848`(gRPC 9848) | nacos / nacos |
| RocketMQ | 5.1.4 | namesrv `127.0.0.1:9876`,broker `127.0.0.1:10911` | - |
| Sentinel | 1.8.6 | `127.0.0.1:8686` | sentinel / sentinel |

数据库(ShardingSphere 分库分表):
`12306_user_0/1`、`12306_order_0/1`、`12306_pay_0/1`、`12306_ticket`
其中 `*_0` 库放 0~15 号分片表,`*_1` 库放 16~31 号。

## 服务

| 服务 | 端口 | 说明 |
|---|---|---|
| gateway-service | 9000 | 网关,profile 必须为 `dev` |
| user-service | 9001 | 用户/乘车人 |
| ticket-service | 9002 | 余票查询/购票(核心高并发) |
| order-service | 9003 | 订单 |
| pay-service | 9004 | 支付 |

## 启动

```powershell
# 1. 启动 Docker Desktop 后拉起中间件(首次会自动导入 SQL)
docker compose -f deploy\docker-compose.yml up -d

# 2. 编译并安装全部模块到本地仓库
mvn -B clean install -DskipTests -Dcheckstyle.skip=true

# 3. 发布 Nacos 配置(hippo4j 动态线程池)
.\deploy\push-nacos-config.ps1

# 4. 生成各服务 classpath(仅依赖变化后需要重跑)
.\deploy\start-services.ps1 -Prepare

# 5. 启动全部服务
.\deploy\start-services.ps1

# 停止
.\deploy\start-services.ps1 -Stop
```

日志在 `logs\<服务名>.log`,PID 在 `logs\pid\`。

## 已做的改动

1. **MySQL 端口 3306 → 13306**
   宿主机 3306 落在 Windows 保留端口段 `3217-3316`(`netsh interface ipv4 show excludedportrange protocol=tcp`),Docker 无法绑定。
   同步修改了 5 处 JDBC 配置:
   - `services/{user,order,pay}-service/src/main/resources/shardingsphere-config.yaml`
   - `services/ticket-service/src/main/resources/application.yaml`
   - `services/aggregation-service/src/main/resources/shardingsphere-config-dev.yaml`

2. **gateway-service 补 Nacos 账号**
   `services/gateway-service/src/main/resources/application.yaml` 原本缺 `username/password`,
   Nacos 开启鉴权后注册会抛 `NacosException: user not found!`,已补齐(其余 4 个服务本来就有)。

3. **gateway profile 切 `dev`**
   默认 `aggregation` 路由到单体服务,拆分版由启动脚本注入 `-Dspring.profiles.active=dev`。

## 踩坑记录

- **JDK 25 编译失败**:项目 Lombok 1.18.30 不支持 JDK 25,注解处理器静默失效,报
  "构造器无法应用/找不到符号"。换 JDK 21 即可(项目声明的是 JDK 17)。
- **`USE` 跨行导致建表全失败**:`resources/db/*.sql` 里写的是 `USE` 换行再跟库名。
  mysql CLI 的 `use` 是按行解析的客户端命令,跨行会报
  `USE must be followed by a database name`,后续建表静默跳过。
  `gen-init.ps1` 已把它压成单行 ``USE `db`;``。
- **RocketMQ broker 起不来**:镜像以 uid 3000 运行,但 `/home/rocketmq/store`、`logs`
  在镜像里不存在,Docker 新建的命名卷属主是 root → 写入被拒 → NPE 重启循环。
  compose 里对两个 RocketMQ 服务加了 `user: root`。
- **brokerIP1 必须是 127.0.0.1**:compose 只把端口发布到 loopback,若 broker 注册宿主机
  LAN IP,客户端会拿到不可达地址。
- **Sentinel 端口**:该镜像忽略 `JAVA_OPTS`,容器内固定监听 8858,compose 做 `8686:8858` 转换。
- **`mvn spring-boot:run` 不可用**:Windows `CreateProcess error=206`(命令行超 32KB),
  且插件版本会漂到 3.1.0。改用 `dependency:build-classpath` 生成 classpath,
  再以 `java @target/java-args.txt` 启动(argfile 内路径统一用正斜杠,避免反斜杠被当转义符)。
- **本地仓库有两份 settings.xml**:用户级 `~/.m2/settings.xml` 指向 `D:/.m2/repository_aliyu`
  并覆盖全局的 `D:\.m2\`。换仓库后需要重新 `mvn install`,否则子模块目录里跑 Maven
  会报 `Non-resolvable import POM: index12306-dependencies`。

## 验证

```powershell
# 网关 → Nacos → ticket-service → ShardingSphere → MySQL
curl "http://127.0.0.1:9000/api/ticket-service/station/all"
```

## 前端(未安装)

`console-vue` 是 Vue 3 + vue-cli 5,代理 `/api` 到 `http://127.0.0.1:9000`:

```powershell
cd console-vue
yarn install    # 或 npm install
yarn serve      # 默认 http://localhost:8080
```
