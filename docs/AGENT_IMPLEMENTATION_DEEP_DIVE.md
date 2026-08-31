# HippoBuddy Agent 实现原理深度手册

这份文档不再停留在“Agent = LLM + Tool”这一层，而是沿真实源码回答五个问题：**状态存在哪里、数据怎样流动、执行顺序是什么、必须维护哪些不变量、在哪些故障窗口会失效**。

建议配合 [Agent 专项面试手册](AGENT_INTERVIEW_PLAYBOOK.md) 使用：专项手册用于快速口述，本篇用于源码追问、系统设计追问和改进方案。

---

## 1. 先用工程语言定义 Agent

从运行时视角看，Agent 不是一个模型，也不是一次 API 请求，而是一个受控的状态转换系统：

```text
State(t) + ExternalEvent
        ↓
Prompt/Context Assembly
        ↓
LLM Policy → AssistantText | ToolCalls
        ↓
Runtime Validation → Authorization → Execution
        ↓
Observation / Pause / Failure
        ↓
State(t+1)
```

可以写成：

```text
S(t+1) = reduce(S(t), validate(execute(policy(S(t)))))
```

其中：

- `policy` 是 LLM，具有概率性，不能被信任；
- `reduce`、权限校验和副作用执行属于 Runtime，必须确定、可审计；
- ToolCall 是模型提出的动作意图，不是执行授权；
- ToolResult 是环境 observation，必须和 ToolCall 通过 `tool_call_id` 成对；
- “等待用户确认”不是循环结束，而是持久化状态机中的暂停状态；
- SSE 是状态投影，不应成为唯一事实来源；
- Transcript/Checkpoint 才应承担恢复依据。

面试时先说这一句：

> LLM 决定“想做什么”，Agent Runtime 决定“能不能做、怎样做、结果如何进入下一轮”，两者之间的信任边界才是 Agent 工程化的核心。

---

## 2. 运行时对象和状态所有权

HippoBuddy 当前不是一个单一 `Agent` 对象，而是多个组件共同持有状态：

| 状态 | 当前所有者 | 生命周期 | 是否持久化 |
|---|---|---|---|
| 对话消息、Token 预算 | `Conversation` / `ContextWindow` | session | Transcript 异步持久化 |
| Agent 最大轮次、工具快照 | `WebAgentOrchestrator` | session/process | 否 |
| 取消标记 | `SessionCancelManager` | session/process | 否 |
| ask_user / Bash / Delete 挂起项 | `WebSessionManager` 静态 Map | session/process | 否 |
| 确认后的剩余 ToolCalls | `WebAgentOrchestrator.remainingToolCalls` | session/process | 否 |
| 会话互斥锁 | `WebSessionManager.sessionLocks` | session/process | 否 |
| 工具注册表 | `ToolRegistry` | process | 否 |
| 文件锁 | `FileLockManager` | path/process | 否 |
| UI 流式状态 | Zustand `sessionStreams` | browser session | 否 |
| 会话日志 | `SessionTranscript` JSONL | disk | 是，异步批量 |
| 长期记忆 | `MemoryStore` | disk/process | 是 |
| Sub-Agent 任务 | `SubAgentManager` / `SubAgentTask` | process | 否 |
| MCP 连接和请求 Future | MCP Client / `JsonRpcHandler` | process/connection | 否 |

这张表能直接推导出恢复边界：进程崩溃后，消息可能从 JSONL 恢复，但确认点、剩余动作、Sub-Agent、MCP 在途调用、取消状态无法恢复。

关键源码：

- [ChatApiHandler.java](../src/main/java/com/example/agent/web/handler/ChatApiHandler.java)
- [WebAgentOrchestrator.java](../src/main/java/com/example/agent/web/orchestrator/WebAgentOrchestrator.java)
- [WebSessionManager.java](../src/main/java/com/example/agent/web/session/WebSessionManager.java)
- [ConversationService.java](../src/main/java/com/example/agent/application/ConversationService.java)
- [SessionTranscript.java](../src/main/java/com/example/agent/session/SessionTranscript.java)

---

## 3. 一次请求怎样进入 Agent

### 3.1 请求入口的真实顺序

`ChatApiHandler` 的主要执行顺序是：

```text
POST /api/chat
  → 先设置 200 + text/event-stream
  → 解析 sessionId/message/mode/rules/images/editMessageId
  → 组装 mode prompt、rules、workspace、skills、date、environment
  → 获取 session lock
  → reset cancel flag
  → 创建或恢复 Conversation
  → 处理 pending ask_user / 清理旧确认
  → 追加 user message
  → setSessionRunning(true)
  → orchestrator.execute(...)
  → finally: unlock + running(false) + complete + close
```

因为响应头在解析和校验之前就已经写成 SSE，后续参数错误、配置错误和执行错误通常只能作为 `error` 事件表达，而不是再改成标准 HTTP 4xx/5xx。这里体现了两层错误协议：

- HTTP 层只表示“流是否建立”；
- SSE 事件表示“任务执行是否成功”。

生产设计中应统一错误 envelope，例如：

```json
{
  "code": "TOOL_ARGUMENT_INVALID",
  "message": "path is required",
  "retryable": false,
  "turn": 3,
  "traceId": "..."
}
```

### 3.2 同会话为什么要串行

同一个 session 若并发执行两个请求，会出现：

- 两个模型都基于相同旧历史决策；
- assistant/tool 消息交叉写入，破坏 Function Calling 配对；
- 一个请求清除另一个请求的 pending confirmation；
- 取消标记、running 标记互相覆盖；
- Transcript 顺序不再代表因果顺序。

