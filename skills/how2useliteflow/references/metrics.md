# LiteFlow 指标监控 liteflow-metrics（v2.16.1 新增）

> 对齐版本：**v2.16.1**。来源：`docs/liteflow-metrics-guide.md` + `liteflow-metrics/` 模块源码。
> 能力：把每条 chain、每个 node 的执行情况（次数/耗时/错误/在途并发）变成 Micrometer 指标，对接 Prometheus / Grafana；另提供 `/actuator/liteflow` 结构检视端点。

## 1. 定位与依赖关系

- 框架无关模块 `liteflow-metrics`，**已是 `liteflow-spring-boot-starter`（Boot 2/3）与 `liteflow-spring-boot4-starter`（Boot 4）的传递依赖**——用这两个 starter 无需单独引入。
- 基于 **Micrometer**（指标界的 SLF4J）：`micrometer-core`、`spring-boot-actuator*` 在模块里都标 `optional`，不污染依赖树；你引哪个 registry，指标就写到哪个。
- 职责切分：LiteFlow 只负责**产生 + 暴露**指标；抓取/存储/画图是 Prometheus/Grafana 的事。要看到曲线需三样：LiteFlow starter + `spring-boot-starter-actuator` + 一个 registry（如 `micrometer-registry-prometheus`）。
- 与老的 `MonitorBus`（自存最近 N 条、自算平均、只打日志）**完全独立、互不影响**：metrics 模块零统计计算、零历史存储，只上报原始测量值。

## 2. 开关与装配条件

唯一自有开关：

```properties
# 可选，默认开启（matchIfMissing=true）；临时关闭采集才设 false
liteflow.metrics.enabled=true
```

装配守护**三条件同时满足**才装配 `ChainMetricsLifeCycle` / `NodeMetricsLifeCycle` / `LiteflowMeterBinder`：

1. classpath 存在 `io.micrometer.core.instrument.MeterRegistry`；
2. 容器中存在 `MeterRegistry` Bean；
3. `liteflow.metrics.enabled` 非 false。

**没有引入任何 registry 就不会有任何指标行为。**

## 3. 端点暴露（采集 ≠ 暴露）

```properties
management.endpoints.web.exposure.include=liteflow,prometheus,metrics
```

- Actuator 两个维度独立：**enabled**（端点存在，除 shutdown 默认都启用）与 **exposed**（对 HTTP 开放，web 默认只暴露 `health`）。不配 `exposure.include`：指标照常采集，但 `/actuator/liteflow`、`/actuator/prometheus`、`/actuator/metrics` 访问 **404**。
- 别图省事用 `include=*`（生产会把 env/heapdump 等敏感端点开出去）。
- 端口：默认随应用主端口（`server.port`）；配了 `management.server.port` 则走独立管理端口。开关 `liteflow.metrics.enabled` 只管采集，与端口无关。

三个端点定位：

| 端点 | 谁提供 | 用途 |
|---|---|---|
| `/actuator/liteflow` | LiteFlow 自有（结构 JSON） | 人看/排查链路；含 EL 原文、组件 class/type、**从未执行过的** chain/node |
| `/actuator/prometheus` | Actuator + registry | 全量指标 Prometheus 文本格式，给 Prometheus 抓 |
| `/actuator/metrics` | Actuator | 单指标浏览/下钻（点号命名 JSON），可 `?tag=chain:mChain` 下钻 |

`/actuator/prometheus` 与 `/actuator/metrics` 只能查到**执行过**的 chain/node；没跑过的看 `/actuator/liteflow`。

## 4. 指标目录（前缀 `liteflow.`，tag 全部低基数）

### Chain 级（按 chainId 聚合）

| 指标 | 类型 | Tags | 含义 |
|---|---|---|---|
| `liteflow.chain.executions` | Timer | `chain`, `scope`(main/sub), `status`(success/failed) | 执行次数、总/平均/最大耗时、成败数 |
| `liteflow.chain.active` | LongTaskTimer | `chain` | 当前在途执行数 + 最长在途耗时（发现卡住/堆积） |
| `liteflow.chain.errors` | Counter | `chain`, `exception`(异常类 simpleName) | 按异常类型分布的失败数 |

- `status` 由执行结束时 `slot.getException()` 是否 null 判定。
- `scope` 区分主链/子链：EL 引用的子链每次执行单独计一次；统计业务调用量筛 `scope=main`。
- 同线程嵌套子链用每线程样本栈正确配对；WHEN 并行子链在各自线程互不影响。

### Node 级（按 nodeId 聚合）

| 指标 | 类型 | Tags | 含义 |
|---|---|---|---|
| `liteflow.node.executions` | Timer | `node`, `type`(NodeTypeEnum.name()), `status` | 执行次数、耗时、成败 |
| `liteflow.node.active` | LongTaskTimer | `node` | 在途组件数（定位慢/挂起组件） |
| `liteflow.node.errors` | Counter | `node`, `exception` | 按异常类型的失败数 |

`type` 取 `COMMON` / `BOOLEAN` / `SWITCH` / `FOR` / `ITERATOR` / `SCRIPT` 等枚举名。

### 全局 Gauge（`LiteflowMeterBinder` 一次性绑定）

| 指标 | 来源 | 含义 |
|---|---|---|
| `liteflow.chains.registered` | `FlowBus.getChainMap().size()` | 已注册 chain 总数 |
| `liteflow.nodes.registered` | `FlowBus.getNodeMap().size()` | 已注册 node 总数 |
| `liteflow.slot.size` | `LiteflowConfig.slotSize` | slot 池容量 |
| `liteflow.slot.occupied` | `DataBus.OCCUPY_COUNT` | 当前在用 slot 数（逼近容量 = 并发吃紧/泄漏） |

