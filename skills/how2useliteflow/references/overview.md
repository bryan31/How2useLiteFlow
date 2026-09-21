> 来源文档（相对 `liteflow-homepage/docs/04.v2.16.X文档/`）：
> - `010.LiteFlow简介.md`、`020.项目特性.md`
> - `030.🧁环境支持/010.JDK支持度.md`、`020.Springboot支持度.md`、`030.Spring的支持度.md`
> - `180.性能表现.md`
> - 模块目录与职责交叉验证自源码仓库 `liteFlow/`（`README.zh-CN.md` + 各模块 `liteflow-*` 目录）
>
> 本文档对齐 **LiteFlow 2.16.2**。

# LiteFlow 框架概览（2.16.2）

## 一句话定位

LiteFlow 是一个**编排式的规则引擎框架**——用 DSL 规则（XML/JSON/YML）把业务逻辑拆成一个个独立组件并任意编排，组件可热刷新、可用脚本写、可对接大模型。它**为解耦复杂业务逻辑而生**，适用于价格引擎、下单流程这类步骤多、易变动的核心业务。

一句话区分边界：LiteFlow 只做**基于逻辑的流转**，不做基于角色/任务的工作流审批（如 A 审批完流转给 B）。后者请用 flowlong / flowable。

## 核心概念与执行模型（高层）

LiteFlow 基于**工作台模式**：组件 = 工人，编排顺序 = 工人座次，上下文(Context) = 工作台，参数 = 工作台上的资源。工人之间互不通信、只看工作台，因而天然解耦、可替换、可复用、可实时插拔。

执行链路（点到为止，源码细节由专门文件展开）：

```
规则文件 (xml/json/yml) ──解析──▶ FlowExecutor
                                        │  编译装配
                                        ▼
                                    Chain（一条业务链）
                                        │  内部是一棵逻辑树
                                        ▼
                              Condition 树（THEN/WHEN/IF/
                                SWITCH/FOR/WHILE 等编排算子）
                                        │  叶子节点
                                        ▼
                              NodeComponent（业务组件）
            普通组件 / 脚本组件 / 声明式组件 / LiteFlow Agent 组件
```

- **FlowExecutor**：入口执行器，负责解析规则、注册组件、装配元信息，并触发链路执行（大部分解析装配在启动期完成）。
- **Chain**：一条编排好的业务链，是规则在运行期的载体。
- **Condition 树**：Chain 内部的逻辑骨架，由编排算子（`THEN` 串行 / `WHEN` 并行 / `IF` 选择 / `SWITCH` / `FOR`/`WHILE`/`ITERATOR` 循环等）递归嵌套而成。
- **NodeComponent**：叶子节点，即一个个业务组件；运行时**上下文(Context)在组件间流转**，组件只读写上下文、互不直接依赖。

> 上述类名（`FlowExecutor` / `Chain` / `Condition` / `NodeComponent`）已交叉验证存在于 `liteflow-core`。具体 API、注解、签名以源码与官方文档为准。

## 模块地图

源码仓库 `liteFlow/` 顶层模块（与职责简述）：

