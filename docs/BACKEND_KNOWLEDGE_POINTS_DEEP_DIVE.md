# HippoBuddy 后端知识点：实现原理与本质详解

> 配套主报告：[《HippoBuddy 后端技术路线与面试手册》](BACKEND_INTERVIEW_GUIDE.md)。  
> 阅读方式：不要背 API，重点掌握每个知识点的“不变量、状态、失败方式和取舍”。
> 分篇学习入口：[《42 个后端知识单元》](backend-knowledge/README.md)，每个知识点均有 Demo 和 Mermaid 思维导图。

## 1. 什么叫理解一个知识点的“本质”

面试官问“虚拟线程怎么实现”“为什么用 JSONL”“工具调用如何保证安全”，通常不是想听类名，而是在判断你是否理解四件事：

1. **它解决什么矛盾**：吞吐与资源、能力与安全、完整信息与有限 Token 等。
2. **核心状态在哪里**：会话消息、pending request、文件版本、Token 预算分别由谁维护。
3. **必须保持什么不变量**：同一 session 有序、tool call/result 成对、多文件锁顺序一致。
4. **失败时会怎样**：超时、重复执行、半写文件、连接断开、上下文溢出是否可恢复。

一个通用回答模板：

> 这个技术的本质是……；项目中由……保存状态，通过……维持不变量；它解决了……，但不能解决……；如果升级到……场景，我会增加……。

## 2. 架构与生命周期

### 2.1 分层架构与应用服务

**表象**：项目有 `web`、`application`、`domain`、`llm`、`tools` 等包。

**本质**：分层不是把文件放进不同目录，而是控制依赖方向和变化传播。HTTP 协议会变、模型供应商会变、存储介质也会变，但“创建会话、追加消息、执行 Agent Loop”这些应用用例应该保持稳定。

**项目实现**：

- `ChatApiHandler` 只处理 HTTP/SSE 参数和响应生命周期；
- `ConversationService` 聚合会话、上下文、Transcript 和 Memory；
- `WebAgentOrchestrator` 编排 LLM 与 Tool；
- `Conversation`、截断策略、Rule/Skill 属于领域模型；
- LLM、文件系统、HTTP Server 属于基础设施。

**关键不变量**：上层业务应该依赖抽象能力，而不是直接依赖某个供应商 JSON 或某个页面字段。

**边界**：当前 `WebAgentOrchestrator` 承担过多职责，说明分层方向存在，但应用编排内部还可进一步拆分。

**面试一句话**：

> 分层的价值不是目录整齐，而是让协议变化和基础设施变化不穿透核心用例。

### 2.2 IoC 与依赖注入

**表象**：`CoreModule` 向 `ServiceLocator` 注册 Config、LlmClient、ToolRegistry 等实例。

**本质**：控制反转是把“对象如何创建、依赖谁、活多久”的决定权，从业务对象转移给组合根。业务类只消费能力，不负责组装整个对象图。

**项目实现**：`CoreModule.configure()` 是 composition root，按基础设施 → 领域服务 → 工具层注册。`ServiceLocator` 以 `Class<?>` 为 key 保存 singleton/provider，并能反射创建无参对象。

**为什么能解耦**：调用方获取 `LlmClient` 接口，而不是硬编码 `OpenAiLlmClient`；测试可以替换接口实现。

**代价**：Service Locator 在方法内部全局查找依赖，会把真实依赖隐藏到运行期。构造器注入能在编译期暴露依赖，通常更易测试。

**改进**：保留 `CoreModule` 作为组合根，让业务类全部使用构造器注入；ServiceLocator 只留在边界层。

### 2.3 单例、全局状态与作用域

**表象**：Config、MemoryModule、部分 Manager 使用 `static` 或 singleton。

**本质**：单例解决的是“一个进程内只需要一份共享状态”，不是“全局变量天然合理”。真正要先判断作用域：进程级、workspace 级、session 级还是 request 级。

**项目映射**：

- `Config`、`ToolRegistry` 接近进程级；
- `WorkspaceContext` 是 workspace 级，但目前也由全局状态表达；
- `Conversation`、`TokenBudget` 必须是 session 级；
- SSE Writer 是 request/connection 级。

**风险**：测试之间状态串扰；切换工作区时旧缓存未失效；资源关闭顺序模糊；未来多租户无法隔离。

**判断原则**：对象包含谁的数据，就至少应该缩小到谁的作用域。

### 2.4 Factory、Adapter、Template Method 与 Strategy

这些模式的共同本质是**隔离变化轴**。

| 模式 | 项目例子 | 本质 |
|---|---|---|
| Factory | `LlmClientFactory`、`TokenEstimatorFactory` | 把“选哪个实现”集中管理 |
| Adapter | `McpToolAdapter`、不同 LLM Client | 把外部协议翻译为内部统一接口 |
| Template Method | `AbstractLlmClient` | 固定请求/重试/流处理骨架，允许子类替换差异步骤 |
| Strategy | 各类 `TruncationStrategy` | 同一目标有多种算法，运行时按内容类型选择 |
| Command | `ToolExecutor` | 把可执行动作封装为对象，统一注册、校验和调度 |
| Chain of Responsibility | `BlockerChain` | 多条规则按序检查，允许短路 |

**面试重点**：不要只说“用了设计模式”，要说清哪个变化轴被隔离。例如新增供应商时，Agent Loop 不应该修改，这才说明 Adapter 有价值。

### 2.5 应用生命周期与优雅关闭

**表象**：入口注册 shutdown hook，线程池执行 `shutdown/awaitTermination/shutdownNow`。

**本质**：优雅关闭是停止接收新工作、等待在途工作、刷出缓冲数据、释放外部资源，并在超时后强制退出。它是一段有顺序约束的状态迁移，不只是调用 `shutdown()`。

**项目实现**：

- `WebApplication`/`DesktopApplication` 管理 HTTP Server 生命周期；
- `ThreadPools` 注册 JVM shutdown hook；
- `GracefulShutdown` 先 shutdown，再最多等待 5 秒，最后 shutdownNow；
- `SessionTranscript` 和 `MemoryStore` 有各自的 flush/close 行为。

**问题**：项目同时存在 `ThreadPools` 和 `GracefulShutdown` 两套注册方式，部分模块还有自建静态 executor，可能出现重复关闭或漏关。

**理想顺序**：停止入口 → 取消 Agent → 等待工具 → flush Transcript/Memory → 关闭 MCP/LLM 连接 → 关闭 executor。

### 2.6 配置加载与环境变量