因此 `WebSessionManager` 为每个 `sessionId` 使用 `ReentrantLock`。但当前超时处理不是“返回失败”，而是把 Map 中的旧锁移除、创建新锁并阻塞获取。旧请求仍可能持有旧锁，新请求却拿到新锁，于是**锁对象被替换后，同一会话可以同时进入临界区**。

这类问题的本质是：锁的 identity 本身也是共享状态，不能在仍可能被持有时替换。

更稳妥的实现：

```java
ReentrantLock lock = locks.computeIfAbsent(sessionId, ignored -> new ReentrantLock());
if (!lock.tryLock(30, TimeUnit.SECONDS)) {
    throw new SessionBusyException(sessionId);
}
try {
    runSessionTurn();
} finally {
    lock.unlock();
    // 只有能证明无人持有、无人等待时才能有条件移除；也可直接保留。
}
```

进一步可使用每 session 的单线程 mailbox/actor，让所有 `UserMessage`、`Confirm`、`Cancel` 进入同一事件队列，从结构上保证顺序。

---

## 4. Agent Loop 的逐行级原理

`WebAgentOrchestrator.execute` 最多执行 50 轮。每一轮不是“再问一次模型”这么简单，而是下面的事务链：

```text
1. 检查 cancel
2. 检查是否已有 pending confirmation
3. 读取推理上下文
4. 确保 system message 在首位
5. 修复孤立 ToolCall/ToolResult
6. 发 thinking SSE
7. 调用 LLM 流式接口并聚合 delta
8. 得到完整 Assistant Message
9. 先持久化 Assistant Message
10. 无 ToolCall → done
11. 有 ToolCall → 逐个执行并写入 ToolResult
12. pending/cancel → 暂停或退出
13. observation 已齐全 → 下一轮
```

### 4.1 为什么 Assistant ToolCall 必须先落状态

正确顺序是：

```text
persist assistant(tool_calls)
    → execute side effect
    → persist tool_result
```

如果先执行工具再记录 ToolCall，执行后进程崩溃，就出现“环境已变化，但系统没有动作记录”。当前实现至少先通过 `ConversationService.addAssistantMessage` 添加 Assistant Message，再进入工具执行，这是正确的因果顺序。

但当前 Transcript 是异步队列，所以“加入内存 Conversation”不等于“ToolCall 已耐久落盘”。严格的副作用一致性仍需要 write-ahead journal 或同步 checkpoint：

```text
INTENT(toolCallId, argsHash) --fsync-->
EXECUTE
RESULT(toolCallId, status) --fsync-->
```

### 4.2 Function Calling 协议不变量

至少维护以下不变量：

1. 每个 assistant tool call 都有非空唯一 `tool_call_id`；
2. 每个 tool result 引用一个已存在的 call id；
3. 一次 call 最多有一个终态 result；
4. assistant(tool_calls) 后紧跟其结果集合，再进入下一次 assistant；
5. 失败也必须形成 ToolResult，不能只写日志；
6. 取消和人工拒绝也要成为显式 observation；
7. 不把半截 JSON 参数交给工具执行。

`MessageSanitizer.removeOrphanToolCalls` 会在发送模型前修复不完整配对。它解决的是“让 Provider 接受请求”的协议防御，不能代替持久化层从源头保证一致性。否则恢复时虽然请求能发出去，但审计事实已被静默改写。

### 4.3 终止条件

当前主要终止条件是：

- 模型没有返回 ToolCall；
- 收到会话取消；
- 进入 ask_user 或危险工具确认；
- LLM/工具抛出不可恢复错误；
- 达到 `MAX_TURNS = 50`。

更成熟的终止策略还应包括：

- 总 Token/金额预算；
- 总工具调用数和单工具次数；
- wall-clock deadline；
- 连续相同 action 检测；
- 连续无进展检测；
- 同一错误指纹的重试上限；
- 用户定义目标校验器。

---

## 5. LLM 流式调用是怎样还原成完整动作的

关键源码：

- [AbstractLlmClient.java](../src/main/java/com/example/agent/llm/client/AbstractLlmClient.java)
- [SseParser.java](../src/main/java/com/example/agent/llm/stream/SseParser.java)
- [IdleTimeoutInputStream.java](../src/main/java/com/example/agent/llm/stream/IdleTimeoutInputStream.java)
- [MergeToolCallDeltasTest.java](../src/test/java/com/example/agent/llm/client/MergeToolCallDeltasTest.java)

### 5.1 请求构造

`chatStream` 大致完成：

```text
messages
  → prompt cache strategy
  → image/reference resolution
  → ChatRequest(stream=true)
  → max tokens / thinking / response format
  → tools + tool_choice=auto
  → Java HttpClient
```

Provider 返回的是一系列 delta，不是最终 Message。Runtime 要同时聚合：

- `reasoning`；
- `content`；
- `tool_calls[index].id`；
- `tool_calls[index].function.name`；
- `tool_calls[index].function.arguments`；
- `finish_reason`；
- `usage`。

### 5.2 ToolCall Delta 合并

工具参数常被拆成：

```text
chunk 1: index=0, id=call_1, name=write_file, arguments={"pa
chunk 2: index=0, arguments=th":"README.md","con
chunk 3: index=0, arguments=tent":"hello"}
```

合并算法按 `index` 找到槽位：

```java
slot.id = firstNonBlank(slot.id, delta.id);
slot.name = firstNonBlank(slot.name, delta.name);
slot.arguments.append(delta.arguments);
```

直到流结束后才解析完整 arguments JSON。这里不能用 `tool_call_id` 作为唯一归并键，因为续传 delta 可能没有 id；也不能每个 chunk 都尝试执行，因为 JSON 尚未闭合。

应防御：

