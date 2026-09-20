> 来源：LiteFlow 官方文档 `04.v2.16.X文档/110.🗂规则配置源/`（本地规则文件、SQL、ZK、Nacos、Etcd、Apollo、Redis 配置源/轮询/订阅、自定义配置源）。内容与依赖坐标对齐 LiteFlow `2.16.2`。

# 规则配置源（Rule Source）

> **【传统配置源与 Rule-DB 分界】** 本文档讲的是传统的 6 个规则插件（`liteflow-rule-sql/redis/zk/nacos/etcd/apollo`）——启动时读取全部规则，变化后通常也会重新读取并全量解析，结果常驻 JVM 堆；每个应用实例独立消费轮询或 watch／推送通知。该模式在 2.16.2 中仍然有效，但没有 Rule-DB 的统一发布版本、增量缓存和周期对账兜底。同一后端迁移到 Rule-DB 时必须移除旧插件，Nacos 两代插件还使用不同客户端主版本，不能共存。
>
> v2.16.1 新增了支持**增量加载**的 **Rule-DB 统一规则数据库**模式（聚合模块 `liteflow-rule-db`，含 SQL / PostgreSQL / MongoDB / Redis / ZooKeeper / etcd / Nacos 7 个插件 + 统一发布 API）：存储为权威源，JVM 只留轻量索引 + Caffeine 有界缓存（懒加载），多节点靠“变更通知（SQL/PostgreSQL/MongoDB/Redis seq 轮询；ZooKeeper/etcd/Nacos 监听）+ 周期对账”达到最终一致。它与本文档的老插件**运行模型独立**，但 `liteflow.rule-source` 与 `liteflow.rule-db.*` **互斥**，同一后端迁移时也必须移除旧插件。
>
> 生产新项目建议优先评估 Rule-DB 模式，详见 `references/rule-db.md`。

---

## 一、定位与选型总览

LiteFlow 通过 **rule-source** 定位规则内容；除了内置的本地文件外，其余配置源都以**独立插件包**形式提供（按需引入 Maven 依赖）。除本地文件外的所有外部配置源都**不再配置 `liteflow.rule-source`**，改用 `liteflow.rule-source-ext-data-map`（YAML）或 `liteflow.rule-source-ext-data`（JSON 字符串，properties 风格）注入插件参数。

| 配置源 | Maven artifactId | 最低版本 | 规则存放形式 | 热刷新机制 | 关键适用场景 |
|---|---|---|---|---|---|
| 本地文件 | （核心内置，无插件） | — | XML／JSON／YML | 默认启动加载；`enable-monitor-file=true` 可监听本地磁盘文件自动热刷新（单文件 v2.10.0+，模糊路径 v2.11.1+） | 单机、规则不常变 |
| SQL | `liteflow-rule-sql` | v2.9.0+ | chain 表 + script 表 | 轮询（可选，v2.11.1+，SHA 对比） | 已有关系库；与业务表共库；运维习惯 SQL |
| ZooKeeper | `liteflow-rule-zk` | — | ZK 节点（chain 节点 + script 节点） | ZK 原生推送，实时 | 已有 ZK 集群；需强一致/实时 |
| Nacos | `liteflow-rule-nacos` | v2.9.0+ | 单个 dataId 内的 XML | Nacos 推送，实时 | 已用 Nacos 做配置中心 |
| Etcd | `liteflow-rule-etcd` | v2.9.0+ | Etcd 节点（chain + script） | Etcd watch，实时 | 已有 Etcd / K8s 生态 |
| Apollo | `liteflow-rule-apollo` | v2.9.5+ | properties Namespace 的 KV | Apollo 推送，实时 | 已用 Apollo 配置中心 |
| Redis（轮询） | `liteflow-rule-redis` | v2.11.0+ | Redis Hash | 定时轮询（指纹对比） | 已有 Redis；客户端不限；可容忍秒级延迟 |
| Redis（订阅） | `liteflow-rule-redis` | v2.11.0+ | Redisson `RMapCache` | Pub/Sub 实时 | 已用 Redisson；对实时性要求高 |
| 自定义 | （继承 `ClassXmlFlowELParser`） | — | 自行组装 XML | 取决于实现 | 多源混合 / 框架未内置的存储 |