**本质**：配置是运行时策略，不是业务代码；密钥是 secret，不应进入代码和日志。配置系统还需要解决来源优先级、默认值、校验、快照一致性和动态更新。

**项目实现**：Jackson YAML 反序列化到分区 POJO；`EnvVariableResolver` 做变量替换；`Config` 聚合 LLM、Tools、Web、Memory、MCP 等配置。

**关键问题**：如果一次请求过程中配置被改了一半，可能出现模型、URL、工具快照不一致。因此复杂系统通常将配置加载为不可变 snapshot，更新时整体替换，并重建受影响客户端。

**密钥原则**：只在创建 HTTP Header 时使用；日志中不得输出 API Key，也不要把完整请求头持久化。

## 3. Java 并发与网络

### 3.1 虚拟线程

**表象**：Dashboard HTTP 和部分工具任务使用 `Thread.ofVirtual()` / `newVirtualThreadPerTaskExecutor()`。

**本质**：虚拟线程是由 JVM 调度的大量轻量执行上下文。阻塞 I/O 时，JVM 可以把虚拟线程从少量 carrier 平台线程上卸载，让 carrier 去运行别的任务。因此它降低的是“等待期间占用平台线程”的成本，不会让 CPU、内存、连接和外部 API quota 变无限。

**项目为什么适合**：LLM HTTP、SSE、文件 I/O、网页抓取大量时间处于等待状态；使用同步代码仍能获得较高 I/O 并发，避免 CompletableFuture 链过度复杂。

**不解决的事情**：

- CPU 密集计算仍受核心数限制；
- `synchronized` 中执行某些阻塞操作、native/foreign 调用可能 pin carrier；
- 数据库连接、文件描述符、LLM 并发仍需限流；
- 共享 Map 和文件仍需要并发控制。

**项目边界**：子 Agent 没有无限使用虚拟线程，而是有界平台线程池，因为瓶颈是 Token 和供应商并发额度。

### 3.2 有界线程池与业务限流

**本质**：线程池的真正作用不是“复用线程”这么简单，而是限制同时占用稀缺资源的任务数量，并通过队列/拒绝策略表达背压。

**项目实现**：`SubAgentManager` 并行度为 `max(2, CPU/2)`，队列上限 100，默认超时 300 秒。

**三种状态**：运行中、排队中、被拒绝。无界队列只是把过载从线程数变成内存和延迟，最终可能 OOM。

**容量依据**：子 Agent 的并行度应由 LLM rate limit、Token 预算、文件冲突率决定，而不应只由 CPU 数决定。当前公式是一个保守默认值，后续应配置化并结合指标调节。

### 3.3 Session 级锁

**本质**：锁保护的不是“代码块”，而是一组必须原子维护的不变量。同一 session 的消息顺序、tool_call/result 配对和 transcript 序号构成一个临界区。

**项目实现**：`ChatApiHandler` 获取 per-session lock；相同 session 串行，不同 session 并发。

**为什么不能只用线程安全 List**：集合线程安全只能保证单次 add 不破坏容器，不能保证“读取历史 → 调 LLM → 追加 assistant → 执行工具 → 追加 result”整段复合操作不被另一请求插入。

**粒度取舍**：全局锁最简单但吞吐差；session 锁准确匹配业务冲突域。

### 3.4 多文件锁与死锁避免

**本质**：死锁的循环等待来自不同任务以不同顺序申请资源。消除循环等待的方法之一，是对所有资源建立全局稳定顺序。

**项目实现**：`FileLockManager` 将路径绝对化、normalize、去重、排序，再依次取得 `ReentrantLock`，finally 逆序释放。

**为什么有效**：如果所有任务永远按 A < B < C 的顺序加锁，就不可能出现任务 1 持 A 等 B、任务 2 持 B 等 A。

**边界**：

- `ReentrantLock` 只在当前 JVM 生效；
- Map 中的 lock 没有按空闲状态淘汰，长期访问大量路径会增长；
- 当前所谓 read lock 也使用互斥 ReentrantLock，不是真正的读写锁；
- 路径规范化不等于解析 symlink 后的真实路径。

### 3.5 SSE

**本质**：SSE 是一个长时间不结束的 HTTP 响应。服务器以 `event:`/`data:` 文本帧持续向客户端单向推送，顺序由同一连接保证。

**项目实现**：Chat API 设置 `text/event-stream`，`SseWriter` 发送 reasoning、content、tool、token 和 error 事件并及时 flush。

**为什么适合**：交互方向主要是 server → client；用户的新输入、确认和取消仍可用普通 HTTP POST。相比 WebSocket，协议和代理兼容更简单。

**失败方式**：代理空闲超时、客户端断网、写阻塞、调用方消费过慢、事件发到一半断开。生产级需要心跳、队列上限、断线标识和可选 Last-Event-ID。

### 3.6 生产者—消费者与背压

**本质**：生产者和消费者速度不同，用队列进行时间解耦；但队列不能创造吞吐，只能吸收短期峰值。队列满时必须选择阻塞、拒绝、丢弃或降级。

**项目实例**：

- `SseWriter` 把多个事件生产者和单一网络写线程解耦；
- `SessionTranscript` 用容量 10,000 的队列、batch 50、500ms flush；
- SubAgent 使用容量 100 的任务队列。

**关键指标**：queue depth、enqueue wait、dropped/rejected count、consumer latency。没有这些指标就无法判断系统是在正常缓冲还是正在积压。

### 3.7 取消、超时和线程中断

**本质**：取消是协作协议，不是强行杀死任意代码。调用链中的每个可中断边界都要观察取消信号、关闭底层资源并停止产生新副作用。

**项目实现**：`SessionCancelManager` 保存 session 取消标志；Orchestrator 在 LLM 后、工具前和下一轮前检查；Bash 有进程管理器；Future/线程捕获 `InterruptedException` 后恢复中断标记。

**为什么要 `Thread.currentThread().interrupt()`**：捕获 InterruptedException 会清除中断状态，恢复标志才能让更上层知道取消发生过。

**超时不等于取消**：超时是触发取消的策略；真正释放资源仍需 close HTTP body、destroy process 或 cancel Future。

### 3.8 MDC 与跨线程上下文传播

**本质**：日志需要关联一次业务链路，但线程池任务会换线程，普通 ThreadLocal/MDC 不会自动携带 sessionId、toolName。

**项目实现**：`LoggingContext.snapshot()` 捕获 Map，在虚拟线程/工具线程中 `restore()`，finally clear。

**为什么必须 finally clear**：平台线程会复用，不清理会让下一任务继承上一 session 的日志字段，形成数据串线。