- 负 index / 超大 index 造成内存膨胀；
- 同一 index 的 id 或 name 中途改变；
- 流结束时 arguments 仍不是合法 JSON；
- finish reason 与实际 ToolCall 内容矛盾；
- Provider 重复发送终态 chunk。

### 5.3 三种超时不是一回事

| 超时 | 保护对象 | 典型问题 |
|---|---|---|
| connect timeout | 建连 | DNS、路由、服务不可达 |
| request/deadline timeout | 整个调用预算 | 总执行时间失控 |
| idle/read timeout | 相邻字节长期无进展 | 已连接但流永久卡住 |

`IdleTimeoutInputStream` 使用守护 watchdog 观察最后一次成功读取时间，超过 60 秒关闭底层流。它保护的是“流建立后无数据”的场景。

### 5.4 取消为什么需要共享信号

`abortCurrentRequest` 中的 ThreadLocal 只能可靠影响当前线程；HTTP 读取线程若要感知另一个请求发出的取消，需要共享的 `SessionCancelManager`。Orchestrator 通过 `setCancelCheck(() -> cancelManager.isCancelled(sessionId))` 把会话级共享状态注入流读取循环。

完整取消链应是：

```text
UI AbortController
  → backend cancel endpoint / connection close
  → SessionCancelManager(sessionId)=cancelled
  → stream read loop closes body
  → Agent loop stops
  → running=false
  → pending external process/sub-agent also receives cancel
```

当前 LLM 和主循环已具备共享取消检查，但 Bash 子进程、Sub-Agent Future、MCP 请求是否真正被中止要分别验证，不能把“主循环返回”当成“所有副作用都停止”。

### 5.5 重试的语义边界

当前非流式调用存在基于异常分类的重试策略；流式 `chatStream` 直接进入 `executeStreamRequest`，不能笼统宣称“所有 LLM 流式调用自动重试”。而且现有指数退避没有 jitter，也没有完整消费 `Retry-After`。

为什么流式重试更难：一旦部分 token 已展示或 ToolCall 已开始聚合，透明重试可能重复文本、拼接两个响应或重复动作。正确做法通常是：

- 首字节前失败：可以安全重试；
- 已输出内容但无动作：以新 attempt 替换旧投影，需 attempt id；
- 已形成或执行 ToolCall：只能依据幂等键和 journal 恢复，不能盲目重放。

---

## 6. 工具系统：从“模型建议”到“受控副作用”

关键源码：

- [ToolRegistry.java](../src/main/java/com/example/agent/tools/ToolRegistry.java)
- [ToolExecutor.java](../src/main/java/com/example/agent/tools/ToolExecutor.java)
- [AgentMode.java](../src/main/java/com/example/agent/core/AgentMode.java)
- [BlockerChain.java](../src/main/java/com/example/agent/core/blocker/BlockerChain.java)
- [SchemaValidationBlocker.java](../src/main/java/com/example/agent/core/blocker/SchemaValidationBlocker.java)
- [FileLockManager.java](../src/main/java/com/example/agent/tools/concurrent/FileLockManager.java)

### 6.1 五层安全管线

理想工具调用管线：

```text
Tool Exposure
  → Argument Parse & Full Schema Validation
  → Capability / Policy Authorization
  → Human Confirmation if Needed
  → Resource Lock / Sandbox / Timeout
  → Execute
  → Output Limit & Untrusted-data Tag
  → Audit + ToolResult
```

HippoBuddy 当前有三处关键控制：

1. `AgentMode` 决定哪些工具暴露给模型；
2. Orchestrator 执行前再次检查 mode，防止模型伪造未暴露工具；
3. `ToolRegistry.execute` 解析参数、经过 `BlockerChain`、按需获取文件锁并执行。

“不暴露”只是减少模型选到该工具的概率，执行前二次鉴权才是真正安全边界。

### 6.2 Schema 校验的实际深度

`SchemaValidationBlocker` 在构造时缓存工具 schema 的 required 字段和顶层基础类型。它不是完整 JSON Schema 引擎，目前不能等价支持：

- 嵌套 object/array 的递归校验；
- `enum`、`pattern`、数值范围；
- `additionalProperties`；
- 组合约束；
- blocker 创建后动态注册的 MCP 工具 schema。

因此面试时准确说法应是：

> 项目已有轻量入参防线，但若面向动态 MCP 和生产安全，应在 Registry 调用边界接入完整 JSON Schema validator，并按工具注册版本更新编译后的 validator。

### 6.3 路径安全不能只做 normalize + startsWith

当前路径校验主要将路径绝对化、规范化，再判断是否位于 workspace 前缀内。这能挡住普通 `../` 穿越，但不能完全防御符号链接：

```text
workspace/link → C:/sensitive
workspace/link/secret.txt
```

词法路径仍在 workspace 下，真实目标却在外面。更严谨的流程是：

```java
Path root = workspace.toRealPath();
Path parent = target.getParent().toRealPath();
Path resolved = parent.resolve(target.getFileName()).normalize();
if (!resolved.startsWith(root)) deny();
```

创建新文件时目标本身还不存在，需要校验最近存在的父目录；真正打开文件时还要考虑 TOCTOU，必要时使用 OS sandbox、受限工作目录和禁止跟随链接的打开方式。

### 6.4 文件锁解决什么、不解决什么

`FileLockManager` 对受影响路径去重、按词法顺序排序、依次获取 `ReentrantLock`，逆序释放。排序用于避免：

```text
T1: lock(A) → wait(B)
T2: lock(B) → wait(A)
```

但它只解决当前 JVM 内、遵守同一 LockManager 的并发写冲突，不解决：

- 外部编辑器和其他进程写入；
- 多实例 Agent；
- 文件读取后的乐观并发冲突；
- 崩溃时半写文件；
- lock Map 长期增长。

