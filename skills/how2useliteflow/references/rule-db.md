# Rule-DB 统一规则数据库（v2.16.1 新增）

> 对齐版本：**LiteFlow v2.16.1（tag 已发布，`cac48e201`，2026-07-27）**；内容已对齐 `84539caba` 澄清后的 `docs/liteflow-rule-db-guide.md`（last-good 语义、撞 id 启动报错等均为澄清后口径）+ `liteflow-rule-db/` 模块源码。源码仓 HEAD 已为修复版 2.16.1.1（多出 `liteflow-script-javax-pro` 的 ThreadLocal 泄漏修复 #IK6XVN）；另有补丁版 2.16.0.1（修复 WHEN 并行子 chain 的 ConcurrentModificationException #IDB16L，v2.16.1 已含）。
> 这是与 `rule-sources.md` 里 6 个传统规则插件运行模型不同的全新模式。传统插件仍可使用，但 `rule-source` 与 Rule-DB 互斥；同一后端迁移时必须移除旧插件，尤其不要同时引入两个 Nacos 插件。

## 目录

- §1–3：定位、七后端选型与快速上手。
- §4–6：完整配置、统一发布 API 与存储结构。
- §7–9：一致性、缓存热路径与故障语义。
- §10–12：限制、手改存储规范与可观测性。
- §13–14：源码索引与传统插件迁移。

## 1. 它是什么、解决什么

**Rule-DB 模式让规则和脚本真正以 SQL / PostgreSQL / MongoDB / Redis / ZooKeeper / etcd / Nacos 为权威源，JVM 只保留轻量索引 + 有界缓存。**

老的 6 个规则插件（`liteflow-rule-sql/redis/zk/nacos/etcd/apollo`）本质是「启动时全量读出 → 拼成一个大 XML → 全量常驻各节点 JVM 堆」，存储只是启动数据源。Rule-DB 解决两个本质痛点：

| 痛点（老插件） | Rule-DB 的做法 |
|---|---|
| 多节点无一致性保证：刷新靠各自轮询/通知，通知丢失无兜底 | 存储是权威源；「变更通知 + 周期对账」两条腿，**最终收敛、秒级窗口** |
| 规则/脚本全量常驻 JVM 堆，规则总量推高内存 | EL 文本/脚本源码/编译产物进 **Caffeine 有界缓存**（按访问热度淘汰）；JVM 常驻规则清单、影子 Chain/Node 与状态索引（条目随规则总量线性增长但单条极小）——正文与编译产物的常驻规模由缓存容量封顶 |

一句话划界：**老 6 个插件 = 启动一次性灌库，之后各节点各跑各的；Rule-DB = 存储永远是权威，JVM 只缓存热规则，所有节点最终一致。**

**影子状态（shadow）**：一个 chain 只注册了 chainId、没有 EL、未编译；一个脚本 Node 只登记元数据（type/language/name）、没有源码。索引常驻、内容按需懒加载——执行到它时才回源拉取并编译。

## 2. 模块与后端选型

根级聚合模块 `liteflow-rule-db` 包含 7 个后端插件 + 独立的统一发布 API：

| 插件 | 变更通知腿 | 发布原子性 | 说明 |
|---|---|---|---|
| `liteflow-rule-db-sql` | seq 轮询（默认 3s） | 单事务 + `change_lock` 顺序锁 | MySQL / MariaDB；H2 仅测试；可复用 `DataSource` |
| `liteflow-rule-db-postgresql` | seq 轮询（默认 3s） | PostgreSQL 单事务 + `change_lock` 顺序锁 | 独立 DDL 与 Publisher，不走通用 SQL 插件 |
| `liteflow-rule-db-mongodb` | seq 轮询（默认 3s） | 多文档事务 | 只支持副本集／分片集群，不支持 standalone |
| `liteflow-rule-db-redis` | seq 轮询（默认 3s），**无 pub/sub** | Lua 多键原子发布 | Cluster 用 `key-hash-tag` 固定到同一 slot |
| `liteflow-rule-db-zk` | CuratorCache watch | 一个 multi-op 写 meta + content | zxid 作变更序号；单条内容发布前按 960KB 预检 |
| `liteflow-rule-db-etcd` | revision watch | 一个 Txn 写 meta + content | 支持 TLS / mTLS；compaction 后全量对账续订 |
| `liteflow-rule-db-nacos` | Listener | CAS 整体替换 Catalog | 要求 Nacos Server 2.x+；单应用一条 Catalog |

- 七者都叠加**周期全量对账**（默认 60s）作为最终兜底。
- **同一时刻 classpath 只能有一个 Rule-DB 插件**，检测到多个直接启动报错。
- v1 暂无 Apollo 的 Rule-DB 实现（`RuleRepository` SPI 已在 core 就位，可自扩展）。

## 3. 快速上手

### 3.1 依赖

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-spring-boot-starter</artifactId>
    <version>2.16.1</version>
</dependency>
<!-- 七选一 -->
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-rule-db-sql</artifactId>
    <!-- 也可选 -postgresql / -mongodb / -redis / -zk / -etcd / -nacos -->
    <version>2.16.1</version>