**更广义本质**：这和 tracing context、security context、locale 的传播是同一个问题——执行上下文和业务上下文不是一回事。

### 3.9 EventBus

**本质**：发布者只声明“发生了什么”，订阅者决定如何响应，从而解耦业务动作与日志/指标/通知。

**项目实现**：ConcurrentHashMap 保存事件类型到 CopyOnWriteArrayList handler；`publish()` 先全局订阅者，再精确类型订阅者；异常被捕获并告警。

**语义边界**：这是进程内同步 EventBus，不是 Kafka。它没有持久化、重试、跨进程、offset 和 exactly-once。慢订阅者会直接拖慢发布线程；一个订阅者异常还可能中断后续 handler，因为 try/catch 包在整体循环外。

## 4. Agent 与 LLM 协议

### 4.1 Agent Loop

**表象**：模型返回工具，后端执行后继续请求模型，最多 50 轮。

**本质**：Agent 是一个“模型决策 + 环境执行 +观察反馈”的闭环状态机：

```text
State_t + UserGoal
  → Model Policy 选择 Action
  → Runtime 校验并执行 Action
  → Observation 写回 State_(t+1)
  → 直到 Terminal Condition
```

LLM 不是执行器，它只是根据当前状态产生下一动作建议。后端 Runtime 才拥有权限、状态和终止权。

**项目状态**：Conversation messages、当前 turn、pending confirmation、cancel flag、remaining tool calls、AgentMode、TokenBudget。

**终止条件**：最终文本且无工具、取消、等待确认/用户输入、StopHook、错误、MAX_TURNS=50。

**架构改进**：目前大量状态隐含在 if/return 和多个 Map 中；显式枚举状态 + transition 能让恢复和测试更清晰。

### 4.2 Function Calling / Tool Calling

**本质**：把自由文本决策约束成结构化的 `{name, arguments}`，将“意图生成”和“副作用执行”分离。

**项目实现**：ToolExecutor 提供 name/description/JSON Schema；ToolRegistry 生成模型工具定义；模型返回 ToolCall；后端验证、执行，再以 role=tool 和 tool_call_id 写回。

**协议不变量**：

- name 必须对应已注册且当前模式可见的工具；
- arguments 必须是完整 JSON；
- 每个 tool_call_id 必须有匹配的 tool result；
- 工具结果必须出现在对应 assistant tool call 之后；
- 执行失败也要返回失败 result，不能让调用悬空。

### 4.3 SSE Delta 合并

**本质**：网络流提供的是字节/片段序列，不保证一次 chunk 对应一个 JSON 字段或一个完整 ToolCall。必须用累积状态把增量事件还原成逻辑消息。

**项目实现**：`SseParser` 解析单帧的 content、reasoning、usage、tool_call delta；`AbstractLlmClient` 按 tool index 累积 id、name 和 arguments，流结束后生成完整 ToolCall。

**为什么不能每帧 parse arguments**：arguments 字符串可能是 `{"pa`、`th":"a`、`.java"}` 三帧，前两帧都不是合法 JSON。正确做法是只拼接，完成后统一解析。

**防御**：限制 tool index 上限和 arguments 总长度，防止恶意/异常流造成稀疏数组或内存膨胀。

### 4.4 多供应商 Adapter

**本质**：建立 Anti-Corruption Layer，把外部供应商各自的认证、请求结构、事件字段和错误体，翻译为内部稳定模型。

**项目实现**：统一 `LlmClient`、Message、ChatRequest/Response、Usage、ToolCall；OpenAI-compatible 共享实现，Anthropic/Ollama/Responses 单独处理差异。

**正确抽象粒度**：不能假设所有供应商都只是 URL 不同。认证 Header、system message、工具协议、reasoning、usage、finish reason 可能都不同。

**扩展标准**：新增供应商时，WebAgentOrchestrator 和 ConversationService 不应改变；只增加 Adapter/Factory 分支和契约测试。

### 4.5 重试、指数退避和幂等

**本质**：重试是在不确定世界中重新执行请求。只有“故障是暂时的”并且“重放不会产生不可接受的重复副作用”时才安全。

**项目实现**：`RetryPolicy` 默认最多 3 次，1s 起步、2 倍退避、最大 10s；只重试连接、超时、5xx 和 rate limit。

**为什么 4xx 多数不重试**：认证错误、模型不存在、参数非法不会因等待自动恢复，盲目重试只增加延迟和费用。

**缺少 jitter 的问题**：许多客户端同时在固定 1/2/4 秒重试，会形成惊群。生产级应使用 full jitter，并尊重 `Retry-After`。

**LLM 请求的特殊风险**：超时时服务端可能已开始生成和计费，重试会重复费用；带工具副作用的整轮重放还需 tool_call UUID/业务幂等键。

### 4.6 Request Timeout 与 Idle Timeout

**本质**：超时不是一个数字，而是多个阶段：连接超时、等待响应头、两次流数据之间的 idle timeout、总 deadline。

**项目问题**：Java HttpClient 的 request timeout 不一定能阻止收到响应头后 body 永久静默。

**项目实现**：`IdleTimeoutInputStream` 的 watchdog 每 500ms 检查 `lastReadTime`；超过阈值关闭底层流，使阻塞 read 抛异常，再转换为明确超时。

**并发原理**：看门狗不能直接“唤醒 read”，但关闭同一个底层 stream 会让 read 返回异常，这是一种资源关闭驱动的协作取消。

**边界**：需要在 EOF/close 后停止 watchdog；轮询线程数量过多也有成本，未来可用共享 scheduler 管理 deadline。

### 4.7 错误分类

**本质**：错误处理不是展示一段字符串，而是把外部异常映射成可决策的内部语义：是否重试、是否提示改 Key、是否缩短上下文、是否切换模型。

**项目实现**：`LlmErrorClassifier` 按 provider-specific → body type/code → 文本 → HTTP status 的优先级分类为 AUTH_FAILED、RATE_LIMITED、CONTEXT_LENGTH_EXCEEDED 等。

**为什么要保留 detail**：统一 errorCode 用于程序决策，原始 detail 用于诊断；两者不能互相替代。

**安全点**：错误体可能包含供应商内部信息或用户输入，输出日志/前端前需要截断和脱敏。

### 4.8 Prompt 前缀缓存

**本质**：部分模型供应商会缓存相同输入前缀的 KV/计算结果。前缀只要有一处字节/Token 变化，后续大段缓存就可能失效。

**项目实现**：同 session 冻结 Tool Schema 快照，Prompt/规则/工具保持稳定顺序；记录 cacheReadInputTokens 和命中率。