生产上应叠加：临时文件 + 原子 rename、写前 hash/version 校验、必要时 OS file lock，以及冲突时让模型重新读取。

### 6.5 当前存在执行路径分叉

普通工具通过 `ToolRegistry.execute`；Bash、Delete 的确认前后以及 Sub-Agent 中存在直接调用 `ToolExecutor` 的路径。这意味着部分路径可能绕过 Registry 内统一的 Blocker、文件锁和 EventBus。

设计原则应是：**所有执行入口最后必须收敛到一个不可绕过的 invoker**：

```java
ToolResult invoke(ToolInvocation invocation) {
    validateSchema(invocation);
    authorize(invocation.capabilitySnapshot());
    acquireResources(invocation);
    return sandbox.execute(invocation);
}
```

人工确认只改变 invocation 的授权状态，不应该切换到另一条更弱的执行路径。

---

## 7. Human-in-the-loop 不是弹窗，而是可恢复 continuation

### 7.1 当前暂停流程

以 Bash 为例：

```text
模型返回 [bash, read_file, ...]
  → Bash 预检查
  → 需要确认
  → 创建 confirmId + PendingBashConfirmation
  → remainingToolCalls 保存后续 ToolCalls
  → SSE tool_confirmation
  → executeToolCalls 返回 false，Agent Loop 暂停
```

确认后：

```text
confirm endpoint
  → poll pending
  → 校验 confirmId / approved
  → 执行 Bash 或写拒绝 ToolResult
  → 取出 remainingToolCalls
  → 继续执行剩余工具
  → 再次进入 Agent Loop
```

### 7.2 continuation 至少要存什么

```json
{
  "sessionId": "s1",
  "runId": "r7",
  "turn": 3,
  "toolCallId": "call_9",
  "toolName": "bash",
  "canonicalArgs": "...",
  "argsHash": "sha256:...",
  "remainingToolCalls": [],
  "policyVersion": 12,
  "workspaceRealPath": "...",
  "status": "WAITING_CONFIRMATION",
  "expiresAt": "..."
}
```

确认动作必须做 compare-and-set：

```text
WAITING_CONFIRMATION
  --approve(confirmId, version)--> EXECUTING
```

重复确认、过期确认、错误 confirmId 都不能消费正确的 pending 状态。

### 7.3 当前恢复边界

当前 pending confirmation 和 `remainingToolCalls` 都只在进程内 Map 中：

- 重启后无法继续；
- `subList` 是原列表的视图，最好改为不可变 `List.copyOf`；
- 确认 handler 没有和 chat handler 共享同一会话串行边界，可能竞态；
- 先 `poll/remove` 再校验 confirmId，错误 ID 可能消费 pending；
- 暂停前的权限、配置、workspace 到确认时可能已经变化；
- 新消息清理旧确认时，应补写明确的 rejected/cancelled ToolResult。

面试改进回答：

> 我会把 HITL 建模为 durable state，而不是内存回调。确认记录带版本和参数 hash，确认端点在会话事务里 CAS；执行仍统一走 ToolInvoker，并再次验证不可变 capability snapshot 或按新策略拒绝。

---

## 8. 上下文管理：模型看到的不等于数据库里存的

### 8.1 三份视图

应区分：

1. 原始会话：`Conversation` 中的全部消息；
2. 推理视图：过滤、修复、注入规则和持久上下文后发给模型的消息；
3. UI 视图：为用户展示和流式拼接的消息。

`ConversationService.prepareForInference` 当前主要执行：

```text
conversation.getEffectiveMessages()
  → MemoryRetriever.prepareContextHeader(...)
  → 返回推理上下文
```

Orchestrator 随后确保 system message 顺序并运行 `MessageSanitizer`。

### 8.2 Token Budget 的实现

`ContextWindow` 使用 `CopyOnWriteArrayList` 持有消息；每次添加消息后重新估算整个上下文 Token。读取安全且快，但消息持续增加时，累计计算成本趋近 O(n²)，写入也会复制数组。

更合适的结构是：

- append-only list + 读写锁；
- 每条 Message 缓存 token count；
- 维护增量总数；
- 编辑/截断时只重算受影响区间；
- Provider-specific tokenizer 与估算误差水位。

### 8.3 当前“自动压缩”实际做了什么

项目中存在：

- `AutoCompactTrigger`；
- `ContextClipper`；
- `ContextSummarizer`；
- `SessionCompactionState`；
- `ManualCompactor`。

但在当前主推理链中，`AutoCompactTrigger` 达到阈值后只注入“建议总结并开启新会话”的 system warning；`prepareForInference` 没有调用 `ContextClipper` 或 `ContextSummarizer`。因此准确结论是：

> 压缩组件和手动压缩能力已经存在，但自动阈值触发尚未把真实压缩接入每轮 Agent 推理闭环。

这是很典型的工程审计方法：**类存在 ≠ 被实例化；被实例化 ≠ 被调用；被调用 ≠ 结果进入主链。**

### 8.4 压缩必须保护 Tool 协议

压缩切分点不能落在：

```text
assistant(tool_calls=[A,B])
tool_result(A)
| 不能在这里切 |
tool_result(B)
```

安全算法先按 turn 分组，让一次 assistant 与其连续 tool results 成为不可拆单元，再从完整用户轮次边界切分。摘要还应保存：

- 已确认的用户目标和约束；
- 已完成动作及关键 observation；
- 尚未完成的计划；
- 文件/资源精确标识；
- 未解决错误；
- 摘要覆盖到的最后 message id。

---

## 9. Memory：写入、检索、注入是三条不同链