</dependency>
```

Spring Boot 4 项目 starter 换成 `liteflow-spring-boot4-starter`；Solon 用 `liteflow-solon-plugin`（支持 rule-db 配置绑定，但不携带 Spring 风格 IDE 元数据）。SQL 模式数据库驱动用户自带。

**发布脚本时，执行应用还必须自行引入对应语言的脚本插件**：例如脚本 `language("groovy")` 需要 `com.yomahub:liteflow-script-groovy:2.16.1`（其他语言同理）。Rule-DB 后端模块和 starter 都不会自动引入任何脚本语言实现；Publisher 只保存源码与语言标识、不编译不校验，缺插件时到节点首次加载该脚本才失败。只发布普通 chain 时不需要脚本插件。

### 3.2 配置（各后端最省姿势）

**SQL**——姿势 A：容器已有 `DataSource` bean → 引依赖零配置，自动复用；`application-name` 自动取 `spring.application.name`。姿势 B：规则库独立，三行起步：

```properties
liteflow.rule-db.sql.url=jdbc:mysql://host:3306/liteflow_rules
liteflow.rule-db.sql.username=root
liteflow.rule-db.sql.password=your-password
# driver-class-name 留空从 url 推断；application-name 留空取 spring.application.name
```

姿势 C：默认 `auto-init-table=false` 需自建四张表（含 `change_lock`；缺表启动报错并附完整 DDL）；或开 `liteflow.rule-db.sql.auto-init-table=true` 启动时 `CREATE TABLE IF NOT EXISTS`。

**Redis**——姿势 A：容器已有 `RedissonClient` bean → 零配置自动复用。姿势 B 一行起步：

```properties
liteflow.rule-db.redis.address=redis://127.0.0.1:6379
# 多地址逗号分隔；哨兵模式再加 master-name
# Cluster 模式还必须配置 liteflow.rule-db.redis.key-hash-tag=liteflow
```

Redis 无需建表，键结构首次发布自动创建。

**ZooKeeper**：

```properties
liteflow.rule-db.zk.connect-string=127.0.0.1:2181
# root-path 默认 /liteflow；session-timeout 默认 60000ms
```

**etcd**：

```properties
liteflow.rule-db.etcd.endpoints=http://127.0.0.1:2379
# root-path 默认 /liteflow；user/password 可选
```

**PostgreSQL / MongoDB / Nacos**：

```properties
# PostgreSQL：可改为复用容器 DataSource
liteflow.rule-db.postgresql.url=jdbc:postgresql://127.0.0.1:5432/liteflow
liteflow.rule-db.postgresql.username=postgres
liteflow.rule-db.postgresql.password=your-password

# MongoDB：必须是副本集或分片集群；也可复用 MongoClient bean
liteflow.rule-db.mongodb.uri=mongodb://127.0.0.1:27017/?replicaSet=rs0
liteflow.rule-db.mongodb.database=liteflow

