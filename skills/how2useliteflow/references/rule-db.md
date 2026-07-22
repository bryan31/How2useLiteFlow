# Rule-DB 统一规则数据库（v2.16.1 新增）

> 对齐版本：**v2.16.1**。来源：`docs/liteflow-rule-db-guide.md` + `liteflow-rule-db/` 模块源码。
> 这是与 `rule-sources.md` 里 6 个老规则插件**完全独立、互不干扰**的全新模式；老插件一行未改，Rule-DB 是纯增量。

## 1. 它是什么、解决什么

**Rule-DB 模式让规则和脚本真正以 SQL 数据库 / Redis / ZooKeeper / etcd 为权威源，JVM 只保留轻量索引 + 有界缓存。**

老的 6 个规则插件（`liteflow-rule-sql/redis/zk/nacos/etcd/apollo`）本质是「启动时全量读出 → 拼成一个大 XML → 全量常驻各节点 JVM 堆」，存储只是启动数据源。Rule-DB 解决两个本质痛点：

| 痛点（老插件） | Rule-DB 的做法 |
|---|---|
| 多节点无一致性保证：刷新靠各自轮询/通知，通知丢失无兜底 | 存储是权威源；「变更通知 + 周期对账」两条腿，**最终收敛、秒级窗口** |
| 规则/脚本全量常驻 JVM 堆，规则总量推高内存 | 常驻只有「id → 版本戳 + 轻量元数据」索引；EL 文本/脚本源码/编译产物进**有界缓存**（LRU 淘汰），内存与规则总量**解耦** |

一句话划界：**老 6 个插件 = 启动一次性灌库，之后各节点各跑各的；Rule-DB = 存储永远是权威，JVM 只缓存热规则，所有节点最终一致。**

**影子状态（shadow）**：一个 chain 只注册了 chainId、没有 EL、未编译；一个脚本 Node 只登记元数据（type/language/name）、没有源码。索引常驻、内容按需懒加载——执行到它时才回源拉取并编译。

## 2. 模块与后端选型

根级聚合模块 `liteflow-rule-db`，4 个插件 + 统一发布 API：

| 插件 | 变更通知腿 | 发布原子性 | 说明 |
|---|---|---|---|
| `liteflow-rule-db-sql` | seq 轮询（默认 3s） | 单事务（UPSERT 内容 + INSERT change_log） | 支持 MySQL / MariaDB；H2 仅用于测试。依赖 Redisson 无、自带 DriverManager/可复用容器 DataSource |
| `liteflow-rule-db-redis` | seq 轮询（默认 3s），**无 pub/sub** | 一段 Lua 脚本原子完成 4 步 | 依赖 Redisson（与旧 `liteflow-rule-redis` 选型一致） |
| `liteflow-rule-db-zk` | watch 实时推送（毫秒级，CuratorCache） | 一个 multi-op 事务写 meta+content | 变更序号用 zxid |
| `liteflow-rule-db-etcd` | watch 实时推送（毫秒级，按 revision 订阅） | 一个 Txn 事务写 meta+content | 变更序号用 KV revision |

- 四者都叠加**周期全量对账**（默认 60s）作为最终兜底。
- **同一时刻 classpath 只能有一个 Rule-DB 插件**，检测到多个直接启动报错。
- v1 暂无 nacos/apollo 的 Rule-DB 实现（`RuleRepository` SPI 已在 core 就位，可自扩展）。

## 3. 快速上手

### 3.1 依赖

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-spring-boot-starter</artifactId>
    <version>2.16.1</version>
</dependency>
<!-- 四选一 -->
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-rule-db-sql</artifactId>   <!-- 或 -redis / -zk / -etcd -->
    <version>2.16.1</version>
