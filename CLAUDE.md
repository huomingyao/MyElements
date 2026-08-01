# 元素炼金物语 (Elemental Alchemy Story) — Godot 化学教育开放世界

## 项目概述

2D 横版像素开放世界，**世界规则就是初中化学课本**——没有魔法，只有化学。
玩家收集真实物质、按真实反应条件合成道具、靠化学知识生存；卡住就去「导师学院」问 4 位 AI 导师。

**当前阶段**：MVP（20 小时比赛版），目标是评委能上手玩 10~15 分钟的 Windows 可玩 demo + 3 分钟演示视频。

---

## 开发规范

### 会话开始规则 ⚠️

**每次开始新对话或进行任何修改前**，必须按顺序完成：

1. 调用 `superpowers:using-superpowers` — 建立技能检索方式（**第一件事，先于回答任何问题**）
2. 阅读 `docs/SPEC.md` — 事实来源索引 + 当前 Phase Checklist 状态
3. 阅读本次改动涉及的分册 spec（见 `docs/SPEC.md` 索引表）
4. 涉及 Godot 引擎实现时，调用 `godot-master` + `godot-prompter:using-godot-prompter`
5. 涉及 bug 定位时，调用 `superpowers:systematic-debugging`
6. 确认自己要动的目录属于当前任务的「责任目录」（见下）

### SSD 铁律（Spec-Driven Development）🔴

**代码不是事实来源，`docs/` 才是。**

- 任何功能开工前，`docs/` 里必须已存在对应的 **FR-ID + 验收标准**。没有就先写 spec，不许先写码。
- 实现与 spec 不一致时，**先改 spec 再改码**，两者必须同一个 commit 落地。
- 任何功能变更后必须同步更新：FR 条目、接口契约、数据 Schema、Phase Checklist、追溯矩阵。
- 需求变更不许口头传达，必须落到 `docs/SPEC-01-需求与验收.md`。

违反此规则将导致规格文档与代码不一致，5 人并行时直接引发合并事故。

### TDD 铁律（Test-Driven Development）🔴

**每个 FR 至少一个自动化测试，循环顺序不许颠倒。开写实现代码前必须先调 `superpowers:test-driven-development`。**

1. **RED** — 先写测试，运行并确认它按预期失败（不是报错，是断言失败）
2. **GREEN** — 写最少的代码让测试通过
3. **REFACTOR** — 清理，再跑一遍全部测试

- 纯逻辑（配方匹配、路由分类、数值结算、数据校验）**必须**有单元测试，不接受"手动点一下看看"。
- 场景/交互层用集成测试 + MCP 实机验证（见「验证方式」）。
- 提交前必须跑完整测试套件，红着的测试不许合进 `main`。
- 测试写法与命名见 `docs/SPEC-06-测试计划.md`；GUT 写法可调 `godot-prompter:godot-testing`。
- **报告完成前**必须调 `superpowers:verification-before-completion`，真跑命令，不许拿代码推断冒充结果。

### 四条产品铁律（任何人任何时刻不得违反）

| # | 铁律 | 原因 |
|---|------|------|
| 1 | 只做"评委 10 分钟能玩懂的闭环"，其余一切进赛后清单 | 20 小时装不下完整设计 |
| 2 | 断网必须可玩（LLM 有本地兜底问答） | 比赛现场网络不可控 |
| 3 | 每个整点可构建、可运行，git 不许留"明天再合"的代码 | 5 人并行，最后一刻合并 = 爆炸 |
| 4 | 改文案不改代码——物质、配方、字幕、导师人设全部数据表驱动 | 内容调整是最后 5 小时的主要工作 |

**功能冻结时间**：H12。之后只修 bug、填内容、调数值，不加任何新功能。
**砍功能裁决人**：P1（一人说了算）。

---

## 技术栈

| 项 | 选择 | 约束 |
|---|---|---|
| 引擎 | Godot 4.6.3-stable（GDScript） | 不升级、不换语言 |
| 测试 | GUT（Godot Unit Test，装到 `addons/gut/`） | headless 可跑，见测试计划 |
| 数据 | JSON 数据表（`res://data/*.json`） | 改内容不改代码（铁律 4） |
| LLM | DeepSeek API（OpenAI 兼容），`HTTPRequest` | key 存 `user://config.cfg`，**不进 git** |
| 分辨率 | 视口 640×360，整数倍缩放 | `canvas_items` + `keep` |
| 导出 | Windows Desktop（exe + pck） | 干净电脑可直接运行 |
| 实机验证 | `addons/godot_mcp`（已装，autoload `MCPGameBridge`） | 截图/输入注入/节点查询 |

---

## 本项目必用的技能（Skills）

> 调用用 `Skill` 工具，名字**带插件前缀**。这些技能装在插件里，不在 `~/.claude/skills`，前缀写错会调不到。
> 全局强制规则见 `~/.claude/CLAUDE.md`「技能强制调用规则」，本节只列本项目高频项。

### 流程类（superpowers v6.2.0）