# Nacos：Server 2.x+；namespace 填 ID，不是显示名称
liteflow.rule-db.nacos.server-addr=127.0.0.1:8848
```

### 3.3 发布第一条规则

发布走统一 API `RulePublisherFactory` + `SqlPublisherConfig`（`RulePublisher` 实现 `AutoCloseable`，推荐 try-with-resources）：

```java
try (RulePublisher publisher = RulePublisherFactory.create(
        SqlPublisherConfig.builder()
                .applicationName("your-app")   // 必须等于执行侧最终解析出的 rule-db.application-name
                .url("jdbc:mysql://host:3306/liteflow_rules")
                .username("root").password("your-password")
                .build())) {
    // expectedVersion(0L)：仅当不存在时创建；并发首发同一 id 时多余请求被明确拒绝
    long version = publisher.publishChain(PublishChainRequest.builder()
            .chainId("orderChain")
            .el("THEN(a, b, IF(c, d, e))")
            .expectedVersion(0L)
            .build()).getVersion();

    publisher.publishScript(PublishScriptRequest.builder()
            .nodeId("s1").type("script")       // 对齐 NodeTypeEnum：script/boolean_script/switch_script/for_script
            .language("groovy")                 // 空则用全局默认；执行应用须自行引入 liteflow-script-groovy
            .script("def a = 1; return a").build());

    publisher.removeChain(RemoveRuleRequest.builder().targetId("orderChain").build());
    publisher.removeScript(RemoveRuleRequest.builder().targetId("s1").build());
}
```

注意：**先发脚本、再发引用它的 chain**（反过来，别的节点可能在收敛窗口内拉到新 chain 却找不到脚本，编译瞬时失败）。

> **SQL 兼容门面（2.16.1 新代码不推荐）**：SQL 模块仍保留 `com.yomahub.liteflow.repository.sql.SqlRulePublisher`（无参构造从全局 `LiteflowConfig` 取配置；`publishChain(chainId, el)` UPSERT 语义返回新版本号，`publishScript` 传 `ScriptRecord`）。下面代码只用于识别和迁移旧调用，不建议新写：
>
> ```java
> SqlRulePublisher publisher = new SqlRulePublisher();
> long v = publisher.publishChain("orderChain", "THEN(a, b)");
> publisher.publishScript(scriptRecord);   // 传 ScriptRecord
> ```
>
> 它不支持 route、namespace、`expectedVersion`，也不走统一 Publisher 的 `change_lock` 顺序锁协议，不能作为多节点或并发发布场景的生产写入入口；迁移时把连接参数放进 `SqlPublisherConfig`、`ScriptRecord` 转成 `PublishScriptRequest`。非 Spring 环境用无参构造需先初始化好全局 `LiteflowConfig` 的 `ruleDb` 配置，否则 NPE / `ConfigErrorException`。

**PostgreSQL / MongoDB / Redis / ZooKeeper / etcd / Nacos 没有简化门面**，统一走 §5 发布 API。

### 3.4 执行

应用侧 API 完全不变：`flowExecutor.execute2Resp("orderChain", param, XxxContext.class)`。首次执行回源拉取 EL 并编译；命中缓存后热路径**零远程调用**。EL 里引用的 `a`/`b`/`c` 仍是应用里已注册的 Java 组件——Rule-DB 只纳管 EL 和脚本，Java 组件照旧随应用部署。

## 4. 配置参考（`liteflow.rule-db.*`）

全部绑定到 `com.yomahub.liteflow.property.RuleDbConfig`（core 内，`LiteflowConfig.ruleDb` 字段），嵌套结构：通用项 + `cache.*` + `sync.*` + 各后端专属项。

### 通用（七后端共用）

| 配置项 | 默认 | 说明 |
|---|---|---|
| `rule-db.enabled` | `true` | 引入依赖即激活；逃生开关，`false` 退回非 Rule-DB 行为 |
| `rule-db.application-name` | 仅两个 Spring Boot starter 在为空时回落 `spring.application.name`；**Solon / 非 Spring 无此回落，须显式配置**；都没有值时回落 `default` | **多应用共库的隔离维度**：同一应用的多个实例必须用**同一个**值（共享同一套规则），共库的不同应用必须**不同**，否则互相读写对方规则。发布侧 `applicationName(...)` 必须与执行侧最终解析值完全一致，否则发布成功但应用永远看不到 |
| `rule-db.cache.capacity` | `500` | Caffeine 有界缓存容量（按 chain 条数），超出按访问热度淘汰退回影子；脚本随 chain 引用计数联动淘汰 |
| `rule-db.cache.preload-chain-ids` | 空 | 启动预热 chain id 列表（逗号分隔），抹平冷启动回源尖刺；失败只 warn 不阻断 |
| `rule-db.sync.poll-seconds` | `3` | 变更序号轮询周期，**仅 SQL/PostgreSQL/MongoDB/Redis 生效**；ZooKeeper/etcd/Nacos 使用监听 |
| `rule-db.sync.reconcile-seconds` | `60` | 周期全量对账（索引与缓存 diff），收敛的最终兜底 |
| `rule-db.sync.fetch-retry-times` | `3` | 回源拉取失败重试次数 |

### SQL 专属（`rule-db.sql.*`）

| 配置项 | 默认 | 说明 |
|---|---|---|
| `url` / `username` / `password` | — | 不配 `url` 则自动查找容器 `DataSource` bean 复用 |
| `driver-class-name` | 从 url 推断 | 留空即可 |
| `datasource-bean-name` | 自动查找 | 多 DataSource 场景指定复用哪个 bean |
| `table-prefix` | `lf_` | 只允许 ASCII 字母/数字/下划线，最长 54 字符；字段名固定不可配 |
| `auto-init-table` | `false` | `true` 则启动时建表；按数据库产品选 MySQL/MariaDB 或 H2 DDL |
| `change-log-batch-size` | `1000` | 每次轮询最多读取的变更日志条数，必须 > 0 |

> 生产建议用容器 DataSource（连接池）：走 `url` 直连是 `DriverManager` 裸连接、无池化，仅适合开发/测试。MySQL/MariaDB DDL 显式 `utf8mb4`。PostgreSQL 必须使用独立的 `liteflow-rule-db-postgresql`；Oracle、SQL Server 不在支持矩阵。

### PostgreSQL / MongoDB 专属

| 配置项 | 默认 | 说明 |
|---|---|---|
| `postgresql.url` / `username` / `password` | — | 不配 URL 则复用 `DataSource`；`driver-class-name` 通常为 `org.postgresql.Driver` |
| `postgresql.datasource-bean-name` | 自动查找 | 多数据源时指定 bean |
| `postgresql.table-prefix` / `auto-init-table` | `lf_` / `false` | 独立 PostgreSQL DDL；前缀最长 52 字符 |
| `postgresql.change-log-batch-size` | `1000` | 单批变更日志上限 |
| `mongodb.uri` | — | 不配则复用 `MongoClient`；必须连接副本集或分片集群 |
| `mongodb.database` / `collection-prefix` | `liteflow` / `lf_` | 数据库与 Collection 前缀 |
| `mongodb.mongo-client-bean-name` | 自动查找 | 多客户端时指定 bean |
| `mongodb.change-log-batch-size` | `1000` | 单批变更日志文档上限 |

### Redis 专属（`rule-db.redis.*`）

| 配置项 | 默认 | 说明 |
|---|---|---|
| `address` | — | 单机/哨兵/集群统一入口，多地址逗号分隔 |
| `master-name` | — | **配置即哨兵模式**；不配按地址数自动推断单机/集群 |
| `username` / `password` | — | Redis 6+ ACL / 口令，可空 |
| `database` | `0` | 逻辑库 |
| `key-prefix` | `lf` | 规则落在 `{prefix}:{app}:...` 键下 |
| `key-hash-tag` | — | Cluster 模式必填；让 Lua 涉及的所有键落在同一 slot，缺失时 fail-fast |
| `redisson-bean-name` | 自动查找 | 容器有 RedissonClient 时复用，鉴权在该 bean 上配 |

### ZooKeeper（`rule-db.zk.*`）与 etcd（`rule-db.etcd.*`）

| 配置项 | 默认 | 说明 |
|---|---|---|
| `zk.connect-string` | — | 多地址逗号分隔 |
| `zk.root-path` | `/liteflow` | 规则挂在 `{root}/{app}/...` 下 |
| `zk.session-timeout` | `60000` | 毫秒 |
| `zk.curator-bean-name` | — | 复用容器 `CuratorFramework` 的**唯一方式**（zk **不做按类型自动查找**）；配置后 `connect-string`/`session-timeout`/`username`/`password` 不再生效，bean 不存在启动抛 `ConfigErrorException` |
| `etcd.endpoints` | — | 逗号分隔 |
| `etcd.root-path` | `/liteflow` | — |
| `etcd.user` / `etcd.password` | — | 可选鉴权 |
| `etcd.client-bean-name` | — | 复用容器 `io.etcd.jetcd.Client` 的**唯一方式**（etcd 同样**不做按类型自动查找**）；配置后连接/认证/TLS 类配置全部不生效，bean 不存在启动抛 `ConfigErrorException` |

etcd 还支持 `ca-certificate`、`client-certificate` + `client-key`、`authority`、连接超时与 keepalive 配置；证书配对、endpoint scheme 或数值非法时启动 fail-fast。ZooKeeper 还支持成对的 digest `username/password`；编码后的单条内容超过 960KB 会在发布前被拒绝。**注意 zk / etcd 不像 SQL/Redis/MongoDB/Nacos 那样按类型自动查找容器客户端**——容器里已有 `CuratorFramework` / jetcd `Client` 却不配 bean 名，不会复用（按自建连接走，或连接参数缺失时报错）。

### Nacos 专属（`rule-db.nacos.*`）

| 配置项 | 默认 | 说明 |
|---|---|---|
| `server-addr` | — | Nacos Server 2.x+；不配则复用容器 `ConfigService` |
| `namespace` | public | 填 namespace ID，不填显示名称 |
| `group` | `LITEFLOW_RULE_DB` | Catalog group |
| `data-id-prefix` | `liteflow-rule-db` | 最终 dataId 为 `{prefix}.{applicationName}.catalog.json` |
| `username/password` 或 `access-key/secret-key` | — | 各自成对，且两套认证不可同时配置 |
| `timeout-millis` | `3000` | 必须大于 0 |
| `config-service-bean-name` | 自动查找 | 复用容器客户端；外部客户端不会被 Provider 关闭 |

### 与旧配置的关系（重要）

进入 Rule-DB 模式后：

- **`liteflow.rule-source` 与 rule-db 互斥**，同时配置启动报错：`rule-source and rule-db mode cannot be used together, please remove one of them`。
- `parseMode`、`enableMonitorFile`、`chainCacheEnabled`/`chainCacheCapacity` **不再被读取**（解析时机、热重载、缓存语义均由 `rule-db.*` 接管），配置了也没有效果，建议删掉以免误导。

## 5. 发布 API（统一，推荐）

七个后端共用 `com.yomahub.liteflow.publisher.RulePublisher`，经 `RulePublisherFactory.create(config)` 通过 `ServiceLoader` 选择唯一匹配的 Provider。**可独立使用**：管理后台只依赖目标插件 jar，不需要拉起 FlowExecutor，也不依赖全局 `LiteflowConfig`。

```java
RulePublisher publisher = RulePublisherFactory.create(
        RedisPublisherConfig.builder()
                .address("redis://127.0.0.1:6379")
                .applicationName("your-app")        // 多应用共库务必各应用不同；且必须与执行侧最终解析出的 rule-db.application-name 完全一致，否则发布成功但应用永远看不到（典型的「管理后台发了规则没生效」）
                .build());