> **单源约束：**框架原生**只允许一种配置源**——不能“一部分规则来自 SQL、另一部分来自 Redis”。若要多源混合或接入未支持的存储，需走“自定义配置源”。

**通用规则／脚本 key 格式（ZK／Etcd／Apollo／Redis 通用）：**

- 规则 key：`规则ID[:是否启用]`，value 为纯 EL（如 `THEN(a,b,c);`）。省略启用项等价于 `true`。
- 脚本 key：`脚本组件ID:脚本类型[:脚本名称:脚本语言:是否启用]`，方括号为可选。value 为脚本数据。
- **位置严格按冒号对齐**：要写第 5 段（是否启用），前 4 段必须补齐，否则报错。例：`s1:script:脚本s1:false` 非法，应写 `s1:script:脚本s1:groovy:false`。
- 只引入了一种脚本语言插件时，"脚本语言"段可省略（自动识别）；多语言共存时必须写明。

---

## 二、本地规则文件配置

无插件依赖，规则文件支持 XML、JSON、YML，以及对应的 `.el.xml`、`.el.json`、`.el.yml` 后缀。Spring 体系下 node 通常由容器自动注册；规则文件中的 `nodes` 主要用于声明脚本节点，或在非 Spring 环境显式声明组件类。

### 2.1 application 配置

```properties
# 单文件
liteflow.rule-source=config/flow.xml
# 多文件（逗号或分号分隔）
liteflow.rule-source=config/flow1.xml,config/flow2.xml
# 扫描所有 jar 包类路径
liteflow.rule-source=classpath*:config/liteflow/**/*.xml
# Spring EL 模糊匹配（工程内）
liteflow.rule-source=config/**/*.xml
# 绝对路径多文件
liteflow.rule-source=/data/lf/flow1.xml,/data/lf/flow2.xml
# 绝对路径模糊匹配（v2.11.1+，支持 * 和 **）
liteflow.rule-source=/data/lf/**/*Rule.xml
```

### 2.2 规则文件样例

XML：

```xml
<flow>
    <!-- Spring 体系可省略 <nodes>；这里声明脚本节点 -->
    <nodes>
        <node id="s1" name="普通脚本1" type="script" language="java">
            这里写脚本
        </node>
    </nodes>
    <chain id="chain1">
        THEN(a, b, c, s1);
    </chain>
</flow>
```

同一条普通 chain 的 JSON 写法：

```json
{
  "flow": {
    "chain": [
      {
        "name": "chain1",
        "value": "THEN(a, b, c);"
      }
    ]
  }
}
```

YML 写法：

```yaml
flow:
  chain:
    - name: chain1
      value: "THEN(a, b, c);"
```

单个 `rule-source` 同时加载不同格式时，还要设置 `liteflow.support-multiple-type=true`；它只表示可混用规则文件格式，不表示可同时使用多个外部配置源。

**热刷新：**

本地文件配置源默认在**启动时加载**，但可配置 `liteflow.enable-monitor-file=true`（默认 `false`）开启**文件监听自动热刷新**：文件改动后自动重载整个规则，无需重启——单文件监听 **v2.10.0+**，模糊匹配路径（如 `/data/lf/**/*Rule.xml`）同样可监听，**v2.11.1+**（官方文档《高级特性 → 本地规则文件监听》；源码 `FlowExecutor.init()` 在 `enableMonitorFile` 为 true 时注册 `MonitorFile`）。
监听仅对 `rule-source` 指向的**本地磁盘文件/模糊路径**生效（底层是 commons-io 对磁盘目录的 `FileAlterationObserver`）；classpath（尤其打包进 jar 的）资源无法被监听，此时改了文件仍需重启，或调用 `FlowExecutor.reloadRule()` / `LiteflowMetaOperator` 热刷新接口。需要配置中心级别的实时推送，请改用外部配置源。

---

## 三、SQL 数据库配置源（`liteflow-rule-sql`，v2.9.0+）

官网推荐的**外置配置源**。只要兼容标准 SQL 语法的库都支持；不约束表名/字段名，全部通过配置映射。

### 3.1 Maven 依赖

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-rule-sql</artifactId>
    <version>2.16.2</version>
