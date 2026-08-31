# 阶段一：架构与对象模型：系统学习路线

建立分层、依赖、对象作用域、设计模式和配置快照的统一语言。

返回[系统化学习指南](../../SYSTEMATIC_LEARNING_GUIDE.md)。

## 前置要求

- 能阅读基础 Java 代码、使用 Maven 和 `rg` 搜索源码。

## 专题顺序

01. [分层架构与应用服务](01-layered-architecture/README.md)：15 个节点，第 1 周。
02. [IoC、DI 与 Service Locator](02-ioc-di-service-locator/README.md)：13 个节点，第 2 周。
03. [对象作用域、全局状态与生命周期](03-scope-lifecycle/README.md)：12 个节点，第 3 周。
04. [HippoBuddy 中的设计模式](04-design-patterns/README.md)：11 个节点，第 4 周。
05. [配置系统与不可变快照](05-configuration/README.md)：14 个节点，第 5 周。

## 阶段验收项目

画出 ChatApiHandler → ConversationService → Orchestrator → LLM/Transcript 调用链，并用 Fake Adapter 验证用例。

## 通过标准

- 所有节点至少 L3；
- 每个专题至少留下一张闭卷调用链/状态图；
- 阶段项目有可运行代码或测试；
- 能在 15 分钟内完成该阶段核心架构讲解；
- 能指出项目当前实现至少三个真实缺口。