PublishResult r = publisher.publishChain(PublishChainRequest.builder()
        .chainId("orderChain")
        .el("THEN(a, b)")
        .route("AND(a)")        // 可选：路由 EL（决策路由 chain）
        .namespace("ns1")       // 可选：命名空间
        .build());
r.getVersion();   // 新版本号
r.getSequence();  // 后端提交后的变更序号

publisher.publishScript(PublishScriptRequest.builder()
        .nodeId("s1").type("script").language("groovy")
        .script("def a = 1; return a").build());

publisher.removeChain(RemoveRuleRequest.builder().targetId("orderChain").build());
publisher.removeScript(RemoveRuleRequest.builder().targetId("s1").build());
```

发布脚本只保存源码与语言标识、不编译：**每个执行应用都必须显式引入对应语言的 `liteflow-script-*` 插件**（groovy → `liteflow-script-groovy`），否则该脚本首次加载时才失败；只发布普通 chain 不需要脚本插件（§3.1）。

**乐观锁 `expectedVersion`（并发安全发布的关键）：**

| 取值 | 语义 |
|---|---|
| 不设（null，默认） | UPSERT：已存在 version+1（行锁/Lua/事务下原子自增），不存在插 version=1 |
| `0` | 必须新建；已存在抛 `VersionConflictException`。**并发首发同一 id 用它** |
| `N`（>0） | CAS：当前版本恰为 N 才更新到 N+1，否则抛 `VersionConflictException`（典型管理后台编辑表单） |

异常体系：`com.yomahub.liteflow.publisher.exception.*`（`VersionConflictException` 与配置/校验错误是独立类型，方便区分「冲突重试」与「参数错误」）。

后端配置类型一一对应：`SqlPublisherConfig`、`PostgresqlPublisherConfig`、`MongoPublisherConfig`、`RedisPublisherConfig`、`ZkPublisherConfig`、`EtcdPublisherConfig`、`NacosPublisherConfig`。`RulePublisherFactory` 会拒绝空配置、空 `applicationName`、找不到 Provider 或多个 Provider 同时匹配的情况。

**生命周期**：`RulePublisher` 实现 `AutoCloseable`。SQL / PostgreSQL 每次操作借连接；Redis / MongoDB / ZooKeeper / etcd / Nacos 可能持有客户端连接，用完必须 `close()`（推荐 try-with-resources）。外部传入的 `DataSource`、`MongoClient`、`ConfigService` 等仍归调用方所有，不会被 Publisher 关闭。执行侧通过 SPI 自动装配 Provider，不需要手动创建 Publisher。

**停用（enable=0）**：v1 没有 `enableChain/enableScript` API。SQL/PostgreSQL/MongoDB/Redis/ZooKeeper/etcd 可按存储协议把 `enable` 置 0，通常最迟下个对账周期感知；想立即生效用 `removeChain`。Nacos Catalog 不接受 `enable=false` 记录，必须走 `removeChain` / `removeScript`。

**发布校验与依赖顺序（务必读）**：Publisher 保证的是**单个目标的存储原子性与版本并发控制**，不负责解析或编译业务规则。

- 它只校验必填字段、长度、后端键名等存储约束，**不校验 EL 语法，也不确认 Java 组件、子 chain 或脚本节点已经存在**。`PublishResult` 只代表存储写入成功，不代表各执行节点编译成功——发布前应在隔离环境用与生产相同的 Java 组件和脚本插件做冷加载测试。
- 一次调用只原子发布**一个** chain 或 script；没有把多条相互依赖规则作为 bundle 同时切换的事务 API，多次调用之间始终存在收敛窗口。
- 依赖顺序：新增/升级按「脚本／叶子子 chain → 引用它们的父 chain」发布；**删除反向**——先去掉父 chain 对依赖的引用，再删脚本或子 chain。
- **回滚 = 把已验证的旧正文作为更高的新版本重新发布**；禁止直接把存储中的 `version` 改小。已存在成功版本时，新版本加载失败会保留 last-good 继续服务（§9）。

## 6. 存储结构速览

### SQL 四张表（前缀默认 `lf_`，DDL 在 `liteflow-rule-db-sql/src/main/resources/sql/ddl-mysql.sql`）

- **`lf_chain`**：主键 (`application_name`, `chain_id`)；列含 `namespace` / `el_data` / `route_data`(NULL) / `version`(发布+1) / `content_md5`（**= MD5(el_data)，不含 route**）/ `enable` / `gmt_create` / `gmt_modified`。
- **`lf_script`**：主键 (`application_name`, `node_id`)；列含 `script_name` / `script_type`（`script`/`boolean_script`/`switch_script`/`for_script`；WHILE/ITERATOR 无脚本变体）/ `script_language` / `script_data` / `content_md5`（= MD5(script_data)）/ version / enable。
- **`lf_change_log`**：主键 `seq` AUTO_INCREMENT，索引 (`application_name`, `seq`)；列 `target_type`(CHAIN/SCRIPT) / `target_id` / `op`(UPSERT/DELETE) / `version`。注意 **seq 是整表全局自增、跨应用共享序号空间，跨应用跳号正常**——SQL/PostgreSQL 运行时不靠查询 `MIN(seq)` 判缺口，而是「水位已前进却读不到本应用记录」时请求全量对账（连续应用级序号的 MongoDB/Redis 才能直接检测断档）。可定期清理（建议留 7 天）：清理不破坏最终正确性，但可能让个别节点失去 seq 轮询的快速收敛路径、退化为 60s 对账收敛；**清理窗口应明显大于节点最长离线时间**，被裁剪的历史主要靠周期对账补齐。
- **`lf_change_lock`**：只使用 `lock_id=1` 的单行顺序锁。统一 SQL Publisher 在事务内 `SELECT ... FOR UPDATE` 并持锁到提交，保证 seq 分配顺序与事务提交顺序一致。旧部署升级必须先建表并插入该行，恢复发布后不可删除或修改。

### Redis 键结构（前缀默认 `lf`，无过期时间）

默认键布局为 `{prefix}:{app}:...`；配置 `key-hash-tag` 后变成 `{prefix}:{hashTag}:{app}:...`。Redis Cluster 必须使用后一种布局，确保 Lua 的多键操作都落在同一 slot。

| 键 | 类型 | 内容 |
|---|---|---|
| `{prefix}:{app}:chain:{chainId}` | HASH | `el`/`route`/`namespace`/`version`/`md5`/`enable` |
| `{prefix}:{app}:script:{nodeId}` | HASH | `script`/`name`/`type`/`language`/`version`/`md5`/`enable` |
| `{prefix}:{app}:chain-ids` / `script-ids` | SET | id 集合（清单先 readAll id，再 pipeline 批量读元数据 HASH） |
| `{prefix}:{app}:seq` | STRING | 全局变更序号（INCR） |
| `{prefix}:{app}:changelog` | ZSET | score=seq，member=JSON。**需运维定期裁剪**（`ZREMRANGEBYSCORE`），断档自愈同上 |

### zk / etcd 结构（同构）

每个 chain/script 拆**两个节点**：`{root}/{app}/chains/meta/{chainId}`（轻量指纹，清单遍历）与 `{root}/{app}/chains/content/{chainId}`（全文，懒加载时读）；scripts 同理。变更序号 zk 用 **zxid**、etcd 用 **KV revision**，无独立 changelog，不需要清理日志。zk 注意 znode 数随规则量线性增长（quota 限制）。

### PostgreSQL / MongoDB / Nacos

- **PostgreSQL**：同样使用 `chain`、`script`、`change_log`、`change_lock` 四张表，但 DDL 使用 `BIGSERIAL`、`BOOLEAN`、`TIMESTAMPTZ`，位于 `liteflow-rule-db-postgresql/src/main/resources/postgresql/ddl.sql`。
- **MongoDB**：默认四个 Collection：`lf_chain`、`lf_script`、`lf_sequence`、`lf_change_log`。Publisher 在多文档事务中同时更新正文、应用级 sequence 与 change log；需先由 Publisher 或 DBA 建好必要索引。
- **Nacos**：每个 `applicationName` 使用一个 `{data-id-prefix}.{application-name}.catalog.json`。Catalog 一次保存全部 chain/script 正文、业务版本、全局 sequence 和 `lastChange`，通过 `publishConfigCas` 整体替换；禁止在控制台直接覆盖写。

## 7. 一致性与收敛模型

- **两条腿**：SQL/PostgreSQL/MongoDB/Redis 用 seq 轮询（默认 3s，Redis **没有 pub/sub**）；ZooKeeper/etcd/Nacos 用 watch 或 Listener；七者都叠加周期全量对账（默认 60s）。
- **收敛窗口**：任何变更最迟 `max(通知延迟, 对账周期)` 内全集群感知。实际多数情况：监听后端为毫秒级或亚秒级，轮询后端 3s 内。
- **版本单调递增，不新旧回跳**：限同一条存续记录——迟到的旧版本通知被幂等忽略；删除后用相同 id 重建属于新记录，版本从 1 重新开始。
- **只发脚本也会收敛**：脚本新版发布后，所有引用它的已编译 chain（含多 chain 共享）都在窗口内切新版，无需重发 chain。
- **语义是最终一致、秒级窗口，不是原子切换/线性一致**：窗口内不同节点可能短暂跑不同版本；进行中的执行持旧条件树引用跑完（copy-on-write）。要求「全集群同一时刻切版」的场景不要用。

## 8. 内存模型与执行热路径

| 数据 | 位置 | 驻留时机 |
|---|---|---|
| 规则清单、版本戳与状态索引（chainId→state、nodeId→state+元数据） | JVM 常驻 | 整个生命周期；条目数随规则总量线性增长 |
| 影子 `Chain`/`Node` 对象 | JVM 常驻 | 每条启用清单记录对应一个轻量对象，内容未加载时也存在 |
| EL 文本 + 编译条件树 | Caffeine 有界缓存 | 命中驻留，按访问热度淘汰退回影子 |
| 脚本源码 + 编译产物 | Caffeine 有界缓存 | 同上；chain 淘汰时引用计数减一，归零一起清 |

正文与编译产物的常驻规模由 `cache.capacity` 封顶，但 **JVM 总内存仍与规则总量有关**：10 万条规则、热点仅 200 条时，JVM 不会常驻 10 万条 EL/脚本正文与编译产物，但仍常驻 10 万条影子对象与状态索引。大清单上线前必须用真实规则规模做堆内存与启动 Manifest 基准，不能只按 `cache.capacity` 估算容量。

热路径：`FlowBus.getChain(chainId)` 本地查找 → 已编译直接执行（零远程调用）→ 否则 chain 上 double-checked locking 回源 `fetchChain`（带 fetch-retry-times 重试）→ 编译、写缓存、登记脚本引用计数。子链引用递归同一路径；脚本节点 per-node double-check 懒加载。**一致性由失效驱动**（变更到达置缓存失效），热路径不逐次比对版本，性能与原模式基本无差。

v1 是**惰性刷新 + last-good**：驻留条目收到变更通知后标记为待刷新，但**已成功激活的条件树/脚本产物不会立即销毁**。下次执行在总线外（`ChainCandidateLoader`）回源并编译候选版——成功才原子替换进 FlowBus，失败则状态记 `FAILED`（`desiredVersion`=新版、`activeVersion` 保持旧版），旧的 last-good 继续执行，后续每次执行继续尝试新版；**只有从未成功激活过的冷规则加载失败才抛 `ChainLoadException`**。进行中的执行始终持旧引用跑完。代价是变更后首次执行有一次回源/编译延迟（「后台预编译、消弭首个请求延迟」留作后续增强）。

## 9. 降级语义

| 故障场景 | 行为 |
|---|---|
| **启动时**存储不可用 | manifest 拉取失败**直接抛异常、启动失败**（不会降级空规则跑起来） |
| 运行期存储挂、**已有成功激活版本**（last-good） | **照常执行 last-good 不受影响**（核心可用性属性）：即便已感知到更高的期望版本，新版回源失败也不会先销毁旧版，仅记 `FAILED` 并在后续执行继续尝试新版 |
| 运行期存储挂、**没有已激活版本**（冷规则缓存未命中） | 按 `fetch-retry-times`（3）重试，仍失败抛 **`ChainLoadException`**（规则存在但取不回来；区别于 `ChainNotFoundException` 规则不存在）。存储恢复后下次执行自动回源 |
| 变更通道故障 | 标记 `DEGRADED` 并重试；轮询后端下周期重试；ZooKeeper/etcd 重建监听并对账；Nacos 回调损坏、序号断档或消费失败时请求全量对账 |
| fetch 到 enable=false 或目标不存在 | **已有激活版本则保留 last-good 继续服务**；无激活版本则抛 `ChainLoadException`。后续对账确认删除后从索引与 FlowBus 移除，再执行按 chain 不存在处理 |
| 变更已感知但回源/编译新版失败 | **已有激活版本**：记 `FAILED`（`desiredVersion`=新版、`activeVersion` 保持旧版），last-good 继续执行，后续每次执行继续尝试新版——普通升级失败**不会中断已激活链路**。**从未成功激活过的冷规则**：本次执行抛 `ChainLoadException`。chain 与脚本同语义；显式删除、删除后重建会改变目标身份，不属于普通升级失败，不保留旧版 |
| SQL 缺表且未开 auto-init-table | `ConfigErrorException`，错误信息附完整可复制 DDL |

一句话：**已成功激活的 last-good 是普通升级失败时的可用性下限**——热点规则一旦激活，存储抖动或新版损坏都不会中断它；冷规则首次加载、显式删除、删除后重建和缓存淘汰则不保留旧版。

## 10. 限制与已知边界（v1）

1. **与 `rule-source` 互斥**，同时配置启动报错。
2. **七个 Rule-DB 插件 classpath 七选一**，多个共存启动报错；Nacos 迁移还必须移除旧 `liteflow-rule-nacos`，避免客户端 1.4.4 与 2.5.3 冲突。
3. **Redis Cluster 必须配置 `key-hash-tag`**；多地址且无 `master-name` 时缺失该值会在建连阶段 fail-fast。已有数据实例不可随意增删该配置，因为键布局会变化。
4. **MongoDB 必须支持多文档事务**，仅支持副本集或分片集群。
5. **Nacos 要求 Server 2.x+，且受单配置容量约束**；全部规则正文位于同一 Catalog，规则规模大时优先 SQL/PostgreSQL/MongoDB。
6. 最终一致、秒级窗口，**不满足**全集群同一时刻切版。
7. v1 不提供：Apollo Rule-DB、`enableChain/enableScript` API、节点实例 ID 持久化、管理 UI。
8. 并发发布：不传 `expectedVersion` 是无条件 UPSERT；`expectedVersion=0` 严格新建；正数为 CAS 更新。七后端都保证成功发布的业务版本单调递增。
9. **手写 `LiteFlowChainELBuilder` build 的 chain 可共存，但 id 不要与存储中的 chain/script 撞车**——id 不在存储清单中的手写 chain 不受对账影响；但手写 chain 与存储 chain 同 id、或应用注册的 script node 与存储 script 同 id 时，Rule-DB 初始化直接抛 `ConfigErrorException`（`assertNoForeignChain`/`assertNoForeignScript`，fail-fast，**不会覆盖应用对象**），必须保证两边 id 集合不相交。
10. **路由模式批量冷加载**：`executeRouteChain` 为取得 route 元数据，会在路由执行前逐个回源并编译所有尚未就绪（非 READY）的 Rule-DB chain（`prepareRouteChains`），而非只加载命中的那条。大清单 + 路由模式的首次请求会产生明显冷启动尖刺；缓解手段是把关键 chain 配进 `cache.preload-chain-ids`、按 `application-name` 拆分清单，并把首次路由延迟纳入压测。

**发布参数与后端限制矩阵**（v2.16.1；长度按 Unicode code point 计，仅 SQL 正文按 UTF-8 字节）：

| 后端 | id／字段限制 | 正文与键限制 |
|---|---|---|
| SQL（MySQL DDL） | `application-name` 64；chain/node id、脚本名 128；namespace 64；type/language 32；`table-prefix` 最长 54 且仅 ASCII 字母/数字/下划线 | `el`/`route`/`script` 各 ≤ 65,535 UTF-8 bytes（对齐 `TEXT`） |
| PostgreSQL | 同 SQL，`table-prefix` 最长 52 | 正文用 PostgreSQL `TEXT`，受库/驱动限制 |
| MongoDB | `application-name`、id 128；namespace 128；脚本名 256；type/language 64；database 仅 ASCII 字母/数字/下划线/连字符；collection-prefix 最长 64 | 受 MongoDB 单文档与事务大小限制 |
| Redis | id ≤ 128 且**不能含 `:` 或空白**；namespace 64；脚本名 128；type/language 32 | Cluster 必须配 `key-hash-tag`；正文受 Redis 单值/Lua/客户端限制 |
| ZooKeeper | applicationName、rootPath 每 segment 不可含 `/`、`..` 或控制字符；rule id 不可为空或含 `/` | 单个编码后的 meta/content znode ≤ 960 KiB |
| etcd | rule id 不可为空或含 `/`；applicationName、rootPath 参与 key 前缀 | 受 etcd 请求大小、配额与历史压缩限制 |
| Nacos | data-id-prefix、application-name、group 只能含字母/数字/`_`/`-`/`.`/`:` | 全部规则位于单个 Catalog，受 Nacos 单配置容量限制 |

跨后端迁移时应按**目标端更严格的限制**提前校验，不要假设在 MongoDB/PostgreSQL 可写入的 id／正文一定能原样搬进 Redis、ZooKeeper 或 SQL。

## 11. 常见坑（手改库必看）

- **只改内容、不改 version 和 content_md5 → 改动永不生效**。对账先比 version、相同再比 `content_md5` **列的存量值**（不会拉全文重算）。手动改一条规则的最小正确姿势：

```sql
UPDATE lf_chain
SET el_data = 'THEN(a, c, b, s1)',
    version = version + 1,          -- 必须：对账感知变更的主判据
    content_md5 = MD5(el_data)      -- 建议：保持指纹与内容一致
