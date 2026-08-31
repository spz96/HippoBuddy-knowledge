# 思维导图节点学习博客总索引

本目录将 42 个后端专题思维导图中的 **538 个末级技术节点**逐一展开为独立学习博客。每篇包含项目语境、底层实现原理、真实源码入口与片段、采用原因、Java 实现、失败推演、实验和面试追问。

返回[后端知识库总索引](../README.md)。

## 六阶段系统路线

- [阶段一：架构与对象模型](01-architecture/ROADMAP.md)：建立分层、依赖、对象作用域、设计模式和配置快照的统一语言。
- [阶段二：并发、网络与取消](02-concurrency-network/ROADMAP.md)：掌握虚拟线程、背压、锁、SSE、队列、取消和异步上下文传播。
- [阶段三：Agent 与 LLM 协议](03-agent-llm/ROADMAP.md)：掌握 Agent 状态机、Function Calling、流式组装、Provider 适配、重试、错误、缓存和成本。
- [阶段四：工具执行与安全](04-tools-security/ROADMAP.md)：把模型建议转成经过 Schema、权限、路径、确认、版本和锁保护的副作用。
- [阶段五：上下文、持久化与检索](05-context-storage/ROADMAP.md)：掌握 Token 预算、协议安全压缩、JSONL 重放、耐久写、索引缓存和检索选型。
- [阶段六：扩展、测试与威胁治理](06-extension-quality/ROADMAP.md)：掌握子 Agent、MCP、指令层次、可观测性、WASM、契约测试和 Agent 威胁模型。

## 架构基本功

- [分层架构与应用服务](01-architecture/01-layered-architecture/README.md)：15 篇节点博客
- [IoC、DI 与 Service Locator](01-architecture/02-ioc-di-service-locator/README.md)：13 篇节点博客
- [对象作用域、全局状态与生命周期](01-architecture/03-scope-lifecycle/README.md)：12 篇节点博客
- [HippoBuddy 中的设计模式](01-architecture/04-design-patterns/README.md)：11 篇节点博客
- [配置系统与不可变快照](01-architecture/05-configuration/README.md)：14 篇节点博客

## 并发与网络

- [Java 21 虚拟线程](02-concurrency-network/01-virtual-threads/README.md)：11 篇节点博客
- [有界线程池、队列与背压](02-concurrency-network/02-bounded-pool-backpressure/README.md)：11 篇节点博客
- [Session 锁、原子性与临界区](02-concurrency-network/03-session-lock-atomicity/README.md)：11 篇节点博客
- [多文件锁与死锁](02-concurrency-network/04-file-lock-deadlock/README.md)：12 篇节点博客
- [SSE 协议与流式响应](02-concurrency-network/05-sse/README.md)：12 篇节点博客
- [生产者—消费者、批处理与背压](02-concurrency-network/06-producer-consumer/README.md)：13 篇节点博客
- [取消、超时、线程中断与 Watchdog](02-concurrency-network/07-cancellation-timeout-watchdog/README.md)：11 篇节点博客
- [MDC 上下文传播与 EventBus](02-concurrency-network/08-mdc-eventbus/README.md)：12 篇节点博客

## Agent 与 LLM

- [Agent Loop 与状态机](03-agent-llm/01-agent-loop-state-machine/README.md)：14 篇节点博客
- [Function Calling 与工具协议](03-agent-llm/02-function-calling/README.md)：14 篇节点博客
- [SSE Delta 解析与增量合并](03-agent-llm/03-stream-delta-assembly/README.md)：13 篇节点博客
- [多供应商 Adapter 与统一模型](03-agent-llm/04-provider-adapter/README.md)：12 篇节点博客
- [重试、指数退避与幂等](03-agent-llm/05-retry-backoff-idempotency/README.md)：10 篇节点博客
- [错误分类与异常语义](03-agent-llm/06-error-taxonomy/README.md)：16 篇节点博客
- [Prompt 前缀缓存](03-agent-llm/07-prompt-cache/README.md)：13 篇节点博客
- [Token Usage、价格与成本治理](03-agent-llm/08-token-cost/README.md)：14 篇节点博客

## 工具与安全

- [Command、Tool Registry 与 JSON Schema](04-tools-security/01-command-registry-schema/README.md)：13 篇节点博客
- [Blocker 责任链与能力权限](04-tools-security/02-blocker-capability/README.md)：12 篇节点博客
- [路径规范化、Sandbox 与符号链接](04-tools-security/03-path-sandbox/README.md)：12 篇节点博客
- [Human-in-the-loop 与两阶段执行](04-tools-security/04-human-in-the-loop/README.md)：14 篇节点博客
- [乐观并发、快照与补偿事务](04-tools-security/05-edit-snapshot-compensation/README.md)：12 篇节点博客
- [工具输出分类与截断策略](04-tools-security/06-output-truncation/README.md)：14 篇节点博客
- [工具并发、依赖与结果排序](04-tools-security/07-concurrent-tools/README.md)：10 篇节点博客

## 上下文、持久化与记忆

- [Tokenizer、Token 估算与预算监听](05-context-storage/01-token-budget/README.md)：14 篇节点博客
- [滑动窗口、摘要压缩与 Session Memory](05-context-storage/02-context-compaction/README.md)：13 篇节点博客
- [JSONL、Append-only Log 与 Event Sourcing](05-context-storage/03-jsonl-event-log/README.md)：12 篇节点博客
- [批量刷盘、幂等、原子写与崩溃恢复](05-context-storage/04-file-durability/README.md)：12 篇节点博客
- [Markdown 记忆、索引与缓存失效](05-context-storage/05-memory-index-cache/README.md)：12 篇节点博客
- [关键词、向量检索与 Progressive Disclosure](05-context-storage/06-retrieval-progressive-disclosure/README.md)：11 篇节点博客
- [文件存储、SQLite 与 PostgreSQL 选型](05-context-storage/07-storage-selection/README.md)：12 篇节点博客

## 扩展与质量

- [子 Agent、任务状态与有界调度](06-extension-quality/01-subagent-scheduling/README.md)：15 篇节点博客
- [JSON-RPC、MCP 与 Transport](06-extension-quality/02-jsonrpc-mcp/README.md)：14 篇节点博客
- [Prompt、Rule、Skill、Tool 的边界](06-extension-quality/03-prompt-rule-skill-tool/README.md)：11 篇节点博客
- [日志、指标、Trace 与健康检查](06-extension-quality/04-observability-health/README.md)：14 篇节点博客
- [Tree-sitter、WASM 与 Chicory](06-extension-quality/05-tree-sitter-wasm/README.md)：12 篇节点博客
- [单元测试、Fake Server 与契约测试](06-extension-quality/06-testing-contracts/README.md)：13 篇节点博客
- [Agent 安全威胁模型](06-extension-quality/07-threat-model/README.md)：22 篇节点博客

## 质量口径

- 专题数：42
- 末级节点博客：538
- 每篇至少包含一个项目源码片段和一个机制完整 Java 实现；
- 完整实现复用所属父专题已经通过 Java 21 编译检查的代码；
- 每篇都必须解释“是什么、底层怎样工作、项目如何接线、为什么这样实现、失败时会怎样”。