Memory 不等于把所有历史塞进 Prompt。完整系统至少包括：

```text
Observe → Extract → Normalize → Deduplicate → Store
                                         ↓
Query → Retrieve → Rerank → Budget → Inject → Cite/Use
                                         ↓
                            Decay / Consolidate / Delete
```

### 9.1 当前已生效的链

`ConversationService.addMessage` 在追加消息后会触发：

- `SessionMemoryExtractor.onMessageAdded`；
- `MemoryExtractor.onMessageAdded`；
- 满足条件时 `MemoryRetriever.markForMemory`；
- Transcript append。

推理前 `MemoryRetriever.prepareContextHeader` 会注入规则和 `USER_PREFERENCE`、`PROJECT_CONTEXT` 等持久上下文，并触发 AutoDream 检查。

### 9.2 语义召回目前没有进入常规 Agent 工具面

源码注释表明可检索知识期望由 `recall_memory` 工具按需获取，但 `MemoryModule` 中该工具注册目前被注释。因此：

- 固定类型的持久上下文注入已生效；
- Memory 的提取、存储组件存在；
- 模型主动调用 `recall_memory` 的常规链路当前未启用。

不要在面试中把这三件事混成“长期记忆完全闭环”。

### 9.3 记忆污染和 Prompt Injection

外部网页、MCP 返回、工具输出中的文本都可能伪装成“系统指令”。Memory 写入前应：

- 标记来源和信任等级；
- 区分事实、用户偏好、模型推断；
- 对敏感信息设置 TTL/删除能力；
- 不把未验证的工具输出提升为 system 指令；
- 检索结果使用明确的 `<untrusted-memory>` 边界；
- 保留证据引用和创建时间。

### 9.4 生命周期问题

`ConversationService` 为每个 session 创建 `MemoryConsolidator`，随后写入共享 `globalMemoryStore.setConsolidator(...)`。这使共享 Store 中的 consolidator 引用被最近创建的 session 覆盖。更清晰的所有权应是：

- 全局唯一 ConsolidationScheduler 管理多 session；或
- Store 只负责存储，不持有 session-scoped consolidator；或
- Map<sessionId, consolidator> 并有显式销毁流程。

---

## 10. Transcript、恢复与崩溃一致性

### 10.1 当前写入模型

`SessionTranscript` 使用：

- 有界队列 10,000；
- 批量 50；
- 最长约 500ms 刷新间隔；
- JSONL 追加；
- UUID 缓存做进程内/时间窗口去重；
- 写失败后清队列并降级内存。

这是一种低延迟与吞吐优先的设计，但 `BufferedWriter.flush()` 不等同于每条 `fsync`。进程/机器突然崩溃时，队列内和 OS page cache 中的数据仍可能丢失。

### 10.2 崩溃窗口矩阵

| 崩溃点 | 当前可能结果 | 理想恢复策略 |
|---|---|---|
| user message 入内存、未入 JSONL | 用户输入丢失 | 请求 event 先耐久化 |
| Assistant ToolCall 入内存、未刷盘 | 副作用意图不可见 | intent WAL 后执行 |
| 工具执行成功、Result 未落盘 | 恢复后可能重复执行 | idempotency key + result journal |
| confirmation 建立后崩溃 | pending 丢失 | durable continuation |
| 多个 ToolCall 执行到一半 | 已执行前缀未知 | 每 call 独立状态与 checkpoint |
| SSE 断线但后端继续 | UI 看不到结果 | 重连后按 event sequence 补放 |
| Sub-Agent 运行中崩溃 | task 丢失 | task store + lease/recovery |
| MCP 调用在途崩溃 | 远端可能已执行 | request id + remote idempotency |

### 10.3 至少一次、至多一次与恰好一次

分布式副作用通常无法凭空实现“恰好一次”。常见组合是：

```text
至少一次投递 + 幂等执行 + 去重记录 ≈ 业务上的恰好一次效果
```

每个工具调用应有稳定 `invocationId`：

```text
invocationId = hash(runId, turn, toolCallId, canonicalArgs)
```

写文件可通过目标内容 hash、临时文件与原子 rename 幂等；发邮件、支付、创建远端资源则需要对方支持 idempotency key 或执行前查询业务状态。

### 10.4 Loader 也要流式

`TranscriptLoader` 能逐行识别损坏/截断 JSONL 并报告恢复状态，这是正确方向。但其大文件分支仍有一次性 `readAllLines` 路径，文件足够大时会造成内存压力。大日志恢复应始终迭代读取，并用 checkpoint/compaction 限制启动扫描范围。

---

## 11. SSE 与前端：只是状态投影，不是事实源

后端 [SseWriter.java](../src/main/java/com/example/agent/web/util/SseWriter.java) 使用容量 2048 的异步队列：Agent 线程负责 enqueue，sender 线程顺序 write/flush。好处是慢客户端不会直接卡住 LLM/工具主线程。

队列满或写失败后会标记连接断开并清理事件，但 Agent 可能继续运行、消息也可能继续持久化。因此系统语义是：

```text
Authoritative State: Conversation / Transcript / Run Store
Projection: SSE events
```

成熟事件应包含：

```json
{
  "sessionId": "s1",
  "runId": "r7",
  "sequence": 42,
  "attempt": 1,
  "type": "tool_result",
  "payload": {}
}
```

前端断线后用 `Last-Event-ID` 或 `afterSequence` 补放；如果事件已经被压缩，则加载当前 run snapshot。

前端使用 `fetch + ReadableStream` 而不是 `EventSource`，因为请求是 POST、包含 JSON body，而且需要 `AbortController`。解析器维护 buffer，按空行拆事件并合并多行 data。注意：通用实现还应兼容 CRLF，并在 EOF 调用一次无参 `decoder.decode()` 刷出 UTF-8 尾部。

