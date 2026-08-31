# HippoBuddy 后端知识库

这不是类名索引，而是一套从概念、底层机制到项目源码和面试表达的学习材料。每个主题独立成篇，包含：学习目标、概念与本质、运行流程、项目真实源码精读、关键实现原理解读、疑难点、Java Demo、Mermaid 思维导图、常见误区、面试题、掌握清单，以及可继续深挖的博客、官方文档或电子书。

> 第二版深度修订：42 篇均已增加独立的“源码级实现原理解读”和“可运行完整实现/完整实现骨架”章节。前者从状态、数据结构、执行顺序、不变量和失败路径解释项目接线；后者提供可编译的 Java 实现，并明确教学实现与生产级保证的差距。新增的 42 个实现代码块均已通过 Java 21 编译检查。

## 系统化学习入口

- [42 周完整学习路线](SYSTEMATIC_LEARNING_GUIDE.md)：前置依赖、每周节奏、阶段项目、复习算法和验收等级；
- [538 个知识点进度表](MASTER_PROGRESS_TRACKER.md)：逐项记录 L0–L5、间隔复习日期和掌握证据。

## 思维导图节点博客

42 个专题思维导图中的 538 个末级知识点已经逐一展开：[进入思维导图节点学习博客总索引](mindmap-blogs/README.md)。每篇都包含底层原理、项目源码、设计原因、完整实现、失败实验和面试追问。

## 推荐学习顺序

### 第一阶段：架构基本功

1. [分层架构与应用服务](01-architecture/01-layered-architecture.md)
2. [IoC、DI 与 Service Locator](01-architecture/02-ioc-di-service-locator.md)
3. [对象作用域、全局状态与生命周期](01-architecture/03-scope-lifecycle.md)
4. [项目中的设计模式](01-architecture/04-design-patterns.md)
5. [配置系统与不可变快照](01-architecture/05-configuration.md)

### 第二阶段：并发与网络

6. [Java 21 虚拟线程](02-concurrency-network/01-virtual-threads.md)
7. [有界线程池、队列与背压](02-concurrency-network/02-bounded-pool-backpressure.md)
8. [Session 锁、原子性与临界区](02-concurrency-network/03-session-lock-atomicity.md)
9. [多文件锁与死锁](02-concurrency-network/04-file-lock-deadlock.md)
10. [SSE 协议与流式响应](02-concurrency-network/05-sse.md)
11. [生产者—消费者模型](02-concurrency-network/06-producer-consumer.md)
12. [取消、超时、线程中断与 Watchdog](02-concurrency-network/07-cancellation-timeout-watchdog.md)
13. [MDC 上下文传播与 EventBus](02-concurrency-network/08-mdc-eventbus.md)

### 第三阶段：Agent 与 LLM

14. [Agent Loop 与状态机](03-agent-llm/01-agent-loop-state-machine.md)
15. [Function Calling 与工具协议](03-agent-llm/02-function-calling.md)
16. [SSE Delta 解析与增量合并](03-agent-llm/03-stream-delta-assembly.md)
17. [多供应商 Adapter 与统一模型](03-agent-llm/04-provider-adapter.md)
18. [重试、指数退避与幂等](03-agent-llm/05-retry-backoff-idempotency.md)
19. [错误分类与异常语义](03-agent-llm/06-error-taxonomy.md)
20. [Prompt 前缀缓存](03-agent-llm/07-prompt-cache.md)
21. [Token Usage、价格与成本治理](03-agent-llm/08-token-cost.md)

### 第四阶段：工具与安全

22. [Command、Tool Registry 与 JSON Schema](04-tools-security/01-command-registry-schema.md)
23. [Blocker 责任链与能力权限](04-tools-security/02-blocker-capability.md)
24. [路径规范化、Sandbox 与符号链接](04-tools-security/03-path-sandbox.md)
25. [Human-in-the-loop 与两阶段执行](04-tools-security/04-human-in-the-loop.md)
26. [乐观并发、快照与补偿事务](04-tools-security/05-edit-snapshot-compensation.md)
27. [工具输出分类与截断策略](04-tools-security/06-output-truncation.md)
28. [工具并发、依赖与结果排序](04-tools-security/07-concurrent-tools.md)

### 第五阶段：上下文、持久化与记忆

29. [Tokenizer、Token 估算与预算监听](05-context-storage/01-token-budget.md)
30. [滑动窗口、摘要压缩与 Session Memory](05-context-storage/02-context-compaction.md)
31. [JSONL、Append-only Log 与 Event Sourcing](05-context-storage/03-jsonl-event-log.md)
32. [批量刷盘、幂等、原子写与崩溃恢复](05-context-storage/04-file-durability.md)
33. [Markdown 记忆、索引与缓存失效](05-context-storage/05-memory-index-cache.md)
34. [关键词、向量检索与 Progressive Disclosure](05-context-storage/06-retrieval-progressive-disclosure.md)
35. [文件存储、SQLite 与 PostgreSQL 选型](05-context-storage/07-storage-selection.md)

### 第六阶段：扩展与质量

36. [子 Agent、任务状态与有界调度](06-extension-quality/01-subagent-scheduling.md)
37. [JSON-RPC、MCP 与 Transport](06-extension-quality/02-jsonrpc-mcp.md)
38. [Prompt、Rule、Skill、Tool 的边界](06-extension-quality/03-prompt-rule-skill-tool.md)
39. [日志、指标、Trace 与健康检查](06-extension-quality/04-observability-health.md)
40. [Tree-sitter、WASM 与 Chicory](06-extension-quality/05-tree-sitter-wasm.md)
41. [单元测试、Fake Server 与契约测试](06-extension-quality/06-testing-contracts.md)
42. [Agent 安全威胁模型](06-extension-quality/07-threat-model.md)

## 使用方法

每学完一个主题，至少完成三件事：

1. 不看文档画出其中的流程图或状态机；
2. 独立运行并修改 Demo，制造一次失败场景；
3. 用“本质—项目实现—边界—改进”结构口述 3 分钟。

所有 Demo 都是教学最小实现，重点展示机制，不等同于生产代码。项目真实实现以对应源码为准。

## 单篇深度标准

每篇专题必须能够独立回答以下问题，才算达到“掌握”而不是“了解”：

1. 术语的严格定义是什么，与相似概念有什么区别；
2. 内部状态、数据结构或协议字段是什么；
3. 一次完整执行按什么顺序发生；
4. 系统必须维持哪些不变量，为什么；
5. 并发、异常、崩溃和恶意输入下如何失败；
6. HippoBuddy 哪些类实现了它，主链是否真正接入；
7. 最小 Demo 和失败 Demo 分别证明什么；
8. 有哪些替代方案，适用边界和迁移条件是什么；
9. 面试官继续追问两到三层时如何回答；
10. 如何通过源码实验或测试证明自己真的理解。

文档深度校验还要求每篇同时具备：概念与原理、项目真实源码链接及源码片段、关键实现本质、显式标注的疑难点、执行流程或状态、至少两个代码/推演示例、失败模式、方案对比、面试追问、实战实验、Mermaid 思维导图、至少两个外部学习资源和最终掌握检查。

阅读“实现”部分时要区分三层：

1. **项目真实实现**：以“项目源码精读”链接到的 HippoBuddy 类为准；
2. **机制完整实现**：以新增的完整 Java 代码验证算法、状态机或协议不变量；
3. **生产级缺口**：以“疑难点”和实现后的边界说明为准，不能把教学 Demo 的简化保证直接套到生产环境。