</dependency>
```

Spring Boot 4 项目 starter 换成 `liteflow-spring-boot4-starter`；Solon 用 `liteflow-solon-plugin`（支持 rule-db 配置绑定，但不携带 Spring 风格 IDE 元数据）。SQL 模式数据库驱动用户自带。

### 3.2 配置（各后端最省姿势）

**SQL**——姿势 A：容器已有 `DataSource` bean → 引依赖零配置，自动复用；`application-name` 自动取 `spring.application.name`。姿势 B：规则库独立，三行起步：

```properties
liteflow.rule-db.sql.url=jdbc:mysql://host:3306/liteflow_rules
liteflow.rule-db.sql.username=root
liteflow.rule-db.sql.password=your-password
# driver-class-name 留空从 url 推断；application-name 留空取 spring.application.name
```

姿势 C：默认 `auto-init-table=false` 需自建三张表（缺表启动报错并附完整 DDL）；或开 `liteflow.rule-db.sql.auto-init-table=true` 启动时 `CREATE TABLE IF NOT EXISTS`。

**Redis**——姿势 A：容器已有 `RedissonClient` bean → 零配置自动复用。姿势 B 一行起步：

```properties
liteflow.rule-db.redis.address=redis://127.0.0.1:6379
# 多地址逗号分隔；哨兵模式再加 master-name；集群只填多地址不配 master-name（但见 §10 限制 3）
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

### 3.3 发布第一条规则

**SQL 有简化门面** `com.yomahub.liteflow.repository.sql.SqlRulePublisher`（无参构造从全局 `LiteflowConfig` 取配置）：

```java
SqlRulePublisher publisher = new SqlRulePublisher();
// UPSERT 语义：已存在 version+1，不存在 version=1；返回新版本号
long version = publisher.publishChain("orderChain", "THEN(a, b, IF(c, d, e))");

ScriptRecord script = new ScriptRecord();
script.setNodeId("s1");
script.setScript("def a = 1; return a");
script.setType("script");        // 对齐 NodeTypeEnum：script/boolean_script/switch_script/for_script
script.setLanguage("groovy");     // 空则用全局默认
publisher.publishScript(script);

publisher.removeChain("orderChain");
publisher.removeScript("s1");
```

注意：**先发脚本、再发引用它的 chain**（反过来，别的节点可能在收敛窗口内拉到新 chain 却找不到脚本，编译瞬时失败）。

> 非 Spring 环境用 `new SqlRulePublisher()` 需先初始化好全局 `LiteflowConfig` 的 `ruleDb` 配置，否则 NPE / `ConfigErrorException`；独立管理后台更推荐用 §5 统一发布 API 显式传 config。

**Redis / zk / etcd 没有简化门面**，统一走 §5 发布 API。

### 3.4 执行

应用侧 API 完全不变：`flowExecutor.execute2Resp("orderChain", param, XxxContext.class)`。首次执行回源拉取 EL 并编译；命中缓存后热路径**零远程调用**。EL 里引用的 `a`/`b`/`c` 仍是应用里已注册的 Java 组件——Rule-DB 只纳管 EL 和脚本，Java 组件照旧随应用部署。

## 4. 配置参考（`liteflow.rule-db.*`）

全部绑定到 `com.yomahub.liteflow.property.RuleDbConfig`（core 内，`LiteflowConfig.ruleDb` 字段），嵌套结构：通用项 + `cache.*` + `sync.*` + 各后端专属项。

### 通用（四后端共用）

| 配置项 | 默认 | 说明 |
|---|---|---|
| `rule-db.enabled` | `true` | 引入依赖即激活；逃生开关，`false` 退回非 Rule-DB 行为 |
| `rule-db.application-name` | SpringBoot 自动取 `spring.application.name`；否则 `default` | **多应用共库的隔离维度**：同一应用的多个实例必须用**同一个**值（共享同一套规则），共库的不同应用必须**不同**，否则互相读写对方规则 |
| `rule-db.cache.capacity` | `500` | 有界缓存容量（按 chain 条数），超出 LRU 淘汰退回影子；脚本随 chain 引用计数联动淘汰 |
| `rule-db.cache.preload-chain-ids` | 空 | 启动预热 chain id 列表（逗号分隔），抹平冷启动回源尖刺；失败只 warn 不阻断 |
| `rule-db.sync.poll-seconds` | `3` | 变更序号轮询周期，**仅 SQL/Redis 生效**（zk/etcd 用 watch） |
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

