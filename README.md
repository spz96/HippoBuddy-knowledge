# HippoBuddy 学习与面试复习仓库

这是 `HippoBuddy` 项目的个人学习归档，集中保存项目源码快照、系统化知识文档和与本项目直接相关的 Codex 会话，便于在其他机器上继续复习。

## 推荐入口

1. [系统化面试复习路线](docs/INTERVIEW_REVIEW_ROADMAP.md)
2. [Agent 专项面试手册](docs/AGENT_INTERVIEW_PLAYBOOK.md)
3. [Agent 实现原理深度手册](docs/AGENT_IMPLEMENTATION_DEEP_DIVE.md)
4. [后端知识库总入口](docs/backend-knowledge/README.md)
5. [42 周系统化学习指南](docs/backend-knowledge/SYSTEMATIC_LEARNING_GUIDE.md)
6. [538 项掌握进度表](docs/backend-knowledge/MASTER_PROGRESS_TRACKER.md)
7. [Codex 会话索引](conversations/README.md)

## 仓库结构

```text
docs/                系统化知识库、面试手册、源码原理文章
conversations/       当前 HippoBuddy 工作区相关的 Codex 会话
src/                 Java 后端源码与测试
frontend/            React 前端
electron/            Electron 桌面端
scripts/             构建、校验与会话导出脚本
PROJECT_README.md     HippoBuddy 原项目说明
```

## 在另一台机器上使用

```bash
git clone https://github.com/spz96/HippoBuddy-knowledge.git
cd HippoBuddy-knowledge
```

建议从复习路线开始，学习每个专题时同时打开对应源码与测试。Codex 会话用于回顾问题背景和结论，正式知识点以 `docs/` 中经过整理的文档为主。

## 隐私说明

会话导出仅保留用户消息、Codex 过程说明和最终回答；系统提示、环境上下文、内部推理、命令、工具调用及工具输出不会进入仓库。仓库应保持为私有仓库。