| 技能 | 本项目何时调 |
|---|---|
| `superpowers:using-superpowers` | 每个新会话第一件事 |
| `superpowers:brainstorming` | 动手前需求不明确时（但**本项目需求已冻结在 `docs/`，优先读 spec 而不是重新头脑风暴**） |
| `superpowers:writing-plans` | 写/改 TP 任务包等实施计划 |
| `superpowers:test-driven-development` | 写任何 `.gd` 实现前 |
| `superpowers:executing-plans` | 按 SPEC-07 §4 逐包推进 |
| `superpowers:verification-before-completion` | 报告"完成"前 |
| `superpowers:systematic-debugging` | bug 定位 |
| `superpowers:requesting-code-review` | 整点合 `main` 前 |
| `superpowers:dispatching-parallel-agents` | 并行派 TP 任务包 |
| `superpowers:subagent-driven-development` | 会话内跑独立任务包 |
| `superpowers:using-git-worktrees` | 任务文件范围重叠时隔离 |

### Godot 类

| 技能 | 用途 |
|---|---|
| `godot-master` | 本机 `~/.claude/skills/`（**无前缀**），Godot 架构/反模式/性能总入口 |
| `godot-prompter:using-godot-prompter` | godot-prompter（v1.13.1）总索引，先调它找领域技能 |
| `godot-prompter:godot-testing` | GUT 单测与 headless 运行（配合 SPEC-06） |
| `godot-prompter:gdscript-patterns` / `gdscript-advanced` | GDScript 写法与进阶模式 |
| `godot-prompter:godot-project-setup` | TP-01 项目骨架与 autoload |
| `godot-prompter:godot-debugging` | 引擎层 bug |
| `godot-prompter:godot-code-review` | GDScript 审查 |
| `godot-prompter:export-pipeline` | TP-18 Windows 导出（配合 SPEC-09） |

**按模块对应的领域技能**（前缀同为 `godot-prompter:`）：

| 本项目模块 | 技能 |
|---|---|
| 玩家控制器（TP-04） | `player-controller`、`input-handling`、`camera-system`、`physics-system` |
| 采集与背包（TP-06） | `inventory-system`、`resource-pattern` |
| HUD / UI / 图鉴（TP-12、TP-16） | `hud-system`、`godot-ui`、`responsive-ui` |
| 怪物 AI（TP-09） | `state-machine`、`2d-essentials` |
| 爆炸与特效（TP-08） | `particles-vfx`、`tween-animation` |
| 字幕引擎与跨模块信号（TP-05） | `event-bus`、`scene-organization` |
| 导师聊天 UI（TP-13） | `godot-ui`、`dialogue-system` |
| 音频（P5） | `audio-system` |
| 昼夜光照（TP-03） | `shader-basics` |

**不在本次范围**（MVP 砍掉，别顺手调）：`save-load`（不做存档）、`multiplayer-*`、`localization`、`xr-*`、`mobile-development`、`csharp-*`、`3d-essentials`。

---

## 目录结构与责任划分

```
res://
├── docs/                # 全部 spec（事实来源）
├── scenes/
│   ├── main/            # P1：主菜单、世界、昼夜、HUD、世界地图页
│   ├── player/          # P1：玩家控制器
│   ├── gameplay/        # P2：采集物、合成台、怪物、道具、爆炸
│   ├── mentor/          # P3：导师学院场景、聊天 UI
│   └── ui/              # P4 资源 + P2/P3 逻辑：卡片、图鉴、背包
├── scripts/
│   ├── autoload/        # P1 建骨架：GameManager / KnowledgeTip / RecipeDB / LLMClient / WorldMap
│   ├── gameplay/        # P2
│   └── mentor/          # P3
├── data/                # P3 填：substances / recipes / tips / mentors / qa_fallback / worldmap.json
├── assets/
│   ├── art/             # P4（generated/ 与 freepack/ 两个子目录）
│   └── audio/           # P5
├── maps/                # P5：TileMap 场景与 tileset
├── tests/
│   ├── unit/            # 各自负责自己模块的单测
│   └── integration/     # P5 主责
└── addons/godot_mcp/    # 已装，勿改
```

**规则**：只改自己的责任目录。`scripts/autoload/` 的接口在 H1 由 P1 定义后**冻结**，别人只调用不修改；需要改接口先在 `docs/SPEC-03-系统与接口契约.md` 提议。

---

## 编码规范

- **GDScript 风格**：类名 `PascalCase`，方法/变量 `snake_case`，常量 `UPPER_SNAKE`，私有成员 `_前缀`。
- **静态类型必写**：`var hp: float = 100.0`、`func try_craft(items: Array, tool: String) -> Dictionary:`。
- **信号命名**：过去式或事件名，`oxygen_changed`、`craft_succeeded`、`night_started`。
- **禁止魔法数字**：数值调参项一律进 `data/*.json` 或 autoload 顶部的常量区（调参阶段要一眼找到）。
- **禁止硬编码中文文案**在逻辑代码里——一律走 `KnowledgeTip.show("tip_id")` 或数据表字段。
- **`get_node` 路径**用 `@onready var x: Node = %UniqueName`（唯一名）优于长路径，重构不易断。
- **资源加载**：`preload` 用于固定依赖，`load` 用于数据驱动的动态路径。
- **错误处理**：JSON 读取、HTTP 请求、文件操作必须判空 + 判错并给出可读日志，不许 `assert` 兜底线上逻辑。