> 生产建议用容器 DataSource（连接池）：走 `url` 直连是 `DriverManager` 裸连接、无池化，仅适合开发/测试。MySQL/MariaDB DDL 显式 `utf8mb4`，手工建表必须保持该字符集。PostgreSQL/Oracle/SQLServer 未通过兼容矩阵，不在本版本支持范围。

### Redis 专属（`rule-db.redis.*`）

| 配置项 | 默认 | 说明 |
|---|---|---|
| `address` | — | 单机/哨兵/集群统一入口，多地址逗号分隔 |
| `master-name` | — | **配置即哨兵模式**；不配按地址数自动推断单机/集群 |
| `username` / `password` | — | Redis 6+ ACL / 口令，可空 |
| `database` | `0` | 逻辑库 |
| `key-prefix` | `lf` | 规则落在 `{prefix}:{app}:...` 键下 |
| `redisson-bean-name` | 自动查找 | 容器有 RedissonClient 时复用，鉴权在该 bean 上配 |

### ZooKeeper（`rule-db.zk.*`）与 etcd（`rule-db.etcd.*`）

| 配置项 | 默认 | 说明 |
|---|---|---|
| `zk.connect-string` | — | 多地址逗号分隔 |
| `zk.root-path` | `/liteflow` | 规则挂在 `{root}/{app}/...` 下 |
| `zk.session-timeout` | `60000` | 毫秒 |
| `etcd.endpoints` | — | 逗号分隔 |
| `etcd.root-path` | `/liteflow` | — |
| `etcd.user` / `etcd.password` | — | 可选鉴权 |

### 与旧配置的关系（重要）

进入 Rule-DB 模式后：

- **`liteflow.rule-source` 与 rule-db 互斥**，同时配置启动报错：`rule-source and rule-db mode cannot be used together, please remove one of them`。
- `parseMode`、`enableMonitorFile`、`chainCacheEnabled`/`chainCacheCapacity` **不再被读取**（解析时机、热重载、缓存语义均由 `rule-db.*` 接管），配置了也没有效果，建议删掉以免误导。

## 5. 发布 API（统一，推荐）

四个后端共用 `com.yomahub.liteflow.publisher.RulePublisher`，经 `RulePublisherFactory.create(config)` 实例化。**可独立使用**：管理后台只依赖一个插件 jar，不需要拉起 FlowExecutor、不依赖全局 LiteflowConfig。

```java
RulePublisher publisher = RulePublisherFactory.create(
        RedisPublisherConfig.builder()              // SQL/zk/etcd 换 SqlPublisherConfig(可传 DataSource)/ZkPublisherConfig/EtcdPublisherConfig
                .address("redis://127.0.0.1:6379")
                .applicationName("your-app")        // 多应用共库务必各应用不同
                .build());

PublishResult r = publisher.publishChain(PublishChainRequest.builder()
        .chainId("orderChain")
        .el("THEN(a, b)")
        .route("AND(a)")        // 可选：路由 EL（决策路由 chain）
        .namespace("ns1")       // 可选：命名空间
        .build());
r.getVersion();   // 新版本号
r.getSequence();  // 变更序号（SQL seq / Redis seq / zk zxid / etcd revision）

publisher.publishScript(PublishScriptRequest.builder()
        .nodeId("s1").type("script").language("groovy")
        .script("def a = 1; return a").build());

publisher.removeChain(RemoveRuleRequest.builder().targetId("orderChain").build());
publisher.removeScript(RemoveRuleRequest.builder().targetId("s1").build());
```

**乐观锁 `expectedVersion`（并发安全发布的关键）：**

| 取值 | 语义 |
|---|---|
| 不设（null，默认） | UPSERT：已存在 version+1（行锁/Lua/事务下原子自增），不存在插 version=1 |
| `0` | 必须新建；已存在抛 `VersionConflictException`。**并发首发同一 id 用它** |
| `N`（>0） | CAS：当前版本恰为 N 才更新到 N+1，否则抛 `VersionConflictException`（典型管理后台编辑表单） |

异常体系：`com.yomahub.liteflow.publisher.exception.*`（`VersionConflictException` 与配置/校验错误是独立类型，方便区分「冲突重试」与「参数错误」）。

