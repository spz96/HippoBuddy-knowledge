# 阶段五：上下文、持久化与检索：系统学习路线

掌握 Token 预算、协议安全压缩、JSONL 重放、耐久写、索引缓存和检索选型。

返回[系统化学习指南](../../SYSTEMATIC_LEARNING_GUIDE.md)。

## 前置要求

- 完成[阶段四：工具执行与安全](../04-tools-security/ROADMAP.md)至少 L3 验收。

## 专题顺序

01. [Tokenizer、Token 估算与预算监听](01-token-budget/README.md)：14 个节点，第 29 周。
02. [滑动窗口、摘要压缩与 Session Memory](02-context-compaction/README.md)：13 个节点，第 30 周。
03. [JSONL、Append-only Log 与 Event Sourcing](03-jsonl-event-log/README.md)：12 个节点，第 31 周。
04. [批量刷盘、幂等、原子写与崩溃恢复](04-file-durability/README.md)：12 个节点，第 32 周。
05. [Markdown 记忆、索引与缓存失效](05-memory-index-cache/README.md)：12 个节点，第 33 周。
06. [关键词、向量检索与 Progressive Disclosure](06-retrieval-progressive-disclosure/README.md)：11 个节点，第 34 周。
07. [文件存储、SQLite 与 PostgreSQL 选型](07-storage-selection/README.md)：12 个节点，第 35 周。

## 阶段验收项目

对 Transcript 做崩溃恢复实验，并为 Memory 构建检索评测集与缓存失效测试。

## 通过标准

- 所有节点至少 L3；
- 每个专题至少留下一张闭卷调用链/状态图；
- 阶段项目有可运行代码或测试；
- 能在 15 分钟内完成该阶段核心架构讲解；
- 能指出项目当前实现至少三个真实缺口。

