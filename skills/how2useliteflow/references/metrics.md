# LiteFlow 指标监控 liteflow-metrics（v2.16.1 新增）

> 对齐版本：**2.16.2**。该模块在 v2.16.1 首次引入；来源为 `docs/liteflow-metrics-guide.md` + `liteflow-metrics/` 模块源码。
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

以下自动装配只适用于两个 Spring Boot starter。当前审计的 **2.16.2 源码**中，**三条件同时满足**就会装配 `ChainMetricsLifeCycle` / `NodeMetricsLifeCycle` / `LiteflowMeterBinder`：

1. classpath 存在 `io.micrometer.core.instrument.MeterRegistry`；
2. 容器中存在 `MeterRegistry` Bean；
3. `liteflow.metrics.enabled` 非 false。

**没有引入任何 registry 就不会有任何指标行为。**

源码核验边界（2026-09-19）：当前两个 starter 的 Metrics 配置没有 `FlowExecutor` Bean 前置条件；关闭 LiteFlow 主装配时同步关闭 `liteflow.metrics.enabled`，避免 Gauge 访问未初始化对象。`LiteflowMeterBinder` 还要求 `LiteflowConfig` Bean，其他采集生命周期要求 MeterRegistry。

根 POM 当前未显式启用 Maven `-parameters`。若 Spring 6.1+ 下参数化 Actuator 端点无法解析 selector 参数，检查实际制品是否保留参数名，必要时在源码构建中启用该编译参数；不要只凭版本号推断已包含某项补丁。

## 3. 端点暴露（采集 ≠ 暴露）

```properties
management.endpoints.web.exposure.include=liteflow,prometheus,metrics
```

- Actuator 两个维度独立：**enabled**（端点存在，除 shutdown 默认都启用）与 **exposed**（对 HTTP 开放，web 默认只暴露 `health`）。不配 `exposure.include`：指标照常采集，但 `/actuator/liteflow`、`/actuator/prometheus`、`/actuator/metrics` 访问 **404**。
- 别图省事用 `include=*`（生产会把 env/heapdump 等敏感端点开出去）。
- 端口：默认随应用主端口（`server.port`）；配了 `management.server.port` 则走独立管理端口。开关 `liteflow.metrics.enabled` 与端口无关——但它**不只管采集**，设为 `false` 会让 `/actuator/liteflow` 端点一并消失（见 §5）。
- 若组织级配置了 `management.endpoints.enabled-by-default=false`（端点默认全部禁用），只加 `exposure.include` 仍会 404，需再显式打开：`management.endpoint.liteflow.enabled=true`（`prometheus`/`metrics` 端点同理）。

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
| `liteflow.slot.size` | `LiteflowConfig.slotSize` | 启动时配置的初始 slot 数，不是扩容后的实时容量 |
| `liteflow.slot.occupied` | `DataBus.OCCUPY_COUNT` | 当前在用 slot 数 |

`DataBus` 在空闲下标耗尽时会按约 1.75 倍自动扩容，而 `liteflow.slot.size` Gauge 仍是初始配置值。因此 `occupied / size` 可能大于 1，不能当成池饱和度；应观察 occupied 的趋势、异常回落和执行延迟来排查并发压力或 slot 未释放。

## 5. 结构端点 `/actuator/liteflow`（只读，`LiteflowMetaView` 提供，`@Endpoint(id="liteflow")`）

| 路由 | 返回 |
|---|---|
| `GET /actuator/liteflow` | 概览（chainsRegistered/nodesRegistered/slotOccupied/chainIds/nodeIds） |
| `GET /actuator/liteflow/chains` | 全部 chain（chainId/namespace/el/elMd5） |
| `GET /actuator/liteflow/nodes` | 全部 node（nodeId/name/type/script/clazz/language） |
| `GET /actuator/liteflow/chains/{chainId}` | 单 chain 详情 + 指标快照 |
| `GET /actuator/liteflow/nodes/{nodeId}` | 单 node 详情 + 指标快照 + `inChains`（包含它的 chain 列表） |
| `GET /actuator/liteflow/ruledb` | Rule-DB 运行时快照（见 `references/rule-db.md` §12） |

指标快照字段：`count` / `failed` / `errorRate`(=failed/count) / `meanMs` / `maxMs`。快照是"尽力而为"的，但要分清两种"没指标"的场景：

- **`liteflow.metrics.enabled=false`：整个端点消失（404）。** Boot2/3 与 Boot4 的 `LiteflowMetricsAutoConfiguration` 类级都挂 `@ConditionalOnProperty(prefix="liteflow.metrics", name="enabled", ...)`，而 `LiteflowMetaView` 与 `LiteflowEndpoint` 只在该配置类内注册——开关一关整个类不装配，端点 Bean 不存在，`/actuator/liteflow` 直接 404，**不是"仍返回结构信息"**。
- **当前 2.16.2 源码中，`liteflow.enable=false` 不会自动抑制 Metrics 自动配置。** 若 classpath 和容器里仍有 `MeterRegistry`，请同步关闭 `liteflow.metrics.enabled`，否则可能在启动阶段出现 NPE。装配条件应以实际使用的制品为准。
- **enabled 未关、但容器中没有 `MeterRegistry` Bean：端点仍在。** `LiteflowMetaView` 允许 null registry，此时仍返回结构信息，只是 `metrics` 快照字段为 null/省略。

