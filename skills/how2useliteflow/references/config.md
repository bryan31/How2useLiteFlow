# 配置项全集

> 来源文档（相对 `04.v2.16.X文档/`）：
> - `050.🍢配置项/010.说明.md`
> - `050.🍢配置项/020.Springboot下的配置项.md`
> - `050.🍢配置项/030.Spring下的配置项.md`
> - `050.🍢配置项/035.Solon下的配置项.md`
> - `050.🍢配置项/040.其他场景代码设置配置项.md`
>
> 版本对齐：LiteFlow **v2.16.X**。本章配置项在 SpringBoot / Spring / 纯代码三种场景下**完全一致**，仅表现形式不同；**Solon 场景存在实质差异**（若干项无配置入口、个别默认值不同），见第四节。下文以 **SpringBoot 为主线**给出完整表格与示例，其余场景只列差异点。

---

## 一、总则

- LiteFlow 配置项大多**非必须**，系统都有默认值。看不懂的项**保持默认**即可。
- `rule-source` 是唯一强依赖：只要用了规则文件就必须配置；若改为**代码动态构造规则**，则 `rule-source` 自动失效（不需要规则文件）。
- v2.16.1 起新增 **Rule-DB 模式**（`liteflow-rule-db-sql/postgresql/mongodb/redis/zk/etcd/nacos` 七选一 + `liteflow.rule-db.*` 配置）：规则/脚本以外部存储为权威源，与 `rule-source` **互斥**（同配启动报错），详见 `references/rule-db.md`。
- 监控相关项在 SpringBoot 下位于 `liteflow.monitor.*` 子节点；在 Spring XML / 纯代码下被**拍平**为 `enableLog / queueLimit / delay / period`。

---

## 二、SpringBoot 配置项完整表（主体）

| key（`liteflow.*`） | 含义 | 默认值 | 取值 / 备注 |
|---|---|---|---|
| `rule-source` | 规则文件路径 | 无 | **必填**（用代码动态构造规则时自动失效） |
| `enable` | liteflow 是否开启 | `true` | |
| `print-banner` | banner 打印是否开启 | `true` | |
| `slot-size` | 上下文的初始数量槽 | `1024` | 会自动扩容，不用刻意配置 |
| `main-executor-works` | `FlowExecutor.execute2Future` 的线程数 | `64` | |
| `main-executor-class` | `execute2Future` 自定义线程池 Builder | `com.yomahub.liteflow.thread.LiteFlowDefaultMainExecutorBuilder` | LiteFlow 提供默认 Builder |
| `request-id-generator-class` | 自定义请求 ID 生成类 | `com.yomahub.liteflow.flow.id.DefaultRequestIdGenerator` | LiteFlow 提供默认生成类 |
| `global-thread-pool-size` | 全局异步节点线程池大小 | `64` | |
| `global-thread-pool-queue-size` | 全局异步节点线程池队列大小 | `512` | |
| `global-thread-pool-executor-class` | 全局异步节点线程池自定义 Builder | `com.yomahub.liteflow.thread.LiteFlowDefaultGlobalExecutorBuilder` | LiteFlow 提供默认 Builder |
| `when-max-wait-time` | 异步线程最长等待时间（只用于 `when`） | `15000` | 数值，配合单位项 |
| `when-max-wait-time-unit` | `when-max-wait-time` 的单位 | `MILLISECONDS`（毫秒） | |
| `when-thread-pool-isolate` | 每个 `WHEN` 是否用单独的线程池 | `false` | |
| `parse-mode` | 解析模式 | `PARSE_ALL_ON_START` | 三选一：`PARSE_ALL_ON_START`（启动全解析）/ `PARSE_ALL_ON_FIRST_EXEC`（首次执行全解析）/ `PARSE_ONE_ON_FIRST_EXEC`（首次执行单条解析） |
| `retry-count` | 全局重试次数 | `0` | 源码中字段与 getter 已 `@Deprecated`，建议改用 EL 的 `.retry(n)` |
| `support-multiple-type` | 是否支持不同类型的加载方式混用 | `false` | |
| `node-executor-class` | 全局默认节点执行器 | `com.yomahub.liteflow.flow.executor.DefaultNodeExecutor` | |
| `print-execution-log` | 是否打印执行过程中的日志 | `true` | |
| `enable-monitor-file` | 是否开启本地文件监听 | `false` | 改文件自动重载规则 |
| `fast-load` | 是否开启快速解析模式 | `false` | |
| `enable-node-instance-id` | 是否开启 Node 节点实例 ID 持久化 | `false` | |
| `enable-virtual-thread` | 是否开启虚拟线程 | `true` | **只在 JDK21+ 环境有效** |
| `fallback-cmp-enable` | 是否启用组件降级（`@FallbackCmp`） | `false` | 见 `references/advanced.md` |
| `check-node-exists` | 是否校验规则里引用的节点是否存在 | `true` | **仅 SpringBoot 场景**（属 `LiteflowProperty`，非 `LiteflowConfig` 字段；Spring XML / 纯代码无法设置）。⚠️ 2.16.1 源码中该键**仅被绑定、未发现任何读取点**（全仓库无 `isCheckNodeExists` 调用方，装配类 `LiteflowPropertyAutoConfiguration` 也未传递）；实际「启动是否校验节点存在」由 `parse-mode` 控制（`PARSE_ONE_ON_FIRST_EXEC` 可跳过启动期校验，见 `references/metadata.md`），不要依赖本项改变校验行为 |
| `chain-cache.enabled` | 是否开启 chain 缓存 | `false` | |
| `chain-cache.capacity` | chain 缓存容量 | `10000` | |
| `monitor.enable-log` | 监控是否开启 | `false` | 默认不开启 |
| `monitor.queue-limit` | 监控队列存储大小 | `200` | |
| `monitor.delay` | 监控一开始延迟多少执行 | `300000` | 毫秒，即 5 分钟 |
| `monitor.period` | 监控日志打印间隔（每过多少时间执行一次） | `300000` | 毫秒，即 5 分钟 |
| `metrics.enabled` | 指标采集开关（v2.16.1 新增 `liteflow-metrics` 模块，基于 Micrometer） | `true` | 用 starter 即为传递依赖，无需单独引入；装配条件与指标目录见 `references/metrics.md` |

