# 阶段三：Agent 与 LLM 协议：系统学习路线

掌握 Agent 状态机、Function Calling、流式组装、Provider 适配、重试、错误、缓存和成本。

返回[系统化学习指南](../../SYSTEMATIC_LEARNING_GUIDE.md)。

## 前置要求

- 完成[阶段二：并发、网络与取消](../02-concurrency-network/ROADMAP.md)至少 L3 验收。

## 专题顺序

01. [Agent Loop 与状态机](01-agent-loop-state-machine/README.md)：14 个节点，第 14 周。
02. [Function Calling 与工具协议](02-function-calling/README.md)：14 个节点，第 15 周。
03. [SSE Delta 解析与增量合并](03-stream-delta-assembly/README.md)：13 个节点，第 16 周。
04. [多供应商 Adapter 与统一模型](04-provider-adapter/README.md)：12 个节点，第 17 周。
05. [重试、指数退避与幂等](05-retry-backoff-idempotency/README.md)：10 个节点，第 18 周。
06. [错误分类与异常语义](06-error-taxonomy/README.md)：16 个节点，第 19 周。
07. [Prompt 前缀缓存](07-prompt-cache/README.md)：13 个节点，第 20 周。
08. [Token Usage、价格与成本治理](08-token-cost/README.md)：14 个节点，第 21 周。

## 阶段验收项目

用脚本化 Fake LLM 完成含工具、重试、取消和成本记账的一轮 Agent。

## 通过标准

- 所有节点至少 L3；
- 每个专题至少留下一张闭卷调用链/状态图；
- 阶段项目有可运行代码或测试；
- 能在 15 分钟内完成该阶段核心架构讲解；
- 能指出项目当前实现至少三个真实缺口。