</dependency>
```

### 3.2 application 配置（YAML）

```yaml
liteflow:
  rule-source-ext-data-map:
    # 连接信息：复用项目数据源时（v2.10.6+）以下四项可省略
    url: jdbc:mysql://localhost:3306/poseidon
    driverClassName: com.mysql.cj.jdbc.Driver
    username: root
    password: 123456
    applicationName: demo              # 必须
    sqlLogEnabled: true                # 默认开启
    # 轮询自动刷新（v2.11.1+），默认不开启
    pollingEnabled: true
    pollingIntervalSeconds: 60         # 默认 60s
    pollingStartSeconds: 60            # 默认 60s
    # —— chain 表映射（必须）——
    chainTableName: chain
    chainApplicationNameField: application_name
    chainNameField: chain_name
    elDataField: el_data
    # 决策路由（v2.12.1+，可选）
    routeField: route
    namespaceField: namespace
    chainEnableField: enable           # 建议定义为 tinyInt，1 生效 / 0 不生效
    chainCustomSql: 这里设置自定义规则表SQL   # v2.12.4+，可选
    # —— script 表映射（用到脚本才配）——
    scriptTableName: script
    scriptApplicationNameField: application_name
    scriptIdField: script_id
    scriptNameField: script_name
    scriptDataField: script_data
    scriptTypeField: script_type
    scriptLanguageField: script_language  # 单一脚本语言时可省略
    scriptEnableField: enable
    scriptCustomSql: 这里设置自定义脚本表SQL   # v2.12.4+，可选
```

### 3.3 配置项说明

| 配置项 | 说明 | 是否必须 |
|---|---|---|
| `url` / `driverClassName` / `username` / `password` | jdbc 连接信息 | 复用项目数据源时可省 |
| `applicationName` | 应用名称（隔离不同应用规则） | 是 |
| `sqlLogEnabled` | 是否开启 SQL 日志，默认开启 | 否 |
| `pollingEnabled` | 轮询自动刷新，默认不开启 | 否 |
| `pollingIntervalSeconds` | 轮询间隔(s)，默认 60 | 否 |
| `pollingStartSeconds` | 首次轮询起始时间(s)，默认 60 | 否 |
| `chainTableName` / `chainApplicationNameField` / `chainNameField` / `elDataField` | chain 表名与映射字段 | 是 |
| `routeField` / `namespaceField` | 决策路由 EL 字段 / namespace（v2.12.1+） | 否 |
| `chainEnableField` | chain 是否生效字段，建议 `tinyInt` | 否（默认生效） |
| `chainCustomSql` | chain 表自定义过滤 SQL（v2.12.4+） | 否 |
| `scriptTableName` 等映射 | script 表名与映射字段 | 用到脚本则必须 |
| `scriptLanguageField` | 脚本语言字段 | 单语言时可省 |
| `scriptEnableField` | script 是否生效字段 | 否 |
| `scriptCustomSql` | script 表自定义过滤 SQL（v2.12.4+） | 否 |

`scriptTypeField` 取值：`script` / `switch_script` / `boolean_script` / `for_script`；`scriptLanguageField` 取值：`groovy` / `qlexpress` / `js` / `python` / `lua` / `aviator` / `java` / `kotlin`。

### 3.4 建表参考

文档不约束表结构，只给示例字段映射。规则表一行 = 一条规则，脚本表一行 = 一个脚本组件。示例（表名/字段名均可改，需与映射配置对应）：

- 规则表 `liteflow_chain`：`id, application_name, chain_name, chain_desc, el_data, create_time, enable`
- 脚本表 `liteflow_script`：`id, application_name, script_id, script_name, script_data, script_type, script_language, create_time, enable`

> 注：官方文档未给出统一的标准 DDL，建表语句需开发者依据上表字段自行编写（以源码/官方文档为准）。

### 3.5 重要进阶特性

- **复用项目数据源**（v2.10.6+）：项目中已有 `spring.datasource.*` 时，`rule-source-ext-data-map` 里 `url/driverClassName/username/password` 可全省；多数据源时框架自动判断；动态数据源需保证**默认数据源**含 LiteFlow 表数据。
- **轮询自动刷新**（v2.11.1+）：`pollingEnabled: true` 开启；按间隔定时拉取，与本地数据 **SHA 值**对比决定是否更新。有微弱性能消耗、存在刷新延迟。
- **自定义过滤 SQL**（v2.12.4+）：`chainCustomSql` / `scriptCustomSql` 配置**完整 SQL**；一旦配置，**完全忽略 `applicationName` 与 `enable`**，仅按你的 SQL 查询，但返回字段仍须符合映射配置。
- **决策路由**（v2.12.1+）：配置 `routeField` 和 `namespaceField`，并在映射字段存入决策路由表达式即可。
- **多数据源框架**（v2.13.0+）：支持 Baomidou `dynamic-datasource` 与 ShardingSphere `shardingsphere-jdbc`，通过 `baomidouDataSource` / `shardingJdbcDataSource` 指定具体数据源名。

---

## 四、ZooKeeper 配置源（`liteflow-rule-zk`）

### 4.1 依赖与配置

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-rule-zk</artifactId>
    <version>2.16.2</version>
</dependency>
```