**优化原则**：稳定内容放前面，易变内容放后面；工具列表排序固定；时间戳、随机 ID 不要放在稳定前缀；不要每轮无意义重建不同文本。

**本质收益**：减少首 Token 延迟和输入计费，不改变模型语义能力。

### 4.9 Token Usage 与成本

**本质**：Token 是模型侧的资源计量单位，不等于字符。成本是输入、输出、缓存读/写等不同单价与 usage 的函数。

**项目实现**：流式解析 Usage，`SessionTokenStats` 和 `CostMetricsCollector` 聚合 prompt/completion/cache token，并按模型价格估算。

**边界**：本地估算用于请求前预算，供应商 usage 用于请求后记账；二者可能因 tokenizer、隐藏 reasoning、工具 Schema 计数方式不同而不一致。

## 5. 工具系统与安全

### 5.1 Command + Registry

**本质**：把行为封装成具有统一元数据和执行接口的对象，再通过注册表完成发现和路由。调用者只知道工具名，不知道具体类。

**项目实现**：`ToolExecutor` 是 Command；`ToolRegistry` 保存 name → executor，并负责转 Schema、解析参数、执行 Blocker 和文件锁。

**收益**：新增工具无需修改 Agent Loop 的大分支；测试可以单独验证工具；权限、统计和截断可统一套在边界。

**边界**：特殊 Bash/Delete/AskUser 仍在 Orchestrator 中有分支，说明“所有工具完全统一”尚未实现。可把确认需求抽象成 ToolExecutionPlan/Effect。

### 5.2 JSON Schema 校验

**本质**：Schema 是模型输出和执行器之间的契约，用结构约束降低自然语言歧义，但不是安全证明。

**项目实现**：工具定义参数类型、必填字段等，`SchemaValidationBlocker` 在执行前检查。

**为什么仍要业务校验**：`path` 是 string 不代表它在工作区；`timeout` 是 number 不代表范围合理；命令符合 Schema 也可能危险。

**校验层次**：语法 JSON → Schema 结构 → 业务语义 → 权限/安全 → 执行期状态。

### 5.3 责任链 Blocker

**本质**：把多个相互独立的前置规则按序组合，任何 deny 都可短路；warning 可以累计/向后传递。

**项目实现**：Schema、ConcurrentEdit、BashDangerous 等 Blocker 返回 `HookResult`；`BlockerChain` 统计每个检查耗时、拦截数和慢样本。

**顺序意义**：便宜且确定的检查应放前面，例如参数结构先于磁盘/命令分析，以减少无效工作。

**边界**：责任链适合独立检查，不适合隐含复杂状态机；“等待确认后恢复”属于工作流，不应只靠 Blocker 表达。

### 5.4 AgentMode 与最小权限

**本质**：能力不是“注册了就都能用”。应根据当前任务模式授予最小工具集合，降低提示词攻击或模型误操作的爆炸半径。

**项目实现**：`AgentMode.CHAT` 只允许读、搜索、询问和 skill；CODING/OFFICE 才开放写文件、bash、delete、subagent 等。

**类似概念**：这是粗粒度 capability/RBAC。模式相当于角色，tool name 相当于 permission。

**边界**：只按工具名授权仍太粗。例如 bash 既能 `mvn test` 也能删除文件；生产级需要参数级 policy、路径 scope 和资源 quota。

### 5.5 路径规范化与 Sandbox

**本质**：用户/模型提供的是不可信路径。安全检查必须把多种字符串表示归一为实际资源身份，再判断是否位于允许根目录。

**项目实现**：相对路径以 workspace root 解析，转 absolute + normalize，使用 `startsWith(allowedRoot)`，并有敏感目录限制和 relaxed 模式。

**为什么 normalize 必要**：`workspace/a/../../secret` 字符串看似以 workspace 开头，规范化后已经越界。

**关键边界**：`normalize()` 只处理 `.`/`..`，不解析符号链接/junction。若 workspace 内 symlink 指向外部，仍可能逃逸；安全写入前应对现有祖先调用 `toRealPath()` 并防 TOCTOU，强隔离应使用 OS sandbox。

### 5.6 Human-in-the-loop 审批

**本质**：模型可以提出高风险动作，但最终授权由人给出。这是一种把不可逆副作用拆成 prepare/commit 两阶段的工作流。

**项目实现**：Bash/Delete 先生成预览和风险信息，保存 `Pending*Confirmation`，通过 SSE 发 confirmation；主循环暂停。确认接口再执行动作、处理剩余 tool calls，并恢复循环。

**状态要求**：confirmationId、sessionId、原参数、过期时间、是否已消费必须绑定，防止重放或跨会话确认。

**TOCTOU 问题**：预览到确认之间文件可能变化。commit 时应重新校验目标和版本，而不能完全信任旧预览。

### 5.7 并发编辑检测：乐观并发控制

**本质**：读取和写入之间不长期持锁，而是在写之前验证资源版本是否仍等于读取时版本；不同则拒绝覆盖。这就是乐观锁思想。

**项目实现**：文件快照/变更跟踪记录旧内容或指纹，`ConcurrentEditBlocker` 检查文件是否被用户或另一个任务修改。

**适用场景**：冲突概率低、读写间隔较长。Agent 可能思考数秒，长期持文件锁会严重影响用户编辑，因此乐观校验更合理。

**版本选择**：mtime 便宜但精度/伪造有限；内容 hash 准确但读文件成本高；可组合 size+mtime+hash。

### 5.8 Snapshot、Undo 与补偿事务

**本质**：文件系统缺少跨多文件 ACID 事务，发生错误时只能记录反向操作进行补偿。Undo 不是数据库 rollback，而是 Saga/补偿事务的简化形式。

**项目实现**：编辑前保存 Snapshot，执行后生成 diff，`UndoFileTool` 用旧快照恢复。

**边界**：如果用户在工具执行后又编辑了文件，直接 Undo 会覆盖新改动；恢复前同样需要版本检查或三方合并。大文件快照还要考虑空间和保留策略。

### 5.9 工具结果截断

**本质**：工具输出是非受控外部数据，可能远大于模型上下文。截断是在固定 Token 预算下尽量保留信息价值，不是简单 `substring`。

**项目实现**：`ContentClassifier` 区分 code/log/diff/list/tree/plain text；`TruncationService` 选择策略，受 per-tool safe limit 和 global hard limit 双重约束，最多迭代强制压缩。

**不同策略原因**：日志错误常在尾部；代码需要首尾和语法边界；diff 要保留 hunk；树结构要保留层次。相同 head-only 算法会丢掉不同类型的关键信息。

