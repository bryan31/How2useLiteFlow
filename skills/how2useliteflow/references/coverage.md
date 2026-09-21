# LiteFlow 2.16.2 技能覆盖报告

核验日期：2026-09-19。知识基线：LiteFlow 2.16.2／AgentScope 2.0.3。
源码提交：`8623451380ee32e2d9eefd3e5f2e721a68482a28`；官网提交：`e50a2e15cc9641c4444a04faed97742349b43113`。以工作区实际文件为准，包含尚未提交的官网文档；文件 SHA-256 记录在 [coverage-map.json](coverage-map.json)。

**已覆盖 239／249 个功能单元，覆盖率 95.98%，目标至少 90%。**

## 口径

核心范围为官网 2.16.X 的每个 Markdown 页面；Rule-DB、Metrics 页面与源码 guide 重复，仅按 guide 计算。Agent、Rule-DB、Metrics 三份 guide 按三级标题划分；没有三级标题的二级章节独立计数。四级及更深内容归入所属单元，代码块中的注释不算标题。旧版文档、英文重复页面、宣传／更新日志不计入。

covered 表示 reference 含本单元的主要用法、配置或 API 以及关键边界，并列出对应源码证据；partial 表示已提供部分说明但不足以代替该章节，按零分计；missing 也按零分计。每个单元等权，各分组也必须达到 90%。

这是人工复核的文档功能覆盖率，不是 Java 行覆盖率、所有公开 API 的覆盖率或实测问答准确率。脚本校验分母完整性、文件指纹、reference 标题、源码证据与统计，不自动判断语义正确；只有读过正文才能更新 covered 状态。

| 范围 | 已覆盖 | 部分 | 未覆盖 | 覆盖率 |
|---|---:|---:|---:|---:|
| agent | 37/38 | 1 | 0 | 97.37% |
| core | 117/122 | 5 | 0 | 95.90% |
| metrics | 29/30 | 1 | 0 | 96.67% |
| rule-db | 56/59 | 3 | 0 | 94.92% |

## 未计入覆盖的部分

- agent／7. 配置速查 / 7.5 模型参数与组件扩展：扩展入口已列出，但 ArtifactDeliveryTarget 自定义交付及所有平台原生参数没有完整实现配方；需按源码扩展。
- rule-db／6. 配置参考 / etcd 专属配置（`liteflow-rule-db-etcd`）：已覆盖 TLS 入口和校验原则，未逐项展开 keepalive／连接参数默认值及完整 mTLS 配方。
- rule-db／7. 存储结构参考 / 7.5 PostgreSQL 四张表：已列四表结构与 DDL 位置，未内置 PostgreSQL 全字段 DDL。
- rule-db／7. 存储结构参考 / 7.6 MongoDB Collection：已说明四个 Collection、事务与索引要求，未内置全部文档字段和索引定义。
- metrics／5. 三个端点分别返回什么 / 5.1 结构端点 `/actuator/liteflow`：端点、字段和空值语义已覆盖，未复刻 guide 的全部 JSON 响应样例。
- core／005.Java脚本引擎.md：提供依赖、共同接口和部分示例，未内置该引擎全部专用语法／选型说明。
- core／010.Groovy脚本引擎.md：提供依赖、共同接口和部分示例，未内置该引擎全部专用语法／选型说明。
- core／020.Javascript脚本引擎.md：提供依赖、共同接口和部分示例，未内置该引擎全部专用语法／选型说明。
- core／040.QLExpress脚本引擎.md：提供依赖、共同接口和部分示例，未内置该引擎全部专用语法／选型说明。
- core／180.性能表现.md：保留历史性能资料与调优原则，未复现实测基准，不将历史吞吐量作为当前保证。

## 复查

```bash
python3 skills/how2useliteflow/scripts/audit-coverage.py \
  --source /path/to/LiteFlow-Jdk17 \
  --homepage /path/to/liteflow-homepage
```

新增／删除章节、证据文件或已核验文档发生变化会使校验失败，须先重新审阅清单；脚本不会自动把新增内容标为已覆盖。核验通过后用 `--write-report` 更新本报告。Skill 结构另用 skill-creator 的 quick_validate.py 校验。

## 本次验证

- 2026-09-21 Jev provider 文档更新：依据 JevConfig、JevProvider、JevChoiceClient 与现有 provider 测试核对 TypeSafe／OpenRouter 的默认地址、模型、路径、覆盖规则及属性绑定失败时机。Skill 结构、5 个 Jev YAML 示例和本次修改的本地链接校验通过；本次未重跑 Java 测试或调用真实模型。全量覆盖审计仍因缺少 docs/liteflow-rule-db-guide.md 中止，历史覆盖分母保持不变。
- 2026-09-21 Jev 增量：[agent-jev.md](agent-jev.md) 依据源码提交 `ad5c12dd6e4cf6a4df8bf99cefea85019422f66e` 之上的本次工作区更新核验，源码与 reference 指纹已记录；Jev 尚未纳入原三份 guide／官网页面清单，不改变上方 2026-09-19 的历史覆盖分母。
- 2026-09-21 Jev 验证：31 项离线测试全部通过；从 reference 提取 SupportRouter 与 SupportContext，使用当前 reactor 类路径和 javac --release 17 编译通过；Skill 结构校验通过。
- 2026-09-21 全量覆盖审计未能完成：当前源码缺少原基线的 docs/liteflow-rule-db-guide.md 与 docs/liteflow-metrics-guide.md。保留原清单与指纹，恢复匹配文档后再运行完整审计；没有把缺失文档移出分母或把历史验证当作本次重跑结果。
- 2026-09-19 基线验证：skill-creator 的 quick_validate.py 通过，Shell 脚本语法检查通过。
- 2026-09-19 基线验证：65 项相关离线测试通过：默认值、Spring Boot 2/3 与 Boot 4 绑定、ExecuteOption 链路、身份、历史、工作区锁、压缩、Skills、最小接入；Shell 测试在允许本地进程执行的环境复跑通过。
- 2026-09-19 基线验证：从 reference 提取 ChatAgentCmp 与 A2A 组件／鉴权覆写，使用当前 reactor 类路径和 javac --release 17 编译通过。
- 2026-09-19 基线验证：覆盖审计的负例验证包括遗漏单元、新增章节、失效标题、源码变化、重复条目和低于 90% 的分组，全部拒绝；代码块伪标题不进入分母。
- 2026-09-19 基线验证：没有调用真实模型、启动 Docker／数据库集成测试或重新执行全仓库测试；本报告不据此承诺平台连通性或全仓库测试结果。

## 逐项映射

源码文件路径和 SHA-256 见 coverage-map.json 的 evidence 字段；以下链接直达技能正文。

### agent