```yaml
liteflow:
  rule-source-ext-data-map:
    connectStr: 127.0.0.1:2181,127.0.0.1:2182,127.0.0.1:2183   # 支持集群
    chainPath: /liteflow/chain
    scriptPath: /liteflow/script     # 没有脚本可不配
```

| 配置项 | 说明 |
|---|---|
| `connectStr` | ZK 连接串，可为集群 |
| `chainPath` | 规则目录节点（其下每个子节点 = 一条规则） |
| `scriptPath` | 脚本目录节点（其下每个子节点 = 一个脚本） |

### 4.2 节点数据约定

- `chainPath` 下每个节点：key 形如 `chain1`、`chain2`，value 为纯 EL（`THEN(a,b,c)`）。
- `scriptPath` 下每个节点：key 形如 `s1:script:脚本组件s1`、`s2:boolean_script:布尔脚本组件s2`，value 为脚本数据。

### 4.3 热刷新与启停

- **实时平滑热刷新**：基于 ZK 通知机制，节点改动自动推送，无需任何操作。
- **逻辑启停**（v2.12.0+）：规则 key 写 `chain1:false` 即关闭；脚本 key 末段写 `false` 即关闭。

---

## 五、Nacos 配置源（`liteflow-rule-nacos`，v2.9.0+）

### 5.1 依赖与配置

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-rule-nacos</artifactId>
    <version>2.16.2</version>
</dependency>
```

```yaml
liteflow:
  rule-source-ext-data-map:
    serverAddr: 127.0.0.1:8848
    dataId: demo_rule
    group: DEFAULT_GROUP
    namespace: your namespace id
    username: nacos
    password: nacos
    # 阿里云 MSE（v2.11.4+）改用如下鉴权：
    # accessKey: xxxxxxxxxx
    # secretKey: xxxxxxxxxx
```

| 配置项 | 说明 |
|---|---|
| `serverAddr` | Nacos 连接串 |
| `dataId` | 存放规则+脚本 XML 的数据节点 id |
| `group` / `namespace` | Nacos group / namespace |
| `username` / `password` | Nacos 账号 / 密码 |
| `accessKey` / `secretKey` | 阿里云 MSE 鉴权（v2.11.4+） |

### 5.2 存储约定（重要）

> **重要：**Nacos 里**只能存 XML 形式**，且**所有规则与脚本必须放在同一个 dataId 里**，不可拆分成多个 dataId。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<flow>
  <nodes>
    <node id="s1" type="script">你的脚本代码</node>
  </nodes>
  <chain name="chain1">
    THEN(a, b, c);
  </chain>
</flow>
```

### 5.3 热刷新

Nacos 节点改动自动推送，实时平滑热刷新，无需任何操作。

---

## 六、Etcd 配置源（`liteflow-rule-etcd`，v2.9.0+）

### 6.1 依赖与配置

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-rule-etcd</artifactId>
    <version>2.16.2</version>
</dependency>
```

```yaml
liteflow:
  rule-source-ext-data-map:
    endpoints: http://127.0.0.1:2379    # 支持逗号分隔多地址，如 http://host1:2379,http://host2:2379
    chainPath: /liteflow/chain
    scriptPath: /liteflow/script
    # 以下三项官方文档未列出，以源码 EtcdParserVO 为准（v2.9.3+）
    # user: root                # etcd 开启 RBAC 鉴权时配置，须与 password 同时配置才生效
    # password: 123456
    # namespace: my-namespace   # jetcd namespace，给所有 key 加统一前缀做隔离，可选