| 模块 | 职责 |
| --- | --- |
| **liteflow-core** | 框架内核：规则解析、组件体系（`NodeComponent` 等）、编排引擎、上下文机制等核心能力，所有场景都依赖它。 |
| **liteflow-el-builder** | EL 表达式构建器，用于用 Java 代码**编程式拼装编排表达式**（`ELBus.then(...)` / `when(...)` / `ifOpt(...)` / `switchOpt(...)` 等 Wrapper，循环为 `forOpt(...)` / `whileOpt(...)` / `iteratorOpt(...)`，对应 `THEN`/`WHEN`/`IF`/`SWITCH`/`FOR`/`WHILE`/`ITERATOR` 算子；全量入口见 `references/dynamic-build.md`）。 |
| **liteflow-script-plugin** | 脚本语言插件聚合，含 11 个子模块（见下）。 |
| **liteflow-rule-plugin** | 规则持久化插件聚合，含 6 个子模块（见下）。 |
| **liteflow-rule-db** | **v2.16.1 新增**：统一规则数据库聚合模块，规则/脚本以存储为权威源，含 sql / postgresql / mongodb / redis / zk / etcd / nacos 7 个插件与统一发布 API，与 `rule-source` 模式互斥（见 `references/rule-db.md`）。 |
| **liteflow-metrics** | **v2.16.1 新增**：基于 Micrometer 的 chain/node 指标与 LiteFlow 结构视图；starter 会传递依赖（见 `references/metrics.md`）。 |
| **liteflow-spring** | 纯 Spring（非 SpringBoot）场景的集成支持。 |
| **liteflow-spring-boot-starter** | SpringBoot 2.X / 3.X 场景的官方 starter。 |
| **liteflow-spring-boot4-starter** | SpringBoot 4.X 场景的专用 starter（API 差异较大，**勿与上面那个混用**）。 |
| **liteflow-solon-plugin** | 国产 Solon 应用框架的集成支持（非 Spring 系生态的另一选择）。 |
| **liteflow-agent** | **v2.16.0 首次引入，2.16.2 迁移到 AgentScope 2**：把 Agent 封装成 LiteFlow 组件。包含本次 Jev 更新的聚合模块含 core / jev / openai / anthropic / gemini / dashscope / redis / mysql / a2a 共 9 个子模块。模型、工具、会话、事件、HITL、Harness 与远程 Agent 见 [agent.md](agent.md)；独立的 Jev 智能选择见 [agent-jev.md](agent-jev.md)。要求 **JDK 17+**。 |
| **liteflow-testcase-el** | EL 编排相关的测试用例集合（2000+ 测试用例的覆盖来源之一）。 |

> 另有 `liteflow-benchmark`（基准压测）辅助模块，一般业务接入不直接依赖（以源码为准）。v2.16.1 起新增两个模块：**`liteflow-rule-db`**（统一规则数据库聚合模块，含 sql / postgresql / mongodb / redis / zk / etcd / nacos 7 个插件 + publisher 统一发布 API，见 `references/rule-db.md`）与 **`liteflow-metrics`**（指标监控模块，基于 Micrometer，已是 `liteflow-spring-boot-starter` / `liteflow-spring-boot4-starter` 的传递依赖，用 starter 无需单独引入，见 `references/metrics.md`）。

### liteflow-script-plugin 的 11 个子模块

官方文档明确支持的脚本语言有 8 种：**Groovy、Java、Kotlin、JavaScript、QLExpress、Python、Lua、Aviator**——均"和 Java 全打通"，可调用 Java 方法、引用任意实例，甚至脚本内调 RPC。仓库实际提供 11 个子模块：

| 子模块 | 说明 |
| --- | --- |
| `liteflow-script-groovy` | Groovy 脚本（官方明确） |
| `liteflow-script-java` | Java 脚本（官方明确） |
| `liteflow-script-kotlin` | Kotlin 脚本（官方明确） |
| `liteflow-script-javascript` | JavaScript 脚本（官方明确） |
| `liteflow-script-qlexpress` | QLExpress 脚本（官方明确） |
| `liteflow-script-python` | Python 脚本（官方明确） |
| `liteflow-script-lua` | Lua 脚本（官方明确） |
| `liteflow-script-aviator` | Aviator 脚本（官方明确） |
| `liteflow-script-graaljs` | 基于 GraalVM GraalJS 的脚本运行时（具体能力/多语言支持以源码为准） |
| `liteflow-script-javax` | 基于 `javax.script`（JSR-223）的通用脚本适配（具体引擎以源码为准） |
| `liteflow-script-javax-pro` | `javax.script` 的增强版本（具体差异以源码为准） |

> 后三个子模块官方"必读文档"未单独描述，按需取用、具体行为以源码/官方文档为准。

### liteflow-rule-plugin 的 6 个子模块

官方明确原生支持的规则存储后端，对应 6 个子模块，把规则存到外部存储以支持热刷新与集群：

