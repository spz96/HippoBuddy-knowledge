# 阶段二：并发、网络与取消：系统学习路线

掌握虚拟线程、背压、锁、SSE、队列、取消和异步上下文传播。

返回[系统化学习指南](../../SYSTEMATIC_LEARNING_GUIDE.md)。

## 前置要求

- 完成[阶段一：架构与对象模型](../01-architecture/ROADMAP.md)至少 L3 验收。

## 专题顺序

01. [Java 21 虚拟线程](01-virtual-threads/README.md)：11 个节点，第 6 周。
02. [有界线程池、队列与背压](02-bounded-pool-backpressure/README.md)：11 个节点，第 7 周。
03. [Session 锁、原子性与临界区](03-session-lock-atomicity/README.md)：11 个节点，第 8 周。
04. [多文件锁与死锁](04-file-lock-deadlock/README.md)：12 个节点，第 9 周。
05. [SSE 协议与流式响应](05-sse/README.md)：12 个节点，第 10 周。
06. [生产者—消费者、批处理与背压](06-producer-consumer/README.md)：13 个节点，第 11 周。
07. [取消、超时、线程中断与 Watchdog](07-cancellation-timeout-watchdog/README.md)：11 个节点，第 12 周。
08. [MDC 上下文传播与 EventBus](08-mdc-eventbus/README.md)：12 个节点，第 13 周。

## 阶段验收项目

构造同 Session 竞态与 SSE 断开，完成 deadline、取消传播、资源关闭和确定性结果测试。

## 通过标准

- 所有节点至少 L3；
- 每个专题至少留下一张闭卷调用链/状态图；
- 阶段项目有可运行代码或测试；
- 能在 15 分钟内完成该阶段核心架构讲解；
- 能指出项目当前实现至少三个真实缺口。