```

| 配置项 | 说明 |
|---|---|
| `endpoints` | Etcd 连接串，支持逗号分隔多个地址（源码按 `,` split 后传入 jetcd） |
| `chainPath` | 规则目录节点 |
| `scriptPath` | 脚本目录节点 |
| `user` / `password` | etcd RBAC 鉴权账号/密码（v2.9.3+），**两者须同时配置才生效**；官方文档未列出，以源码 `EtcdParserVO` 为准 |
| `namespace` | jetcd namespace（v2.9.3+），给所有 key 加统一前缀做隔离，可选；同样以源码 `EtcdParserVO` 为准 |

### 6.2 节点约定与热刷新

- key/value 格式、逻辑启停（v2.12.0+）与 ZK 配置源**完全一致**。
- 基于 Etcd watch 自动推送，**实时平滑热刷新**，无需操作。

---

## 七、Apollo 配置源（`liteflow-rule-apollo`，v2.9.5+）

### 7.1 依赖与配置

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-rule-apollo</artifactId>
    <version>2.16.2</version>
</dependency>
```

```yaml
liteflow:
  rule-source-ext-data-map:
    chainNamespace: chainConfig
    scriptNamespace: scriptConfig
```

| 配置项 | 说明 |
|---|---|
| `chainNamespace` | 规则命名空间名称 |
| `scriptNamespace` | 脚本命名空间名称 |

> **连接信息：**Apollo 推荐把连接信息和环境信息放在服务器 `appdatas` 下的 `server.properties` 中，**LiteFlow 配置里不指定连接信息**。

### 7.2 存储约定与热刷新

- 规则需单独创建一个 **`properties` 类型**的 Namespace，每对 KV 就是一条规则。key 格式 `规则ID[:是否启用]`，value 为纯 EL。
- 脚本 Namespace 的 key 格式 `脚本组件ID:脚本类型[:脚本名称:脚本语言:是否启用]`，value 为脚本数据。
- Apollo 推送变更自动**实时平滑热刷新**，无需操作。

---

## 八、Redis 配置源（`liteflow-rule-redis`，v2.11.0+）

同一依赖、两种刷新模式，通过 `mode` 区分；不指定时**默认轮询模式**。

### 8.1 依赖

```xml
<dependency>
    <groupId>com.yomahub</groupId>
    <artifactId>liteflow-rule-redis</artifactId>
    <version>2.16.2</version>
</dependency>
```

### 8.2 两种模式对比

| 维度 | 轮询模式（默认） | 订阅模式 |
|---|---|---|
| `mode` 取值 | `poll` | `sub`（或 `subscribe`） |
| 存储结构 | Redis 原生 **Hash** | Redisson **`RMapCache`** |
| 客户端 | 任意客户端（Jedis、Redisson 等） | **只能用 Redisson**（读写都受限） |
| 刷新机制 | 定时拉取，本地 **SHA-1 指纹**对比，按需拉变化 | Pub/Sub 事件，实时刷新 |
| 实时性 | 有轮询间隔延迟 | 实时 |
| 适用 | 客户端不受限、容忍秒级延迟 | 实时性要求高、接受 Redisson |

### 8.3 通用连接参数（两种模式共用）

| 配置项 | 说明 |
|---|---|
| `redisMode` | `single` / `sentinel` / `cluster`，默认 `single`（cluster 需 v2.15.0+） |
| `host` / `port` | 单点模式连接地址 |
| `masterName` / `sentinelAddress` | 哨兵模式主节点名 / 哨兵地址（`ip:port`，逗号分隔） |
| `clusterAddress` | 集群模式节点地址（`ip:port`，逗号分隔，v2.15.0+） |
| `username` / `password` | Redis 用户名（6.0+）/ 密码，按需配 |
| `connectionPoolSize` / `connectionMinimumIdleSize` | 连接池大小（v2.12.2+，可选） |
| `chainDataBase` / `chainKey` | 规则库号 / Redis key 名（必须） |
| `scriptDataBase` / `scriptKey` | 脚本库号 / Redis key 名（用到脚本必须） |

### 8.4 轮询模式额外参数与配置示例