**生命周期**：`RulePublisher` 实现 `AutoCloseable`。SQL 后端 `close()` 空操作；**Redis/zk/etcd 持有客户端连接，用完必须 `close()`**（推荐 try-with-resources）。执行侧（节点进程）通过 SPI 自动装配 provider，**不需要**自己创建 publisher——publisher 只在管理后台/发布工具侧手动创建。

**停用（enable=0）**：v1 没有 `enableChain/enableScript` API。临时停用可直写存储把 `enable` 置 0（SQL `UPDATE lf_chain SET enable=0 ...` / Redis `HSET ... enable 0` / zk、etcd 改 meta 节点标志）。直改 enable 不产生变更通知，各节点最迟下个对账周期感知；想立即生效用 `removeChain`。

## 6. 存储结构速览

### SQL 三张表（前缀默认 `lf_`，DDL 在 `liteflow-rule-db-sql/src/main/resources/sql/ddl-mysql.sql`）

- **`lf_chain`**：主键 (`application_name`, `chain_id`)；列含 `namespace` / `el_data` / `route_data`(NULL) / `version`(发布+1) / `content_md5`（**= MD5(el_data)，不含 route**）/ `enable` / `gmt_create` / `gmt_modified`。
- **`lf_script`**：主键 (`application_name`, `node_id`)；列含 `script_name` / `script_type`（`script`/`boolean_script`/`switch_script`/`for_script`；WHILE/ITERATOR 无脚本变体）/ `script_language` / `script_data` / `content_md5`（= MD5(script_data)）/ version / enable。
- **`lf_change_log`**：主键 `seq` AUTO_INCREMENT，索引 (`application_name`, `seq`)；列 `target_type`(CHAIN/SCRIPT) / `target_id` / `op`(UPSERT/DELETE) / `version`。可定期清理（建议留 7 天）——节点发现 `lastAppliedSeq` 小于表中最小 seq（断档）会自动触发全量对账，**清理不影响正确性**。

### Redis 键结构（前缀默认 `lf`，无过期时间）

| 键 | 类型 | 内容 |
|---|---|---|
| `{prefix}:{app}:chain:{chainId}` | HASH | `el`/`route`/`namespace`/`version`/`md5`/`enable` |
| `{prefix}:{app}:script:{nodeId}` | HASH | `script`/`name`/`type`/`language`/`version`/`md5`/`enable` |
| `{prefix}:{app}:chain-ids` / `script-ids` | SET | id 集合（清单先 readAll id，再 pipeline 批量读元数据 HASH） |
| `{prefix}:{app}:seq` | STRING | 全局变更序号（INCR） |
| `{prefix}:{app}:changelog` | ZSET | score=seq，member=JSON。**需运维定期裁剪**（`ZREMRANGEBYSCORE`），断档自愈同上 |

### zk / etcd 结构（同构）

每个 chain/script 拆**两个节点**：`{root}/{app}/chains/meta/{chainId}`（轻量指纹，清单遍历）与 `{root}/{app}/chains/content/{chainId}`（全文，懒加载时读）；scripts 同理。变更序号 zk 用 **zxid**、etcd 用 **KV revision**，无独立 changelog，不需要清理日志。zk 注意 znode 数随规则量线性增长（quota 限制）。

## 7. 一致性与收敛模型

- **两条腿**：变更通知（SQL/Redis seq 轮询 3s；zk/etcd watch 毫秒级推送）+ 周期全量对账（60s，最终兜底）。Redis **没有 pub/sub**。
- **收敛窗口**：任何变更最迟 `max(通知延迟, 对账周期)` 内全集群感知。实际多数情况：zk/etcd 毫秒级，SQL/Redis 3s 内。
- **版本单调递增，不新旧回跳**：迟到的旧版本通知被幂等忽略。
- **只发脚本也会收敛**：脚本新版发布后，所有引用它的已编译 chain（含多 chain 共享）都在窗口内切新版，无需重发 chain。
- **语义是最终一致、秒级窗口，不是原子切换/线性一致**：窗口内不同节点可能短暂跑不同版本；进行中的执行持旧条件树引用跑完（copy-on-write）。要求「全集群同一时刻切版」的场景不要用。

## 8. 内存模型与执行热路径