Zustand 以 `sessionId` 隔离 messages、stream、tools、waiting、done、error 等状态，保证切换页面后后台会话仍能继续。但前端收到 `complete` 只能说明流结束，不能单独证明 Agent 业务成功；业务终态应以 `done/error/cancelled/waiting_*` 为准。

---

## 12. Sub-Agent：并行带来的不只是吞吐

关键源码：

- [SubAgentManager.java](../src/main/java/com/example/agent/subagent/SubAgentManager.java)
- [SubAgentRunner.java](../src/main/java/com/example/agent/subagent/SubAgentRunner.java)
- [SubAgentTask.java](../src/main/java/com/example/agent/subagent/SubAgentTask.java)

### 12.1 正确的抽象

Sub-Agent 应是一个受预算和能力约束的子任务：

```text
TaskSpec {
  taskId, parentRunId, objective,
  contextSnapshot,
  capabilitySet,
  token/time/tool budgets,
  dependencies,
  outputContract
}
```

父子 Agent 不是简单共享整段可变 Conversation。更安全的是传不可变上下文快照和显式产出合同，结果以 observation 合并回父任务。

### 12.2 当前线程池与背压

`SubAgentManager` 使用固定大小线程池和容量 100 的有界队列。队列有界是正确的背压思想，但默认拒绝策略会抛 `RejectedExecutionException`。如果任务已经先注册进 `activeTasks` 再 submit，拒绝后可能留下永远 PENDING 的任务，因此注册和提交需要原子化或失败补偿。

### 12.3 DAG 依赖的真实状态

`SubAgentTask` 有 `dependsOn`，Manager 也存在 schedule/wait 相关逻辑；但当前 `createSubAgent` 路径直接 `submitTask`，传入依赖并不会阻止任务马上执行。因此当前更接近“记录依赖字段”，还不是完整 DAG 调度器。

真正的 DAG scheduler 应维护：

```text
PENDING_DEPENDENCIES
  → READY
  → RUNNING
  → SUCCEEDED | FAILED | CANCELLED
```

并检测环、传播失败、限制 fan-out，只有所有依赖成功后才能 READY。

### 12.4 工具执行和重试风险

`SubAgentRunner` 直接从 Registry 取 executor 执行，没有统一经过 `ToolRegistry.execute`，因而可能绕过 BlockerChain、文件锁和统一事件审计。其异常重试还可能重放带副作用工具。

改进原则：

- 主 Agent 和 Sub-Agent 共用同一个 ToolInvoker；
- capability 只能继承父权限的子集；
- 只对明确标记 `idempotent=true` 的调用自动重试；
- Task Future 与 LLM、进程、MCP cancel token 绑定；
- 保存 parent/child trace 和每个任务预算；
- fan-out、深度、总任务数全部设硬上限。

### 12.5 上下文共享与 Prompt Cache

当前 fork 会复制父会话的 Message 列表，Message 对象本身是浅共享，然后添加子任务指令。相同前缀有利于 Provider prompt cache，但“前缀相同”不等于缓存必然命中：模型、system prompt、工具定义顺序、请求参数、Provider 缓存规则都会影响 cache key。

工具来自 `ConcurrentHashMap` 的遍历顺序并不天然稳定。会话级 tool snapshot 能让同一 session 后续轮次稳定，但不同 session/重启后的初始顺序仍可能变化。应在快照前按工具名稳定排序。

---

## 13. MCP：协议接入不等于能力治理

关键源码：

- [McpServiceManager.java](../src/main/java/com/example/agent/mcp/McpServiceManager.java)
- [AbstractMcpClient.java](../src/main/java/com/example/agent/mcp/client/AbstractMcpClient.java)
- [JsonRpcHandler.java](../src/main/java/com/example/agent/mcp/protocol/JsonRpcHandler.java)

MCP 主链应是：

```text
Transport(stdio/SSE)
  → JSON-RPC initialize
  → capability negotiation
  → tools/list
  → local adapter registration
  → tools/call
  → untrusted result
```

### 13.1 当前实现特点

- 工具名映射为 `mcp_{server}_{tool}`；
- stdio 以一行一个 JSON 消息读写，stdout 必须保持协议纯净；
- SSE transport 负责收流并 POST 消息；
- `JsonRpcHandler` 用 request id 关联 pending Future，并清理超时请求；
- MCP 工具同步等待远端 Future，默认有调用超时。

### 13.2 当前主启动链没有完成装配

在 `DesktopApplication`、`WebApplication`、`DashboardServer`、`WebInitializer` 和 `CoreModule` 中没有找到 `McpServiceManager` 的实例化/初始化入口。因此源码中存在 MCP 管理组件和测试，不代表桌面主程序已自动连接并把 MCP 工具注册到日常 Agent。

### 13.3 动态工具的生命周期问题

连接时工具会注册进 `ToolRegistry`，但断开连接时当前逻辑主要注销 resources/prompts，没有对应注销已注册的 MCP tools。后果是模型仍可能看到一个无法工作的陈旧工具。Registry 需要支持：

```text
register(ownerId, toolVersion, executor)
unregisterAll(ownerId)
snapshot(registryVersion)
```

而会话 tool snapshot 还要定义：MCP 断开后，老 session 是保留旧 schema 但执行时报连接失效，还是立即使快照失效。二者都可设计，但必须显式。

### 13.4 MCP 是远程代码能力边界

远程 MCP server 的 tool description、schema、返回内容都不应默认可信。需要：

