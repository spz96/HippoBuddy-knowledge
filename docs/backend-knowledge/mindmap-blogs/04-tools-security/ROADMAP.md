# 阶段四：工具执行与安全：系统学习路线

把模型建议转成经过 Schema、权限、路径、确认、版本和锁保护的副作用。

返回[系统化学习指南](../../SYSTEMATIC_LEARNING_GUIDE.md)。

## 前置要求

- 完成[阶段三：Agent 与 LLM 协议](../03-agent-llm/ROADMAP.md)至少 L3 验收。

## 专题顺序

01. [Command、Tool Registry 与 JSON Schema](01-command-registry-schema/README.md)：13 个节点，第 22 周。
02. [Blocker 责任链与能力权限](02-blocker-capability/README.md)：12 个节点，第 23 周。
03. [路径规范化、Sandbox 与符号链接](03-path-sandbox/README.md)：12 个节点，第 24 周。
04. [Human-in-the-loop 与两阶段执行](04-human-in-the-loop/README.md)：14 个节点，第 25 周。
05. [乐观并发、快照与补偿事务](05-edit-snapshot-compensation/README.md)：12 个节点，第 26 周。
06. [工具输出分类与截断策略](06-output-truncation/README.md)：14 个节点，第 27 周。
07. [工具并发、依赖与结果排序](07-concurrent-tools/README.md)：10 个节点，第 28 周。

## 阶段验收项目

实现安全文件编辑链：canonical path → capability → confirmation → compare-and-write → undo。

## 通过标准

- 所有节点至少 L3；
- 每个专题至少留下一张闭卷调用链/状态图；
- 阶段项目有可运行代码或测试；
- 能在 15 分钟内完成该阶段核心架构讲解；
- 能指出项目当前实现至少三个真实缺口。