> 注：原 Spring 章节 md 中 `<property name="period">` 与 `<property name="delay">` 的中文注释被互换，但**属性名本身正确**。语义以本表为准：`delay`=初始延迟，`period`=打印间隔（与 SpringBoot / 纯代码两章一致）。

### 1. application.yaml 示例

```yaml
liteflow:
  # 规则文件路径（必填）
  rule-source: config/flow.xml
  # ---------- 以下均有默认值，按需开启 ----------
  enable: true
  print-banner: true
  slot-size: 1024
  parse-mode: PARSE_ALL_ON_START          # 启动即全量解析
  retry-count: 0
  support-multiple-type: false
  print-execution-log: true
  enable-monitor-file: false              # 文件变更自动重载
  fast-load: false
  enable-virtual-thread: true             # 仅 JDK21+ 生效
  # when 并发相关
  when-max-wait-time: 15000
  when-max-wait-time-unit: MILLISECONDS
  when-thread-pool-isolate: false
  # 线程池
  main-executor-works: 64
  global-thread-pool-size: 64
  global-thread-pool-queue-size: 512
  # 简易监控
  monitor:
    enable-log: false
    queue-limit: 200
    delay: 300000
    period: 300000
```

### 2. application.properties 示例

```properties
liteflow.rule-source=config/flow.xml
# ---------- 以下非必须 ----------
liteflow.enable=true
liteflow.print-banner=true
liteflow.slot-size=1024
liteflow.parse-mode=PARSE_ALL_ON_START
liteflow.retry-count=0
liteflow.support-multiple-type=false
liteflow.print-execution-log=true
liteflow.enable-monitor-file=false
liteflow.fast-load=false
liteflow.enable-virtual-thread=true
liteflow.when-max-wait-time=15000
liteflow.when-max-wait-time-unit=MILLISECONDS
liteflow.when-thread-pool-isolate=false
liteflow.global-thread-pool-size=64
liteflow.global-thread-pool-queue-size=512
liteflow.main-executor-works=64
liteflow.monitor.enable-log=false
liteflow.monitor.queue-limit=200
liteflow.monitor.delay=300000
liteflow.monitor.period=300000
```

> 上面两段均只列出常用项；完整项见上表。各类 `*-class` 项默认即用 LiteFlow 自带实现，自定义时再覆盖。

### 3. Rule-DB 模式配置（v2.16.1 新增，`liteflow.rule-db.*`）

v2.16.1 新增 **Rule-DB 统一规则数据库**模式：规则/脚本以 SQL / PostgreSQL / MongoDB / Redis / ZooKeeper / etcd / Nacos 为权威源，JVM 只留轻量索引 + 有界缓存（LRU）。引入对应 `liteflow-rule-db-*` 插件（七选一）后，用 `liteflow.rule-db.*` 取代 `rule-source`。通用配置（七后端共用）：