```yaml
liteflow:
  rule-source-ext-data-map:
    # 单点示例（哨兵/集群按上表替换）
    host: 127.0.0.1
    port: 6379
    username: root
    password: 123456
    # 刷新相关
    mode: poll
    pollingInterval: 60          # 默认 60s
    pollingStartTime: 60         # 默认 60s
    chainDataBase: 1
    chainKey: chainKey
    scriptDataBase: 1
    scriptKey: scriptKey
```

工作原理：首次拉取后将 KV（key=数据Id，value=SHA-1 指纹）缓存本地；之后每次轮询只在 Redis 端算指纹并传回对比，仅对变化项拉取真实数据并更新本地缓存。

**Hash 内存储格式**（`chainKey`/`scriptKey` 即 Hash 名）：
- 规则 Hash 的 field 格式 `规则ID[:是否启用]`，value 为纯 EL。
- 脚本 Hash 的 field 格式 `脚本组件ID:脚本类型[:脚本名称:脚本语言:是否启用]`，value 为脚本数据。

> **客户端编码：**用代码（如 Redisson）写入轮询模式的 Hash 时，**Codec 必须设为 `StringCodec`**；直接在 Redis UI／命令行写入则无此问题。

### 8.5 订阅模式配置示例与约束

只需把 `mode` 改为 `sub`，其余参数与轮询模式一致（连接参数、`chainKey`/`scriptKey` 等）：

```yaml
liteflow:
  rule-source-ext-data-map:
    host: 127.0.0.1
    port: 6379
    mode: sub                 # 订阅模式
    chainDataBase: 1
    chainKey: chainKey
    scriptDataBase: 1
    scriptKey: scriptKey
```

数据写入必须用 Redisson 的 `RMapCache`。下面的客户端必须连接与配置相同的 Redis DB `1`，Map 名必须与 `chainKey`／`scriptKey` 完全一致：

```java
RMapCache<String, String> chains = redissonClient.getMapCache("chainKey");
chains.put("chain1", "THEN(a, b, c);");

RMapCache<String, String> scripts = redissonClient.getMapCache("scriptKey");
scripts.put("s1:script:脚本组件1", "defaultContext.setData(\"test1\",\"hello\");");
```

key/value 格式与轮询模式一致；`RMapCache` 自带监听，底层通过额外 Key + Lua 脚本自动走 Pub/Sub，**实时平滑热刷新**。

---

## 九、自定义配置源（继承 `ClassXmlFlowELParser`）

### 9.1 何时使用

需要**整合两种及以上配置源**，或从框架未内置的存储取规则/脚本时使用。框架只提供扩展接口，逻辑由开发者实现——内置配置源也是这样实现的。

### 9.2 实现方式

继承 `ClassXmlFlowELParser`，重写 `parseCustom()`，返回**拼装好的完整规则 XML**：

```java
public class TestCustomParser extends ClassXmlFlowELParser {
    @Override
    public String parseCustom() {
        // 从任意数据源（可多个）取数据，组装成完整 XML 返回
        String xmlContent = null;
        return xmlContent;
    }
}
```

返回的 XML 形式：

```xml
<flow>
    <nodes>
        <node id="脚本id1" name="脚本名称" type="script" language="脚本语言">...</node>
    </nodes>
    <chain name="chain1">...</chain>
    <chain name="chain2">...</chain>
</flow>
```

> **Spring 注入：**自定义 parser 类会**自动注入 Spring 上下文**，类内可用 `@Autowired`／`@Resource` 注入任意 bean，便于读取业务数据源、调用服务等。

### 9.3 配置路径

把 `rule-source` 写成 `el_xml:` 前缀 + 自定义 parser 类全限定名：

```properties
liteflow.rule-source=el_xml:com.yomahub.liteflow.test.TestCustomParser
```

---

## 十、速查决策建议

- **没有外部基础设施** → 本地文件，最轻量。
- **已有关系库 / 想和业务表共库 / 运维熟 SQL** → SQL 源（推荐外置方案）。
- **已有 ZK / Nacos / Etcd / Apollo 任一** → 直接用对应源，享受实时推送热刷新，零额外中间件成本。
- **已有 Redis**：客户端不限、容忍秒级延迟 → 轮询模式；用 Redisson、要实时 → 订阅模式。
- **多源混合 / 未支持的存储** → 自定义配置源，实现 `parseCustom()`。