- server identity 与配置签名；
- 每 server capability allowlist；
- 连接凭证最小化和 secret 隔离；
- 工具 schema 完整校验；
- 输出长度限制与 prompt-injection 标记；
- 调用超时、限流、熔断；
- 断连后立即回收工具；
- 审计 server/tool/args hash/result hash；
- JSON-RPC id 类型兼容与重连状态重建。

---

## 14. 把当前循环重构成显式状态机

当前 Orchestrator 用 `for + return + Map pending state` 隐式表达状态。随着确认、ask_user、重连、Sub-Agent、重试增多，显式状态机会更容易验证。

### 14.1 状态定义

```java
sealed interface RunState {
    record Ready(RunContext ctx) implements RunState {}
    record CallingLlm(RunContext ctx, int attempt) implements RunState {}
    record ExecutingTool(RunContext ctx, ToolInvocation call) implements RunState {}
    record WaitingUser(RunContext ctx, PendingQuestion question) implements RunState {}
    record WaitingConfirmation(RunContext ctx, PendingAction action) implements RunState {}
    record Completed(RunContext ctx, String answer) implements RunState {}
    record Failed(RunContext ctx, AgentError error) implements RunState {}
    record Cancelled(RunContext ctx) implements RunState {}
}
```

### 14.2 事件定义

```java
sealed interface RunEvent {
    record UserSubmitted(Message message) implements RunEvent {}
    record LlmCompleted(Message assistant) implements RunEvent {}
    record ToolSucceeded(String callId, String result) implements RunEvent {}
    record ToolFailed(String callId, AgentError error) implements RunEvent {}
    record UserConfirmed(String confirmId, long version) implements RunEvent {}
    record UserRejected(String confirmId, long version) implements RunEvent {}
    record CancelRequested(String reason) implements RunEvent {}
    record DeadlineExceeded() implements RunEvent {}
}
```

### 14.3 transition 与 effect 分离

```text
transition(state, event) → newState + effects
effectRunner(effect)     → new event
```

例如：

```text
Ready + Start
  → CallingLlm + [PersistState, InvokeLlm]

CallingLlm + LlmCompleted(toolCall)
  → ExecutingTool + [PersistAssistant, ValidateTool]

ExecutingTool + RequiresConfirmation
  → WaitingConfirmation + [PersistPending, EmitSse]
```

`transition` 可以是纯函数，便于表驱动测试；所有 I/O 放到 effect runner。每次先持久化新状态，再执行不可逆 effect，恢复时依据状态继续或人工介入。

### 14.4 核心数据模型

```java
record RunContext(
    String runId,
    String sessionId,
    long version,
    int turn,
    Budget budget,
    String toolSnapshotHash,
    String policyVersion,
    List<MessageRef> history,
    Set<String> completedInvocationIds
) {}
```

`version` 支持乐观并发；`toolSnapshotHash` 保证恢复时知道模型当时看见了哪些工具；`completedInvocationIds` 用于副作用去重。

---

## 15. 测试 Agent，不能只断言最终文本

Agent 输出具有随机性，Runtime 协议却应该确定。测试金字塔如下：

### 15.1 纯单元测试

- ToolCall delta 合并；
- JSON Schema validator；
- mode/capability 判定；
- 路径 canonicalization；
- MessageSanitizer 协议不变量；
- 状态机 transition；
- Token 增量预算；
- retry classifier。

### 15.2 Scripted LLM 集成测试

使用 `MockLlmClient` 固定返回序列：

```text
turn 1 → tool_call(read_file)
tool → observation
turn 2 → tool_call(edit_file)
tool → observation
turn 3 → final answer
```

断言消息精确顺序、ToolCall/Result 配对、次数、终止原因、SSE event sequence，而不是只检查最终字符串包含什么。

### 15.3 故障注入

必须覆盖：

- SSE 任意字节边界拆包；
- UTF-8 多字节字符跨 chunk；
- ToolCall arguments 在任意位置切分；
- LLM 首字节前/后断线；
- 工具成功后、Result 落盘前崩溃；
- pending confirmation 后重启；
- Transcript 尾行被截断；
- 队列满和慢消费者；
- MCP 断连/重连；
- Sub-Agent 队列拒绝、依赖失败、取消；
- symlink workspace escape。

### 15.4 属性测试不变量

对随机消息序列验证：

```text
∀ tool_result: exists earlier assistant.tool_call with same id
∀ terminal run: no RUNNING tool invocation remains
∀ approved invocation: confirmation.argsHash == invocation.argsHash
∀ file target: realPath(target) is under realPath(workspace)
turn <= maxTurns
spentBudget <= hardLimit
```

### 15.5 现有测试入口

- [WebAgentOrchestratorTest.java](../src/test/java/com/example/agent/web/orchestrator/WebAgentOrchestratorTest.java)
- [ToolRegistryTest.java](../src/test/java/com/example/agent/tools/ToolRegistryTest.java)
- [SseWriterTest.java](../src/test/java/com/example/agent/web/util/SseWriterTest.java)
- [TranscriptP0EndToEndTest.java](../src/test/java/com/example/agent/session/TranscriptP0EndToEndTest.java)
- [ContextManagementIntegrationTest.java](../src/test/java/com/example/agent/context/ContextManagementIntegrationTest.java)
- [SubAgentTaskBoundaryConditionsTest.java](../src/test/java/com/example/agent/subagent/SubAgentTaskBoundaryConditionsTest.java)
- [McpIntegrationTest.java](../src/test/java/com/example/agent/mcp/McpIntegrationTest.java)

---

## 16. 当前能力审计：Implemented / Partial / Not Wired