| 数据 | 位置 | 驻留时机 |
|---|---|---|
| 版本戳索引（chainId→version、nodeId→version+元数据） | JVM 常驻 | 整个生命周期，条目极小 |
| EL 文本 + 编译条件树 | 有界缓存 | 命中驻留，LRU 淘汰退回影子 |
| 脚本源码 + 编译产物 | 有界缓存 | 同上；chain 淘汰时引用计数减一，归零一起清 |

热路径：`FlowBus.getChain(chainId)` 本地查找 → 已编译直接执行（零远程调用）→ 否则 chain 上 double-checked locking 回源 `fetchChain`（带 fetch-retry-times 重试）→ 编译、写缓存、登记脚本引用计数。子链引用递归同一路径；脚本节点 per-node double-check 懒加载。**一致性由失效驱动**（变更到达置缓存失效），热路径不逐次比对版本，性能与原模式基本无差。

v1 是**惰性失效**：驻留条目收到变更通知后先标记失效、下次执行懒加载新版，进行中执行持旧引用跑完。代价是变更后首次执行有一次回源延迟（「后台预编译」留作后续增强）。

## 9. 降级语义

| 故障场景 | 行为 |
|---|---|
| **启动时**存储不可用 | manifest 拉取失败**直接抛异常、启动失败**（不会降级空规则跑起来） |
| 运行期存储挂、缓存**命中** | **照常执行不受影响**（核心可用性属性） |
| 运行期存储挂、缓存未命中 | 按 `fetch-retry-times`（3）重试，仍失败抛 **`ChainLoadException`**（规则存在但取不回来；区别于 `ChainNotFoundException` 规则不存在）。存储恢复后下次执行自动回源 |
| 变更通道故障 | 标记 `DEGRADED` 并重试；zk 断线 Curator 自动重连+补订阅+全量对账；etcd watch 失败（含 revision compacted）指数退避重试后触发全量对账。丢失变更由周期对账兜底 |
| fetch 到 enable=false 或目标不存在 | 本次抛 `ChainLoadException`；下个对账周期从索引移除，之后报 chain 不存在 |
| 变更已感知但回源新版失败 | 惰性失效：之后每次执行重试回源，成功前该 chain 执行失败。**避开存储抖动窗口发布** |
| SQL 缺表且未开 auto-init-table | `ConfigErrorException`，错误信息附完整可复制 DDL |

一句话：**缓存是可用性下限**——热点规则在缓存里，存储再怎么抖动业务照跑。

## 10. 限制与已知边界（v1）

1. **与 `rule-source` 互斥**，同时配置启动报错。
2. **四个 Rule-DB 插件 classpath 四选一**，多个共存启动报错。
3. **Redis Cluster 当前不支持原子发布**：发布 Lua 脚本触碰 4 个键且未共享 hash-tag，Cluster 下 `EVAL` 报 `CROSSSLOT`。v1 支持单机/哨兵；需 Cluster 请用 SQL/zk/etcd。
4. 最终一致、秒级窗口，**不满足**全集群同一时刻切版。
5. v1 不提供：nacos/apollo 实现（SPI 已就位）、`enableChain/enableScript` API、节点实例 ID 持久化、管理 UI。
6. 并发发布：不传 expectedVersion 是无条件 UPSERT（并发首发同一 id 由唯一键竞态转更新，各自产生连续版本）；`expectedVersion=0` 严格新建。
7. **手动 `LiteFlowChainELBuilder` build 的 chain 可共存，但 id 不要与存储中的 chain 撞车**——对账只管理清单内条目，不会删手写 chain；但 id 撞车时懒加载/失效路径会用存储内容**覆盖**手动 build 的版本。

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
- 绕过 API 直写存储必须完整复制原子语义：SQL 单事务；Redis **必须一段 Lua**（参考 `liteflow-rule-db-redis/src/main/resources/lua/publish-chain.lua`），普通命令拼接有竞态；zk/etcd 必须一个事务同写 meta+content。

## 12. 可观测性