**注意**：`read_file` 当前绕过通用 tool output 截断，依赖读取工具自身分页/限制；面试可指出要统一验证最终 Token 上限。

### 5.10 并发工具结果排序

**本质**：执行可以乱序完成，但协议或 UI 可能要求与输入工具列表稳定对应。因此需要把“完成顺序”和“逻辑顺序”分离。

**项目实现**：`ConcurrentToolExecutor` 为每个 ToolCall 保存 index，Future 完成后按 index 排序结果。

**主链状态**：组件已经实现并注册，但 WebAgentOrchestrator 当前仍逐个执行工具，不能声称 Web 主链已经全面并发。

**并行前提**：只有副作用不冲突或已建立依赖/锁时才安全。两个 read 可以并行，write A 与基于 A 结果的 edit 不能盲目并行。

## 6. 上下文治理

### 6.1 Tokenizer 与 Token 估算

**本质**：模型处理的是 token 序列，字符只是输入表示。Token 数由模型 tokenizer 决定，同一文本在中文、英文、代码及不同模型下比例不同。

**项目实现**：`TokenEstimator` 抽象；`TiktokenEstimator` 优先，初始化失败回退 `SimpleTokenEstimator`；估算结果可缓存。

**为什么需要回退**：Token 预算是保护性功能，精确 tokenizer 不可用时“近似但可用”优于整个应用不能启动。

**边界**：OpenAI tokenizer 对其他供应商只是近似；最终以供应商返回 usage 为准，并留安全余量。

### 6.2 TokenBudget 与 Observer

**本质**：预算对象维护一个连续数值，多个策略关心它跨越阈值的事件。Observer 让计数与响应策略解耦。

**项目实现**：`TokenBudget.update()` 更新 AtomicInteger，检查 75/85/90/95/97.5 阈值；每个阈值只触发一次，通知 WarningInjector、AutoCompactTrigger、BlockingGuard 等 Listener。

**为什么只触发一次**：每新增消息都重新告警会污染上下文并产生事件风暴；reset 后才允许重新触发。

**并发点**：当前 token 值原子更新，triggeredThresholds 需要同步保护；Listener 本身也要避免耗时或递归修改预算。

### 6.3 滑动窗口

**本质**：在固定容量内保留最近且最相关状态，丢弃较旧信息。它是缓存淘汰/流式窗口思想在对话上的应用。

**项目实现**：`ContextClipper` 按 ConversationTurn 分组，从锚点或尾部选择目标 10k～40k Token 的窗口，优先保留最近 3 轮和至少 5 个有效文本块。

**最重要的不变量**：不能切断 assistant tool_call 与 tool result；system message 要保留；未完成工具轮要特殊处理。

**为什么不能按固定消息数**：每条消息 Token 差异巨大，且消息数不知道协议边界。

### 6.4 摘要压缩与两级降级

**本质**：滑窗是确定性删除，摘要是有损语义编码。前者稳定便宜，后者信息密度高但需要额外 LLM、可能幻觉或失败。

**项目实现**：`ManualCompactor`/压缩链优先尝试 ContextClipper，必要时调用 ContextSummarizer；加入 boundary marker 和摘要，`SessionCompactionState` 记录边界、次数和连续失败。

**为什么要记录边界**：增量压缩只应摘要“上次边界之后的新历史”，否则每次重复总结会逐渐漂移并重复计费。

**防止递归失败**：同一 query loop 限制压缩次数，连续失败达到阈值后停止尝试，避免“为了省 Token 反而耗尽 Token”。

### 6.5 Session Memory

**本质**：把工作状态从逐字对话历史提升为结构化、长期稳定的任务状态，例如目标、决策、修改文件、未完成项。它类似 checkpoint，而不是聊天全文备份。

**项目实现**：`session-memory.md`；达到初始 10k Token、后续增长 8k 或累计 5 次工具调用并处于自然停顿时触发提取。

**为什么在自然停顿提取**：工具调用尚未完成时抽取，可能得到不一致状态；等到一个完整动作结束，checkpoint 更可靠。

**恢复作用**：上下文过大时可以用 session memory +近期消息恢复，而不是重新加载全部历史。

### 6.6 内容分类与 Strategy

**本质**：信息价值取决于内容结构。先分类再选择压缩算法，本质是把统一资源约束与领域特定保留规则分开。

**项目实现**：ContentType 映射到 Code、Log、Diff、List、Tree、HeadTail 策略；注册 Map 允许扩展。

**评估方法**：不应只看压缩率，还要看关键错误行、diff hunk、文件路径、函数签名等是否被保留。可建立带答案的数据集做信息召回评测。

## 7. 文件型持久化与记忆

### 7.1 Append-only JSONL

**本质**：Append-only log 把每次状态变化记录为不可变事件。当前状态是事件顺序重放后的结果。它与 WAL/Event Sourcing 思想相近，但项目并非完整 Event Sourcing 框架。

**项目实现**：`conversation.jsonl` 每行一个 TranscriptEntry，持续 append；加载时按序恢复 Message。

**优势来源**：追加通常比重写大文件更小、更局部；进程崩溃多半只影响尾部；可流式扫描；用户可直接审计。

**代价**：读取完整状态需要重放；删除/修改需要 tombstone 或重写；跨文件事务弱；文件越来越大需要 compaction/snapshot。

### 7.2 WAL 和 Event Sourcing 的区别

**WAL 本质**：先记录恢复所需信息，再修改主状态，保证崩溃后可 redo/undo。

**Event Sourcing 本质**：事件本身是业务真相源，当前状态只是投影。

**项目定位**：Conversation JSONL 更像 append-only event log；session.json 是元数据投影。如果明确规定 JSONL 为 source of truth，metadata 可从日志重建，就更接近 Event Sourcing；目前跨文件语义还没有完全形式化。

### 7.3 异步批量刷盘

**本质**：每条消息立即写盘耐久性高但系统调用多；批量写吞吐高但会扩大尚未落盘的数据窗口。这是在 durability、latency 和 throughput 之间取舍。

**项目实现**：Transcript 队列 10,000，batch size 50，flush interval 500ms。消费线程批量写入 BufferedWriter 并 flush。

**崩溃窗口**：进程突然退出时，队列中及 OS page cache 中尚未真正持久化的数据可能丢失。`flush()` 只把 Java 缓冲送到 OS，不等于 fsync 到稳定介质。

**面试要诚实**：Memory 关键写入用了 `FileChannel.force(true)`；Transcript 的普通 flush 不能宣称提供同等级别的落盘保证。

