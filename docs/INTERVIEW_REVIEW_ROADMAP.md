# HippoBuddy 系统化面试复习路线

这份文档是现有知识库的“面试导航层”。目标不是再读一遍所有材料，而是把 42 个专题、538 个末级知识点组织成能画图、能追源码、能回答追问的知识网络。Agent 是主线，其余 Java、并发、网络、安全、存储与测试知识都围绕 Agent 工程化展开。

Agent 建议按两层复习：先用 [Agent 专项面试手册](AGENT_INTERVIEW_PLAYBOOK.md) 建立口述框架，再用 [Agent 实现原理深度手册](AGENT_IMPLEMENTATION_DEEP_DIVE.md) 追状态、源码、并发边界和故障恢复。

## 1. 先建立项目定位

### 30 秒版本

> HippoBuddy 是一个基于 Java 21 的本地 AI 桌面 Agent。它不是简单转发 LLM 请求，而是自研了多轮 Agent Loop，把流式模型调用、Function Calling、文件与 Shell 工具、安全确认、上下文压缩、会话持久化、长期记忆、Sub-Agent 和 MCP 扩展串成完整执行链。后端使用轻量 HTTP Server、SSE、虚拟线程和文件型存储，适合个人本地工具场景。

### 2 分钟版本的固定结构

1. 场景：本地聊天、编码和 Office 助手；
2. 主链：用户请求 → LLM 决策 → 工具执行 → observation 回填 → 最终答案；
3. 难点：流式协议、工具副作用安全、长上下文、取消与恢复；
4. 亮点：多 Provider 适配、会话级工具快照、JSONL 转录、文件锁与快照撤销；
5. 边界：面向单机个人，不等同于多租户生产 SaaS；MCP、Memory、Sub-Agent 仍有工程化空间。

## 2. 全部知识点的六层地图