| key（`liteflow.rule-db.*`） | 含义 | 默认值 | 取值 / 备注 |
|---|---|---|---|
| `enabled` | 是否开启 Rule-DB 模式 | `true` | 引入依赖即激活；逃生开关，`false` 退回非 Rule-DB 行为 |
| `application-name` | 应用名（多应用共库的隔离维度） | **仅两个 SpringBoot starter** 在为空时回落到 `spring.application.name`；**Solon / 纯代码无此回落，必须显式配置**；都没有值时落 `default` | 共库时务必各应用不同，否则会互相读写对方规则 |
| `cache.capacity` | 规则缓存容量（按 chain 条数，超出 LRU 淘汰） | `500` | |
| `cache.preload-chain-ids` | 启动预热的 chain id 列表 | 空 | 逗号分隔 |
| `sync.poll-seconds` | 变更序号轮询周期 | `3` | 仅 SQL / PostgreSQL / MongoDB / Redis 生效；ZooKeeper / etcd / Nacos 使用监听 |
| `sync.reconcile-seconds` | 周期全量对账间隔 | `60` | |
| `sync.fetch-retry-times` | 回源拉取失败重试次数 | `3` | |

> ⚠️ **与 `rule-source` 互斥**：两者同配启动直接报错。进入 Rule-DB 模式后，`parse-mode`、`enable-monitor-file`、`chain-cache.*` **不再被读取**（解析时机、热重载、缓存语义均由 `rule-db.*` 接管），配置了也没有效果。各后端专属配置位于 `rule-db.sql.*` / `postgresql.*` / `mongodb.*` / `redis.*` / `zk.*` / `etcd.*` / `nacos.*`，完整语义见 `references/rule-db.md` §4。

---

## 三、Spring（非 Boot）场景差异

通过 XML bean 注册 `com.yomahub.liteflow.property.LiteflowConfig`，用 `<property>` 注入。差异点：

- **属性名改为驼峰**（Java 字段名），不是 kebab-case：`ruleSource`、`printBanner`、`slotSize`、`mainExecutorWorks`、`mainExecutorClass`、`requestIdGeneratorClass`、`globalThreadPoolSize`、`globalThreadPoolQueueSize`、`globalThreadPoolExecutorClass`、`whenMaxWaitTime`、`whenMaxWaitTimeUnit`、`whenThreadPoolIsolate`、`parseMode`、`retryCount`、`supportMultipleType`、`nodeExecutorClass`、`printExecutionLog`、`enableMonitorFile`、`fastLoad`、`enableNodeInstanceId`、`enableVirtualThread`、`chainCacheEnabled`、`chainCacheCapacity`（对应主表 `chain-cache.*`）、`fallbackCmpEnable`（对应 `fallback-cmp-enable`）、`ruleSourceExtData`、`ruleSourceExtDataMap`、`instanceIdGeneratorClass`。
- `instanceIdGeneratorClass` **没有对应的 `liteflow.*` key**（SpringBoot starter 未绑定），仅 Spring XML / 纯代码场景可直接设置，getter 兜底为 `DefaultRequestIdGenerator`（见 `references/code-internals.md`）。
- **监控项被拍平**（不再有 `monitor.` 前缀）：`enableLog`、`queueLimit`、`delay`、`period`，全部直接挂在同一个 bean 上。
- `whenMaxWaitTimeUnit` / `parseMode` 以**字符串**形式注入（如 `"MILLISECONDS"`、`"PARSE_ALL_ON_START"`）。

```xml
<bean id="liteflowConfig" class="com.yomahub.liteflow.property.LiteflowConfig">
    <property name="ruleSource" value="config/flow.xml"/>
    <!-- 以下均非必须 -->
    <property name="enable" value="true"/>
    <property name="printBanner" value="true"/>
    <property name="slotSize" value="1024"/>
    <property name="parseMode" value="PARSE_ALL_ON_START"/>
    <property name="retryCount" value="0"/>
    <property name="supportMultipleType" value="false"/>
    <property name="printExecutionLog" value="true"/>
    <property name="enableMonitorFile" value="false"/>
    <property name="fastLoad" value="false"/>
    <property name="enableVirtualThread" value="true"/>
    <property name="whenMaxWaitTime" value="15000"/>
    <property name="whenMaxWaitTimeUnit" value="MILLISECONDS"/>
    <property name="whenThreadPoolIsolate" value="false"/>
    <property name="globalThreadPoolSize" value="64"/>
    <!-- 监控（拍平） -->
    <property name="enableLog" value="false"/>
    <property name="queueLimit" value="200"/>
    <property name="delay" value="300000"/>
    <property name="period" value="300000"/>
</bean>
```