### 7.4 有界队列与数据丢弃策略

**本质**：当磁盘长期慢于消息生产速度，系统必须决定“阻塞 Agent 保数据”还是“保持 Agent 响应但可能丢日志”。没有完美答案，要按数据重要性选择。

**项目实现**：队列满后短时间 offer，失败则告警/丢弃，避免主 Agent 无限阻塞。

**风险**：Transcript 是恢复依据，静默丢弃比普通日志严重。更稳妥方案是同步降级写、切换 emergency file、对 Agent 施加背压，或至少把 session 标为 incomplete。

### 7.5 UUID 幂等

**本质**：幂等表示同一逻辑操作执行多次，最终效果与一次相同。分布式/异步系统无法可靠区分“上次没执行”和“执行成功但响应丢了”，因此需要业务 id。

**项目实现**：TranscriptEntry 带 UUID；内存缓存记录最近 2 小时、最多 100,000 个 UUID，命中则跳过重复 append。

**边界**：缓存过期或进程重启后，需要从历史日志恢复部分 UUID；窗口外重复仍可能写入。真正强幂等需持久唯一索引或 sequence 约束。

### 7.6 原子文件替换

**本质**：不能直接覆盖关键文件，因为崩溃可能留下半个 JSON。安全模式是 copy-on-write：先生成完整新版本，再用原子 rename 让目录项一次切换。

**项目实现**：写 sibling temp file，Memory 关键路径 `FileChannel.force(true)`，然后 `Files.move(..., ATOMIC_MOVE, REPLACE_EXISTING)`。

**为什么同目录**：rename 的原子性通常只保证在同一文件系统；临时文件跨盘移动会退化为复制+删除。

**完整耐久性细节**：文件 fsync 后，极端断电一致性还可能需要 fsync 父目录，Java 跨平台支持有限。`ATOMIC_MOVE` 不支持时也要有降级策略。

### 7.7 崩溃恢复与尾行修复

**本质**：恢复代码必须假设最后一次写可能只完成前缀。追加日志的优势是可以丢弃损坏尾部，保留之前所有完整记录。

**项目实现**：`TranscriptLoader` 逐行解析，识别截断最后一行、兼容旧格式、寻找压缩边界，并修复孤立 tool call。

**为什么只自动处理尾部**：中间行损坏说明更严重的数据/磁盘问题，直接跳过可能破坏事件顺序；应告警并提供人工修复，而不能无声吞掉。

**恢复不变量**：得到的 Message 列表必须满足模型协议，即使最后一次工具执行中断，也要补失败 result 或移除不完整组合。

### 7.8 Markdown Frontmatter 记忆

**本质**：内容和元数据分离：Markdown body 给人和模型阅读，frontmatter 给程序索引。它是一种本地、透明的 document store。

**项目实现**：一条 Memory 一个 UUID.md；frontmatter 保存 type/tags/time 等；启动扫描建立 ConcurrentHashMap metadata index；内容按需读取。

**优点**：可 Git、可手工修改、易迁移、无服务依赖。

**缺点**：Schema 不强、跨文件事务弱、复杂查询慢、并发写需要自行实现、用户手改可能产生格式错误。

### 7.9 内存索引与缓存失效

**本质**：索引是源数据的派生投影，丢失后应该能重建；缓存正确性的核心不是“存起来”，而是何时失效。

**项目实现**：MemoryStore 启动扫描源 Markdown 重建 metadata Map；异步生成最多 200 行/25KB 的 `MEMORY.md` 摘要索引。持久上下文缓存 key 使用符合类型的记忆数量 + lastUpdated 时间戳和。

**失效边界**：时间戳和理论上可能碰撞；外部手改文件若未更新 frontmatter 时间或未触发重扫，缓存可能陈旧。更稳妥可使用目录 watcher、版本号或内容 hash。

### 7.10 关键词检索与向量检索

**关键词本质**：比较字面 token/标签重合；精准透明，但无法很好处理同义表达。

**向量本质**：Embedding 将文本映射到语义空间，以距离近似语义相关；召回强但需要模型、索引和评测，也可能召回“语义相似但任务无关”的内容。

**项目选择**：本地个人规模优先 Markdown、type/tag/title/keyword；持久偏好和项目上下文自动注入，其他知识不全量自动塞入。

**正确演进**：先建立查询集和相关性标注，再评估 BM25、embedding 和 hybrid search，不应为了“用了向量库”直接增加复杂度。

### 7.11 Progressive Disclosure

**本质**：上下文容量有限，先只暴露轻量索引；确定相关后再加载全文。它与虚拟内存按需分页、数据库二级索引的思想类似。

**项目实例**：系统 Prompt 只注入 Skill 名称和描述，需要时通过 `skill` 工具加载正文；Memory 索引也限制大小，详细内容按需读取。

**收益**：Skill/Memory 数量增长时，基础 Prompt 不线性膨胀；同时提高前缀稳定性。

### 7.12 为什么当前不使用数据库

**本质**：存储选型由数据访问模式、一致性级别、规模和部署约束决定，不是“数据库越高级越好”。

**当前访问模式**：单用户、本机、按 session 顺序追加、按 id/文件读取、强调可迁移和人类可读，JSONL/Markdown 的收益高。

**数据库更合适的信号**：多用户/多实例、复杂查询、跨实体事务、权限隔离、并发更新、百万级 Memory、审计与备份 SLA。

**演进方案**：SQLite 适合保持单机零运维并获得事务/索引；PostgreSQL 适合 SaaS。可保留事件模型，把 conversation event 存表、metadata 做投影、大 tool output 放对象存储。

## 8. 子 Agent、MCP 与开放扩展

### 8.1 子 Agent 任务模型

**本质**：子 Agent 是隔离的任务执行上下文，不只是新线程。它应拥有独立的 Conversation、状态、预算、超时、权限和结果边界。

**项目实现**：`SubAgentTask` 管理 taskId/status/dependencies/timeout；Manager 管理 active Map、log、callback；Runner 运行子 Agent Loop。

**状态机**：PENDING → WAITING/RUNNING → COMPLETED/FAILED/CANCELLED。状态迁移应是单向且幂等，完成回调只能触发一次。

**资源约束**：有界并行/队列、超时和取消，防止一个主 Agent 指数级 fork。

### 8.2 父子上下文与前缀复用

**本质**：子 Agent 需要足够上下文理解任务，但复制全部历史会增加 Token。保持父消息前缀不变可争取供应商 Prompt Cache，新增任务指令放在尾部。

**项目实现**：新建独立 sub Conversation，复制/复用父消息内容，再追加 instruction。