WHERE application_name = 'your-app' AND chain_id = 'chain1';
```

  只做这一步最迟 60s（reconcile）生效；想 3s（轮询）内生效需再补一条 change_log（一个事务内：UPSERT 内容行 + INSERT change_log；删除同理 DELETE + `op=DELETE` 日志）。`lf_script` 同理，指纹是 `MD5(script_data)`。停用只需 `enable=0`（从 manifest 消失，对账按 DELETE 处理）。
- md5 双保险防「version 撞车但内容不同」（备份恢复/跨环境导表）和「内容变了 version 没加」——防不住裸改。
- 绕过 API 直写存储必须完整复制原子语义：SQL/PostgreSQL 要在单事务内同时更新正文、版本、change log，并使用 `change_lock`；MongoDB 要用多文档事务；Redis **必须一段 Lua**；ZooKeeper/etcd 必须一个事务同写 meta+content。
- **Nacos 不支持控制台直写 Catalog**：正确发布必须基于 MD5 做 CAS，并同步维护正文指纹、业务版本、连续 sequence 与 `lastChange`，只能使用 `RulePublisher`。

## 12. 可观测性

- **Spring Boot actuator 端点**（`liteflow-metrics` 提供，两个 starter 已传递依赖）：`GET /actuator/liteflow/ruledb` 返回 `RuleDbRuntimeSnapshot` JSON：`changeSource.status`（STARTING/UP/DEGRADED/DOWN）、`lastAppliedSeq`、`targets` 按状态计数（shadow/loading/ready/stale/failed/deleted）、`failedTargets` 明细（最多 20 条，含 desiredVersion/activeVersion/error——定位「某条规则为什么执行报错」的入口）。`failedTargets` 中 `activeVersion > 0` 表示该目标仍有 last-good 在服务（执行不会中断）、`activeVersion = 0` 才表示没有可回退的成功版本（再执行会抛 `ChainLoadException`）。
- **非 Spring / Solon**：直接调 `com.yomahub.liteflow.repository.RuleDbRuntime.snapshot()` 拿同一对象自行对接。

## 13. 源码类索引（v2.16.1）

| 关注点 | 位置 |
|---|---|
| 配置绑定 | `liteflow-core/.../property/RuleDbConfig.java`（聚合 cache/sync + `RuleDbSqlConfig` / `RuleDbPostgresqlConfig` / `RuleDbMongoConfig` / `RuleDbRedisConfig` / `RuleDbZkConfig` / `RuleDbEtcdConfig` / `RuleDbNacosConfig`），挂在 `LiteflowConfig.ruleDb` |
| 仓储 SPI / 运行时 | `liteflow-core/.../repository/`：`RuleRepository`（SPI）、`RuleDbProvider(Holder)`、`RuleDbRuntime`（`snapshot()`）、`RuleDbSyncManager`、`RuleDbCache`、`RuleChangeSource` / `RuleChangeListener` / `ChangeSourceHealth` |
| 目标状态机 | `liteflow-core/.../repository/runtime/RuleTargetState.java` / `RuleTargetStatus.java`（shadow/loading/ready/stale/failed/deleted） |
| VO | `repository/vo/`：`ChainRecord` / `ScriptRecord` / `RuleManifest` / `ChangeRecord` / `RuleDbRuntimeSnapshot` 等 |
| 发布 API | 独立模块 `liteflow-rule-db-publisher`：`RulePublisher` / `RulePublisherFactory` / 请求与结果类型 / `PublisherBackend` 七枚举值 / `exception.*`；各插件提供对应 `*PublisherConfig` 与 SPI Provider，SQL 另有旧式简化门面 `SqlRulePublisher` |
| 新异常 | `liteflow-core/.../exception/ChainLoadException.java`（@since 2.16.1）、`SeqGapException` |
| 官方完整指南 | 仓库 `docs/liteflow-rule-db-guide.md`（上手篇 + 参考篇；行数随版本变化，以对齐 tag `v2.16.1` 的 `84539caba` 澄清版为准） |

## 14. 从老规则插件迁移（liteflow-rule-sql 等 → Rule-DB）

**不是直接换依赖**，连接配置、存储协议、发布方式和一致性模型都要换。传统插件在 2.16.1 中仍然有效，不迁也能继续用；要迁则注意：

| 维度 | 老插件（`liteflow-rule-sql/redis/...`） | Rule-DB（`liteflow-rule-db-sql/redis/...`） |
|---|---|---|
| 配置 | `rule-source-ext-data-map`（连接信息 + 表名/字段映射如 `chainTableName`、`elDataField`） | `liteflow.rule-db.*`；**整体删掉旧的 `rule-source*` 配置**（互斥，同配启动报错） |
| 存储结构 | 不约束表名/字段名，全靠配置映射 | 后端协议固定：SQL/PostgreSQL 为四张表（含 `change_lock`），MongoDB 为四个 Collection，Redis/ZooKeeper/etcd/Nacos 各有固定键或 Catalog 布局；存量数据需自行迁移 |
| 写入方式 | 直接插/改库行，启动或轮询时全量重读 | 走发布 API（`SqlRulePublisher` 门面或统一 API）；**手改库必须 `version+1`**（+ `content_md5`，要 3s 级生效还得同事务补 change_log），否则改动永不生效（§11） |
| 一致性 | 规则全量常驻 JVM 堆，多节点各跑各的 | 存储权威源 + 索引/缓存，「轮询/watch + 60s 对账」最终一致（秒级窗口，非原子切版，§7） |

迁移期还要记住：`parseMode`/`enableMonitorFile`/`chainCache*` 配置失效（§4）；启动时存储不可用直接启动失败（§9）；回源失败抛 `ChainLoadException`（§9）；发布顺序先脚本后 chain（§3.3）。

### 备份恢复

- 备份必须覆盖同一后端的**完整协议状态**：SQL/PostgreSQL 四张表（含 `change_log` 和 `change_lock`）、MongoDB 四个 Collection、Redis 内容键/id 集合/seq/changelog、ZooKeeper/etcd 的 meta 与 content、Nacos 整份 Catalog。只恢复正文、不恢复版本和序号会破坏收敛判据。
- **不要把更低 `version` 的备份在线覆盖到仍在运行的相同 `application-name`**——节点会把它当迟到旧版本忽略。完整灾备应先停该应用的 Publisher 与执行节点、原子恢复协议状态再重启；或恢复到新 `application-name` 后切流。
- 在线回滚单条规则应通过 Publisher 把旧正文发布成更高的新版本（§5），不要直接改小 `version`、也不要只改正文而不更新 MD5 与变更日志（§11）。
- SQL/PostgreSQL 恢复后必须确认 `change_lock` 仍有 `lock_id=1` 行；Redis/MongoDB 确认 sequence 不低于保留的 changelog；Nacos Catalog 须整体恢复并通过正文 MD5、sequence、`lastChange` 校验。恢复后先启动一个执行节点，检查 Rule-DB 快照、冷加载关键 chain 并观察至少一个 `reconcile-seconds` 周期再放量。

### 执行账号与发布账号

建议分离只读执行账号与可写 Publisher 账号（能力边界如下，精确 ACL 随后端与部署而异）：

| 后端 | 执行账号（只读） | Publisher 账号（可写） |
|---|---|---|
| SQL / PostgreSQL | 规则表/日志表/锁表 `SELECT`；开 `auto-init-table` 还需 DDL | `SELECT/INSERT/UPDATE/DELETE` + `change_lock` 行锁；初始化需建表 |
| MongoDB | 读四个 Collection + 事务/快照会话 | 读写四个 Collection + 事务；首次初始化建 Collection/索引 |
| Redis | 读内容/id 集合/seq/changelog 所需命令 | 相同 key 前缀上执行发布 Lua 及读写命令 |
| ZooKeeper | 四棵 meta/content 路径递归读 + watch | 这些路径的 CRD + multi-op |
| etcd | 规则前缀的 Range + Watch | 同前缀的 Range/Put/Delete/Txn |
| Nacos | Catalog 读 + Listener | 读 Catalog + CAS 发布配置 |
