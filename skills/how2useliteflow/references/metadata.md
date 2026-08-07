> 来源：`docs/04.v2.16.X文档/120.🍼元数据管理/` 下 010~040 四篇官方文档，对齐 LiteFlow v2.16.X。
> 本篇只覆盖元数据操作器、平滑热刷新、启动不检查规则/脚本。API 以官方文档为准；文档未展开的细节标注"（以源码/官方文档为准）"。

# 元数据管理（metadata）

LiteFlow 里最核心的两个概念是 **规则（Chain）** 和 **组件（Node）**。框架提供元数据管理器 `LiteflowMetaOperator` 来在运行期用代码动态查询、刷新、卸载这两类元数据；同时提供平滑热刷新机制和多档启动校验开关。

## 一、元数据操作器 LiteflowMetaOperator

**版本支持：v2.13.0+**

> 说明：官方"元数据操作器"文档列出的方法全部挂在 `LiteflowMetaOperator` 上。早期版本中类似能力存在于 `FlowBus`，但 v2.16.X 文档示例统一用 `LiteflowMetaOperator`。本篇以官方文档列出的 API 为准；`FlowBus` 是否仍保留同名方法未在本文档展开（以源码/官方文档为准）。

### 1. 查询类方法

| 方法签名 | 作用 |
| --- | --- |
| `Chain getChain(String chainId)` | 通过 chainId 拿到 Chain 对象 |
| `List<Chain> getChainsContainsNodeId(String nodeId)` | 找出所有包含指定 nodeId 的 Chain |
| `List<Node> getNodes(Executable executable)` | 从任意 `Executable`（包括 Chain、Condition、Node）中取出 Node 列表 |
| `List<Node> getNodes(String chainId)` | 通过 chainId 拿到该 Chain 中所有 Node |
| `List<Node> getNodesInAllChain(String nodeId)` | 通过 nodeId 找到在所有 Chain 中存在的 Node 列表 |

典型用法——排查某个组件被哪些链路引用、检查某条链路里的全部组件：

```java
// 1. 拿到 Chain 对象
Chain chain = LiteflowMetaOperator.getChain("chain1");

// 2. 这条链路里都用了哪些 Node
List<Node> nodesInChain = LiteflowMetaOperator.getNodes("chain1");

// 3. 反查：nodeId = "a" 的组件被哪些 Chain 引用（排查组件改动影响面）
List<Chain> affected = LiteflowMetaOperator.getChainsContainsNodeId("a");

// 4. 也可以直接从任意 Executable 对象里取 Node（Chain/Condition/Node 都行）
List<Node> nodesFromAny = LiteflowMetaOperator.getNodes(someCondition);
```

### 2. 节点实例 ID 查询（需开启 `liteflow.enable-node-instance-id=true`）

当同一个 `nodeId` 在一条 Chain 中出现多次（例如 `THEN(a, b, a)` 中的 `a`），仅靠 nodeId 无法定位到具体某一次出现。开启 `liteflow.enable-node-instance-id=true` 后，每个 Node 会带一个在 Chain 内唯一的 **节点实例 ID（nodeInstanceId）**，可用下面 5 个方法精确定位（此 API 族官方"元数据操作器"文档未展开，以源码 `LiteflowMetaOperator.java` 为准）。

| 方法签名 | 作用 |
| --- | --- |
| `List<Node> getNodes(String chainId, String nodeId)` | 取该 nodeId 在 Chain 中 **每一次出现** 的 Node 列表 |
| `Node getNode(String chainId, String nodeInstanceId)` | 通过 nodeInstanceId 取唯一 Node |
| `Node getNode(String chainId, String nodeId, int index)` | 通过 nodeId + 序号取 Node（index 从 0 开始） |
| `int getNodeIndex(String chainId, String nodeInstanceId)` | 查 nodeInstanceId 在 Chain 中的位置（从 0 开始） |
| `List<String> getNodeInstanceIds(String chainId, String nodeId)` | 取该 nodeId 的全部 instanceId |

要点：
- **必须开启 `liteflow.enable-node-instance-id=true`**（默认 `false`）。源码 javadoc 明确：只有开启该开关，Node 对象才会携带 instanceId，上述方法才有意义；未开启时调用结果无意义。
- **core 自带默认实现，无需插件**：`DefaultNodeInstanceIdManageSpiImpl`（`@since 2.13.0`）由 `liteflow-core` 提供，通过 Java ServiceLoader 加载，找不到第三方 SPI 时自动兜底。其持久化方式是把每个 Chain 的 instanceId 列表写入本地 `.node_instance_id/<chainId>` 文件（基于 `user.dir`）。
- 典型场景：同一 nodeId 在一条 Chain 中出现多次时，区分并定位到具体某一次节点（例如分别排查执行结果、定向操作单次节点）。

```java
// 假设 chain1 = THEN(a, b, a)，其中 a 出现了 2 次
// 1. 取 a 的全部 instanceId（共 2 个）
List<String> ids = LiteflowMetaOperator.getNodeInstanceIds("chain1", "a");

// 2. 用 instanceId 反查 Node 和它在 Chain 中的位置
Node node = LiteflowMetaOperator.getNode("chain1", ids.get(0));
int pos = LiteflowMetaOperator.getNodeIndex("chain1", ids.get(0));

// 3. 也可以直接用 nodeId + index 定位（index 从 0 开始），取第 1 个 a
Node firstA = LiteflowMetaOperator.getNode("chain1", "a", 0);
```