**准确口径**：这更准确叫“上下文前缀复用”，不应仅凭日志里的“零拷贝”就声称 Java 内存完全零复制。

**隔离问题**：父子列表不能共享可变 Message 容器导致相互修改；文件副作用仍共享同一 workspace，需要 Tool 层锁和权限。

### 8.3 DAG 依赖与调度

**本质**：`dependsOn` 将任务关系从并行列表升级为有向无环图。节点只能在所有前驱成功/完成后运行。

**需要处理**：依赖不存在、依赖失败传播、循环依赖检测、取消传播、部分结果是否允许继续。

**项目现状**：具备 dependsOn 和等待语义；面试中不要扩展描述成成熟 DAG 调度平台，除非能展示完整 cycle detection、持久化和重启恢复。

### 8.4 JSON-RPC 2.0

**本质**：请求和响应通过 id 关联，notification 没有响应，error 有标准结构。传输可以是 stdio、SSE 或其他通道，RPC 语义与 transport 分离。

**项目实现**：`JsonRpcHandler` 生成递增 id，pending Map 保存 `id → CompletableFuture`；收到响应按 id complete；定时清理超时请求；断开时异常完成所有 pending。

**并发关键**：响应可以乱序到达，因此不能靠发送顺序匹配；id 必须唯一。future 只能完成一次，超时与正常响应竞争时需要原子 remove/complete。

### 8.5 MCP 初始化握手

**本质**：客户端和服务端先交换 protocolVersion、capabilities、client/server info，再正式使用工具。握手避免双方对功能做错误假设。

**项目实现**：发送 `initialize`，保存 serverInfo，再发送 `initialized` notification；之后 list tools/resources/prompts 并注册 Adapter。

**接入状态**：`McpServiceManager` 有完整管理逻辑，但当前入口未调用 initialize，属于“组件实现、主链未接线”。

### 8.6 stdio Transport

**本质**：父进程启动 MCP 子进程，以 stdin/stdout 传结构化消息。操作系统 pipe 提供字节流和进程隔离边界。

**项目实现**：`StdioMcpClient` 启动 Process、写 stdin、读 stdout，JSON-RPC 负责消息匹配。

**关键约束**：stdout 必须只输出协议消息，普通日志要写 stderr；要持续消费 stderr 防止 pipe 填满导致子进程阻塞；进程退出必须清理 pending future；命令和环境变量也需要信任控制。

### 8.7 SSE MCP Transport

**本质**：用一个长连接接收 server → client 事件，另一个 HTTP POST 通道发送 client → server 消息，从而模拟双向 RPC。

**项目实现**：OkHttp EventSource 收消息，HTTP 客户端 POST 发请求；AbstractMcpClient 负责重连次数、延迟和 disconnect listener。

**重连难点**：连接恢复不代表旧 session/pending request 仍有效；必须决定旧请求失败、重放还是查询状态。盲目重放 tool call 可能产生重复副作用。

### 8.8 Prompt、Rule、Skill、Tool 的本质区别

| 概念 | 本质 | 是否产生副作用 | 加载方式 |
|---|---|---:|---|
| Prompt | 定义模型角色与推理行为 | 否 | 通常每轮 system 前缀 |
| Rule | 长期有效的约束/政策 | 否 | 项目/用户级选择性注入 |
| Skill | 按需加载的操作知识 | 否 | 先索引、后读取全文 |
| Tool | 读取外部状态或执行动作 | 可能 | 结构化调用并由 Runtime 授权 |

**面试重点**：Skill 不是 Tool。Skill 告诉模型“如何做”，Tool 才让系统“真的做”。把所有知识塞 system prompt 会导致 Token 膨胀和缓存失效。

## 9. 可观测性、解析与测试

### 9.1 日志、指标和 Trace 的区别

- **Log**：离散事件的详细上下文，适合排查单次故障；
- **Metric**：聚合数字时间序列，适合告警和趋势；
- **Trace**：一次请求跨组件的因果路径，适合定位延迟。

**项目实现**：SLF4J/Logback + MDC；Cost/Event Metrics；session/tool/turn 等字段关联日志。尚不是完整分布式 tracing。

**Agent 特有指标**：首 Token 延迟、每轮耗时、平均 turns、工具成功率、confirmation 率、cache hit、Token/费用、上下文压缩次数、子 Agent queue time。

### 9.2 Health Check

**本质**：健康检查回答“实例是否存活”和“是否准备好接流量”，而不是罗列所有内部状态。

**项目实现**：HealthCheckRegistry 聚合 System、Config、LLM indicator。

**边界**：本地应用主要用于诊断；服务化后应拆：

- liveness 只判断进程是否卡死，不依赖外部 LLM；
- readiness 判断配置、磁盘、关键依赖是否可用；
- 不应每次探针都调用收费模型。

### 9.3 成本指标

**本质**：Agent 的成本不是请求数，而是多轮输入/输出、工具回填、子 Agent 和缓存行为的共同函数。

**项目实现**：Usage + `LlmPricing` 估算；session stats 汇总 cache hit/miss。

**业务用途**：预算拦截、模型路由、异常循环检测、功能 ROI。价格表会变化，应配置化并记录版本，历史账单不能用新价格重新解释。

### 9.4 Tree-sitter + WASM + Chicory

**本质**：Tree-sitter 是增量语法解析器；WASM 是可移植、安全边界较清晰的字节码格式；Chicory 让 JVM 直接执行 WASM，避免 JNI/native library 的平台分发问题。

**项目实现**：`TreeSitterWasmParser` 加载语言 Parser WASM，返回结构化 SyntaxError，用于 lint diagnostics。

**为什么比正则可靠**：语法错误、括号和字符串上下文需要语法树，正则无法正确处理嵌套语言结构。

**边界**：需要为每种语言提供兼容 grammar；WASM 初始化和解析有成本；语法正确不代表类型/语义正确，不能替代 javac/语言服务器。

### 9.5 单元测试

**本质**：验证一个小单元在可控输入下保持不变量。不是“类覆盖了多少行”，而是关键边界和错误路径是否被证明。

**本项目高价值单测**：SSE 拆帧合并、Retry 分类、Context tool pair、锁排序、危险命令、截断策略、JSONL 尾行恢复。

**测试替身选择**：纯逻辑用 fake/stub；只验证交互时用 mock；不要把所有对象都 mock 到只剩实现细节。

### 9.6 契约测试与 Fake Server

**本质**：外部协议 Adapter 最容易发生“本地单测通过、供应商格式变了”。契约测试验证请求/响应边界。