---

## 四、Solon 场景差异

> ⚠️ 官方「035.Solon下的配置项」只有一句"同 Springboot 下的配置项"，**与源码实际不符**。以下差异逐条来自 `liteflow-solon-plugin` 源码：绑定类 `config/LiteflowProperty.java`、装配类 `config/LiteflowAutoConfiguration.java`（:29-58）、插件自带默认值 `META-INF/liteflow-default.properties`（启动时由 `integration/XPluginImpl` 以 `putIfAbsent` 载入，用户配置优先）。

### 1. 有实质差异的项

| 项 | Solon 实际行为 |
|---|---|
| WHEN 超时 | **不支持** `liteflow.when-max-wait-time` / `when-max-wait-time-unit`：`LiteflowProperty` 无这两个字段，配了**静默无效**。只能用 **`liteflow.when-max-wait-seconds`（单位固定为秒，默认 `15`）**；它非空时优先于 `whenMaxWaitTime` 生效（`ParallelStrategyExecutor.java:91-99`） |
| 文件监听热重载 | **无 `enable-monitor-file` 入口**（无绑定字段、装配未传递），恒为 `LiteflowConfig` 默认 `false`：本地规则文件变更自动重载不可用 |
| 快速解析 | **无 `fast-load` 入口**，恒为默认 `false` |
| 脚本特殊设置 | **无 `script-setting` 入口**，恒为空 Map |
| 虚拟线程 | **无 `enable-virtual-thread` 入口**：字段保持 `null`，`LiteflowConfig.getEnableVirtualThread()` 对 null 兜底为 `TRUE`（:544-550），即 **JDK21+ 下恒开、无法通过配置关闭** |
| 全局线程池大小 | `liteflow.global-thread-pool-size` **默认 `16`**（插件默认 properties 与 `LiteflowProperty.getGlobalThreadPoolSize()` 的 null 兜底均为 16），**不是 SpringBoot 的 `64`** |

### 2. 与 SpringBoot 一致的项

- `liteflow.monitor.*` 子节点（独立的 `LiteflowMonitorProperty`，`@Inject("${liteflow.monitor}")`）、`parse-mode`、`chain-cache.*`、`rule-db.*`、`agent.*` 的 key 结构与绑定方式同 SpringBoot。
- 其余通用项（`rule-source`、`slot-size`、`main-executor-*`、`print-banner`、`print-execution-log`、`retry-count`、`support-multiple-type`、`node-executor-class`、`request-id-generator-class`、`global-thread-pool-queue-size`（默认 `512`）、`global-thread-pool-executor-class`、`when-thread-pool-isolate`、`enable-node-instance-id`、`fallback-cmp-enable`）写法同第二节表格。
- 例外提醒：Rule-DB 的 `application-name` 在 Solon 下**没有** `spring.application.name` 回落（`LiteflowAutoConfiguration.java:57` 直接 `setRuleDb`），必须显式配置，详见第二节第 3 小节。

---

## 五、纯代码场景差异（`LiteflowConfig` setter）

适用于非 Spring/非 Solon 的纯 Java 场景。`new LiteflowConfig()` 后逐项 `setXxx`。差异点：

- 属性名同 Spring XML（驼峰），通过 setter 注入：`setRuleSource`、`setEnable`、`setPrintBanner`、`setSlotSize`、`setMainExecutorWorks`、`setMainExecutorClass`、`setRequestIdGeneratorClass`、`setGlobalThreadPoolSize`、`setGlobalThreadPoolQueueSize`、`setGlobalThreadPoolExecutorClass`、`setWhenMaxWaitTime`、`setWhenMaxWaitTimeUnit`、`setWhenThreadPoolIsolate`、`setParseMode`、`setRetryCount`、`setSupportMultipleType`、`setNodeExecutorClass`、`setPrintExecutionLog`、`setEnableMonitorFile`、`setFastLoad`、`setEnableNodeInstanceId`、`setEnableVirtualThread`、`setEnableLog`、`setQueueLimit`、`setDelay`、`setPeriod`、`setChainCacheEnabled`、`setChainCacheCapacity`、`setFallbackCmpEnable`、`setRuleSourceExtData`、`setRuleSourceExtDataMap`、`setInstanceIdGeneratorClass`（无对应 `liteflow.*` key，仅 XML / 纯代码可设，见 `references/code-internals.md`）。
- **类型为强类型枚举/对象**，不再是字符串：
  - `setWhenMaxWaitTimeUnit(TimeUnit.MILLISECONDS)` —— `java.util.concurrent.TimeUnit`
  - `setParseMode(ParseModeEnum.PARSE_ALL_ON_START)` —— `ParseModeEnum`
  - `setDelay(300000L)` / `setPeriod(300000L)` —— `long`