| 能力 | 状态 | 证据与边界 |
|---|---|---|
| 多轮 Agent Loop | Implemented | 最多 50 轮，LLM → Tool → observation |
| 流式文本/推理/ToolCall 合并 | Implemented | Provider 流经 callback 和 delta merge |
| 会话取消 | Partial | 主循环和 LLM 可感知；外部副作用全链取消需逐项补齐 |
| 会话互斥 | Partial | 有 session lock；超时替换锁对象会破坏互斥 |
| mode 工具权限 | Implemented | 暴露时过滤，执行前再次检查 |
| 完整 JSON Schema 校验 | Partial | 当前主要校验 required 和顶层基础类型 |
| 路径沙箱 | Partial | 防普通穿越；缺少 realpath/symlink 完整防御 |
| 人工确认 | Partial | 运行时可暂停恢复；continuation 不耐久且存在竞态窗口 |
| 文件并发锁 | Partial | JVM 内路径锁；不覆盖外部进程/多实例 |
| 自动上下文压缩 | Not Wired | 阈值只注入 warning，压缩器未接推理主链 |
| 固定持久上下文注入 | Implemented | preference/project context 会注入 |
| recall_memory 主动召回 | Not Wired | 工具注册当前被注释 |
| JSONL 会话恢复 | Implemented | 异步批量写、Loader 可识别损坏尾部 |
| 副作用恰好一次恢复 | Not Implemented | 缺少 durable invocation journal/idempotency |
| Sub-Agent 并发执行 | Implemented | 有界线程池和任务状态 |
| Sub-Agent DAG | Partial | dependsOn 存在，create 路径未真正按依赖调度 |
| MCP 客户端组件 | Implemented | stdio/SSE、JSON-RPC、工具适配存在 |
| MCP 桌面主链装配 | Not Wired | 主启动路径未发现 Manager 初始化 |
| SSE 前端状态投影 | Implemented | fetch stream + session-scoped Zustand |
| SSE 断线补放 | Not Implemented | 缺少 sequence/event replay |

这张表不是“挑错清单”，而是面试时展示工程判断力：能区分源码资产、实际接线和生产保证。

---

## 17. 高频深挖题与回答骨架

### Q1：为什么 Agent Loop 不能全部交给 LLM？

> 因为模型输出是概率性、不可信文本。Runtime 必须掌握 schema、权限、确认、资源锁、超时、预算、持久化和终止权。模型只提出 action，不能直接获得系统副作用能力。

### Q2：工具执行成功，但响应回填前崩溃怎么办？

> 这是经典不确定提交窗口。仅靠重试会重复副作用。我会先持久化 invocation intent，使用稳定 idempotency key；执行后持久化 result。恢复时先查 completed invocation，外部系统支持幂等键则复用，否则查询业务状态或进入人工恢复。

### Q3：为什么 ask_user 和 dangerous-tool confirmation 都应建模为状态？

> 两者都会让 Agent 跨请求暂停，依赖未来事件继续。若只存 Java 对象，重启即丢失；若没有 version/CAS，重复或并发响应会推进两次。它们本质上都是 durable continuation。

### Q4：上下文压缩最难的是什么？

> 不是把文本变短，而是保持协议与任务语义：不能拆 ToolCall/Result，对已完成事实、未完成计划、资源标识和约束要可追溯，还要保存摘要边界，避免反复摘要造成信息漂移。

### Q5：Sub-Agent 为什么不能直接共享父 Agent 所有权限？

> 并行会放大副作用、成本和攻击面。子 Agent 应拿父 capability 的子集和独立预算，使用不可变上下文快照；合并结果时处理冲突，取消要传播到其 LLM、工具和远程请求。

### Q6：MCP 接入后最大的风险是什么？

> MCP 不只是多一个 API，而是动态扩展模型可调用能力。server identity、schema、工具描述和返回文本都可能不可信；必须做 capability allowlist、动态注册生命周期、输出隔离、限流熔断和审计。

### Q7：SSE 断开是否应该取消 Agent？

> 取决于产品语义。若 Agent 是用户前台交互，可在断线后 grace period 取消；若支持后台任务，Agent 应继续，SSE 只是投影，并允许 sequence replay。不能让偶发网络断线隐式决定副作用事务状态。

### Q8：怎样判断一个 Agent 在“原地打转”？

> 对连续 action 做规范化指纹：tool name + canonical args + observation hash；结合计划进度和错误指纹。连续重复且状态无变化时触发反思、换策略或终止，而不只是依赖最大 50 轮。

---

## 18. 面试前的源码复习顺序

第一遍只追主链：

```text
ChatApiHandler
  → WebAgentOrchestrator.execute
  → AbstractLlmClient.chatStream
  → executeToolCalls
  → ToolRegistry.execute
  → ConversationService.addToolResult
```

第二遍追暂停和恢复：

```text
ask_user / Bash confirmation / Delete confirmation
  → WebSessionManager pending maps
  → confirmation handler
  → continueAfterConfirmation
```

第三遍追可靠性：

```text
SessionCancelManager
SseWriter
SessionTranscript / TranscriptLoader
ContextWindow / TokenBudget
PathSecurityUtils / FileLockManager
```

第四遍追扩展：

```text
SubAgentManager / Runner / Task
McpServiceManager / Client / JsonRpcHandler
MemoryRetriever / MemoryStore / Consolidator
```

每看一个类都回答：

1. 它拥有哪份状态？
2. 谁创建它，生命周期多长？
3. 哪些线程会访问？
4. 外部输入在哪里被校验？
5. 副作用发生前后分别写了什么？
6. 进程在任意一行崩溃会怎样？
7. 重试会不会重复副作用？
8. 取消能否真正传到最底层？
9. UI 事件丢了能否从事实源恢复？
10. 测试验证的是文本结果，还是运行时不变量？

能围绕这十个问题讲清楚，才算真正掌握 Agent 的实现原理。