**实现建议**：本地 fake HTTP Server 按脚本发送 SSE：正常 chunk、arguments 拆帧、429 + Retry-After、500、错误 JSON、响应头后静默、突然断线。MCP 用 fake stdio process 和 fake SSE endpoint。

**真实 API 测试**：少量、可选、使用专用 Key 和费用上限，不应成为每个 PR 的不稳定依赖。

### 9.7 覆盖率

**本质**：覆盖率只说明代码被执行，不说明断言正确，更不说明需求完整。Branch coverage 比 line coverage 更接近控制流风险，但仍不是质量本身。

**项目现状**：已引入 JaCoCo，但无强制门禁；CI Maven test 被注释，release 跳过测试。正确口径是“测试资产丰富，但持续质量门禁需要恢复”，不能声称全量测试当前稳定通过。

### 9.8 安全威胁模型

**本质**：先识别资产、信任边界、攻击者和影响，再选择控制。这个项目最大的信任边界不是登录表单，而是“非可信 Prompt/网页内容 → LLM 决策 → 本机 Tool 副作用”。

**主要威胁**：

1. Prompt injection 引导读取密钥或执行危险命令；
2. Path traversal/symlink 逃出工作区；
3. Dashboard 绑定公网且无鉴权；
4. 恶意 MCP Server 返回危险 Schema/内容；
5. 工具输出把秘密回传给模型供应商；
6. 审批预览与实际执行之间发生 TOCTOU；
7. 日志/Transcript 保存敏感内容。

**纵深防御**：最小工具权限、路径 allowlist、OS sandbox、网络 egress policy、人工审批、参数级 policy、secret redaction、审计、localhost token、MCP 信任列表。

**本质结论**：字符串黑名单只能是辅助控制，真正的安全来自能力隔离和最小权限。

## 10. 把知识点串成 8 条面试主线

### 主线一：一次对话怎么跑完

Session lock → 组装 Prompt/Memory → LLM SSE → delta 合并 → Tool Registry → Blocker/HITL → tool result → 下一轮 →终止/持久化。

### 主线二：并发为什么不乱

不同 session 用虚拟线程并发；同 session 串行；文件写用规范化路径锁；编辑前做乐观版本检查；子 Agent 有界并发。

### 主线三：模型为什么不会直接伤害系统

模型只生成提议；AgentMode 限权；Schema/Blocker/Path sandbox 检查；高风险动作人工审批；Runtime 才执行。

### 主线四：长会话怎么不爆

Tokenizer 估算 → TokenBudget 阈值 → 工具输出分类截断 →按完整轮次滑窗 → LLM 摘要 → Session Memory checkpoint。

### 主线五：异常退出后怎么恢复

JSONL append → UUID 幂等 →批量 flush →尾行检测 →工具对修复 → session-memory +近期消息恢复。

### 主线六：如何兼容多个模型

内部统一模型 → Factory 选 Provider Adapter → Template Method 复用流处理 →错误分类 →临时故障退避重试。

### 主线七：如何扩展能力

Tool Command/Registry → Skill progressive disclosure → SubAgent 独立上下文 → MCP JSON-RPC/Transport/Adapter。

### 主线八：如何从本地版演进到 SaaS

localhost 单用户假设 →鉴权/RBAC/租户 → OS 容器沙箱 → PostgreSQL 事件存储 →任务队列/租约 →对象存储 →指标与 Trace →预算和审计。

## 11. 判断自己是否真的掌握

如果下面问题能脱离文档回答，就已经不是“背项目”：

1. 为什么线程安全集合不能代替 session lock？
2. 为什么虚拟线程仍然需要业务限流？
3. 为什么 `normalize()` 不能完全防住 symlink 逃逸？
4. 为什么收到 HTTP 响应头后仍可能永久卡住？
5. 为什么 tool arguments 不能每个 SSE chunk 单独 parse？
6. 为什么 tool execution 失败也要写一条 tool result？
7. 为什么多文件锁排序能消除循环等待？
8. 为什么 `flush()` 不等于 fsync？
9. JSONL 更像 WAL 还是 Event Sourcing？当前项目差在哪里？
10. 为什么滑窗必须按完整 ConversationTurn，而不是消息条数？
11. 为什么 LLM 摘要应该是滑窗之后的第二级方案？
12. 为什么 Human-in-the-loop 仍然有 TOCTOU？
13. 为什么关键词检索在当前项目可能比向量数据库更合适？
14. 为什么 MCP request 必须靠 id 而不是顺序匹配？
15. 为什么“有 2,557 个测试注解”不能证明高质量？

## 12. 源码对照表

| 知识点 | 建议阅读源码 |
|---|---|
| 启动/DI | `DesktopApplication`、`WebApplication`、`CoreModule`、`ServiceLocator` |
| 虚拟线程/关闭 | `DashboardServer`、`ThreadPools`、`GracefulShutdown` |
| HTTP/SSE | `ChatApiHandler`、`SseWriter` |
| Agent Loop | `WebAgentOrchestrator`、`StopHook` |
| LLM Adapter | `LlmClientFactory`、`AbstractLlmClient`、各 Provider Client |
| 流式解析 | `SseParser`、`IdleTimeoutInputStream` |
| 重试/错误 | `RetryPolicy`、`LlmErrorClassifier` |
| 工具注册 | `ToolExecutor`、`ToolRegistry`、`ConcurrentToolExecutor` |
| 工具安全 | `BlockerChain`、各 Blocker、`PathSecurityUtils`、`AgentMode` |
| 文件并发 | `FileLockManager`、`FileChangeTracker`、`FileSnapshotService` |
| Token/压缩 | `TokenBudget`、`ContextWindow`、`ContextClipper`、`ContextSummarizer` |
| 截断 | `TruncationService`、`ContentClassifier`、各 Strategy |
| 会话日志 | `SessionTranscript`、`TranscriptLoader`、`SessionStorage` |
| 记忆 | `MemoryStore`、`MemoryRetriever`、`SessionMemoryExtractor` |
| 子 Agent | `SubAgentManager`、`SubAgentRunner`、`SubAgentTask` |
| MCP | `JsonRpcHandler`、`AbstractMcpClient`、`McpServiceManager`、`McpToolAdapter` |
| Prompt/Rule/Skill | `PromptLibrary`、`RuleManager`、`SkillManager` |
| 可观测性 | `LoggingContext`、`CostMetricsCollector`、`HealthCheckRegistry` |

学习时每看一个类，都尝试回答：它持有什么状态、谁能修改、如何并发、如何失败、如何恢复。能回答这五个问题，才算真正理解实现原理。