---

## 验证方式（每次改动后必做）

1. **单元测试**：`gut` headless 跑 `tests/unit/`（命令见 `docs/SPEC-06-测试计划.md`）。
2. **场景冒烟**：主场景能加载、无 script error、无缺失资源报错。
3. **实机验证（godot_mcp）**：涉及可见行为（HUD、字幕、爆炸、聊天框）的改动，用 MCP 截图确认，不靠"应该没问题"。
4. **构建验证**：每个整点导出一次 Windows 包，导出失败优先修导出。

改完不许只说"已实现"，必须报告：跑了什么、结果是什么、什么没能验证。
**声称完成前**先调 `superpowers:verification-before-completion`。

### godot_mcp 用法与前提

- 已装：编辑器插件 `addons/godot_mcp/`（v4.1.0）+ autoload `MCPGameBridge`，**勿改**。
- 通道：WebSocket 服务端默认 `127.0.0.1:6550`（仅本机回环，不对外监听）。
- 能力：截图、输入注入、节点树查询、运行时状态采样、性能剖析、TileMap 操作。
- 典型用法：跑起游戏 → 注入输入走到目标状态 → 截图 → 查节点确认数值/可见性 → 再报告。
- 适用改动：HUD 三条数值条、字幕三种样式、爆炸动画、底部聊天框、地图页 13 热区、图鉴网格。
- **前提检查**：`/mcp` 里看不到 godot MCP 服务器时，实机验证不可用（当前 Claude Code 侧 `mcpServers` 为空，需先注册）。此时必须**明确写出"未能实机验证"及原因**，不许拿代码推断冒充截图结论。

---

## Git 工作流

- **分支**：`main`（始终可运行）+ 每人一个 `dev-p1`…`dev-p5`。
- **流程**：自己分支干活 → 整点提 PR 合 `main` → P1 过一遍就合，不搞正式 review。
- **commit 格式**：`[模块] 做了什么`，如 `[mentor] 接入DeepSeek并调通化学老师人设`。模块名取 `main/player/gameplay/mentor/ui/data/art/maps/docs/test`。
- **提交前**：跑测试 + 确认主场景能跑。
- **绝对禁止**：`--no-verify`、force push 到 `main`、`reset --hard` / `clean -f` 等破坏性操作、把 API key 或 `user://config.cfg` 提交进仓库。
- 只在用户明确要求时创建 commit。

---

## 安全红线

- API key 只存 `user://config.cfg`，**任何情况下不写进 `res://`、不进 git、不打进日志**。
- LLM 返回内容视为不可信数据：只做文本渲染，不 `eval`、不驱动任何游戏状态变更。
- 玩家输入（导师聊天框）做长度截断与字符清理后再进 prompt。
- 联网失败必须走兜底路径，不许卡死 UI 或抛未捕获异常。

---

## 多子 Agent 协作约定

- 派活时必须带上：**FR-ID + 责任目录 + 验收标准 + 允许改的文件范围**。
- 子 Agent 只在自己的责任目录内写文件；跨目录需求回报主 Agent，不自行越界。
- 并行派活前先确认任务之间无文件重叠；有重叠的改成串行或用 worktree 隔离。
- 子 Agent 交付必须包含：改了哪些文件 + 跑了什么测试 + 测试结果。
- autoload 接口变更只能由主 Agent 统一执行（等价于 P1 的裁决权）。

### 派活必调的技能

| 场景 | 技能 |
|---|---|
| 派 2 个以上互不共享状态、无先后依赖的任务 | `superpowers:dispatching-parallel-agents` |
| 在当前会话里执行含独立任务的实施计划（TP 任务包） | `superpowers:subagent-driven-development` |
| 任务间文件范围有重叠，又不想串行 | `superpowers:using-git-worktrees` |
| 写/改 TP 任务包这类实施计划本身 | `superpowers:writing-plans` |
| 按已定稿计划逐包推进（带 review 检查点） | `superpowers:executing-plans` |

**TP 任务包与技能的对应**：18 个任务包见 `docs/SPEC-07-实施计划与Agent派活.md` §4，其 §3.2 并行安全矩阵就是 `dispatching-parallel-agents` 的输入——先查矩阵判定能否并行，再决定并行、串行还是 worktree，不许凭感觉派。

**子 Agent 的 prompt 必须带上** `docs/SPEC-07` §4.0 通用头（含强制 TDD、文件白名单、不改 SPEC-03 接口、不创建 commit）。

---

## 相关文档

`docs/SPEC.md` 是总索引与事实来源入口，先读它。分册清单见该文件索引表。