- **Spring Boot actuator 端点**（`liteflow-metrics` 提供，两个 starter 已传递依赖）：`GET /actuator/liteflow/ruledb` 返回 `RuleDbRuntimeSnapshot` JSON：`changeSource.status`（STARTING/UP/DEGRADED/DOWN）、`lastAppliedSeq`、`targets` 按状态计数（shadow/loading/ready/stale/failed/deleted）、`failedTargets` 明细（最多 20 条，含 desiredVersion/activeVersion/error——定位「某条规则为什么执行报错」的入口）。
- **非 Spring / Solon**：直接调 `com.yomahub.liteflow.repository.RuleDbRuntime.snapshot()` 拿同一对象自行对接。

## 13. 源码类索引（v2.16.1）

| 关注点 | 位置 |
|---|---|
| 配置绑定 | `liteflow-core/.../property/RuleDbConfig.java`（+ `RuleDbCacheConfig` / `RuleDbSyncConfig` / `RuleDbSqlConfig` / `RuleDbRedisConfig` / `RuleDbZkConfig` / `RuleDbEtcdConfig`），挂在 `LiteflowConfig.ruleDb` |
| 仓储 SPI / 运行时 | `liteflow-core/.../repository/`：`RuleRepository`（SPI）、`RuleDbProvider(Holder)`、`RuleDbRuntime`（`snapshot()`）、`RuleDbSyncManager`、`RuleDbCache`、`RuleChangeSource` / `RuleChangeListener` / `ChangeSourceHealth` |
| 目标状态机 | `liteflow-core/.../repository/runtime/RuleTargetState.java` / `RuleTargetStatus.java`（shadow/loading/ready/stale/failed/deleted） |
| VO | `repository/vo/`：`ChainRecord` / `ScriptRecord` / `RuleManifest` / `ChangeRecord` / `RuleDbRuntimeSnapshot` 等 |
| 发布 API | 独立模块 `liteflow-rule-db-publisher`：`com.yomahub.liteflow.publisher.*`（`RulePublisher` / `RulePublisherFactory` / `PublishChainRequest` / `PublishScriptRequest` / `RemoveRuleRequest` / `PublishResult` / `exception.*`）；各后端配置类在各插件内（如 `liteflow-rule-db-sql/.../repository/sql/SqlRulePublisher.java` 门面、`SqlPublisherConfig`） |
| 新异常 | `liteflow-core/.../exception/ChainLoadException.java`（@since 2.16.1）、`SeqGapException` |
| 官方完整指南 | 仓库 `docs/liteflow-rule-db-guide.md`（806 行，上手篇 + 参考篇） |

## 14. 从老规则插件迁移（liteflow-rule-sql 等 → Rule-DB）

**不是直接换依赖**，四个体系都要换。老插件 2.16.1 中依然有效，不迁也能继续用；要迁则注意：

| 维度 | 老插件（`liteflow-rule-sql/redis/...`） | Rule-DB（`liteflow-rule-db-sql/redis/...`） |
|---|---|---|
| 配置 | `rule-source-ext-data-map`（连接信息 + 表名/字段映射如 `chainTableName`、`elDataField`） | `liteflow.rule-db.*`；**整体删掉旧的 `rule-source*` 配置**（互斥，同配启动报错） |
| 表结构 | 不约束表名/字段名，全靠配置映射 | **固定三张表** `lf_chain`/`lf_script`/`lf_change_log`（仅前缀可配，字段名固定）；存量数据需自行迁移进新表（老表 `chain_name` → 新表 `chain_id` 等映射自己处理，无现成脚本；手工建表保持 utf8mb4） |
| 写入方式 | 直接插/改库行，启动或轮询时全量重读 | 走发布 API（`SqlRulePublisher` 门面或统一 API）；**手改库必须 `version+1`**（+ `content_md5`，要 3s 级生效还得同事务补 change_log），否则改动永不生效（§11） |
| 一致性 | 规则全量常驻 JVM 堆，多节点各跑各的 | 存储权威源 + 索引/缓存，「轮询/watch + 60s 对账」最终一致（秒级窗口，非原子切版，§7） |

迁移期还要记住：`parseMode`/`enableMonitorFile`/`chainCache*` 配置失效（§4）；启动时存储不可用直接启动失败（§9）；回源失败抛 `ChainLoadException`（§9）；发布顺序先脚本后 chain（§3.3）。