## 5. 结构端点 `/actuator/liteflow`（只读，`LiteflowMetaView` 提供，`@Endpoint(id="liteflow")`）

| 路由 | 返回 |
|---|---|
| `GET /actuator/liteflow` | 概览（chainsRegistered/nodesRegistered/slotOccupied/chainIds/nodeIds） |
| `GET /actuator/liteflow/chains` | 全部 chain（chainId/namespace/el/elMd5） |
| `GET /actuator/liteflow/nodes` | 全部 node（nodeId/name/type/script/clazz/language） |
| `GET /actuator/liteflow/chains/{chainId}` | 单 chain 详情 + 指标快照 |
| `GET /actuator/liteflow/nodes/{nodeId}` | 单 node 详情 + 指标快照 + `inChains`（包含它的 chain 列表） |
| `GET /actuator/liteflow/ruledb` | Rule-DB 运行时快照（见 `references/rule-db.md` §12） |

指标快照字段：`count` / `failed` / `errorRate`(=failed/count) / `meanMs` / `maxMs`。快照是"尽力而为"：`metrics.enabled=false` 或无 MeterRegistry 时仍返回结构信息，只是省略 `metrics` 字段。

## 6. 分位 / 直方图（Micrometer 标准配置，LiteFlow 不另立配置项）

Timer 默认只发 count/sum/max，倒推不出 P95/P99：

```properties
# 方式一：客户端分位（进程内计算）
management.metrics.distribution.percentiles[liteflow.chain.executions]=0.95,0.99
# 方式二（推荐）：直方图 bucket，交 Prometheus histogram_quantile，支持跨实例聚合
management.metrics.distribution.percentiles-histogram[liteflow.chain.executions]=true
management.metrics.distribution.percentiles-histogram[liteflow.node.executions]=true
# 可选 SLO 边界
management.metrics.distribution.slo[liteflow.chain.executions]=50ms,100ms,500ms
```

裁剪指标用标准 `MeterFilter` Bean（如 `MeterFilter.deny(id -> id.getName().endsWith(".active"))`）。

## 7. 常用 PromQL（Prometheus 命名转换：`.`→`_`，Timer 带 `_seconds`，Counter 带 `_total`）

```promql
# chain QPS（统计业务调用量请加 scope="main" 过滤，排除 EL 引用的子链）
rate(liteflow_chain_executions_seconds_count{chain="mChain"}[1m])
rate(liteflow_chain_executions_seconds_count{chain="mChain", scope="main"}[1m])
# 平均耗时（秒）
rate(liteflow_chain_executions_seconds_sum{chain="mChain"}[1m])
  / rate(liteflow_chain_executions_seconds_count{chain="mChain"}[1m])
# 错误率
sum(rate(liteflow_chain_executions_seconds_count{chain="mChain", status="failed"}[5m]))
  / sum(rate(liteflow_chain_executions_seconds_count{chain="mChain"}[5m]))
# 按异常类型分布
sum by (exception) (rate(liteflow_chain_errors_total{chain="mChain"}[5m]))
# P95（需先开直方图）
histogram_quantile(0.95, sum by (le) (rate(liteflow_chain_executions_seconds_bucket{chain="mChain"}[5m])))
# slot 池饱和度
liteflow_slot_occupied / liteflow_slot_size
# 在途执行数（LongTaskTimer 后缀是 _active_count / _duration_sum，不是 _count/_sum）
liteflow_chain_active_seconds_active_count{chain="mChain"}
```

## 8. 非 Spring / Solon 环境

`liteflow-metrics` 框架无关，但**钩子不会自动发现**：Spring/Solon 下两个 LifeCycle 是作为 `LifeCycle` Bean 被扫描注册进 `LifeCycleHolder` 的；非 Spring 环境**只 new 出实例不会产生任何指标**，必须手动两步：

```java
// 1. 注册执行钩子（否则永远不会被回调）
LifeCycleHolder.addLifeCycle(new ChainMetricsLifeCycle(registry));
LifeCycleHolder.addLifeCycle(new NodeMetricsLifeCycle(registry));
// 2. 注册表 / slot 池 Gauge 手动 bindTo
new LiteflowMeterBinder(config).bindTo(registry);
```

`/actuator/liteflow` 结构端点是 Spring Actuator 能力，非 Spring 不可用，但指标照常采集。

## 9. 性能与基数

- 未引入 metrics 时开销接近零（node 钩子在 `NodeComponent.execute()` 的 finally 只多一次空列表判断）；引入后亚微秒级，通常 < 1%（Meter 按 tag 组合缓存，`timer.record` 是几次 LongAdder.add）。
- 基数控制：chain + node 两级 → 内存 O(chain 数 + node 数)，几千量级仅几 MB。已规避：不用 node-in-chain 三级组合、exception 只取类 simpleName、不含 requestId/完整异常 message。

## 10. 快速核对清单与集成资产

- 依赖：starter + actuator + registry；`exposure.include` 含 `liteflow,prometheus`；`curl /actuator/prometheus | grep liteflow_` 有输出。
- 开箱即用的 Prometheus + Grafana `docker-compose.yml`、`prometheus.yml`、「LiteFlow 概览」仪表盘 JSON 在仓库 `docs/metrics-integration/`（演示用，生产自行加固）。
- 源码：`liteflow-metrics/`（`ChainMetricsLifeCycle` / `NodeMetricsLifeCycle` / `LiteflowMeterBinder` / `LiteflowMetaView`）；starter 侧装配 `liteflow-spring-boot-starter/.../metrics/LiteflowMetricsAutoConfiguration.java` + `LiteflowEndpoint.java`（boot4 同名）。node 指标钩子基于 core 新增的 `PostProcessNodeExecuteLifeCycle`（见 `references/lifecycle.md`）。