| 文档功能单元 | 状态 | 技能位置 |
|---|---|---|
| 1. 快速开始 / 1.1 添加依赖 | covered | [agent.md：2.1 依赖](agent.md#21-%E4%BE%9D%E8%B5%96) |
| 1. 快速开始 / 1.2 添加配置 | covered | [agent.md：2.2 最小配置](agent.md#22-%E6%9C%80%E5%B0%8F%E9%85%8D%E7%BD%AE) |
| 1. 快速开始 / 1.3 编写 Agent 组件 | covered | [agent.md：2.3 组件](agent.md#23-%E7%BB%84%E4%BB%B6) |
| 1. 快速开始 / 1.4 编写流程 | covered | [agent.md：2.4 EL](agent.md#24-el) |
| 1. 快速开始 / 1.5 接收流式输出并获取最终结果 | covered | [agent.md：9. 启动验证与结果流](agent.md#9-%E5%90%AF%E5%8A%A8%E9%AA%8C%E8%AF%81%E4%B8%8E%E7%BB%93%E6%9E%9C%E6%B5%81) |
| 1. 快速开始 / 1.6 启动与验证 | covered | [agent.md：9. 启动验证与结果流](agent.md#9-%E5%90%AF%E5%8A%A8%E9%AA%8C%E8%AF%81%E4%B8%8E%E7%BB%93%E6%9E%9C%E6%B5%81) |
| 2. 会话与存储 / 2.1 延续同一段对话 | covered | [agent-state-events-hitl.md：1. 会话身份与续聊](agent-state-events-hitl.md#1-%E4%BC%9A%E8%AF%9D%E8%BA%AB%E4%BB%BD%E4%B8%8E%E7%BB%AD%E8%81%8A) |
| 2. 会话与存储 / 2.2 选择存储方式 | covered | [agent-state-events-hitl.md：2. Session 存储](agent-state-events-hitl.md#2-session-%E5%AD%98%E5%82%A8) |
| 2. 会话与存储 / 2.3 JSON：不需要额外依赖 | covered | [agent-state-events-hitl.md：JSON](agent-state-events-hitl.md#json) |
| 2. 会话与存储 / 2.4 Redis：添加依赖和连接配置 | covered | [agent-state-events-hitl.md：Redis](agent-state-events-hitl.md#redis) |
| 2. 会话与存储 / 2.5 MySQL：添加依赖和连接配置 | covered | [agent-state-events-hitl.md：MySQL](agent-state-events-hitl.md#mysql) |
| 2. 会话与存储 / 2.6 查询和删除聊天记录 | covered | [agent-state-events-hitl.md：3. 聊天历史 API](agent-state-events-hitl.md#3-%E8%81%8A%E5%A4%A9%E5%8E%86%E5%8F%B2-api) |
| 2. 会话与存储 / 2.7 部署时保持这几个设置一致 | covered | [agent-state-events-hitl.md：7. 会话与工作区并发](agent-state-events-hitl.md#7-%E4%BC%9A%E8%AF%9D%E4%B8%8E%E5%B7%A5%E4%BD%9C%E5%8C%BA%E5%B9%B6%E5%8F%91) |
| 3. 本地与 Docker / 3.1 开启命令工具 | covered | [agent-harness.md：1. 默认能力与权限](agent-harness.md#1-%E9%BB%98%E8%AE%A4%E8%83%BD%E5%8A%9B%E4%B8%8E%E6%9D%83%E9%99%90) |
| 3. 本地与 Docker / 3.2 本地模式 | covered | [agent-harness.md：GUARDED_LOCAL](agent-harness.md#guarded_local) |
| 3. 本地与 Docker / 3.3 Docker 模式 | covered | [agent-harness.md：DOCKER](agent-harness.md#docker) |
| 3. 本地与 Docker / 3.4 Docker 常用调整 | covered | [agent-harness.md：容器生命周期](agent-harness.md#%E5%AE%B9%E5%99%A8%E7%94%9F%E5%91%BD%E5%91%A8%E6%9C%9F) |
| 3. 本地与 Docker / 3.5 命令白名单与超时 | covered | [agent-harness.md：3. 命令白名单与超时](agent-harness.md#3-%E5%91%BD%E4%BB%A4%E7%99%BD%E5%90%8D%E5%8D%95%E4%B8%8E%E8%B6%85%E6%97%B6) |
| 3. 本地与 Docker / 3.6 给 Agent 提供文件 | covered | [agent-harness.md：4. 输入文件与附件交付](agent-harness.md#4-%E8%BE%93%E5%85%A5%E6%96%87%E4%BB%B6%E4%B8%8E%E9%99%84%E4%BB%B6%E4%BA%A4%E4%BB%98) |
| 4. 工具与 Skills / 4.1 添加 Java 业务工具 | covered | [agent-models-tools.md：3. Java 工具](agent-models-tools.md#3-java-%E5%B7%A5%E5%85%B7) |
| 4. 工具与 Skills / 4.2 接入 MCP 工具服务 | covered | [agent-models-tools.md：5. MCP 工具](agent-models-tools.md#5-mcp-%E5%B7%A5%E5%85%B7) |
| 4. 工具与 Skills / 4.3 添加 Skill | covered | [agent-models-tools.md：7. Skills](agent-models-tools.md#7-skills) |
| 4. 工具与 Skills / 4.4 限制可用技能 | covered | [agent-models-tools.md：7. Skills](agent-models-tools.md#7-skills) |
| 5. 模型与输出 / 5.1 更换模型平台 | covered | [agent-models-tools.md：1. 模型平台](agent-models-tools.md#1-%E6%A8%A1%E5%9E%8B%E5%B9%B3%E5%8F%B0) |
| 5. 模型与输出 / 5.2 接入自建模型服务 | covered | [agent-models-tools.md：2. ModelSpec 参数](agent-models-tools.md#2-modelspec-%E5%8F%82%E6%95%B0) |
| 5. 模型与输出 / 5.3 返回结构化结果 | covered | [agent-state-events-hitl.md：5. 结构化输出](agent-state-events-hitl.md#5-%E7%BB%93%E6%9E%84%E5%8C%96%E8%BE%93%E5%87%BA) |
| 5. 模型与输出 / 5.4 展示工具状态和流式内容 | covered | [agent-state-events-hitl.md：4. 事件与 Token 用量](agent-state-events-hitl.md#4-%E4%BA%8B%E4%BB%B6%E4%B8%8E-token-%E7%94%A8%E9%87%8F) |
| 6. 按需添加能力 / 6.1 编排多个 Agent | covered | [agent.md：3. 多 Agent 编排](agent.md#3-%E5%A4%9A-agent-%E7%BC%96%E6%8E%92) |
| 6. 按需添加能力 / 6.2 长对话与长期记忆 | covered | [agent-harness.md：6. 长期记忆与工具结果](agent-harness.md#6-%E9%95%BF%E6%9C%9F%E8%AE%B0%E5%BF%86%E4%B8%8E%E5%B7%A5%E5%85%B7%E7%BB%93%E6%9E%9C)、[agent-harness.md：5. 自动压缩与模型容量](agent-harness.md#5-%E8%87%AA%E5%8A%A8%E5%8E%8B%E7%BC%A9%E4%B8%8E%E6%A8%A1%E5%9E%8B%E5%AE%B9%E9%87%8F) |
| 6. 按需添加能力 / 6.3 工具调用前人工确认 | covered | [agent-state-events-hitl.md：6. 人工确认（HITL）](agent-state-events-hitl.md#6-%E4%BA%BA%E5%B7%A5%E7%A1%AE%E8%AE%A4hitl) |
| 6. 按需添加能力 / 6.4 让主 Agent 自行分派子任务 | covered | [agent-harness.md：7. 子代理、计划和任务](agent-harness.md#7-%E5%AD%90%E4%BB%A3%E7%90%86%E8%AE%A1%E5%88%92%E5%92%8C%E4%BB%BB%E5%8A%A1) |
| 6. 按需添加能力 / 6.5 调用其他服务中的 Agent | covered | [agent-a2a.md：2. 最小组件](agent-a2a.md#2-%E6%9C%80%E5%B0%8F%E7%BB%84%E4%BB%B6) |
| 7. 配置速查 / 7.1 常用设置 | covered | [agent-config.md：1. 常用设置](agent-config.md#1-%E5%B8%B8%E7%94%A8%E8%AE%BE%E7%BD%AE) |
| 7. 配置速查 / 7.2 存储设置 | covered | [agent-config.md：2. 存储设置](agent-config.md#2-%E5%AD%98%E5%82%A8%E8%AE%BE%E7%BD%AE) |
| 7. 配置速查 / 7.3 执行环境设置 | covered | [agent-config.md：3. 执行环境设置](agent-config.md#3-%E6%89%A7%E8%A1%8C%E7%8E%AF%E5%A2%83%E8%AE%BE%E7%BD%AE) |
| 7. 配置速查 / 7.4 Skills、记忆与调用协调 | covered | [agent-config.md：4. Skills、记忆与调用协调](agent-config.md#4-skills%E8%AE%B0%E5%BF%86%E4%B8%8E%E8%B0%83%E7%94%A8%E5%8D%8F%E8%B0%83) |
| 7. 配置速查 / 7.5 模型参数与组件扩展 | partial | [agent.md：8. 常用扩展点](agent.md#8-%E5%B8%B8%E7%94%A8%E6%89%A9%E5%B1%95%E7%82%B9) |
| 8. 常见问题 | covered | [agent-state-events-hitl.md：8. 排错入口](agent-state-events-hitl.md#8-%E6%8E%92%E9%94%99%E5%85%A5%E5%8F%A3)、[agent-harness.md：8. 故障定位](agent-harness.md#8-%E6%95%85%E9%9A%9C%E5%AE%9A%E4%BD%8D)、[agent-models-tools.md：8. 常见排查](agent-models-tools.md#8-%E5%B8%B8%E8%A7%81%E6%8E%92%E6%9F%A5) |

### core

| 文档功能单元 | 状态 | 技能位置 |
|---|---|---|
| 010.LiteFlow简介.md | covered | [overview.md：一句话定位](overview.md#%E4%B8%80%E5%8F%A5%E8%AF%9D%E5%AE%9A%E4%BD%8D) |
| 020.项目特性.md | covered | [overview.md：适用 / 不适用场景](overview.md#%E9%80%82%E7%94%A8--%E4%B8%8D%E9%80%82%E7%94%A8%E5%9C%BA%E6%99%AF) |
| 030.🧁环境支持/010.JDK支持度.md | covered | [overview.md：JDK](overview.md#jdk) |
| 030.🧁环境支持/020.Springboot支持度.md | covered | [overview.md：SpringBoot](overview.md#springboot) |
| 030.🧁环境支持/030.Spring的支持度.md | covered | [overview.md：Spring（非 SpringBoot）](overview.md#spring%E9%9D%9E-springboot) |
| 040.🍟快速开始(Hello world)/005.说明.md | covered | [quickstart.md：一、SpringBoot 场景（主线，完整最小示例）](quickstart.md#%E4%B8%80springboot-%E5%9C%BA%E6%99%AF%E4%B8%BB%E7%BA%BF%E5%AE%8C%E6%95%B4%E6%9C%80%E5%B0%8F%E7%A4%BA%E4%BE%8B) |
| 040.🍟快速开始(Hello world)/010.Springboot场景安装运行.md | covered | [quickstart.md：一、SpringBoot 场景（主线，完整最小示例）](quickstart.md#%E4%B8%80springboot-%E5%9C%BA%E6%99%AF%E4%B8%BB%E7%BA%BF%E5%AE%8C%E6%95%B4%E6%9C%80%E5%B0%8F%E7%A4%BA%E4%BE%8B) |
| 040.🍟快速开始(Hello world)/020.Spring场景安装运行.md | covered | [quickstart.md：二、Spring 场景（关键差异点）](quickstart.md#%E4%BA%8Cspring-%E5%9C%BA%E6%99%AF%E5%85%B3%E9%94%AE%E5%B7%AE%E5%BC%82%E7%82%B9) |
| 040.🍟快速开始(Hello world)/030.Solon场景安装运行.md | covered | [quickstart.md：三、Solon 场景（关键差异点）](quickstart.md#%E4%B8%89solon-%E5%9C%BA%E6%99%AF%E5%85%B3%E9%94%AE%E5%B7%AE%E5%BC%82%E7%82%B9) |
| 040.🍟快速开始(Hello world)/040.其他场景安装运行.md | covered | [quickstart.md：四、其他场景（非 Spring 体系）](quickstart.md#%E5%9B%9B%E5%85%B6%E4%BB%96%E5%9C%BA%E6%99%AF%E9%9D%9E-spring-%E4%BD%93%E7%B3%BB) |
| 050.🍢配置项/010.说明.md | covered | [config.md：一、总则](config.md#%E4%B8%80%E6%80%BB%E5%88%99) |
| 050.🍢配置项/020.Springboot下的配置项.md | covered | [config.md：二、SpringBoot 配置项完整表（主体）](config.md#%E4%BA%8Cspringboot-%E9%85%8D%E7%BD%AE%E9%A1%B9%E5%AE%8C%E6%95%B4%E8%A1%A8%E4%B8%BB%E4%BD%93) |
| 050.🍢配置项/030.Spring下的配置项.md | covered | [config.md：三、Spring（非 Boot）场景差异](config.md#%E4%B8%89spring%E9%9D%9E-boot%E5%9C%BA%E6%99%AF%E5%B7%AE%E5%BC%82) |
| 050.🍢配置项/035.Solon下的配置项.md | covered | [config.md：四、Solon 场景差异](config.md#%E5%9B%9Bsolon-%E5%9C%BA%E6%99%AF%E5%B7%AE%E5%BC%82) |
| 050.🍢配置项/040.其他场景代码设置配置项.md | covered | [config.md：五、纯代码场景差异（`LiteflowConfig` setter）](config.md#%E4%BA%94%E7%BA%AF%E4%BB%A3%E7%A0%81%E5%9C%BA%E6%99%AF%E5%B7%AE%E5%BC%82liteflowconfig-setter) |
| 060.🔗组件/010.🛍继承式组件/010.普通组件.md | covered | [components.md：1. 普通组件 `NodeComponent`](components.md#1-%E6%99%AE%E9%80%9A%E7%BB%84%E4%BB%B6-nodecomponent) |
| 060.🔗组件/010.🛍继承式组件/020.选择组件.md | covered | [components.md：2. 选择组件 `NodeSwitchComponent`](components.md#2-%E9%80%89%E6%8B%A9%E7%BB%84%E4%BB%B6-nodeswitchcomponent) |
| 060.🔗组件/010.🛍继承式组件/030.布尔组件.md | covered | [components.md：3. 布尔组件 `NodeBooleanComponent`（v2.12.0+）](components.md#3-%E5%B8%83%E5%B0%94%E7%BB%84%E4%BB%B6-nodebooleancomponentv2120) |
| 060.🔗组件/010.🛍继承式组件/040.次数循环组件.md | covered | [components.md：4. 次数循环组件 `NodeForComponent`（v2.9.0+）](components.md#4-%E6%AC%A1%E6%95%B0%E5%BE%AA%E7%8E%AF%E7%BB%84%E4%BB%B6-nodeforcomponentv290) |
| 060.🔗组件/010.🛍继承式组件/055.迭代循环组件.md | covered | [components.md：5. 迭代循环组件 `NodeIteratorComponent`（v2.9.7+）](components.md#5-%E8%BF%AD%E4%BB%A3%E5%BE%AA%E7%8E%AF%E7%BB%84%E4%BB%B6-nodeiteratorcomponentv297) |
| 060.🔗组件/010.🛍继承式组件/060.LiteflowComponent.md | covered | [components.md：二、`@LiteflowComponent` 与 nodeId 规则](components.md#%E4%BA%8Cliteflowcomponent-%E4%B8%8E-nodeid-%E8%A7%84%E5%88%99) |
| 060.🔗组件/010.🛍继承式组件/070.组件内方法覆盖和调用.md | covered | [components.md：三、组件内可覆盖的方法（生命周期钩子）](components.md#%E4%B8%89%E7%BB%84%E4%BB%B6%E5%86%85%E5%8F%AF%E8%A6%86%E7%9B%96%E7%9A%84%E6%96%B9%E6%B3%95%E7%94%9F%E5%91%BD%E5%91%A8%E6%9C%9F%E9%92%A9%E5%AD%90) |
| 060.🔗组件/020.🎁声明式组件/010.什么叫声明式组件.md | covered | [components.md：四、声明式组件](components.md#%E5%9B%9B%E5%A3%B0%E6%98%8E%E5%BC%8F%E7%BB%84%E4%BB%B6) |
| 060.🔗组件/020.🎁声明式组件/020.类级别式声明.md | covered | [components.md：1. 类级别式声明](components.md#1-%E7%B1%BB%E7%BA%A7%E5%88%AB%E5%BC%8F%E5%A3%B0%E6%98%8E) |
| 060.🔗组件/020.🎁声明式组件/030.方法级别式声明.md | covered | [components.md：2. 方法级别式声明（v2.9.0+）](components.md#2-%E6%96%B9%E6%B3%95%E7%BA%A7%E5%88%AB%E5%BC%8F%E5%A3%B0%E6%98%8Ev290) |
| 070.🧩EL规则/010.说明.md | covered | [el-rules.md：1. EL 总述](el-rules.md#1-el-%E6%80%BB%E8%BF%B0) |
| 070.🧩EL规则/020.串行编排.md | covered | [el-rules.md：2. 串行编排 THEN](el-rules.md#2-%E4%B8%B2%E8%A1%8C%E7%BC%96%E6%8E%92-then) |
| 070.🧩EL规则/030.并行编排.md | covered | [el-rules.md：3. 并行编排 WHEN](el-rules.md#3-%E5%B9%B6%E8%A1%8C%E7%BC%96%E6%8E%92-when) |
| 070.🧩EL规则/040.选择编排.md | covered | [el-rules.md：4. 选择编排 SWITCH](el-rules.md#4-%E9%80%89%E6%8B%A9%E7%BC%96%E6%8E%92-switch) |
| 070.🧩EL规则/050.条件编排.md | covered | [el-rules.md：5. 条件编排 IF（v2.8.5+）](el-rules.md#5-%E6%9D%A1%E4%BB%B6%E7%BC%96%E6%8E%92-ifv285) |
| 070.🧩EL规则/060.循环编排.md | covered | [el-rules.md：6. 循环编排（v2.9.0+）](el-rules.md#6-%E5%BE%AA%E7%8E%AF%E7%BC%96%E6%8E%92v290) |
| 070.🧩EL规则/070.异步循环模式.md | covered | [el-rules.md：6.7 异步循环模式（v2.11.0+）](el-rules.md#67-%E5%BC%82%E6%AD%A5%E5%BE%AA%E7%8E%AF%E6%A8%A1%E5%BC%8Fv2110) |
| 070.🧩EL规则/080.捕获异常表达式.md | covered | [el-rules.md：7. 捕获异常表达式 CATCH（v2.10.0+）](el-rules.md#7-%E6%8D%95%E8%8E%B7%E5%BC%82%E5%B8%B8%E8%A1%A8%E8%BE%BE%E5%BC%8F-catchv2100) |
| 070.🧩EL规则/090.与或非表达式.md | covered | [el-rules.md：8. 与或非表达式 AND / OR / NOT（v2.10.2+）](el-rules.md#8-%E4%B8%8E%E6%88%96%E9%9D%9E%E8%A1%A8%E8%BE%BE%E5%BC%8F-and--or--notv2102) |
| 070.🧩EL规则/100.使用子流程.md | covered | [el-rules.md：9.1 使用子流程](el-rules.md#91-%E4%BD%BF%E7%94%A8%E5%AD%90%E6%B5%81%E7%A8%8B) |
| 070.🧩EL规则/110.使用子变量.md | covered | [el-rules.md：9.2 使用子变量](el-rules.md#92-%E4%BD%BF%E7%94%A8%E5%AD%90%E5%8F%98%E9%87%8F) |
| 070.🧩EL规则/120.复杂编排例子.md | covered | [el-rules.md：17. 复杂编排例子（综合）](el-rules.md#17-%E5%A4%8D%E6%9D%82%E7%BC%96%E6%8E%92%E4%BE%8B%E5%AD%90%E7%BB%BC%E5%90%88) |
| 070.🧩EL规则/130.前置和后置编排.md | covered | [el-rules.md：10. 前置 PRE / 后置 FINALLY](el-rules.md#10-%E5%89%8D%E7%BD%AE-pre--%E5%90%8E%E7%BD%AE-finally) |
| 070.🧩EL规则/140.🍉组件参数语法/000.说明.md | covered | [el-rules.md：11. 组件参数语法（tag / data / bind）](el-rules.md#11-%E7%BB%84%E4%BB%B6%E5%8F%82%E6%95%B0%E8%AF%AD%E6%B3%95tag--data--bind) |
| 070.🧩EL规则/140.🍉组件参数语法/010.tag语法.md | covered | [el-rules.md：11.1 tag](el-rules.md#111-tag) |
| 070.🧩EL规则/140.🍉组件参数语法/020.data语法.md | covered | [el-rules.md：11.2 data（v2.9.0+）](el-rules.md#112-datav290) |
| 070.🧩EL规则/140.🍉组件参数语法/030.bind语法.md | covered | [el-rules.md：11.3 bind（v2.13.0+）](el-rules.md#113-bindv2130) |
| 070.🧩EL规则/150.重试语法.md | covered | [el-rules.md：12. 重试 retry（v2.12.0+）](el-rules.md#12-%E9%87%8D%E8%AF%95-retryv2120) |
| 070.🧩EL规则/160.超时控制语法.md | covered | [el-rules.md：13. 超时控制（v2.11.0+）](el-rules.md#13-%E8%B6%85%E6%97%B6%E6%8E%A7%E5%88%B6v2110) |
| 070.🧩EL规则/170.链路继承.md | covered | [el-rules.md：14. 链路继承（v2.12.0+，Beta 实验性）](el-rules.md#14-%E9%93%BE%E8%B7%AF%E7%BB%A7%E6%89%BFv2120beta-%E5%AE%9E%E9%AA%8C%E6%80%A7) |
| 070.🧩EL规则/180.验证规则.md | covered | [el-rules.md：15. 验证规则（v2.9.4+）](el-rules.md#15-%E9%AA%8C%E8%AF%81%E8%A7%84%E5%88%99v294) |
| 070.🧩EL规则/190.关于注释.md | covered | [el-rules.md：1. EL 总述](el-rules.md#1-el-%E6%80%BB%E8%BF%B0) |
| 070.🧩EL规则/200.关于分号.md | covered | [el-rules.md：1. EL 总述](el-rules.md#1-el-%E6%80%BB%E8%BF%B0) |
| 070.🧩EL规则/210.组件名包装.md | covered | [el-rules.md：16. 组件名包装 node](el-rules.md#16-%E7%BB%84%E4%BB%B6%E5%90%8D%E5%8C%85%E8%A3%85-node) |
| 080.🌮上下文/010.说明.md | covered | [context.md：上下文是什么](context.md#%E4%B8%8A%E4%B8%8B%E6%96%87%E6%98%AF%E4%BB%80%E4%B9%88) |
| 080.🌮上下文/020.数据上下文的定义和使用.md | covered | [context.md：定义与使用](context.md#%E5%AE%9A%E4%B9%89%E4%B8%8E%E4%BD%BF%E7%94%A8) |
| 080.🌮上下文/030.用初始化好的上下文传入.md | covered | [context.md：传入已初始化的上下文实例（v2.8.4+）](context.md#%E4%BC%A0%E5%85%A5%E5%B7%B2%E5%88%9D%E5%A7%8B%E5%8C%96%E7%9A%84%E4%B8%8A%E4%B8%8B%E6%96%87%E5%AE%9E%E4%BE%8Bv284) |
| 080.🌮上下文/040.给上下文设置别名.md | covered | [context.md：上下文别名](context.md#%E4%B8%8A%E4%B8%8B%E6%96%87%E5%88%AB%E5%90%8D) |
| 080.🌮上下文/050.上下文参数注入.md | covered | [context.md：上下文参数注入（v2.12.1+，仅声明式组件）](context.md#%E4%B8%8A%E4%B8%8B%E6%96%87%E5%8F%82%E6%95%B0%E6%B3%A8%E5%85%A5v2121%E4%BB%85%E5%A3%B0%E6%98%8E%E5%BC%8F%E7%BB%84%E4%BB%B6) |
| 080.🌮上下文/060.用表达式获取上下文参数.md | covered | [context.md：用 EL 表达式取/设上下文参数（v2.13.1+，通用）](context.md#%E7%94%A8-el-%E8%A1%A8%E8%BE%BE%E5%BC%8F%E5%8F%96%E8%AE%BE%E4%B8%8A%E4%B8%8B%E6%96%87%E5%8F%82%E6%95%B0v2131%E9%80%9A%E7%94%A8) |
| 090.🛩执行器/010.说明.md | covered | [executor.md：执行方法总览](executor.md#%E6%89%A7%E8%A1%8C%E6%96%B9%E6%B3%95%E6%80%BB%E8%A7%88) |
| 090.🛩执行器/020.执行方法.md | covered | [executor.md：执行方法总览](executor.md#%E6%89%A7%E8%A1%8C%E6%96%B9%E6%B3%95%E6%80%BB%E8%A7%88) |
| 090.🛩执行器/030.流程入参.md | covered | [executor.md：流程入参（param）](executor.md#%E6%B5%81%E7%A8%8B%E5%85%A5%E5%8F%82param) |
| 090.🛩执行器/040.LiteflowResponse对象.md | covered | [executor.md：LiteflowResponse 对象](executor.md#liteflowresponse-%E5%AF%B9%E8%B1%A1) |
| 090.🛩执行器/050.直接执行EL规则.md | covered | [executor.md：直接执行 EL 规则（不经规则文件）](executor.md#%E7%9B%B4%E6%8E%A5%E6%89%A7%E8%A1%8C-el-%E8%A7%84%E5%88%99%E4%B8%8D%E7%BB%8F%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6) |
| 100.🍋脚本组件/005.脚本语言介绍.md | covered | [scripts.md：一、概念与定位](scripts.md#%E4%B8%80%E6%A6%82%E5%BF%B5%E4%B8%8E%E5%AE%9A%E4%BD%8D) |
| 100.🍋脚本组件/010.🍫脚本语言种类/005.Java脚本引擎.md | partial | [scripts.md：三、支持的语言与依赖坐标](scripts.md#%E4%B8%89%E6%94%AF%E6%8C%81%E7%9A%84%E8%AF%AD%E8%A8%80%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%9D%90%E6%A0%87)、[scripts.md：四、规则文件中定义脚本节点](scripts.md#%E5%9B%9B%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6%E4%B8%AD%E5%AE%9A%E4%B9%89%E8%84%9A%E6%9C%AC%E8%8A%82%E7%82%B9)、[scripts.md：5.3 各语言差异要点](scripts.md#53-%E5%90%84%E8%AF%AD%E8%A8%80%E5%B7%AE%E5%BC%82%E8%A6%81%E7%82%B9) |
| 100.🍋脚本组件/010.🍫脚本语言种类/010.Groovy脚本引擎.md | partial | [scripts.md：三、支持的语言与依赖坐标](scripts.md#%E4%B8%89%E6%94%AF%E6%8C%81%E7%9A%84%E8%AF%AD%E8%A8%80%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%9D%90%E6%A0%87)、[scripts.md：四、规则文件中定义脚本节点](scripts.md#%E5%9B%9B%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6%E4%B8%AD%E5%AE%9A%E4%B9%89%E8%84%9A%E6%9C%AC%E8%8A%82%E7%82%B9)、[scripts.md：5.3 各语言差异要点](scripts.md#53-%E5%90%84%E8%AF%AD%E8%A8%80%E5%B7%AE%E5%BC%82%E8%A6%81%E7%82%B9) |
| 100.🍋脚本组件/010.🍫脚本语言种类/020.Javascript脚本引擎.md | partial | [scripts.md：三、支持的语言与依赖坐标](scripts.md#%E4%B8%89%E6%94%AF%E6%8C%81%E7%9A%84%E8%AF%AD%E8%A8%80%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%9D%90%E6%A0%87)、[scripts.md：四、规则文件中定义脚本节点](scripts.md#%E5%9B%9B%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6%E4%B8%AD%E5%AE%9A%E4%B9%89%E8%84%9A%E6%9C%AC%E8%8A%82%E7%82%B9)、[scripts.md：5.3 各语言差异要点](scripts.md#53-%E5%90%84%E8%AF%AD%E8%A8%80%E5%B7%AE%E5%BC%82%E8%A6%81%E7%82%B9) |
| 100.🍋脚本组件/010.🍫脚本语言种类/040.QLExpress脚本引擎.md | partial | [scripts.md：三、支持的语言与依赖坐标](scripts.md#%E4%B8%89%E6%94%AF%E6%8C%81%E7%9A%84%E8%AF%AD%E8%A8%80%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%9D%90%E6%A0%87)、[scripts.md：四、规则文件中定义脚本节点](scripts.md#%E5%9B%9B%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6%E4%B8%AD%E5%AE%9A%E4%B9%89%E8%84%9A%E6%9C%AC%E8%8A%82%E7%82%B9)、[scripts.md：5.3 各语言差异要点](scripts.md#53-%E5%90%84%E8%AF%AD%E8%A8%80%E5%B7%AE%E5%BC%82%E8%A6%81%E7%82%B9) |
| 100.🍋脚本组件/010.🍫脚本语言种类/050.Python脚本引擎.md | covered | [scripts.md：三、支持的语言与依赖坐标](scripts.md#%E4%B8%89%E6%94%AF%E6%8C%81%E7%9A%84%E8%AF%AD%E8%A8%80%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%9D%90%E6%A0%87)、[scripts.md：四、规则文件中定义脚本节点](scripts.md#%E5%9B%9B%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6%E4%B8%AD%E5%AE%9A%E4%B9%89%E8%84%9A%E6%9C%AC%E8%8A%82%E7%82%B9)、[scripts.md：5.3 各语言差异要点](scripts.md#53-%E5%90%84%E8%AF%AD%E8%A8%80%E5%B7%AE%E5%BC%82%E8%A6%81%E7%82%B9) |
| 100.🍋脚本组件/010.🍫脚本语言种类/060.Lua脚本引擎.md | covered | [scripts.md：三、支持的语言与依赖坐标](scripts.md#%E4%B8%89%E6%94%AF%E6%8C%81%E7%9A%84%E8%AF%AD%E8%A8%80%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%9D%90%E6%A0%87)、[scripts.md：四、规则文件中定义脚本节点](scripts.md#%E5%9B%9B%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6%E4%B8%AD%E5%AE%9A%E4%B9%89%E8%84%9A%E6%9C%AC%E8%8A%82%E7%82%B9)、[scripts.md：5.3 各语言差异要点](scripts.md#53-%E5%90%84%E8%AF%AD%E8%A8%80%E5%B7%AE%E5%BC%82%E8%A6%81%E7%82%B9) |
| 100.🍋脚本组件/010.🍫脚本语言种类/070.Aviator脚本引擎.md | covered | [scripts.md：三、支持的语言与依赖坐标](scripts.md#%E4%B8%89%E6%94%AF%E6%8C%81%E7%9A%84%E8%AF%AD%E8%A8%80%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%9D%90%E6%A0%87)、[scripts.md：四、规则文件中定义脚本节点](scripts.md#%E5%9B%9B%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6%E4%B8%AD%E5%AE%9A%E4%B9%89%E8%84%9A%E6%9C%AC%E8%8A%82%E7%82%B9)、[scripts.md：5.3 各语言差异要点](scripts.md#53-%E5%90%84%E8%AF%AD%E8%A8%80%E5%B7%AE%E5%BC%82%E8%A6%81%E7%82%B9) |
| 100.🍋脚本组件/010.🍫脚本语言种类/080.Kotlin脚本引擎.md | covered | [scripts.md：三、支持的语言与依赖坐标](scripts.md#%E4%B8%89%E6%94%AF%E6%8C%81%E7%9A%84%E8%AF%AD%E8%A8%80%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%9D%90%E6%A0%87)、[scripts.md：四、规则文件中定义脚本节点](scripts.md#%E5%9B%9B%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6%E4%B8%AD%E5%AE%9A%E4%B9%89%E8%84%9A%E6%9C%AC%E8%8A%82%E7%82%B9)、[scripts.md：5.3 各语言差异要点](scripts.md#53-%E5%90%84%E8%AF%AD%E8%A8%80%E5%B7%AE%E5%BC%82%E8%A6%81%E7%82%B9) |
| 100.🍋脚本组件/015.脚本与Java进行交互.md | covered | [scripts.md：六、脚本与 Java 交互](scripts.md#%E5%85%AD%E8%84%9A%E6%9C%AC%E4%B8%8E-java-%E4%BA%A4%E4%BA%92) |
| 100.🍋脚本组件/020.多脚本语言混合共存.md | covered | [scripts.md：七、多脚本语言混合共存（v2.10.0+）](scripts.md#%E4%B8%83%E5%A4%9A%E8%84%9A%E6%9C%AC%E8%AF%AD%E8%A8%80%E6%B7%B7%E5%90%88%E5%85%B1%E5%AD%98v2100) |
| 100.🍋脚本组件/030.文件脚本的定义.md | covered | [scripts.md：八、文件脚本（外部脚本文件）](scripts.md#%E5%85%AB%E6%96%87%E4%BB%B6%E8%84%9A%E6%9C%AC%E5%A4%96%E9%83%A8%E8%84%9A%E6%9C%AC%E6%96%87%E4%BB%B6) |
| 100.🍋脚本组件/050.动态刷新脚本.md | covered | [scripts.md：九、动态刷新 / 热更新脚本（v2.12.0+）](scripts.md#%E4%B9%9D%E5%8A%A8%E6%80%81%E5%88%B7%E6%96%B0--%E7%83%AD%E6%9B%B4%E6%96%B0%E8%84%9A%E6%9C%ACv2120) |
| 100.🍋脚本组件/060.验证脚本.md | covered | [scripts.md：十、验证脚本](scripts.md#%E5%8D%81%E9%AA%8C%E8%AF%81%E8%84%9A%E6%9C%AC) |
| 100.🍋脚本组件/070.卸载脚本.md | covered | [scripts.md：十一、卸载脚本（v2.12.0+）](scripts.md#%E5%8D%81%E4%B8%80%E5%8D%B8%E8%BD%BD%E8%84%9A%E6%9C%ACv2120) |
| 110.🗂规则配置源/020.本地规则文件配置.md | covered | [rule-sources.md：二、本地规则文件配置](rule-sources.md#%E4%BA%8C%E6%9C%AC%E5%9C%B0%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6%E9%85%8D%E7%BD%AE) |
| 110.🗂规则配置源/030.SQL数据库配置源.md | covered | [rule-sources.md：三、SQL 数据库配置源（`liteflow-rule-sql`，v2.9.0+）](rule-sources.md#%E4%B8%89sql-%E6%95%B0%E6%8D%AE%E5%BA%93%E9%85%8D%E7%BD%AE%E6%BA%90liteflow-rule-sqlv290) |
| 110.🗂规则配置源/040.ZK规则文件配置源.md | covered | [rule-sources.md：四、ZooKeeper 配置源（`liteflow-rule-zk`）](rule-sources.md#%E5%9B%9Bzookeeper-%E9%85%8D%E7%BD%AE%E6%BA%90liteflow-rule-zk) |
| 110.🗂规则配置源/050.Nacos配置源.md | covered | [rule-sources.md：五、Nacos 配置源（`liteflow-rule-nacos`，v2.9.0+）](rule-sources.md#%E4%BA%94nacos-%E9%85%8D%E7%BD%AE%E6%BA%90liteflow-rule-nacosv290) |
| 110.🗂规则配置源/060.Etcd配置源.md | covered | [rule-sources.md：六、Etcd 配置源（`liteflow-rule-etcd`，v2.9.0+）](rule-sources.md#%E5%85%ADetcd-%E9%85%8D%E7%BD%AE%E6%BA%90liteflow-rule-etcdv290) |
| 110.🗂规则配置源/065.Apollo配置源.md | covered | [rule-sources.md：七、Apollo 配置源（`liteflow-rule-apollo`，v2.9.5+）](rule-sources.md#%E4%B8%83apollo-%E9%85%8D%E7%BD%AE%E6%BA%90liteflow-rule-apollov295) |
| 110.🗂规则配置源/066.📑Redis配置源（旧）/010.配置说明.md | covered | [rule-sources.md：八、Redis 配置源（`liteflow-rule-redis`，v2.11.0+）](rule-sources.md#%E5%85%ABredis-%E9%85%8D%E7%BD%AE%E6%BA%90liteflow-rule-redisv2110) |
| 110.🗂规则配置源/066.📑Redis配置源（旧）/020.轮询模式配置.md | covered | [rule-sources.md：8.4 轮询模式额外参数与配置示例](rule-sources.md#84-%E8%BD%AE%E8%AF%A2%E6%A8%A1%E5%BC%8F%E9%A2%9D%E5%A4%96%E5%8F%82%E6%95%B0%E4%B8%8E%E9%85%8D%E7%BD%AE%E7%A4%BA%E4%BE%8B) |
| 110.🗂规则配置源/066.📑Redis配置源（旧）/030.订阅模式配置.md | covered | [rule-sources.md：8.5 订阅模式配置示例与约束](rule-sources.md#85-%E8%AE%A2%E9%98%85%E6%A8%A1%E5%BC%8F%E9%85%8D%E7%BD%AE%E7%A4%BA%E4%BE%8B%E4%B8%8E%E7%BA%A6%E6%9D%9F) |
| 110.🗂规则配置源/070.自定义配置源.md | covered | [rule-sources.md：九、自定义配置源（继承 `ClassXmlFlowELParser`）](rule-sources.md#%E4%B9%9D%E8%87%AA%E5%AE%9A%E4%B9%89%E9%85%8D%E7%BD%AE%E6%BA%90%E7%BB%A7%E6%89%BF-classxmlflowelparser) |
| 120.🍼元数据管理/010. 元数据操作器.md | covered | [metadata.md：一、元数据操作器 LiteflowMetaOperator](metadata.md#%E4%B8%80%E5%85%83%E6%95%B0%E6%8D%AE%E6%93%8D%E4%BD%9C%E5%99%A8-liteflowmetaoperator) |
| 120.🍼元数据管理/020.平滑热刷新.md | covered | [metadata.md：二、平滑热刷新](metadata.md#%E4%BA%8C%E5%B9%B3%E6%BB%91%E7%83%AD%E5%88%B7%E6%96%B0) |
| 120.🍼元数据管理/030.启动不检查规则.md | covered | [metadata.md：三、启动不检查规则 / 不检查脚本](metadata.md#%E4%B8%89%E5%90%AF%E5%8A%A8%E4%B8%8D%E6%A3%80%E6%9F%A5%E8%A7%84%E5%88%99--%E4%B8%8D%E6%A3%80%E6%9F%A5%E8%84%9A%E6%9C%AC) |
| 120.🍼元数据管理/040.启动不检查脚本.md | covered | [metadata.md：三、启动不检查规则 / 不检查脚本](metadata.md#%E4%B8%89%E5%90%AF%E5%8A%A8%E4%B8%8D%E6%A3%80%E6%9F%A5%E8%A7%84%E5%88%99--%E4%B8%8D%E6%A3%80%E6%9F%A5%E8%84%9A%E6%9C%AC) |
| 125.🌌异步中的线程池/010.说明.md | covered | [thread-pools.md：两层线程池总览](thread-pools.md#%E4%B8%A4%E5%B1%82%E7%BA%BF%E7%A8%8B%E6%B1%A0%E6%80%BB%E8%A7%88) |
| 125.🌌异步中的线程池/020.FlowExecutor层面的线程池.md | covered | [thread-pools.md：FlowExecutor 层：主执行器线程池](thread-pools.md#flowexecutor-%E5%B1%82%E4%B8%BB%E6%89%A7%E8%A1%8C%E5%99%A8%E7%BA%BF%E7%A8%8B%E6%B1%A0) |
| 125.🌌异步中的线程池/030.组件异步层面的线程池.md | covered | [thread-pools.md：组件异步层：编排内并行线程池](thread-pools.md#%E7%BB%84%E4%BB%B6%E5%BC%82%E6%AD%A5%E5%B1%82%E7%BC%96%E6%8E%92%E5%86%85%E5%B9%B6%E8%A1%8C%E7%BA%BF%E7%A8%8B%E6%B1%A0) |
| 125.🌌异步中的线程池/040.虚拟线程.md | covered | [thread-pools.md：虚拟线程（JDK 21+）](thread-pools.md#%E8%99%9A%E6%8B%9F%E7%BA%BF%E7%A8%8Bjdk-21) |
| 130.🎲动态构造/010.说明.md | covered | [dynamic-build.md：何时用动态构造](dynamic-build.md#%E4%BD%95%E6%97%B6%E7%94%A8%E5%8A%A8%E6%80%81%E6%9E%84%E9%80%A0) |
| 130.🎲动态构造/020.构造Node.md | covered | [dynamic-build.md：用 `LiteFlowNodeBuilder` 动态构造 Node](dynamic-build.md#%E7%94%A8-liteflownodebuilder-%E5%8A%A8%E6%80%81%E6%9E%84%E9%80%A0-node) |
| 130.🎲动态构造/030.构造EL.md | covered | [dynamic-build.md：用 `ELBus` 在代码里拼 EL（不写 EL 字符串）](dynamic-build.md#%E7%94%A8-elbus-%E5%9C%A8%E4%BB%A3%E7%A0%81%E9%87%8C%E6%8B%BC-el%E4%B8%8D%E5%86%99-el-%E5%AD%97%E7%AC%A6%E4%B8%B2) |
| 130.🎲动态构造/040.构造Chain.md | covered | [dynamic-build.md：用 `LiteFlowChainELBuilder` 动态构造并注册 Chain](dynamic-build.md#%E7%94%A8-liteflowchainelbuilder-%E5%8A%A8%E6%80%81%E6%9E%84%E9%80%A0%E5%B9%B6%E6%B3%A8%E5%86%8C-chain) |
| 140.🧮决策路由/010.概念以及介绍.md | covered | [decision-routing.md：一、决策路由解决什么问题](decision-routing.md#%E4%B8%80%E5%86%B3%E7%AD%96%E8%B7%AF%E7%94%B1%E8%A7%A3%E5%86%B3%E4%BB%80%E4%B9%88%E9%97%AE%E9%A2%98) |
| 140.🧮决策路由/020.决策路由用法.md | covered | [decision-routing.md：九、最小可运行示例](decision-routing.md#%E4%B9%9D%E6%9C%80%E5%B0%8F%E5%8F%AF%E8%BF%90%E8%A1%8C%E7%A4%BA%E4%BE%8B) |
| 150.😸生命周期/010.启动时生命周期.md | covered | [lifecycle.md：二、启动时生命周期（构造阶段）](lifecycle.md#%E4%BA%8C%E5%90%AF%E5%8A%A8%E6%97%B6%E7%94%9F%E5%91%BD%E5%91%A8%E6%9C%9F%E6%9E%84%E9%80%A0%E9%98%B6%E6%AE%B5) |
| 150.😸生命周期/020.执行时生命周期.md | covered | [lifecycle.md：三、执行时生命周期（运行阶段）](lifecycle.md#%E4%B8%89%E6%89%A7%E8%A1%8C%E6%97%B6%E7%94%9F%E5%91%BD%E5%91%A8%E6%9C%9F%E8%BF%90%E8%A1%8C%E9%98%B6%E6%AE%B5) |
| 160.🎨高级特性/031.本地规则文件监听.md | covered | [advanced.md：本地规则文件监听](advanced.md#%E6%9C%AC%E5%9C%B0%E8%A7%84%E5%88%99%E6%96%87%E4%BB%B6%E7%9B%91%E5%90%AC) |
| 160.🎨高级特性/035.组件降级.md | covered | [advanced.md：组件降级](advanced.md#%E7%BB%84%E4%BB%B6%E9%99%8D%E7%BA%A7) |
| 160.🎨高级特性/040.组件别名.md | covered | [advanced.md：组件别名](advanced.md#%E7%BB%84%E4%BB%B6%E5%88%AB%E5%90%8D) |
| 160.🎨高级特性/060.组件事件回调.md | covered | [advanced.md：组件事件回调](advanced.md#%E7%BB%84%E4%BB%B6%E4%BA%8B%E4%BB%B6%E5%9B%9E%E8%B0%83) |
| 160.🎨高级特性/061.组件回滚.md | covered | [advanced.md：组件回滚](advanced.md#%E7%BB%84%E4%BB%B6%E5%9B%9E%E6%BB%9A) |
| 160.🎨高级特性/070.隐式子流程.md | covered | [advanced.md：隐式子流程](advanced.md#%E9%9A%90%E5%BC%8F%E5%AD%90%E6%B5%81%E7%A8%8B) |
| 160.🎨高级特性/075.活跃规则保活策略.md | covered | [advanced.md：活跃规则保活策略](advanced.md#%E6%B4%BB%E8%B7%83%E8%A7%84%E5%88%99%E4%BF%9D%E6%B4%BB%E7%AD%96%E7%95%A5) |
| 160.🎨高级特性/080.私有投递.md | covered | [advanced.md：私有投递](advanced.md#%E7%A7%81%E6%9C%89%E6%8A%95%E9%80%92) |
| 160.🎨高级特性/110.组件切面.md | covered | [advanced.md：组件切面](advanced.md#%E7%BB%84%E4%BB%B6%E5%88%87%E9%9D%A2) |
| 160.🎨高级特性/120.步骤信息.md | covered | [advanced.md：步骤信息](advanced.md#%E6%AD%A5%E9%AA%A4%E4%BF%A1%E6%81%AF) |
| 160.🎨高级特性/125.异常.md | covered | [advanced.md：异常](advanced.md#%E5%BC%82%E5%B8%B8) |
| 160.🎨高级特性/130.打印信息详解.md | covered | [advanced.md：打印信息详解](advanced.md#%E6%89%93%E5%8D%B0%E4%BF%A1%E6%81%AF%E8%AF%A6%E8%A7%A3) |
| 160.🎨高级特性/140.自定义请求Id.md | covered | [advanced.md：自定义请求 Id](advanced.md#%E8%87%AA%E5%AE%9A%E4%B9%89%E8%AF%B7%E6%B1%82-id) |
| 160.🎨高级特性/145.快速解析模式.md | covered | [advanced.md：快速解析模式](advanced.md#%E5%BF%AB%E9%80%9F%E8%A7%A3%E6%9E%90%E6%A8%A1%E5%BC%8F) |
| 160.🎨高级特性/150.不同格式规则加载.md | covered | [advanced.md：不同格式规则加载](advanced.md#%E4%B8%8D%E5%90%8C%E6%A0%BC%E5%BC%8F%E8%A7%84%E5%88%99%E5%8A%A0%E8%BD%BD) |
| 160.🎨高级特性/170.自定义组件执行器.md | covered | [advanced.md：自定义组件执行器](advanced.md#%E8%87%AA%E5%AE%9A%E4%B9%89%E7%BB%84%E4%BB%B6%E6%89%A7%E8%A1%8C%E5%99%A8) |
| 160.🎨高级特性/180.简单监控.md | covered | [advanced.md：简单监控](advanced.md#%E7%AE%80%E5%8D%95%E7%9B%91%E6%8E%A7) |
| 160.🎨高级特性/190.XML的DTD.md | covered | [advanced.md：XML 的 DTD](advanced.md#xml-%E7%9A%84-dtd) |
| 170.⛱测试用例以及示例/010.测试用例.md | covered | [testing.md：二、SpringBoot 下的标准测试范式（最高频）](testing.md#%E4%BA%8Cspringboot-%E4%B8%8B%E7%9A%84%E6%A0%87%E5%87%86%E6%B5%8B%E8%AF%95%E8%8C%83%E5%BC%8F%E6%9C%80%E9%AB%98%E9%A2%91) |
| 170.⛱测试用例以及示例/020.DEMO案例.md | covered | [testing.md：七、外部 DEMO 案例（官方提供）](testing.md#%E4%B8%83%E5%A4%96%E9%83%A8-demo-%E6%A1%88%E4%BE%8B%E5%AE%98%E6%96%B9%E6%8F%90%E4%BE%9B) |
| 180.性能表现.md | partial | [overview.md：性能表现](overview.md#%E6%80%A7%E8%83%BD%E8%A1%A8%E7%8E%B0) |

### metrics

| 文档功能单元 | 状态 | 技能位置 |
|---|---|---|
| 0. 先搞懂这套东西 | covered | [metrics.md：1. 定位与依赖关系](metrics.md#1-%E5%AE%9A%E4%BD%8D%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%85%B3%E7%B3%BB) |
| 1. 五分钟跑通：从零到看见曲线 / Step 1：让应用产出指标（加 3 个依赖） | covered | [metrics.md：1. 定位与依赖关系](metrics.md#1-%E5%AE%9A%E4%BD%8D%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%85%B3%E7%B3%BB) |
| 1. 五分钟跑通：从零到看见曲线 / Step 2：打开端点，确认指标已经在吐 | covered | [metrics.md：3. 端点暴露（采集 ≠ 暴露）](metrics.md#3-%E7%AB%AF%E7%82%B9%E6%9A%B4%E9%9C%B2%E9%87%87%E9%9B%86--%E6%9A%B4%E9%9C%B2) |
| 1. 五分钟跑通：从零到看见曲线 / Step 3：一键起 Prometheus + Grafana | covered | [metrics.md：11. 从指标到 Grafana 曲线](metrics.md#11-%E4%BB%8E%E6%8C%87%E6%A0%87%E5%88%B0-grafana-%E6%9B%B2%E7%BA%BF) |
| 1. 五分钟跑通：从零到看见曲线 / Step 4：确认 Prometheus 抓到了你的应用 | covered | [metrics.md：11. 从指标到 Grafana 曲线](metrics.md#11-%E4%BB%8E%E6%8C%87%E6%A0%87%E5%88%B0-grafana-%E6%9B%B2%E7%BA%BF) |
| 1. 五分钟跑通：从零到看见曲线 / Step 5：打开 Grafana 看板 | covered | [metrics.md：11. 从指标到 Grafana 曲线](metrics.md#11-%E4%BB%8E%E6%8C%87%E6%A0%87%E5%88%B0-grafana-%E6%9B%B2%E7%BA%BF) |
| 1. 五分钟跑通：从零到看见曲线 / Step 6：打点流量，看曲线动起来 | covered | [metrics.md：11. 从指标到 Grafana 曲线](metrics.md#11-%E4%BB%8E%E6%8C%87%E6%A0%87%E5%88%B0-grafana-%E6%9B%B2%E7%BA%BF) |
| 2. 引入依赖（细节） / Spring Boot 2 / 3 项目 | covered | [metrics.md：1. 定位与依赖关系](metrics.md#1-%E5%AE%9A%E4%BD%8D%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%85%B3%E7%B3%BB) |
| 2. 引入依赖（细节） / Spring Boot 4 项目（JDK 17+） | covered | [metrics.md：1. 定位与依赖关系](metrics.md#1-%E5%AE%9A%E4%BD%8D%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%85%B3%E7%B3%BB) |
| 2. 引入依赖（细节） / 非 Spring / Solon 项目 | covered | [metrics.md：8. Solon / 非 Spring 环境](metrics.md#8-solon--%E9%9D%9E-spring-%E7%8E%AF%E5%A2%83) |
| 3. 开关与端点暴露 / LiteFlow 自有开关（仅一个） | covered | [metrics.md：2. 开关与装配条件](metrics.md#2-%E5%BC%80%E5%85%B3%E4%B8%8E%E8%A3%85%E9%85%8D%E6%9D%A1%E4%BB%B6) |
| 3. 开关与端点暴露 / 暴露 Actuator 端点 | covered | [metrics.md：3. 端点暴露（采集 ≠ 暴露）](metrics.md#3-%E7%AB%AF%E7%82%B9%E6%9A%B4%E9%9C%B2%E9%87%87%E9%9B%86--%E6%9A%B4%E9%9C%B2) |
| 4. 指标目录 / 4.1 Chain 级指标（按 `chainId` 聚合） | covered | [metrics.md：Chain 级（按 chainId 聚合）](metrics.md#chain-%E7%BA%A7%E6%8C%89-chainid-%E8%81%9A%E5%90%88) |
| 4. 指标目录 / 4.2 Node 级指标（按 `nodeId` 聚合） | covered | [metrics.md：Node 级（按 nodeId 聚合）](metrics.md#node-%E7%BA%A7%E6%8C%89-nodeid-%E8%81%9A%E5%90%88) |
| 4. 指标目录 / 4.3 全局 / 注册表 Gauge（`LiteflowMeterBinder` 一次性绑定） | covered | [metrics.md：全局 Gauge（`LiteflowMeterBinder` 一次性绑定）](metrics.md#%E5%85%A8%E5%B1%80-gaugeliteflowmeterbinder-%E4%B8%80%E6%AC%A1%E6%80%A7%E7%BB%91%E5%AE%9A) |
| 5. 三个端点分别返回什么 / 5.1 结构端点 `/actuator/liteflow` | partial | [metrics.md：5. 结构端点 `/actuator/liteflow`（只读，`LiteflowMetaView` 提供，`@Endpoint(id="liteflow")`）](metrics.md#5-%E7%BB%93%E6%9E%84%E7%AB%AF%E7%82%B9-actuatorliteflow%E5%8F%AA%E8%AF%BBliteflowmetaview-%E6%8F%90%E4%BE%9Bendpointidliteflow) |
| 6. 分位 / 直方图 / 客户端分位（进程内计算，默认发布到所有 registry） | covered | [metrics.md：6. 分位 / 直方图（Micrometer 标准配置，LiteFlow 不另立配置项）](metrics.md#6-%E5%88%86%E4%BD%8D--%E7%9B%B4%E6%96%B9%E5%9B%BEmicrometer-%E6%A0%87%E5%87%86%E9%85%8D%E7%BD%AEliteflow-%E4%B8%8D%E5%8F%A6%E7%AB%8B%E9%85%8D%E7%BD%AE%E9%A1%B9) |
| 6. 分位 / 直方图 / 直方图（发布 bucket，交 Prometheus 用 histogram_quantile 计算） | covered | [metrics.md：6. 分位 / 直方图（Micrometer 标准配置，LiteFlow 不另立配置项）](metrics.md#6-%E5%88%86%E4%BD%8D--%E7%9B%B4%E6%96%B9%E5%9B%BEmicrometer-%E6%A0%87%E5%87%86%E9%85%8D%E7%BD%AEliteflow-%E4%B8%8D%E5%8F%A6%E7%AB%8B%E9%85%8D%E7%BD%AE%E9%A1%B9) |
| 6. 分位 / 直方图 / 过滤 / 裁剪指标 | covered | [metrics.md：6. 分位 / 直方图（Micrometer 标准配置，LiteFlow 不另立配置项）](metrics.md#6-%E5%88%86%E4%BD%8D--%E7%9B%B4%E6%96%B9%E5%9B%BEmicrometer-%E6%A0%87%E5%87%86%E9%85%8D%E7%BD%AEliteflow-%E4%B8%8D%E5%8F%A6%E7%AB%8B%E9%85%8D%E7%BD%AE%E9%A1%B9) |
| 7. 常用 PromQL 与告警 / QPS（每秒执行次数） | covered | [metrics.md：7. 常用 PromQL（Prometheus 命名转换：`.`→`_`，Timer 带 `_seconds`，Counter 带 `_total`）](metrics.md#7-%E5%B8%B8%E7%94%A8-promqlprometheus-%E5%91%BD%E5%90%8D%E8%BD%AC%E6%8D%A2_timer-%E5%B8%A6-_secondscounter-%E5%B8%A6-_total) |
| 7. 常用 PromQL 与告警 / 平均耗时（秒） | covered | [metrics.md：7. 常用 PromQL（Prometheus 命名转换：`.`→`_`，Timer 带 `_seconds`，Counter 带 `_total`）](metrics.md#7-%E5%B8%B8%E7%94%A8-promqlprometheus-%E5%91%BD%E5%90%8D%E8%BD%AC%E6%8D%A2_timer-%E5%B8%A6-_secondscounter-%E5%B8%A6-_total) |
| 7. 常用 PromQL 与告警 / 错误率 | covered | [metrics.md：7. 常用 PromQL（Prometheus 命名转换：`.`→`_`，Timer 带 `_seconds`，Counter 带 `_total`）](metrics.md#7-%E5%B8%B8%E7%94%A8-promqlprometheus-%E5%91%BD%E5%90%8D%E8%BD%AC%E6%8D%A2_timer-%E5%B8%A6-_secondscounter-%E5%B8%A6-_total) |
| 7. 常用 PromQL 与告警 / P95 耗时（需开启 §6 的直方图） | covered | [metrics.md：7. 常用 PromQL（Prometheus 命名转换：`.`→`_`，Timer 带 `_seconds`，Counter 带 `_total`）](metrics.md#7-%E5%B8%B8%E7%94%A8-promqlprometheus-%E5%91%BD%E5%90%8D%E8%BD%AC%E6%8D%A2_timer-%E5%B8%A6-_secondscounter-%E5%B8%A6-_total) |
| 7. 常用 PromQL 与告警 / slot 池饱和度 | covered | [metrics.md：全局 Gauge（`LiteflowMeterBinder` 一次性绑定）](metrics.md#%E5%85%A8%E5%B1%80-gaugeliteflowmeterbinder-%E4%B8%80%E6%AC%A1%E6%80%A7%E7%BB%91%E5%AE%9A) |
| 7. 常用 PromQL 与告警 / 在途执行数（LongTaskTimer 的 active 数） | covered | [metrics.md：7. 常用 PromQL（Prometheus 命名转换：`.`→`_`，Timer 带 `_seconds`，Counter 带 `_total`）](metrics.md#7-%E5%B8%B8%E7%94%A8-promqlprometheus-%E5%91%BD%E5%90%8D%E8%BD%AC%E6%8D%A2_timer-%E5%B8%A6-_secondscounter-%E5%B8%A6-_total) |
| 7. 常用 PromQL 与告警 / 常用告警规则示例 | covered | [metrics.md：告警规则示例（Prometheus alerting rules）](metrics.md#%E5%91%8A%E8%AD%A6%E8%A7%84%E5%88%99%E7%A4%BA%E4%BE%8Bprometheus-alerting-rules) |
| 8. 职责归属与性能 / 8.1 谁算 QPS / 平均 / 分位 | covered | [metrics.md：1. 定位与依赖关系](metrics.md#1-%E5%AE%9A%E4%BD%8D%E4%B8%8E%E4%BE%9D%E8%B5%96%E5%85%B3%E7%B3%BB) |
| 8. 职责归属与性能 / 8.2 性能影响与基数控制 | covered | [metrics.md：9. 性能与基数](metrics.md#9-%E6%80%A7%E8%83%BD%E4%B8%8E%E5%9F%BA%E6%95%B0) |
| 附录 A：快速核对清单 | covered | [metrics.md：10. 快速核对清单与集成资产](metrics.md#10-%E5%BF%AB%E9%80%9F%E6%A0%B8%E5%AF%B9%E6%B8%85%E5%8D%95%E4%B8%8E%E9%9B%86%E6%88%90%E8%B5%84%E4%BA%A7) |
| 附录 B：集成资产清单 | covered | [metrics.md：10. 快速核对清单与集成资产](metrics.md#10-%E5%BF%AB%E9%80%9F%E6%A0%B8%E5%AF%B9%E6%B8%85%E5%8D%95%E4%B8%8E%E9%9B%86%E6%88%90%E8%B5%84%E4%BA%A7) |

### rule-db

| 文档功能单元 | 状态 | 技能位置 |
|---|---|---|
| 1. 它解决什么 | covered | [rule-db.md：1. 它是什么、解决什么](rule-db.md#1-%E5%AE%83%E6%98%AF%E4%BB%80%E4%B9%88%E8%A7%A3%E5%86%B3%E4%BB%80%E4%B9%88) |
| 2. 快速上手（SQL） / Step 1：引入依赖 | covered | [rule-db.md：3.1 依赖](rule-db.md#31-%E4%BE%9D%E8%B5%96) |
| 2. 快速上手（SQL） / Step 2：写配置（三种姿势，按需选最省事的） | covered | [rule-db.md：3.2 配置（各后端最省姿势）](rule-db.md#32-%E9%85%8D%E7%BD%AE%E5%90%84%E5%90%8E%E7%AB%AF%E6%9C%80%E7%9C%81%E5%A7%BF%E5%8A%BF) |
| 2. 快速上手（SQL） / Step 3：发布第一条规则 | covered | [rule-db.md：5. 发布 API（统一，推荐）](rule-db.md#5-%E5%8F%91%E5%B8%83-api%E7%BB%9F%E4%B8%80%E6%8E%A8%E8%8D%90) |
| 2. 快速上手（SQL） / Step 4：执行 | covered | [rule-db.md：3.4 执行](rule-db.md#34-%E6%89%A7%E8%A1%8C) |
| 3. 快速上手（Redis） / Step 1：引入依赖 | covered | [rule-db.md：3.1 依赖](rule-db.md#31-%E4%BE%9D%E8%B5%96) |
| 3. 快速上手（Redis） / Step 2：写配置（一行起步） | covered | [rule-db.md：3.2 配置（各后端最省姿势）](rule-db.md#32-%E9%85%8D%E7%BD%AE%E5%90%84%E5%90%8E%E7%AB%AF%E6%9C%80%E7%9C%81%E5%A7%BF%E5%8A%BF) |
| 3. 快速上手（Redis） / Step 3：发布第一条规则 | covered | [rule-db.md：5. 发布 API（统一，推荐）](rule-db.md#5-%E5%8F%91%E5%B8%83-api%E7%BB%9F%E4%B8%80%E6%8E%A8%E8%8D%90) |
| 3. 快速上手（Redis） / Step 4：执行 | covered | [rule-db.md：3.4 执行](rule-db.md#34-%E6%89%A7%E8%A1%8C) |
| 4. 快速上手（ZooKeeper） / Step 1：引入依赖 | covered | [rule-db.md：3.1 依赖](rule-db.md#31-%E4%BE%9D%E8%B5%96) |
| 4. 快速上手（ZooKeeper） / Step 2：写配置 | covered | [rule-db.md：3.2 配置（各后端最省姿势）](rule-db.md#32-%E9%85%8D%E7%BD%AE%E5%90%84%E5%90%8E%E7%AB%AF%E6%9C%80%E7%9C%81%E5%A7%BF%E5%8A%BF) |
| 4. 快速上手（ZooKeeper） / Step 3：发布第一条规则 | covered | [rule-db.md：5. 发布 API（统一，推荐）](rule-db.md#5-%E5%8F%91%E5%B8%83-api%E7%BB%9F%E4%B8%80%E6%8E%A8%E8%8D%90) |
| 4. 快速上手（ZooKeeper） / Step 4：执行 | covered | [rule-db.md：3.4 执行](rule-db.md#34-%E6%89%A7%E8%A1%8C) |
| 5. 快速上手（etcd） / Step 1：引入依赖 | covered | [rule-db.md：3.1 依赖](rule-db.md#31-%E4%BE%9D%E8%B5%96) |
| 5. 快速上手（etcd） / Step 2：写配置 | covered | [rule-db.md：3.2 配置（各后端最省姿势）](rule-db.md#32-%E9%85%8D%E7%BD%AE%E5%90%84%E5%90%8E%E7%AB%AF%E6%9C%80%E7%9C%81%E5%A7%BF%E5%8A%BF) |
| 5. 快速上手（etcd） / Step 3：发布第一条规则 | covered | [rule-db.md：5. 发布 API（统一，推荐）](rule-db.md#5-%E5%8F%91%E5%B8%83-api%E7%BB%9F%E4%B8%80%E6%8E%A8%E8%8D%90) |
| 5. 快速上手（etcd） / Step 4：执行 | covered | [rule-db.md：3.4 执行](rule-db.md#34-%E6%89%A7%E8%A1%8C) |
| 5.1 快速上手（PostgreSQL） | covered | [rule-db.md：3.2 配置（各后端最省姿势）](rule-db.md#32-%E9%85%8D%E7%BD%AE%E5%90%84%E5%90%8E%E7%AB%AF%E6%9C%80%E7%9C%81%E5%A7%BF%E5%8A%BF) |
| 5.2 快速上手（MongoDB） | covered | [rule-db.md：3.2 配置（各后端最省姿势）](rule-db.md#32-%E9%85%8D%E7%BD%AE%E5%90%84%E5%90%8E%E7%AB%AF%E6%9C%80%E7%9C%81%E5%A7%BF%E5%8A%BF) |
| 5.3 快速上手（Nacos） / Step 1：引入依赖 | covered | [rule-db.md：3.1 依赖](rule-db.md#31-%E4%BE%9D%E8%B5%96) |
| 5.3 快速上手（Nacos） / Step 2：写配置 | covered | [rule-db.md：3.2 配置（各后端最省姿势）](rule-db.md#32-%E9%85%8D%E7%BD%AE%E5%90%84%E5%90%8E%E7%AB%AF%E6%9C%80%E7%9C%81%E5%A7%BF%E5%8A%BF) |
| 5.3 快速上手（Nacos） / Step 3：发布第一条规则 | covered | [rule-db.md：5. 发布 API（统一，推荐）](rule-db.md#5-%E5%8F%91%E5%B8%83-api%E7%BB%9F%E4%B8%80%E6%8E%A8%E8%8D%90) |
| 5.3 快速上手（Nacos） / Step 4：执行 | covered | [rule-db.md：3.4 执行](rule-db.md#34-%E6%89%A7%E8%A1%8C) |
| 6. 配置参考 / 通用配置（七个后端共用） | covered | [rule-db.md：通用（七后端共用）](rule-db.md#%E9%80%9A%E7%94%A8%E4%B8%83%E5%90%8E%E7%AB%AF%E5%85%B1%E7%94%A8) |
| 6. 配置参考 / SQL 专属配置（`liteflow-rule-db-sql`） | covered | [rule-db.md：SQL 专属（`rule-db.sql.*`）](rule-db.md#sql-%E4%B8%93%E5%B1%9Erule-dbsql) |
| 6. 配置参考 / PostgreSQL 专属配置（`liteflow-rule-db-postgresql`） | covered | [rule-db.md：PostgreSQL / MongoDB 专属](rule-db.md#postgresql--mongodb-%E4%B8%93%E5%B1%9E) |
| 6. 配置参考 / MongoDB 专属配置（`liteflow-rule-db-mongodb`） | covered | [rule-db.md：PostgreSQL / MongoDB 专属](rule-db.md#postgresql--mongodb-%E4%B8%93%E5%B1%9E) |
| 6. 配置参考 / Redis 专属配置（`liteflow-rule-db-redis`） | covered | [rule-db.md：Redis 专属（`rule-db.redis.*`）](rule-db.md#redis-%E4%B8%93%E5%B1%9Erule-dbredis) |
| 6. 配置参考 / ZooKeeper 专属配置（`liteflow-rule-db-zk`） | covered | [rule-db.md：ZooKeeper（`rule-db.zk.*`）与 etcd（`rule-db.etcd.*`）](rule-db.md#zookeeperrule-dbzk%E4%B8%8E-etcdrule-dbetcd) |
| 6. 配置参考 / etcd 专属配置（`liteflow-rule-db-etcd`） | partial | [rule-db.md：ZooKeeper（`rule-db.zk.*`）与 etcd（`rule-db.etcd.*`）](rule-db.md#zookeeperrule-dbzk%E4%B8%8E-etcdrule-dbetcd) |
| 6. 配置参考 / Nacos 专属配置（`liteflow-rule-db-nacos`） | covered | [rule-db.md：Nacos 专属（`rule-db.nacos.*`）](rule-db.md#nacos-%E4%B8%93%E5%B1%9Erule-dbnacos) |
| 6. 配置参考 / 与旧配置的关系 | covered | [rule-db.md：与旧配置的关系（重要）](rule-db.md#%E4%B8%8E%E6%97%A7%E9%85%8D%E7%BD%AE%E7%9A%84%E5%85%B3%E7%B3%BB%E9%87%8D%E8%A6%81) |
| 7. 存储结构参考 / 7.1 SQL 四张表 | covered | [rule-db.md：SQL 四张表（前缀默认 `lf_`，DDL 在 `liteflow-rule-db-sql/src/main/resources/sql/ddl-mysql.sql`）](rule-db.md#sql-%E5%9B%9B%E5%BC%A0%E8%A1%A8%E5%89%8D%E7%BC%80%E9%BB%98%E8%AE%A4-lf_ddl-%E5%9C%A8-liteflow-rule-db-sqlsrcmainresourcessqlddl-mysqlsql) |
| 7. 存储结构参考 / 7.2 Redis 键结构 | covered | [rule-db.md：Redis 键结构（前缀默认 `lf`，无过期时间）](rule-db.md#redis-%E9%94%AE%E7%BB%93%E6%9E%84%E5%89%8D%E7%BC%80%E9%BB%98%E8%AE%A4-lf%E6%97%A0%E8%BF%87%E6%9C%9F%E6%97%B6%E9%97%B4) |
| 7. 存储结构参考 / 7.3 ZooKeeper 路径结构 | covered | [rule-db.md：zk / etcd 结构（同构）](rule-db.md#zk--etcd-%E7%BB%93%E6%9E%84%E5%90%8C%E6%9E%84) |
| 7. 存储结构参考 / 7.4 etcd 键结构 | covered | [rule-db.md：zk / etcd 结构（同构）](rule-db.md#zk--etcd-%E7%BB%93%E6%9E%84%E5%90%8C%E6%9E%84) |
| 7. 存储结构参考 / 7.5 PostgreSQL 四张表 | partial | [rule-db.md：PostgreSQL / MongoDB / Nacos](rule-db.md#postgresql--mongodb--nacos) |
| 7. 存储结构参考 / 7.6 MongoDB Collection | partial | [rule-db.md：PostgreSQL / MongoDB / Nacos](rule-db.md#postgresql--mongodb--nacos) |
| 7. 存储结构参考 / 7.7 Nacos Catalog | covered | [rule-db.md：PostgreSQL / MongoDB / Nacos](rule-db.md#postgresql--mongodb--nacos) |
| 8. 发布协议与写入规范 / 8.1 推荐：统一发布 API | covered | [rule-db.md：5. 发布 API（统一，推荐）](rule-db.md#5-%E5%8F%91%E5%B8%83-api%E7%BB%9F%E4%B8%80%E6%8E%A8%E8%8D%90) |
| 8. 发布协议与写入规范 / 8.2 SQL 兼容门面（不推荐新代码使用） | covered | [rule-db.md：3.3 发布第一条规则](rule-db.md#33-%E5%8F%91%E5%B8%83%E7%AC%AC%E4%B8%80%E6%9D%A1%E8%A7%84%E5%88%99) |
| 8. 发布协议与写入规范 / 8.3 停用（enable=0） | covered | [rule-db.md：5. 发布 API（统一，推荐）](rule-db.md#5-%E5%8F%91%E5%B8%83-api%E7%BB%9F%E4%B8%80%E6%8E%A8%E8%8D%90) |
| 8. 发布协议与写入规范 / 8.4 绕过 API 直接写存储的规范（不推荐，但可做） | covered | [rule-db.md：11. 常见坑（手改库必看）](rule-db.md#11-%E5%B8%B8%E8%A7%81%E5%9D%91%E6%89%8B%E6%94%B9%E5%BA%93%E5%BF%85%E7%9C%8B) |
| 8. 发布协议与写入规范 / 8.5 content_md5 对账双保险 | covered | [rule-db.md：11. 常见坑（手改库必看）](rule-db.md#11-%E5%B8%B8%E8%A7%81%E5%9D%91%E6%89%8B%E6%94%B9%E5%BA%93%E5%BF%85%E7%9C%8B) |
| 8. 发布协议与写入规范 / 8.6 发布校验与依赖顺序 | covered | [rule-db.md：3.3 发布第一条规则](rule-db.md#33-%E5%8F%91%E5%B8%83%E7%AC%AC%E4%B8%80%E6%9D%A1%E8%A7%84%E5%88%99) |
| 9. 一致性与收敛模型 / 9.1 两条腿 | covered | [rule-db.md：7. 一致性与收敛模型](rule-db.md#7-%E4%B8%80%E8%87%B4%E6%80%A7%E4%B8%8E%E6%94%B6%E6%95%9B%E6%A8%A1%E5%9E%8B) |
| 9. 一致性与收敛模型 / 9.2 收敛窗口 | covered | [rule-db.md：7. 一致性与收敛模型](rule-db.md#7-%E4%B8%80%E8%87%B4%E6%80%A7%E4%B8%8E%E6%94%B6%E6%95%9B%E6%A8%A1%E5%9E%8B) |
| 9. 一致性与收敛模型 / 9.3 一致性语义（务必读） | covered | [rule-db.md：7. 一致性与收敛模型](rule-db.md#7-%E4%B8%80%E8%87%B4%E6%80%A7%E4%B8%8E%E6%94%B6%E6%95%9B%E6%A8%A1%E5%9E%8B) |
| 10. 内存与性能 / 10.1 内存模型 | covered | [rule-db.md：8. 内存模型与执行热路径](rule-db.md#8-%E5%86%85%E5%AD%98%E6%A8%A1%E5%9E%8B%E4%B8%8E%E6%89%A7%E8%A1%8C%E7%83%AD%E8%B7%AF%E5%BE%84) |
| 10. 内存与性能 / 10.2 执行热路径 | covered | [rule-db.md：8. 内存模型与执行热路径](rule-db.md#8-%E5%86%85%E5%AD%98%E6%A8%A1%E5%9E%8B%E4%B8%8E%E6%89%A7%E8%A1%8C%E7%83%AD%E8%B7%AF%E5%BE%84) |
| 10. 内存与性能 / 10.3 调优建议 | covered | [rule-db.md：8. 内存模型与执行热路径](rule-db.md#8-%E5%86%85%E5%AD%98%E6%A8%A1%E5%9E%8B%E4%B8%8E%E6%89%A7%E8%A1%8C%E7%83%AD%E8%B7%AF%E5%BE%84) |
| 10. 内存与性能 / 10.4 v1 实现注记：惰性刷新与 last-good | covered | [rule-db.md：8. 内存模型与执行热路径](rule-db.md#8-%E5%86%85%E5%AD%98%E6%A8%A1%E5%9E%8B%E4%B8%8E%E6%89%A7%E8%A1%8C%E7%83%AD%E8%B7%AF%E5%BE%84) |
| 11. 可观测性 / Spring Boot：actuator 端点 | covered | [rule-db.md：12. 可观测性](rule-db.md#12-%E5%8F%AF%E8%A7%82%E6%B5%8B%E6%80%A7) |
| 11. 可观测性 / 非 Spring / 无 actuator 环境 | covered | [rule-db.md：12. 可观测性](rule-db.md#12-%E5%8F%AF%E8%A7%82%E6%B5%8B%E6%80%A7) |
| 12. 降级语义 | covered | [rule-db.md：9. 降级语义](rule-db.md#9-%E9%99%8D%E7%BA%A7%E8%AF%AD%E4%B9%89) |
| 13. 限制与已知边界 / 13.1 发布参数与后端限制矩阵 | covered | [rule-db.md：10. 限制与已知边界（v1）](rule-db.md#10-%E9%99%90%E5%88%B6%E4%B8%8E%E5%B7%B2%E7%9F%A5%E8%BE%B9%E7%95%8Cv1) |
| 14. 迁移、备份与权限 / 14.1 从旧规则插件迁移 | covered | [rule-db.md：14. 从老规则插件迁移（liteflow-rule-sql 等 → Rule-DB）](rule-db.md#14-%E4%BB%8E%E8%80%81%E8%A7%84%E5%88%99%E6%8F%92%E4%BB%B6%E8%BF%81%E7%A7%BBliteflow-rule-sql-%E7%AD%89--rule-db) |
| 14. 迁移、备份与权限 / 14.2 备份恢复 | covered | [rule-db.md：备份恢复](rule-db.md#%E5%A4%87%E4%BB%BD%E6%81%A2%E5%A4%8D) |
| 14. 迁移、备份与权限 / 14.3 执行账号与发布账号 | covered | [rule-db.md：执行账号与发布账号](rule-db.md#%E6%89%A7%E8%A1%8C%E8%B4%A6%E5%8F%B7%E4%B8%8E%E5%8F%91%E5%B8%83%E8%B4%A6%E5%8F%B7) |