- 监控项同样拍平：`setEnableLog` / `setQueueLimit` / `setDelay` / `setPeriod`。

```java
LiteflowConfig config = new LiteflowConfig();
// 规则文件路径（必填，代码动态构造规则时自动失效）
config.setRuleSource("config/flow.xml");
// ---------- 以下非必须 ----------
config.setEnable(true);
config.setPrintBanner(true);
config.setSlotSize(1024);
config.setParseMode(ParseModeEnum.PARSE_ALL_ON_START);
config.setRetryCount(0);
config.setSupportMultipleType(false);
config.setPrintExecutionLog(true);
config.setEnableMonitorFile(false);
config.setFastLoad(false);
config.setEnableVirtualThread(true);          // 仅 JDK21+ 生效
// when 并发
config.setWhenMaxWaitTime(15000);
config.setWhenMaxWaitTimeUnit(TimeUnit.MILLISECONDS);
config.setWhenThreadPoolIsolate(false);
// 线程池
config.setMainExecutorWorks(64);
config.setGlobalThreadPoolSize(64);
config.setGlobalThreadPoolQueueSize(512);
// 监控（拍平）
config.setEnableLog(false);
config.setQueueLimit(200);
config.setDelay(300000L);
config.setPeriod(300000L);
```

---

## 六、重点配置速记

| 重点项 | 默认 | 何时改 |
|---|---|---|
| `rule-source` | — | 用规则文件时必填；代码动态构造规则时不填 |
| `parse-mode` | `PARSE_ALL_ON_START` | 想懒加载规则时改 `PARSE_ONE_ON_FIRST_EXEC` / `PARSE_ALL_ON_FIRST_EXEC` |
| `slot-size` | `1024` | 一般不动，会自动扩容 |
| `enable-monitor-file` | `false` | 需要本地规则文件变更自动重载时设 `true` |
| `support-multiple-type` | `false` | 需要「规则文件 + 代码 / 多种来源」混装时设 `true` |
| `when-max-wait-time` (+unit) | `15000` ms | `when` 并发整体超时阈值，按业务最长分支调整 |
| `global-thread-pool-size` | `64` | 全局异步节点并发上限（v2.16.X 的并发线程数由它控制） |
| `fast-load` | `false` | 开启快速解析模式 |
| `enable-log`（`monitor.enable-log`） | `false` | 开启简易监控统计 |
| `print-execution-log` | `true` | 关闭可减少执行过程日志 |
| `enable-virtual-thread` | `true` | JDK21+ 用虚拟线程；低于 JDK21 不生效 |

---

## 七、不存在 / 不生效的命名（避免臆造）

> ⚠️ 修正：早期版本曾把 `chainCache*` 列为"不存在的配置项"，这是**错误**的。`chain-cache.enabled`(默认 `false`) 与 `chain-cache.capacity`(默认 `10000`) 是**真实存在**的配置（见上表与源码 `liteflow-default.properties`、`LiteflowConfig.chainCacheEnabled/chainCacheCapacity`），只是未出现在官方「050.配置项」章节里。请勿因此避开该特性。

下列名称在 v2.16.X 中**不存在或配置了也不生效**（均不在 050 文档，也不在任何 `liteflow-default.properties` 默认值中），易与真实项混淆，请勿使用：

- `whenMaxWorkers` —— 精确说：Solon 插件的 `LiteflowProperty` 中**残留** `whenMaxWorkers` 字段（`liteflow-solon-plugin/.../config/LiteflowProperty.java:50`，含 getter/setter :175-181），属历史遗留，但**从不接入 `LiteflowConfig`**（`LiteflowAutoConfiguration` 装配时无对应调用，`LiteflowConfig` 本身也无此字段），配置了没有任何效果。并发线程数由 **`global-thread-pool-size`**（全局异步节点线程池大小，SpringBoot 默认 64 / Solon 默认 16，见第四节）控制。
- `printExecutionResult` —— 只有 `print-execution-log`（执行过程日志），无 `printExecutionResult`。

> 提示：判断一个配置名是否真实，最可靠的方式是查 `liteflow-spring-boot-starter/src/main/resources/META-INF/liteflow-default.properties` 与 `LiteflowConfig` / `LiteflowProperty` 字段（可用 `scripts/source-lookup.sh grep`）。**"没写进 050 文档" ≠ "不存在"**——050 章节本身相对源码并不完整。