| 子模块 | 后端 |
| --- | --- |
| `liteflow-rule-sql` | 标准结构化数据库 |
| `liteflow-rule-zk` | Zookeeper |
| `liteflow-rule-nacos` | Nacos |
| `liteflow-rule-etcd` | Etcd |
| `liteflow-rule-apollo` | Apollo |
| `liteflow-rule-redis` | Redis |

也支持自行扩展接口把规则存到任何地方。

## 环境支持度

### JDK

- 最低 **JDK 8**，**v2.15.0（含）以上版本（即 v2.16.X）支持 JDK 8 ~ JDK 25**，直接依赖、无需任何 JVM 参数。
- 历史参考：v2.10.6 ~ v2.13.2 仅支持 JDK 8~17，且 JDK 9 以上需加 `--add-opens java.base/sun.reflect.annotation=ALL-UNNAMED`（v2.16.X 无此负担）。
- **JDK 21+ 原生支持虚拟线程**。
- 官方提供 2000+ 测试用例；测试数量与技能功能覆盖率不是同一指标。

### SpringBoot

- 支持 **SpringBoot 2.X ~ 4.X**，最低 2.0。需按大版本选 starter：

| SpringBoot 版本 | starter 依赖 | JDK 要求 |
| --- | --- | --- |
| 2.X ~ 3.X | `liteflow-spring-boot-starter` | JDK 8 及以上（**3.X 需 JDK 17+**） |
| 4.X | `liteflow-spring-boot4-starter` | **JDK 17 及以上** |

> SpringBoot 4.X 底层 API 变化大，必须用 `liteflow-spring-boot4-starter`，**不要在 4.X 里用普通 starter**。

### Spring（非 SpringBoot）

- 支持 **Spring 5.X ~ Spring 6.X**，最低 Spring 5.0。
- 用 Spring 6.X 需 JDK 17+。

### Solon

- 提供 `liteflow-solon-plugin` 用于 Solon 框架集成（支持度细节以官方文档为准）。

## 性能表现

- 框架**绝大部分工作在启动期完成**（解析规则、注册组件、装配元信息），执行链路时几乎无额外开销；核心代码做过专门性能优化。
- 实战压测：公司级核心业务、50+ 组件组成的链路，单点约 **1500 TPS**，集群 **1W+ TPS**，经历过双11、顶流带货等大流量。
- 官方 Demo（价格计算引擎，11 节点，mock 数据不走 DB IO）在 mac M3 Pro + JMeter 5.6 + SpringBoot 自带 Tomcat 下：300/600/900 并发各循环 300 次均有压测结果。
- **整体 TPS 取决于业务组件本身**：大量循环 DB IO、bad SQL、同步 RPC 都会拉低实际吞吐——这是组件问题，不是框架问题。

## 适用 / 不适用场景

**适用**：业务逻辑复杂、步骤多、易变动的核心系统（价格引擎、下单流程等），可按业务粒度拆成独立组件装配、复用、变更，避免"改一处动全身"。

**不适用**：基于角色/任务流转的审批工作流（A 审完转 B 审）——请用 flowlong / flowable。

## 常见坑 / 注意

- **SpringBoot 4.X 必须用 `liteflow-spring-boot4-starter`**，两个 starter 不可混用。
- **SpringBoot 3.X / Spring 6.X 起需 JDK 17+**（这是 Spring 自身的 JDK 要求，不是 LiteFlow 单独限制）。
- **`liteflow-agent`（AI Agent）要求 JDK 17+**，2.16.2 基于 AgentScope Java 2.0.3；核心框架的 JDK 8+ 支持不等于 Agent 模块也能在 JDK 8 上运行。
- v2.16.X（≥ v2.15.0）在 JDK 9+ 下**无需**再加 `--add-opens` JVM 参数（老版本的旧坑已解决）。
- 脚本语言官方明确支持的是 8 种；仓库里的 `graaljs` / `javax` / `javax-pro` 子模块官方文档未单独说明，使用前以源码/官方文档为准。
- LiteFlow **不是审批流引擎**，不要拿它做角色任务流转。