也就是说，想"临时关采集、但保留结构端点"目前**没有这样的组合**——关开关会连端点一起关。

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
# 当前占用 slot 数；slot 会自动扩容，不能除以 slot_size 当作饱和度
liteflow_slot_occupied
# 在途执行数（LongTaskTimer 后缀是 _active_count / _duration_sum，不是 _count/_sum）
liteflow_chain_active_seconds_active_count{chain="mChain"}
```

### 告警规则示例（Prometheus alerting rules）

骨架固定为 `groups → rules → alert/expr/for/labels/annotations`，`expr` 可直接复用上面的错误率 PromQL：

```yaml
groups:
  - name: liteflow
    rules:
      # chain 错误率 5 分钟内超过 5%
      - alert: LiteflowChainHighErrorRate
        expr: |
          sum by (chain) (rate(liteflow_chain_executions_seconds_count{status="failed"}[5m]))
            /
          sum by (chain) (rate(liteflow_chain_executions_seconds_count[5m]))
            > 0.05
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "LiteFlow chain {{ $labels.chain }} 错误率过高"
```

## 8. Solon / 非 Spring 环境

`liteflow-metrics` 的采集类本身与框架无关，但只有 Spring Boot starter 提供指标自动装配。Solon 插件既不传递依赖 `liteflow-metrics`，也不创建指标钩子；使用者必须显式引入该模块，把 `ChainMetricsLifeCycle`、`NodeMetricsLifeCycle` 注册为 Solon Bean，并自行调用 `LiteflowMeterBinder.bindTo(registry)` 绑定全局 Gauge。Solon 会把用户注册的 `LifeCycle` Bean 加入 `LifeCycleHolder`。

纯 Java 环境没有 Bean 扫描，必须手动完成两步：

```java
// 1. 注册执行钩子（否则永远不会被回调）
LifeCycleHolder.addLifeCycle(new ChainMetricsLifeCycle(registry));
LifeCycleHolder.addLifeCycle(new NodeMetricsLifeCycle(registry));
// 2. 注册表 / slot 池 Gauge 手动 bindTo
new LiteflowMeterBinder(config).bindTo(registry);
```

`/actuator/liteflow` 结构端点由 Spring Boot Actuator 自动配置提供，Solon 与纯 Java 环境不会自动拥有该端点；完成上述注册后，Micrometer 指标本身仍可照常采集。

## 9. 性能与基数

- 未引入 metrics 时开销接近零（node 钩子在 `NodeComponent.execute()` 的 finally 只多一次空列表判断）；引入后亚微秒级，通常 < 1%（Meter 按 tag 组合缓存，`timer.record` 是几次 LongAdder.add）。
- 基数控制：chain + node 两级 → 内存 O(chain 数 + node 数)，几千量级仅几 MB。已规避：不用 node-in-chain 三级组合、exception 只取类 simpleName、不含 requestId/完整异常 message。

## 10. 快速核对清单与集成资产

- 依赖：starter + actuator + registry；`exposure.include` 含 `liteflow,prometheus`；`curl /actuator/prometheus | grep liteflow_` 有输出。
- 开箱即用的 Prometheus + Grafana `docker-compose.yml`、`prometheus.yml`、「LiteFlow 概览」仪表盘 JSON 在仓库 `docs/metrics-integration/`（演示用，生产自行加固）。
- 源码：`liteflow-metrics/`（`ChainMetricsLifeCycle` / `NodeMetricsLifeCycle` / `LiteflowMeterBinder` / `LiteflowMetaView`）；starter 侧装配 `liteflow-spring-boot-starter/.../metrics/LiteflowMetricsAutoConfiguration.java` + `LiteflowEndpoint.java`（boot4 同名）。node 指标钩子基于 core 新增的 `PostProcessNodeExecuteLifeCycle`（见 `references/lifecycle.md`）。

## 11. 从指标到 Grafana 曲线

源码仓库 `docs/metrics-integration/` 包含 docker-compose.yml、prometheus.yml 和 Grafana provisioning／仪表盘。先在应用引入 starter、actuator 和 prometheus registry，暴露端点，再将 Prometheus scrape target 设置为应用可达的管理端口。

在该目录执行 `docker compose up -d`。Prometheus 默认 9090，打开 Targets 确认应用为 UP；Grafana 默认 3000，演示 compose 默认开启匿名 Admin 访问并预置 LiteFlow 仪表盘。容器里 localhost 指向容器自身，宿主应用在 Docker Desktop 可用 host.docker.internal，Linux 按网络配置处理。

连续执行一条真实 chain 产生流量；先用 `/actuator/prometheus` 确认有 liteflow 指标，再排查 scrape target、数据源和看板时间范围。未执行节点没有执行 Timer 样本。演示匿名访问和默认凭据不能直接沿用于公网服务。具体端口／凭据以 compose 文件为准。