### 3. 刷新与卸载类方法

| 方法签名 | 作用 |
| --- | --- |
| `void reloadAllChain()` | 刷新所有规则（全量） |
| `void reloadOneChain(String chainId, String el)` | 用新的 EL 刷新指定规则，自动替换缓存 |
| `void reloadOneChain(String chainId, String el, String routeEl)` | 刷新指定规则并同时刷新决策路由（v2.12.2+，决策路由详见对应章节） |
| `void removeChain(String chainId)` | 从元数据中卸载单个 chain |
| `void removeChain(String... chainIds)` | 批量卸载多个 chain |

卸载示例：

```java
// 卸载单个
LiteflowMetaOperator.removeChain("chain1");

// 批量卸载
LiteflowMetaOperator.removeChain("chain1", "chain2", "chain3");
```

---

## 二、平滑热刷新

### 1. 机制要点

- 不重启服务即可重载规则，且 **高并发下完全平滑**：刷新瞬间正在执行的线程走旧流程，**不会被中断**；刷新完成后，后续请求自动切换到新流程。
- 热刷新范围同时覆盖 **规则** 和 **脚本**。

### 2. 自动刷新场景（无需写代码）

| 场景 | 触发方式 | 备注 |
| --- | --- | --- |
| zk / etcd / nacos / apollo 配置源 | 规则变更后自动平滑刷新 | 用 LiteFlow 原生插件即可 |
| 本地磁盘规则文件 + 自动监听 | 文件变更后自动刷新 | 需开启自动监听（见"本地规则文件监听"章节） |
| sql / redis 配置源 + 轮询开关 | 更新规则/脚本后自动平滑热刷新 | 受轮询间隔影响，**有一定延时** |

### 3. 主动代码刷新

适用于数据库存储规则、或自定义配置源的场景。下面三类方法都来自 `LiteflowMetaOperator`。

**全量刷新：**

```java
LiteflowMetaOperator.reloadAllChain();
```

> - 按启动时的方式重新拉取所有规则与组件配置，做一次平滑热刷新。
> - 性能：官方实测每秒可刷新约 1000 条规则，属于 CPU 级操作；规则未到大几千、几万条时推荐用全量刷新。
> - **多节点部署务必每个节点都刷新**：规则存在于 JVM 内存，RPC（如 dubbo）接口只会打到其中一个节点。推荐做法：通过 MQ 广播一条消息，各节点监听后各自刷新。

**刷新单条规则：**

```java
LiteflowMetaOperator.reloadOneChain("chain1", "THEN(a, b, c)");
```

> - 适用于规则量很大（成千上万条）或只想刷新改动项的场景。
> - 需自行获取改动后的 EL 内容传入；方法会 **自动替换缓存中已有的规则**，无需在 build 前销毁旧流程。
> - 多节点部署同样需每个节点都刷新。

**刷新单条带决策路由的规则（v2.12.2+）：**

```java
// 第三个参数为决策路由 EL，例如 AND(r1, r2)
LiteflowMetaOperator.reloadOneChain("chain1", "THEN(a, b, c)", "AND(r1, r2)");
```

> 官方"平滑热刷新"文档此处原文提到"可以通过 FlowBus 连带决策体一起刷新"，但给出的示例代码用的是 `LiteflowMetaOperator.reloadOneChain(chainId, el, routeEl)`。本篇以代码示例为准。

**刷新单个脚本：**

```java
LiteflowMetaOperator.reloadScript(nodeId, script);
```

---

## 三、启动不检查规则 / 不检查脚本

### 1. 背景

默认情况下，LiteFlow 在启动期会解析所有规则，但协作开发时常出现"规则里写了某组件、但该组件还没开发完"的情况，导致启动报错。通过 `parse-mode` 可以把校验推迟到首次执行时。

### 2. 配置项 liteflow.parse-mode

```properties
liteflow.parse-mode=PARSE_ONE_ON_FIRST_EXEC
```

三档取值：

| 取值 | 含义 |
| --- | --- |
| `PARSE_ALL_ON_START` | 启动时解析所有规则（**默认值**，不配置即此项） |
| `PARSE_ALL_ON_FIRST_EXEC` | 启动时不解析；第一次执行任意规则时，解析所有规则 |
| `PARSE_ONE_ON_FIRST_EXEC` | 启动时不解析；第一次执行相关规则时，只解析对应规则 |

### 3. 官方建议与版本支持

- 想让启动期不检查规则，**直接设 `PARSE_ONE_ON_FIRST_EXEC`** 即可。
- **"启动不检查规则"**：v2.12.0+ 支持。
- **"启动不检查脚本"**：v2.13.0+ 才支持，但用的是 **同一个配置项** `liteflow.parse-mode=PARSE_ONE_ON_FIRST_EXEC`。低于 2.13.0 时该配置仅对规则生效，不对脚本生效。

### 4. 适用场景

- 多人协作、组件尚未就绪，但规则已先行提交，避免启动期校验失败。
- 按需加载、减少启动耗时的场景（规则非常多时，可推迟到首次执行）。