| 层次 | 必须掌握的专题 | 面试时要证明什么 | 总入口 |
|---|---|---|---|
| 架构 | 分层、IoC/DI、作用域、设计模式、配置快照 | 能从入口追到外部 I/O，说明依赖和生命周期 | [架构专题](backend-knowledge/README.md#第一阶段架构基本功) |
| 并发网络 | 虚拟线程、有界池、Session 锁、文件锁、SSE、背压、取消、MDC/EventBus | 能解释“高并发不等于无限资源”和完整取消链 | [并发专题](backend-knowledge/README.md#第二阶段并发与网络) |
| Agent/LLM | Agent Loop、Function Calling、Delta 合并、Provider Adapter、重试、错误分类、Prompt Cache、Token 成本 | 能画状态机，说明模型与 Runtime 的职责边界 | [Agent 专题](backend-knowledge/README.md#第三阶段agent-与-llm) |
| 工具安全 | Registry/Schema、Blocker、Capability、Sandbox、人工确认、快照补偿、截断、并发工具 | 能证明不可信模型不能直接产生系统副作用 | [工具专题](backend-knowledge/README.md#第四阶段工具与安全) |
| 上下文存储 | Token 预算、压缩、JSONL、刷盘恢复、Memory 索引、检索、存储选型 | 能说明协议不变量、恢复边界和场景化选型 | [上下文专题](backend-knowledge/README.md#第五阶段上下文持久化与记忆) |
| 扩展质量 | Sub-Agent、MCP、Prompt/Rule/Skill/Tool、可观测性、Tree-sitter、测试、威胁模型 | 能说明如何扩展、验证和治理 Agent | [扩展专题](backend-knowledge/README.md#第六阶段扩展与质量) |

完整逐项清单见 [538 个知识点进度表](backend-knowledge/MASTER_PROGRESS_TRACKER.md)。

### 前端、桌面端与工程化补充

现有 42 专题主要覆盖后端；如果面试岗位会追问全栈，还要补齐以下链路：

| 领域 | 项目实现 | 高频追问 |
|---|---|---|
| Electron 生命周期 | `electron/main.js` 启动 Java 后端、探活、创建窗口、退出清理和自动更新 | 主/渲染进程区别；后端僵尸进程；单实例；优雅退出 |
| Electron 安全 | preload + IPC，`contextIsolation=true`、`nodeIntegration=false`，但当前 `sandbox=false` | IPC 能力最小化、路径参数校验、外链校验、为何 preload 不能暴露任意 Node API |
| React 架构 | React 18 + TypeScript + Vite；同时保留旧版静态 JS UI | 渐进迁移、双实现一致性、构建入口选择 |
| 状态管理 | Zustand 按 `sessionId` 分区保存 messages、stream、tools、waiting、error | 为什么流式状态必须按会话隔离；不可变更新；缓存失效 |
| 前端 SSE | `fetch + ReadableStream` 解析 POST `/api/chat`，用 AbortController 取消 | 为什么不用 EventSource；拆帧、UTF-8、事件路由、断流半成品 |
| 内容渲染 | marked、DOMPurify、highlight.js、KaTeX、Mermaid | Markdown XSS、代码高亮成本、第三方渲染隔离 |
| 工作区与预览 | CodeMirror、diff、文件树、图片与 OOXML/WASM 预览 | 大文件、Blob URL 回收、Worker、编辑冲突、二进制格式 |
| 官网与交付 | Docusaurus i18n、Maven Shade、electron-builder、多平台资源 | 前后端版本一致、打包体积、升级失败与回滚 |

前端 Agent 主线要能讲成：后端 SSE event → 类型化解析 → 以 `sessionId` 定向路由 → Zustand 状态迁移 → Tool Timeline/Message 渲染 → `done` 时幂等固化；切换会话不能让流式内容串台，取消时既 abort 本地 fetch，也通知后端停止实际 LLM/Tool 消耗。

## 3. 面试优先级

### P0：必须闭卷讲清

1. Agent 与普通聊天、固定工作流的区别；
2. 一次 `/api/chat` 请求的完整调用链；
3. Agent Loop 状态、状态迁移和终止条件；
4. Function Calling 的 schema、callId、参数增量与 tool result 配对；
5. 为什么模型只是策略函数，Runtime 才拥有执行权；
6. 工具参数校验、权限、路径沙箱和 Human-in-the-loop；
7. SSE 流式解析、半开连接、idle timeout 与取消；
8. Token 预算、上下文裁剪和 tool-call 协议不变量；
9. JSONL 会话恢复、幂等、刷盘和尾行损坏；
10. Sub-Agent 的隔离、有界并发、取消、结果收敛；
11. MCP 的 JSON-RPC、初始化握手、transport 与工具适配；
12. Agent 的评测、可观测性与安全威胁。

### P1：必须能够比较

- SSE vs WebSocket；
- 虚拟线程 vs 平台线程池；
- Agent vs Workflow；
- Tool vs Skill vs MCP；
- 短期上下文 vs Session Memory vs 长期 Memory；
- 关键词检索 vs 向量检索 vs 混合检索；
- JSONL vs SQLite vs PostgreSQL；
- 重试 vs fallback vs 熔断；
- 单 Agent vs Sub-Agent；
- 乐观并发 vs 悲观锁；
- 快照补偿 vs 数据库事务；
- 单元测试 vs Provider/MCP 契约测试 vs Agent 端到端评测。

### P2：能准确承认边界

- 当前 Orchestrator 较大，显式状态机仍可继续拆分；
- 最大轮数只是安全阀，不能代替停滞检测和预算控制；
- 本地 JVM 路径锁不能提供跨进程一致性；
- 文件存储适合单机个人场景，不适合直接扩展为多人 SaaS；
- Prompt Injection 不能只靠 Prompt 防御，必须在执行层最小授权；
- Memory、Sub-Agent、MCP 的“类已存在”不等于所有启动链和产品路径都已完整接通。

## 4. 八条源码主线

| 主线 | 从哪里开始 | 最终讲到哪里 |
|---|---|---|
| 启动与装配 | `DesktopApplication` / `WebApplication` | `CoreModule`、`ServiceLocator`、`DashboardServer` |
| 一次 Agent 对话 | `ChatApiHandler` | `WebAgentOrchestrator` → `LlmClient` → `ToolRegistry` → SSE |
| 流式模型协议 | `AbstractLlmClient` | `SseParser`、delta 合并、Usage、异常分类 |
| 工具与安全 | `ToolRegistry` | Blocker、Mode、Path、确认、锁、Snapshot、Undo |
| 长上下文 | `ConversationService` | `ContextWindow`、TokenBudget、AutoCompact、Session Memory |
| 会话恢复 | `SessionTranscript` | JSONL append、batch flush、loader、消息修复 |
| 并行 Agent | `ForkAgentTool` | `SubAgentManager`、`SubAgentRunner`、状态和结果格式化 |
| 开放扩展 | `McpServiceManager` | JSON-RPC、stdio/SSE、Tool/Resource/Prompt Registry |

先看 [Agent 专项面试手册](AGENT_INTERVIEW_PLAYBOOK.md)，再按 [后端技术路线与面试手册](BACKEND_INTERVIEW_GUIDE.md) 补齐全项目，最后用 [实现原理与本质详解](BACKEND_KNOWLEDGE_POINTS_DEEP_DIVE.md) 处理追问。

## 5. 14 天面试冲刺计划

| 天 | 主题 | 当天输出 |
|---:|---|---|
| 1 | 项目定位、分层、启动与 DI | 30 秒和 2 分钟项目介绍；启动图 |
| 2 | Agent Loop 与状态机 | 闭卷画状态图；讲完一次完整 turn |
| 3 | Function Calling 与流式 Delta | 手写 tool-call 合并与配对不变量 |
| 4 | Tool Registry 与安全 | 画五层安全边界；回答 Prompt Injection |
| 5 | 上下文、Token 与压缩 | 解释为什么不能按消息条数截断 |
| 6 | Session、JSONL 与恢复 | 制造半行损坏并解释恢复策略 |
| 7 | Provider Adapter、重试与错误 | 比较 timeout/retry/fallback/idempotency |
| 8 | Java 21 并发、SSE、取消 | 画取消传播链；解释虚拟线程边界 |
| 9 | Memory 与 RAG | 画写入、检索、注入链；比较三类记忆 |
| 10 | Sub-Agent | 讲任务隔离、有界调度、失败和取消 |
| 11 | MCP 与扩展模型 | 画 initialize → list → call 流程 |
| 12 | 可观测性、测试、Eval、安全 | 写指标表、测试金字塔和威胁清单 |
| 13 | Java/架构/存储综合追问 | 完成 2 轮白板模拟面试 |
| 14 | 全真模拟与补弱 | 60 分钟模拟；只回补答错项 |

每天固定采用 90 分钟闭环：20 分钟闭卷回忆，25 分钟追源码，20 分钟制造失败，15 分钟口述，10 分钟记录错题。只阅读不输出，不计为掌握。

## 6. 7 天紧急路线

1. 第 1 天：项目介绍、总架构、一次对话主链；
2. 第 2 天：Agent Loop、Function Calling、SSE Delta；
3. 第 3 天：工具安全、确认、路径、锁与撤销；
4. 第 4 天：Token、上下文压缩、Memory、Prompt Cache；
5. 第 5 天：Sub-Agent、MCP、并发与取消；
6. 第 6 天：持久化、测试、可观测性、安全；
7. 第 7 天：项目亮点故事、技术债、两轮模拟面试。

## 7. 每个知识点的回答模板

不要只报定义，统一按下面五段回答：

1. 本质：它解决什么约束；
2. 原理：内部状态、协议字段或算法怎样工作；
3. 项目：HippoBuddy 的入口、核心类和执行顺序；
4. 边界：在哪些并发、异常、崩溃或恶意输入下会失败；
5. 改进：生产化时增加什么，为什么。

示例：回答“Agent 是什么”时，不要只说“能调用工具的大模型”。应说明它是一个由 LLM 策略、受控 Runtime、状态、工具和终止条件构成的闭环；再落到项目的 `WebAgentOrchestrator`；最后说明最大轮数、停滞检测、权限和持久化边界。

## 8. 掌握验收

每个 P0 主题只有同时满足以下条件才算通过：

- 3 分钟内闭卷说清；
- 能画出状态机或时序图；
- 能指出至少 2 个真实源码位置；
- 能说出 2 个失败模式；
- 能比较 1 个替代方案；
- 能回答连续 3 层“为什么”；
- 能写一个 Fake 或失败测试验证关键不变量。

建议把掌握度写回 [全量进度表](backend-knowledge/MASTER_PROGRESS_TRACKER.md)：L0 未接触、L1 了解、L2 会用、L3 掌握、L4 面试熟练、L5 可改造。面试前 P0 全部达到 L4，其他核心节点达到 L3。

## 9. 资料使用顺序

1. [Agent 专项面试手册](AGENT_INTERVIEW_PLAYBOOK.md)：先建立最核心的 Agent 知识网络；
2. [后端技术路线与面试手册](BACKEND_INTERVIEW_GUIDE.md)：形成全项目表达；
3. [实现原理与本质详解](BACKEND_KNOWLEDGE_POINTS_DEEP_DIVE.md)：处理底层追问；
4. [42 专题知识库](backend-knowledge/README.md)：逐主题深挖；
5. [538 节点博客](backend-knowledge/mindmap-blogs/README.md)：查漏补缺；
6. [系统学习指南](backend-knowledge/SYSTEMATIC_LEARNING_GUIDE.md)：长期复习；
7. [架构报告](ARCHITECTURE_REPORT.md)：准备边界、风险和演进题。
