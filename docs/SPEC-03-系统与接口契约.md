# SPEC-03｜系统与接口契约

> **本文件在 H1 由 P1 定稿后冻结。** 之后任何接口变更必须先改本文件（含变更记录 §9），再改代码。
> 其他人只调用，不修改 autoload 签名。子 Agent 无权变更本文件。

---

## 1. 架构总览

```
┌──────────────────── Autoload 层（全局单例，P1 冻结） ────────────────────┐
│ GameManager   三值 / 昼夜 / 区域 / 死亡复活 / 全局标记                     │
│ KnowledgeTip  字幕引擎（tips.json）                                       │
│ RecipeDB      配方匹配（recipes.json + substances.json）                  │
│ LLMClient     DeepSeek 调用 / 超时 / 离线兜底                             │
│ WorldMap      13 区域状态与地图页（worldmap.json）                        │
└──────────────────────────────────────────────────────────────────────────┘
        ▲              ▲                ▲                ▲
        │ 信号/调用     │                │                │
┌───────┴──────┐ ┌─────┴──────┐ ┌───────┴──────┐ ┌───────┴──────┐
│ scenes/main  │ │scenes/player│ │scenes/gameplay│ │ scenes/mentor│
│ P1: HUD/菜单 │ │P1: 控制器   │ │P2: 玩法       │ │P3: 导师       │
└──────────────┘ └─────────────┘ └───────────────┘ └──────────────┘
                                  │
                          ┌───────┴───────┐
                          │  scenes/ui    │ P4 资源 + P2/P3 逻辑
                          └───────────────┘
```

**依赖方向铁律**：
- Autoload **不允许**反向依赖具体场景（不 `get_node("/root/World/...")`）。要通知场景，发信号。
- 场景之间**不横向直连**（`gameplay` 不找 `mentor` 的节点）。跨模块通信一律走 autoload 信号。
- 数据表只由 autoload 读取并对外提供查询；场景不自己 `FileAccess.open` 数据表。

---

## 2. GameManager（P1）

职责：三值、昼夜时钟、区域判定、死亡复活、全局事件标记。

### 2.1 状态

```gdscript
# 三值（0..max）
var oxygen: float
var energy: float
var health: float
var oxygen_max: float = 100.0
var energy_max: float = 100.0
var health_max: float = 100.0

# 时间
var day_count: int = 1
var time_of_day: float = 0.0      # 当前昼夜周期内已过秒数

# 全局标记（供跨模块查询，禁止其他模块直接写除 setter 外的字段）
var explosion_happened: bool = false
var purity_check_unlocked: bool = false
```

### 2.2 方法

| 签名 | 说明 |
|---|---|
| `tick(delta: float) -> void` | **唯一时间推进入口**：推进昼夜时钟 + 结算三值消耗。由 `scenes/main/world.gd` 在 `_process(delta)` 里调用；测试可一次注入 600 秒（[SPEC-06 §3](SPEC-06-测试计划.md) 可测性约束）。autoload 自身**不**在 `_process` 里跑时钟 |
| `is_night() -> bool` | 当前是否夜晚 |
| `current_zone() -> String` | 当前区域 id（`grassland/camp/saltlake/mine/academy`） |
| `set_zone(zone_id: String) -> void` | 区域触发器调用；内部去重后发 `zone_changed` |
| `modify_oxygen(delta: float) -> void` | 增减氧气，内部 clamp + 发信号 |
| `modify_energy(delta: float) -> void` | 同上 |
| `modify_health(delta: float) -> void` | 同上；归零触发死亡流程 |
| `move_speed_multiplier() -> float` | 能量归零返回 0.5，否则 1.0 |
| `sleep_until_morning() -> void` | 床调用：跳夜、生命回满、天数 +1、发 `resources_respawned` |
| `respawn_player() -> void` | 复活：三值回满、位置回床、清空背包（掉落由 gameplay 处理） |
| `set_flag(key: String, value: bool) -> void` | 设置全局标记（只允许 `explosion_happened` / `purity_check_unlocked`） |
| `get_flag(key: String) -> bool` | 读取标记；未知 key 返回 false + 警告日志 |
| `get_balance(key: String, default_value: Variant) -> Variant` | 读 `balance.json`；缺键返回默认值 + 警告 |
| `get_ui_string(key: String) -> String` | 读 `ui_strings.json`（[SPEC-04 §11](SPEC-04-数据模型.md)）；缺 key 返回 key 本身 + 警告，不崩溃 |

### 2.3 信号

```gdscript
signal oxygen_changed(current: float, max_value: float)
signal energy_changed(current: float, max_value: float)
signal health_changed(current: float, max_value: float)
signal zone_changed(zone_id: String)
signal day_started(day_count: int)
signal night_started(day_count: int)
signal resources_respawned()
signal player_died(death_position: Vector2)
signal player_respawned()
signal flag_changed(key: String, value: bool)
```

### 2.4 约束

- 三值消耗速率、昼夜时长、伤害值全部走 `get_balance()`，**不许写死在逻辑里**。
- 界面短语走 `get_ui_string()`，知识字幕走 `KnowledgeTip`；两者都不许在场景/脚本里写中文字面量（NFR-04）。
- `modify_health` 在归零时只发 `player_died` 一次（需要内部去重，防止同帧多次伤害重复触发）。
- 区域切换必须去重：同一区域重复 `set_zone` 不发信号。

---

## 3. KnowledgeTip（P3 实现，P1 定接口）

职责：字幕引擎，唯一文案出口。

| 签名 | 说明 |
|---|---|
| `show(tip_id: String) -> void` | 按 `tips.json` 的 style/duration 显示；不存在则警告日志、不崩溃 |
| `show_once(tip_id: String) -> void` | 同上，但同一 id 只显示一次（用于区域/首次拾取） |
| `show_custom(text: String, style: String, duration: float) -> void` | 仅用于必须动态拼接的极少场景（如物质名 + 数量），**不得用来绕过数据表** |
| `is_shown(tip_id: String) -> bool` | 是否已展示过（供测试断言） |
| `clear_queue() -> void` | 清空队列（场景切换/测试用） |

信号：`signal tip_shown(tip_id: String)`、`signal tip_finished(tip_id: String)`。

约束：
- 内部队列串行播放，同 style 不重叠；`warning` 可打断 `bubble`（危险优先）。
- 任何模块显示文案**只能**走这里，逻辑代码里出现中文字面量视为违规（NFR-04）。

---

## 4. RecipeDB（P2 实现，P1 定接口）

职责：物质表与配方表的查询与匹配。

| 签名 | 说明 |
|---|---|
| `get_substance(id: String) -> Dictionary` | 返回物质记录；不存在返回空字典 |
| `all_substances() -> Array[Dictionary]` | 全部 17 条（图鉴用；HUD 计数集合为其中 16 条） |
| `try_craft(items: Array, tool: String, condition: String) -> Dictionary` | 核心匹配 |
| `get_recipe(id: String) -> Dictionary` | 按 id 取配方 |
| `unlocked_recipes() -> Array[String]` | 已解锁（已成功合成过）的配方 id 列表，图鉴用 |
| `get_fail_message(fail_id: String) -> Dictionary` | 按 `fail_tip_id` 取失败文案记录 `{id, reason, text}`；不存在返回空字典。失败池 id 只在 `fail_messages.json`，不在 `tips.json`（[SPEC-01 FR-G-07 判定口径](SPEC-01-需求与验收.md)） |
| `reload() -> void` | 重新读数据表（调参/测试用） |

`try_craft` 返回结构（**契约，不许改字段名**）：

```gdscript
{
    "success": bool,
    "recipe_id": String,        # 失败为 ""
    "outputs": Array[String],   # 失败为 []
    "card": Dictionary,         # {title, equation, body, application, footer}；失败为 {}
    "fail_reason": String,      # "no_match" / "wrong_condition" / "needs_purity_check" / ""
    "fail_tip_id": String,      # 失败时的字幕 id；成功为 ""
    "requires_pure_check": bool # 命中 R4 且未验纯时为 true
}
```

匹配规则（**测试必须逐条覆盖**）：
1. `items` 排序后与配方 `inputs` 排序比较，**材料顺序不影响结果**。
2. 材料匹配但 `tool` 或 `condition` 不符 → `success=false`，`fail_reason="wrong_condition"`。
3. 命中 `requires_pure_check` 的配方且 `GameManager.purity_check_unlocked == false` → `success=false`，`fail_reason="needs_purity_check"`（由 gameplay 触发爆炸事件）。
4. 无任何配方材料匹配 → `fail_reason="no_match"`，`fail_tip_id` 从失败文案池轮换。
5. 匹配成功后记录该 recipe_id 为已解锁。

---

## 5. 交互接口（IInteractable 约定，P1 定义）

玩家交互系统不认识具体类型，只认约定。任何可交互对象必须满足：

```gdscript
# 挂在 Area2D 或其父节点上
func get_interact_prompt() -> String     # 返回提示文本 id（走 KnowledgeTip 或 UI 短语表）
func can_interact() -> bool              # 当前是否可交互
func interact(player: Node) -> void      # 执行交互
```

约束：
- 玩家控制器**只**调用这三个方法，新增交互物不需要改玩家代码（FR-P-02 AC3）。
- 范围内多个对象时按距离最近选择。
- `interact()` 内部不许阻塞（异步逻辑用信号/await，不用 `while`）。

### 5.1 玩家场景（`scenes/player/`，TP-04 落地）

场景层，**不属冻结面**（不是 autoload）。只调用 autoload，不自读数据表（§1）。
节点结构与唯一名：

```
Player（CharacterBody2D，player.gd）
├── Body            # CollisionShape2D
├── %Interactor     # Area2D，interactor.gd，半径 player.interact_radius
├── %PromptBubble   # Label，头顶「按 E」提示（文案走 get_ui_string）
├── %ViewLight      # PointLight2D，半径按 dark/torch_view_radius 切换
└── %Camera         # Camera2D，player_camera.gd
```
<!-- PLAYER_TABLES -->

## 6. 导师模块接口（P3）

### 6.1 MentorRouter（`scripts/mentor/mentor_router.gd`）

纯逻辑类，**不依赖场景，可被单测直接实例化**（这是 UT-M04/M05 能跑的前提）。

| 签名 | 说明 |
|---|---|
| `classify(question: String) -> String` | 返回 `"combat"/"learning"/"chemistry"/"other"` |
| `route_targets(category: String) -> Array[String]` | 返回被派导师 id 数组，如 `["think","assistant"]` |
| `parse_mentions(text: String) -> Array[String]` | 解析回复中的 @xx → 导师 id 数组 |
| `handle_message(question: String) -> Array[Dictionary]` | 完整一轮对话，返回消息序列 |

`handle_message` 返回结构：

```gdscript
[
  {"mentor_id": "monitor", "text": "别慌…… @化学老师 你来把原理讲透！", "offline": false},
  {"mentor_id": "chem",    "text": "2H₂ + O₂ =点燃= 2H₂O……",        "offline": false}
]
```

**硬约束（对应 FR-M-05）**：
- 第一条消息的 `mentor_id` **必须**是 `"monitor"`。
- 返回数组长度 ≤ 3（班主任 + 最多 2 个被派老师，"学习方法类"派两位时为 3）。
- 只解析 `monitor` 消息中的 @；其他导师消息中的 @ 一律忽略（不触发新一轮）。
- 递归深度硬上限 1 次调度，代码层面用计数器保证，不依赖 prompt 自觉。

**非契约辅助**（TP-14 落地新增，不属冻结面，调用方勿依赖）：

| 签名 | 说明 |
|---|---|
| `load_from(rows: Array) -> void` | 数据注入口（SPEC-06 §3），`_init()` 内部调它读 `mentors.json` |
| `set_reply_provider(provider: Callable) -> void` | 注入回复来源 `(mentor_id, question) -> String`；未注入时走 `LLMClient.ask` |
| `dispatch_count() -> int` | 本次 `handle_message` 已调度次数（硬上限 1 的可观测点） |
| `system_prompt_for(mentor_id: String) -> String` | 人设段 + 通用后缀；未知 id 返回 `""`（不许把后缀单独喂给 LLM） |

### 6.1.1 PromptSuffix（`scripts/mentor/prompt_suffix.gd`）

纯逻辑 `RefCounted`，可直接实例化。承载 SPEC-04 §6 的通用 system 后缀，是**唯一**允许把 prompt 文本写进代码的文件（后缀属技术约束而非人设内容，人设一律在 `mentors.json`，FR-M-06 AC1）。

| 签名 | 说明 |
|---|---|
| `text() -> String` | 返回通用后缀原文 |
| `append_to(persona: String) -> String` | 人设段 + 后缀；人设段为空时返回 `""` |

### 6.2 LLMClient（P3）

| 签名 | 说明 |
|---|---|
| `ask(mentor_id: String, question: String, history: Array) -> String` | await 式调用，返回回复文本；失败自动兜底 |
| `is_offline() -> bool` | 当前是否离线模式 |
| `set_offline(value: bool) -> void` | 手动切换（演示保险开关） |
| `has_api_key() -> bool` | `user://config.cfg` 中是否有可用 key |
| `set_api_key(key: String) -> void` | 写入 `user://config.cfg` |

信号：`signal reply_started(mentor_id)`、`signal reply_chunk(mentor_id, text)`、`signal reply_finished(mentor_id, full_text, offline)`、`signal mode_changed(offline: bool)`。

约束：
- 唯一真实网络出口是私有 `_generate_reply()`；测试通过注入 stub 替换它，**不发真实请求**。
- 超时 8 秒 + 重试 1 次（常量可在测试中调小）。
- key 只从 `user://config.cfg` 读；**不得**出现在日志、错误消息、`res://` 任何文件（NFR-05）。
- 历史只带最近 4 轮。
- 玩家输入在进入 prompt 前必须经过 `sanitize_input()`（截断 200 字符 + 清理控制字符）。

**非契约辅助**（TP-15 落地新增，不属冻结面，调用方勿依赖）：

| 签名 | 说明 |
|---|---|
| `set_transport(transport: Callable) -> void` | 注入传输层 `(payload: Dictionary) -> Dictionary`，返回 `{result, code, body}`；这是 `_generate_reply()` 内部**唯一**发包处，测试注入后不发真实请求 |
| `build_request_body(mentor_id, question, history) -> Dictionary` | 组请求体（供 IT-M07 直接断言 `model` / `messages` / `max_tokens` / `temperature`） |
| `attempt_count() -> int` | 上一次 `ask()` 实际发包次数（重试上限的可观测点；离线时为 0） |
| `timeout_seconds() -> float` / `retry_count() -> int` | 当前生效值，默认读 `balance.json` 的 `llm.*` |
| `set_timeout_seconds(value: float)` / `set_retry_count(value: int)` | 测试调小用（FR-M-08 AC1「常量可在测试中调小」） |
| `set_qa_fallback(qa: RefCounted) -> void` | 注入离线兜底表（默认自建 `scripts/mentor/qa_fallback.gd`） |

**传输层返回约定**（`set_transport` 的 Callable 与真实 `HTTPRequest` 共用同一形状）：

| 键 | 类型 | 说明 |
|---|---|---|
| `result` | `int` | `HTTPRequest.Result`，`RESULT_SUCCESS` 之外一律算失败（超时用 `RESULT_TIMEOUT`，连不上用 `RESULT_CANT_CONNECT`） |
| `code` | `int` | HTTP 状态码，无响应时为 `0`；非 200 算失败 |
| `body` | `String` | 响应正文；非法 JSON 或缺 `choices[0].message.content` 算失败（畸形 body） |

四种失败（超时 / 网络错 / 非 200 / 畸形 body）一律返回空串，由 `ask()` 转入离线兜底，**不抛异常**（FR-M-08 AC2）。

**历史元素约定**（消除「4 轮」的歧义）：`history` 的每个元素是一**轮**对话
`{"question": String, "answer": String}`，进请求体时展开为 `user` + `assistant` 两条 message。
`_trim_history()` 只保留最后 `llm.history_rounds`（默认 4）个元素。

**网络常量**（非玩家可见文案，属技术约束，写在 `llm_client.gd` 常量区）：
端点 `https://api.deepseek.com/chat/completions`、模型 `deepseek-chat`、鉴权头 `Authorization: Bearer <key>`（OpenAI 兼容）。
`max_tokens` / `temperature` 读 `balance.json` 的 `llm.max_tokens` / `llm.temperature`。

**离线回答组装**：`_offline_reply()` = `QaFallback.answer(question)` + `ui_strings.chat_offline_badge`。
兜底表为空（无兜底行）时只返回角标，保证离线回复永不为空串（否则 UI 显示空气泡）。

### 6.3 离线兜底（`scripts/mentor/qa_fallback.gd`）

| 签名 | 说明 |
|---|---|
| `answer(question: String) -> String` | 关键词命中最多者胜；平票取表中先出现者；零命中返回班主任固定话术 |
| `match_score(question: String, keywords: Array) -> int` | 命中关键词数（供测试直接断言） |

离线回答由调用方统一追加「（离线模式）」后缀，**不在数据表里写这个后缀**。

### 6.4 配置面板占位（`scenes/mentor/config_panel.tscn` + `config_panel.gd`）

FR-M-10 的 UI 占位，**不属冻结面**（场景层，不是 autoload）。只调用 autoload，不自读数据表（§1）。
| 签名 | 说明 |
|---|---|
| `apply_api_key() -> bool` | 把输入框里的 key 交给 `LLMClient.set_api_key()`（只写 `user://config.cfg`）。空串视为不改动并返回 false；成功返回 true。**不回显、不记录 key** |
| `set_offline_toggle(value: bool) -> void` | 手动离线开关（FR-M-08 AC4），转发 `LLMClient.set_offline()`；面板打开时按 `is_offline()` 同步显示 |
| `personality() -> float` | 性格滑块当前值。**只读展示，任何模块都不许消费它**（FR-M-10 AC2「可拖动但不改变行为」） |
| `note_text() -> String` | 界面上的「赛后可配置」说明，取自 `GameManager.get_ui_string("config_note")` |

**非契约辅助**（测试用，调用方勿依赖）：`set_client(client: Node) -> void` 注入 LLM 客户端（默认 `/root/LLMClient`）。
测试**不许**让面板碰真实 `user://config.cfg`（里面是玩家的 key），一律注入假客户端断言「转发了什么」。

节点唯一名（`%Name`）：`%KeyInput`（`LineEdit`，`secret = true`）、`%ApplyButton`、`%OfflineToggle`、`%PersonalitySlider`、`%NoteLabel`。

约束：
- key 输入框 `secret = true`，且**不许**把输入内容写进任何 `push_*` / `print`（NFR-05）。
- 面板不缓存 key、不提供读取 key 的方法；只有「写入」方向。
- 性格滑块不连任何逻辑——`personality()` 仅供测试断言「拖动后值变了但行为没变」。
- 界面短语只走 `get_ui_string()`（NFR-04），本面板不新增 `ui_strings.json` 键（`config_note` 已存在，SPEC-05 §9）。

---

## 7. WorldMap（P1）

| 签名 | 说明 |
|---|---|
| `open() -> void` | 打开地图页 |
| `close() -> void` | 关闭 |
| `is_unlocked(zone_id: String) -> bool` | 区域是否解锁 |
| `all_zones() -> Array[Dictionary]` | 13 条区域记录（含未解锁预告语） |
| `get_zone(zone_id: String) -> Dictionary` | 单条查询 |

约束：区域数据全部来自 `worldmap.json`，UI 不硬编码区域名与预告语。

---

## 8. 场景树规范

```
World（scenes/main/world.tscn，P1）
├── TileMapLayers          # maps/，P5
├── Player                 # scenes/player/player.tscn，P1
├── ZoneTriggers           # Area2D ×5，调用 GameManager.set_zone()，P1
├── Collectables           # 采集物容器，P2
├── Facilities             # 过滤器/电解器/篝火/床/合成台，P2
├── Monsters               # 怪物容器，P2
├── AcademyBuilding        # 导师学院四房间 + 四位导师，P3
├── CanvasModulate         # 昼夜 tint，P1
└── UILayer（CanvasLayer）
    ├── HUD                # P1
    ├── TipLayer           # KnowledgeTip 挂载点，P3
    ├── CraftPanel         # P2
    ├── CardPopup          # P2
    ├── InventoryPanel     # P2
    ├── ChatPanel          # P3
    ├── WorldMapPanel      # P1
    └── CodexPanel         # P2
```

规则：
- UI 面板默认互斥（同一时刻只允许一个模态面板）；登记为**同组**的面板可同屏并列（当前仅背包+合成台的 `crafting` 组），跨组打开仍互斥；Esc 逐层关闭最上面板。由 `scenes/main/ui_manager.gd`（P1）统一裁决。
- 面板打开时屏蔽玩家输入，**但聊天框例外**（FR-M-02 AC1：世界不暂停）。
- 节点引用一律用唯一名 `%Name`，不用长路径。

---

## 9. 接口变更记录

| 日期 | 变更 | 原因 | 批准 |
|---|---|---|---|
| 2026-08-01 | 初版定稿 | 规格阶段 | 待 P1 在 H1 确认冻结 |
| 2026-08-02 | **接口冻结生效**（TP-01 完成，UT-C09/UT-D08/IT-C01 全绿）。五个 autoload 骨架按本文件签名建立，反射断言通过 | H1 冻结点到达 | P1 |
| 2026-08-02 | **新增契约方法** `GameManager.tick(delta: float) -> void`（§2.2 首行）。理由：SPEC-06 §3 要求「昼夜与三值消耗接受 `delta` 参数推进，不直接读 `Time`」，但冻结面上原本没有任何时间推进入口，规格自相矛盾。本次只**新增**，未修改任何已有签名 | TP-03（FR-C-02/03/04）实现需要，且补齐 SPEC-06 §3 可测性约束的缺口 | P1 |
| 2026-08-02 | 补记骨架期新增的**非契约**辅助方法（不属冻结面，调用方勿依赖）：`GameManager.reload_config/reset_stats/set_respawn_reference_position`、`KnowledgeTip.reload/queue_size`、`RecipeDB.reload/mark_unlocked`、`WorldMap.reload/is_open`、`LLMClient.sanitize_input`（FR-M-03 要求）、`scripts/autoload/data_loader.gd`（静态数据读取工具，不注册 autoload） | 实现需要，且不改动 §2..§7 已冻结签名 | P1 |
| 2026-08-02 | TP-03 新增的**非契约**辅助（不属冻结面，调用方勿依赖）：`GameManager.reset_clock()`（时钟回第一天清晨，测试/新开局用）、`GameManager.oxygen_net_rate() -> float`（当前区域氧气净速率，供 HUD 与测试查询）、`KnowledgeTip.load_from(rows: Array)`（数据注入口，SPEC-06 §3 可测性约束，`reload()` 内部改为调它） | TP-03（FR-C-02/03/04）实现与可测性需要，未改动 §2..§7 已冻结签名 | P1 |
| 2026-08-02 | **新增契约方法** `RecipeDB.get_fail_message(fail_id: String) -> Dictionary`（§4 表）。理由：`try_craft` 返回的 `fail_tip_id` 是 `fail_messages.json` 的 id 而非 `tips.json` 的 id，冻结面上原本没有把它换成文案的入口，调用方只能自己 `FileAccess` 读表——违反 §1「数据表只由 autoload 读取」。本次只**新增**，未修改任何已有签名 | TP-07（FR-G-07）实现需要，补齐失败文案取用入口 | P1 |
| 2026-08-02 | TP-07 新增的**非契约**辅助（不属冻结面，调用方勿依赖）：`RecipeDB.all_recipes()`（12 条配方记录，测试与图鉴用）、`all_fail_messages()`（失败池全量）、`build_card(recipe)`（按 FR-G-06 组装卡片五字段）、`reset_rotation()`（失败文案轮转计数器复位，SPEC-06 §3 确定性约束）、`reset_unlocked()`（已解锁进度复位，测试/新开局用；进度非表数据故不并入 `reload()`）。行为变更：骨架期 `try_craft` 恒返回 `no_match`，本次按 §4 规则 1~5 实现真匹配 | TP-07（FR-G-04/G-07）实现与可测性需要，未改动 §2..§7 已冻结签名 | P1 |
| 2026-08-02 | TP-06 新增两个 `scripts/gameplay/` **纯逻辑类**（**不属冻结面**，不是 autoload，可被单测直接实例化，同 §6.1 MentorRouter 的定位）：`inventory.gd`（`slot_count/stack_limit/slots/used_slots/count_of/has_item/add_item/remove_item/clear` + 信号 `inventory_changed`；格数与堆叠上限走 `GameManager.get_balance("inventory.hotbar_slots"/"inventory.stack_limit")`）、`discovery.gd`（`discover/is_discovered/discovered_count/discovered_ids/count_total/counted_count/reset` + 信号 `substance_discovered(substance_id)`；计数集合总数由 `RecipeDB.all_substances()` 数 `count_in_hud=true` 得出，**不写死 16**）。二者只调用已冻结的 `get_balance` / `all_substances`，未改动 §2..§7 任何签名 | TP-06（FR-G-02/G-03）实现需要；数据表仍只由 autoload 读取（§1） | P1 |
| 2026-08-02 | TP-14 新增两个 `scripts/mentor/` **纯逻辑类**（**不属冻结面**，不是 autoload，可被单测直接实例化，见 §6.1 / §6.1.1）：`mentor_router.gd`（§6.1 四个契约方法 + 非契约辅助 `load_from` / `set_reply_provider` / `dispatch_count` / `system_prompt_for`；分类关键词、派活对象、调度语、人设全部读自 `mentors.json`，代码里零内容文本）、`prompt_suffix.gd`（SPEC-04 §6 通用后缀 `text()` / `append_to()`，唯一允许写 prompt 文本的文件）。二者只经静态 `DataLoader` 读表、只调用已冻结的 `LLMClient.ask`，未改动 §2..§7 任何签名 | TP-14（FR-M-04/M-05/M-06）实现需要；数据表仍不由场景自读（§1） | P1 |
| 2026-08-02 | TP-15 §6.2 补齐三处**规格缺口**（均为新增，未改动 §2..§7 已冻结签名）：①「历史只带最近 4 轮」原未定义「一轮」的数据形状，实现只能猜——现约定 `history` 元素为 `{"question", "answer"}`，进请求体展开成 `user`+`assistant` 两条；②「测试通过注入 stub 替换 `_generate_reply()`」在 GDScript 里无法对 autoload 做方法替换——改为在 `_generate_reply()` 内部留唯一发包点 `set_transport(Callable)`，并定义传输层返回形状 `{result, code, body}` 与四种失败的判定口径；③ 端点/模型/鉴权头此前无处记载，现钉在 §6.2「网络常量」。同时补记非契约辅助 `build_request_body` / `attempt_count` / `timeout_seconds` / `retry_count` / `set_timeout_seconds` / `set_retry_count` / `set_qa_fallback`。行为变更：骨架期 `_offline_reply()` 只返回角标，本次改为 `QaFallback.answer()` + 角标 | TP-15（FR-M-07/M-08/M-09）实现与 UT-M08/IT-M07 可测性需要 | P1 |
| 2026-08-02 | TP-15 新增 `scripts/mentor/qa_fallback.gd`（§6.3 契约 `answer` / `match_score` + 非契约辅助 `load_from` / `best_row` / `mentor_id_for`）。纯逻辑 `RefCounted`，经静态 `DataLoader` 读 `qa_fallback.json`，零命中话术取自表中兜底行（SPEC-04 §7），代码里零玩家可见文案 | TP-15（FR-M-09）实现需要 | P1 |
| 2026-08-02 | TP-15 新增 §6.4「配置面板占位」：`scenes/mentor/config_panel.tscn` + `config_panel.gd`（**场景层，不属冻结面**）。理由：FR-M-10 只在 SPEC-01/02 里描述了「key 输入框可用 + 滑块可拖不生效 + 明示赛后可配置」，冻结面上没有任何落点，实现无处对齐——现钉住四个方法（`apply_api_key` / `set_offline_toggle` / `personality` / `note_text`）、五个唯一名节点与 NFR-05 口径（`secret = true`、不回显、不记录、只写不读）。同时把 FR-M-08 AC4 的手动离线开关归到本面板。未新增 `ui_strings.json` 键（`config_note` 已在 SPEC-05 §9），未改动 §2..§7 已冻结签名 | TP-15（FR-M-10 / FR-M-08 AC4）实现需要；MT-M10 手工验收的对齐基线 | P1 |
| 2026-08-02 | TP-05 新增的**非契约**辅助（不属冻结面，调用方勿依赖）：`KnowledgeTip.advance(delta: float)`（唯一时间推进入口，由渲染层在 `_process` 里调；autoload 自身不跑 `_process`）、`current_tip_id()`、`current_text()`、`current_style()`（供渲染层与测试读当前显示状态）。行为变更：骨架期的「入队即立刻出队」改为**真串行队列**——排队中的字幕在上台时才发 `tip_shown`，`warning` 抢占时被打断的字幕直接作废不重播 | TP-05（FR-U-01）实现需要；§3 已冻结的 5 个方法签名与 2 个信号未变 | P1 |
| 2026-08-02 | TP-08 新增 `scripts/gameplay/hydrogen_event.gd`（**纯逻辑 RefCounted，不属冻结面**：`ignite(items)` / `is_purity_check_available()` / `do_purity_check()` / `unlock_purity_check()` + 信号 `explosion_triggered` / `purity_check_performed`；爆炸伤害读 `balance.json damage.hydrogen_explosion`，解锁走 `debug.force_purity_unlock` 或导师回调）与 `scenes/gameplay/explosion.gd/.tscn`（场景层表现：`bind(event)` 唯一接线，火光 tween + 相机衰减震屏，音效挂载点无 stream 静默跳过）。只调用已冻结的 `RecipeDB.try_craft/build_card`、`GameManager.modify_health/set_flag`、`KnowledgeTip.show`，未改动 §2..§7 任何签名 | TP-08（FR-G-08/G-09）实现需要 | P1 |
| 2026-08-02 | TP-09 新增 `scripts/gameplay/item_effects.gd`（**纯逻辑 RefCounted，不属冻结面**：`use_item/equip/unequip/is_equipped/equipped_ids/effect_value`，八种道具效果按 items.json 的 `effect_value_key` 动态读 balance.json）与 `scenes/gameplay/monster_co_ghost.*` / `monster_acid_mist.*` / `monster_spawner.gd`（场景层，刷怪区间与伤害全读 balance；玩家经 `player` 组或 `target_player` 写入定位，装备经 `player.get_equipped_item_ids()` 可选方法读取）。未改动 §2..§7 任何签名 | TP-09（FR-G-10/G-11/G-12）实现需要 | P1 |
| 2026-08-02 | TP-10 新增 `scenes/gameplay/facility_*`（场景层，不属冻结面）：`facility_base.gd` 基类统一 §5 三方法与 autoload 访问，过滤器/电解器/篝火/床/实验台/湖水六个设施 + `facility_salt_purifier.gd` 粗盐三步纯逻辑状态机（`dissolve→filter→evaporate` 顺序强制）。设施经 `player.get("inventory")` 鸭子类型取背包（玩家侧挂载点由主 Agent 统一补）。电解 1:2 产出计数暂锚 `facility_electrolyzer.gd` 常量区（data/ 单写者约束，recipes.json 增加 outputs 计数字段后可下沉）。未改动 §2..§7 任何签名 | TP-10（FR-G-13/G-14、FR-C-05）实现需要 | P1 |
| 2026-08-02 | TP-11 新增 `scenes/gameplay/drop_bag.*` 与 `scenes/ui/death_screen.*`（场景层，不属冻结面）：掉落包 `spawn_at(parent, position, items)` 静态入口（新包替换旧包）、死亡画面监听 `player_died` 弹出、任意键 `confirm()` → `respawn_player()`。`game_manager.gd` 死亡段经核对已由 TP-01/03 落地，本包未改动任何冻结签名 | TP-11（FR-C-06）实现需要 | P1 |
| 2026-08-02 | TP-12 新增 `scenes/main/hud.*` / `main_menu.*` / `world_map_panel.*` / `pause_menu.*`（场景层，不属冻结面）：HUD 三条数值条纯信号驱动（无 `_process` 轮询）+ 低氧闪烁；主菜单三个门托管地图页；13 热区全部按 worldmap.json 构建；Esc 暂停菜单（`pause_toggled` 信号；`get_tree().paused` 由 world/ui_manager 统一裁决，§8）。场景路径约定：`world.tscn` / `academy.tscn` / `codex_panel.tscn` 为三个门的导航目标。未改动 §2..§7 任何签名 | TP-12（FR-C-07/C-08、FR-U-03）实现需要 | P1 |
| 2026-08-02 | TP-13 新增 `scenes/mentor/`（场景层，不属冻结面）：`academy.*`（四房间 + ZoneTrigger）、`mentor_npc.*`（§5 三方法，`prompt_ask`）、`chat_panel.*`（世界不暂停、逐字打字、idle/talk 切换；打字速度常量 `DEFAULT_TYPING_SPEED=40` 字/秒锚本文件常量区，测试经公共变量 `typing_chars_per_second` 调快）、`mentor_registry.gd` / `mentor_art.gd`（纯逻辑/加载辅助，立绘缺失时确定性纯色占位）。输入先过 `LLMClient.sanitize_input`，LLM 文本只做 Label 渲染。未改动 §2..§7 任何签名 | TP-13（FR-M-01/M-02）实现需要 | P1 |
| 2026-08-02 | TP-16 新增 `scenes/ui/codex_*`（场景层，不属冻结面）：`codex_panel.*`（网格自 `RecipeDB.all_substances()` 得出不写死 17、`set_discovery()` 注入口、循环翻页空态安全）、`codex_cell.*`（未收集剪影着色 + `codex_locked` 占位不泄露真名/化学式；icon 缺失时 id 散列稳定色占位）。未改动 §2..§7 任何签名 | TP-16（FR-U-04）实现需要 | P1 |
| 2026-08-02 | 主 Agent 集成补记（本批 7 包并行收敛后）：①`player.gd` 补 `var inventory` / `var item_effects` 挂载点 + `get_equipped_item_ids()` + `add_to_group("player")`（TP-09/TP-10 报告的集成缺口，场景层非冻结面）；②SPEC-05 §9 新增 8 个 ui_strings 键（`hud_day`/`hud_night`/`pause_title`/`pause_continue`/`pause_to_menu`/`menu_map`/`chat_send`/`chat_close`），替换 hud/pause_menu/chat_panel 的英文/ASCII 占位文案，`validate_data.gd` 的 `UI_STRING_KEYS` 白名单同步。未改动 §2..§7 任何签名 | 7 包交付报告中的文案缺口与玩家侧接线缺口，归 P1 裁决项 | P1 |
| 2026-08-02 | TP-06 补 `scenes/gameplay/collectable.*`（场景层，不属冻结面）：FR-G-01 采集物，只配 `substance_id`，记录解析先查 substances（经 RecipeDB）再查 items（经 ItemEffects 纯逻辑类），背包满留原地、未知 id 不崩溃、`collected(substance_id)` 信号供世界接 Discovery/HUD | FR-G-01 实现需要；IT-G01 9 项全绿 | P1 |
| 2026-08-02 | TP-07 补 `scenes/ui/craft_panel.*` 与 `scenes/ui/card_popup.*`（场景层，不属冻结面）：合成界面 3 材料格 + 3 器材 + 反应/点燃/验纯（H₂+O₂ 便携格点燃走 HydrogenEvent），失败材料不消耗、取消全回背包、支持背包拖入（`_can_drop_data/_drop_data`）、`managed/close_requested` 供 ui_manager 裁决；卡片弹窗五字段 + 任意键跳过 + `closed` 信号。SPEC-05 §9 同步新增 7 个 ui_strings 键（`craft_title`/`craft_tool_portable`/`craft_tool_lamp`/`craft_tool_bench`/`craft_cancel`/`craft_slot_empty`/`inventory_title`），validator 白名单同步 | FR-G-05/G-06 与 FR-G-08 AC1、FR-G-09 AC1..3 的界面部分；IT-G05 14 项、IT-G06 6 项全绿 | P1 |
| 2026-08-02 | TP-06 补 `scenes/ui/inventory_panel.*`（场景层，不属冻结面）：Tab 开关、格数跟随背包配置不写死、信号驱动刷新、图标缺失按 id 散列稳定色占位、格子可拖拽、`managed/toggle_requested` 供 ui_manager 裁决；同包新增 `scenes/main/ui_manager.gd`（§8 裁决器：模态互斥 + `input_blocked`，聊天框注册为不屏蔽） | FR-U-05 实现需要；IT-U05 9 项全绿 | P1 |
| 2026-08-02 | TP-05 补 `scenes/ui/tip_layer.*`（场景层，不属冻结面）：KnowledgeTip 唯一 `advance(delta)` 调用方；bubble 头顶（`set_player` 后画布投影跟随）/ banner 底部 / warning 中部红字 | FR-U-01 三种样式的可见渲染；渲染层测试 6 项全绿 | P1 |
| 2026-08-02 | TP-17 世界总装：`maps/whitebox_map.tscn`（四区 + 学院白盒布局、地面碰撞、采集物标记）、`scenes/main/world.tscn/world.gd`（§8 场景树落地：ZoneTriggers×4 + 学院自带触发、采集物生成与清晨刷新、CO 幽灵矿洞常驻/草原夜刷、酸雾怪 spawner 接线、死亡掉落包与复活回床、CanvasModulate 昼夜 tint、睡觉渐黑、use_item 1-8 快捷使用、codex 热键 C）、`scenes/main/zone_trigger.gd`（可配 zone_id 或一次性 tip_id，如 zone_river）。`player.gd` 补 `input_blocked`（ui_manager 裁决写入）；`facility_bed.gd` 补 `slept` 信号；`facility_bench.gd` 补 `craft_requested` 信号（均为场景层新增，未改 §2..§7 签名）；`project.godot` 新增 `codex` 输入动作（SPEC-02 §8 同步） | FR-C-03/04/05/06、FR-G-01/05/06/10/11/12、FR-U-02/04/05 的世界接线；test_world.gd 16 项全绿 | P1 |
| 2026-08-02 | FR-G-09 AC1 接线：`hydrogen_event.gd` 补 `question_mentions_hydrogen(question)`（关键词读 qa_fallback.json 的 `qa_h2_explosion` 行，代码零中文关键词）；`chat_panel.gd` 补 `set_hydrogen_event()`，发送问题命中后经 `unlock_purity_check()` 置 `purity_check_unlocked`。均为非冻结面新增 | SPEC-02 §4.5「由导师模块回调设置」的落地；test_chat_purity_unlock.gd 3 项全绿 | P1 |
| 2026-08-02 | 数据裁决：`hcl`/`naoh`/`caoh2` 的 `zone` 由 `[]` 改为 `["camp"]`（营地试剂架可拾取）——12 条配方无一条产出这三者，但 R6/R7/R8 以它们为材料，不补来源演示路径不可达；SPEC-05 §1 同步并记裁决口径，配方仍恰好 12 条 | R6/R7/R8 与「中和喷雾打酸雾怪」演示路径可达性 | P1 |
| 2026-08-02 | `main.tscn` 改为承载 MainMenu 实例（原为空 Node2D，启动后黑屏） | FR-C-08 主菜单入口落地 | P1 |
| 2026-08-02 | 补全批（WORKLOG A1..A5/B1..B8）：①items.json 增 `carbon_mask`（equip/immune_co），幽灵 `contact_damage_per_second` 实现 FR-G-10 AC5 装备免疫 + 玩家在 academy 不追踪（FR-M-01 AC2）；②电解器成功额外灌装 `oxygen_tank`×1（D4）；③collectable 增 `%PickupPlayer` 音效挂载点（无 stream 静默）；④craft_panel 点燃在 mine 区域按 `low_oxygen` 匹配（D3）+ 成功消费配方 `unlock_tip`；⑤新增 `scenes/main/facility_signpost.*`（§5 三方法，`interact()` 调 `WorldMap.open()`）摆进 world.tscn 营地；⑥HUD 氧气首破 `tutorial_oxygen_hint_at` 弹 `sys_oxygen_tutorial`（tips.json 新增，once）+ 三条 bar theme fill 语义色；⑦world 监听 `zone_changed` 触发 `sys_mine_breath`/`zone_photosynthesis`；⑧player ViewLight 无纹理时程序生成 GradientTexture2D 兜底；⑨D2：`main_menu.open_academy()` 改为导航 world + 树根元数据 `world_spawn_override="academy_gate"` 一次性出生点覆盖，world `_resolve_spawn_point()` 消费。`validate_data.gd` 的 `ITEM_EFFECTS` 枚举增 `immune_co`（SPEC-04 §10 已同步）。未改动 §2..§7 任何签名 | WORKLOG 缺口清单 A/B 级收口；SPEC-01 FR-G-10 AC5、FR-C-08 AC1（D2）、SPEC-02 §4.4/§5、SPEC-05 §1/§3/§8 已先行同步 | P1 |
| 2026-08-02 | 对标优化包C-3（Wave 1）：`KnowledgeTip` once 字幕的 `_shown` 已展示标记时机由**入队**改为**开播**（`_start()` 内标记）；被 `warning` 抢占打断的 once 字幕经 `_unmark_once()` 撤销已展示记录，之后可再次触发——修复"once 字幕被 warning 顶掉后永久丢失"。同时**事实回写**：`warning` 可打断 `banner`（§3 原仅写可打断 `bubble`，实现自 TP-05 起 warning 抢占一切在播样式）。非冻结面行为修正，§3 已冻结签名未变 | 包C-3 缺陷修复与既有实现事实回写 | P1 |
| 2026-08-02 | 对标优化包C-1（Wave 1）：`mentor_router.set_reply_provider` 向后兼容扩展——provider 返回值除 `String`（空串视为离线兜底，旧语义不变）外，也接受 `{text, offline}` 字典（回答来源自报在线状态）；`handle_message` 返回消息的 `offline` 标记跟随实际回答来源透传（LLMClient 取 `is_offline()`），不再硬编码 false。非冻结面辅助方法的行为扩展，§6.1 四个契约方法签名未变 | 离线角标漏显修复（FR-M-08 离线标识透传） | P1 |
| 2026-08-02 | 事实回写：`LLMClient.reply_chunk` 信号**本期不发射**——DeepSeek 按非流式请求实现，`_generate_reply` 只发 `reply_started` / `reply_finished`；§6.2 的信号声明保留（流式逐字输出为赛后项），调用方不得依赖 `reply_chunk` | 对标调研发现的契约-实现差异，登记避免误依赖 | P1 |
| 2026-08-02 | 事实回写：`WorldMap.is_unlocked(zone_id)` 为 **MVP 静态解锁**——直接读 `worldmap.json` 各区 `unlocked` 字段（5 已解锁 + 8 锁定），无动态解锁逻辑；8 个未解锁区域统一标注「赛后解锁」（SPEC-05 §7） | 对标调研确认契约与实现一致，登记口径 | P1 |
| 2026-08-02 | 审计修复包B（A2）——**离线调度路径**：离线模式下 `mentor_router` 首条消息恒走数据表 `dispatch.line` 调度语直出（不再走不可达路径），qa 兜底答案只由被派导师输出，调度链在离线语义下与联网一致（FR-M-09 AC4）。涉及接口：`mentor_router` 离线路径（非冻结面辅助逻辑）。**不影响冻结签名** | 五路审计 A2 修复 | P1 |
| 2026-08-02 | 审计修复包C（A3）——**聊天框/配置面板走 ui_manager 裁决**：`academy.tscn` 实例化 `config_panel`，聊天框底栏新增「设置」按钮（`chat_config` 键），经 `ui_manager.open("config")` 模态裁决打开；学院聊天框亦经 `ui_manager.open("chat")` 纳管，面板互斥收口。涉及接口：academy 经 `ui_manager.open("chat")` / `open("config")`（场景层，§8 裁决器）。**不影响冻结签名** | 五路审计 A3 修复 | P1 |
| 2026-08-02 | 审计修复包A/C——**Discovery 会话共享**：主菜单图鉴门与游戏内共享收集进度，`codex_panel` 经树根元数据 `SESSION_DISCOVERY_META`（`"session_discovery"`）传递 Discovery 实例，无主单例时自建仓并写回。涉及接口：`codex_panel` `SESSION_DISCOVERY_META` 元数据约定（场景层）。**不影响冻结签名** | 五路审计相关修复（WORKLOG F6） | P1 |
| 2026-08-02 | 审计修复包A（A4）——**首次区域触发解耦**：`game_manager._zone` 初值改为空串，首次定位（如出生在草原）与同区去重解耦——空串初值不被 `set_zone("grassland")` 的去重吞掉，出生区横幅正常触发；氧气结算在 `_zone` 空串时按 `DEFAULT_ZONE` 取值。涉及接口：`game_manager._zone` 初值语义（§2 契约 `set_zone`/`current_zone` 签名未变）。**不影响冻结签名** | 五路审计 A4 修复 | P1 |
| 2026-08-02 | ui_manager 新增 `"config"` 面板注册：`config_panel` 采用自注册模式（`PANEL_CONFIG="config"` 常量），academy 实例化后注册进 §8 裁决器，与聊天框同受模态互斥裁决。场景层新增，**不影响冻结签名** | FR-M-10 入口落地（A3 配套） | P1 |
| 2026-08-02 | `ui_strings.json` 新增 `config_apply`（确定）/ `chat_config`（设置）两键（SPEC-05 §9 已补登），validator `UI_STRING_KEYS` 白名单同步。数据表新增键，**不影响冻结签名** | 配置面板「确定」与聊天框「设置」按钮文案 | P1 |
| 2026-08-02 | FR-U-06 面板自适应布局（场景层，不属冻结面）：合成/背包/卡片模态面板由固定像素尺寸改为锚点比例铺开（宽 76%/70%/80%、高 60%/70%/70%）并居中；主菜单/暂停菜单按钮组改为中心锚点（`anchors_preset=8`）；死亡画面四行文案改垂直中心锚点 + 全宽居中文本。`project.godot` 显式补 `window/stretch/aspect="keep"`（运行时默认即 keep，补写对齐 FR-C-01 AC1 文案）。**不影响冻结签名** | FR-U-06 落地（IT-U06 6 项全绿）；并修复会话中 Godot 进程改写 project.godot 丢失 640×360 视口行的问题 | P1 |
| 2026-08-02 | **4 个玩法对象节点树模块化重构**（场景层，不属冻结面，纯结构重构无行为变更）：collectable / monster_co_ghost / monster_acid_mist / explosion 由扁平节点树改为模块化层级——世界空间视觉部件拆成 `%Visuals` 容器下的独立命名节点（collectable：`%Glow`/`%IconSprite`；ghost：`%Glow`/`%Body`/`%EyeL`/`%EyeR`；acid：`%Glow`/`%Body`/`%Core`；explosion：`%Fireball`/`%Shockwave`），音频进 `%Audio` 容器（`%PickupPlayer`/`%BoomPlayer`），explosion 全屏闪光留在根层 `FlashLayer`(CanvasLayer)。脚本侧视觉逻辑按部件拆分独立方法（collectable `_apply_glow/_apply_icon/_tween_float/_tween_glow`；ghost/acid `_apply_visuals/_start_glow_pulse`；explosion `_tween_flash/_tween_fireball/_tween_shockwave`）。7 个既有唯一名（`%Glow %IconSprite %PickupPlayer %ContactArea %HitArea %Flash %BoomPlayer`）、根节点类型、物理碰撞体、根方法/信号契约全部保留。**不影响冻结签名** | 用户需求：对象节点太少不便针对性修改，先做 4 个核心示范（视觉逻辑分离）；IT-G01/IT-G08/IT-G10/IT-G11 各增 1 项结构断言 | P1 |
| 2026-08-02 | 背包/合成面板美术替换（场景层，不属冻结面）：`inventory_panel`/`craft_panel` 的 `Panel` 由 PanelContainer 改为 Control + `Bg`(TextureRect) 宝箱底图（`assets/art/ui/inventory_bg.png`/`craft_bg.png`，由 `panels.png` 切分），控件按锚点对准底图格子，按钮改 flat；面板比例按底图调整为背包 51.5%×83.3%、合成 34.1%×88.9%（FR-U-06 AC1 口径同步）。全部唯一名（`%Grid %TitleLabel %Slot0..2 %Tool* %React/%Ignite/%Purity/%CancelButton`）、根方法/信号契约保留。**不影响冻结签名** | 用户提供宝箱美术，要求替换合成与背包面板 UI | P1 |
| 2026-08-02 | 主菜单按钮组下移（场景层，不属冻结面）：`main_menu` 的 `MenuBox` 垂直锚点由 0.5 改为 0.62（水平居中不变），按钮组呈「中间偏下」、避开背景人物区；暂停菜单保持视口居中。FR-U-06 AC2 与 IT-U06 口径同步。**不影响冻结签名** | 用户审美需求：主菜单按钮中间偏下更好看 | P1 |
| 2026-08-02 | 背包内合成快捷入口（FR-G-05 AC4，场景层）：新增输入动作 `craft`（X 键）；`inventory_panel` 新增信号 `craft_requested()`（背包打开时按 X 发出，未打开不触发）与 `%HintLabel` 提示（ui_strings `inventory_craft_hint`）；world `_setup_ui` 接线 `craft_requested → ui_manager.open("craft")`（互斥自动关背包）。合成台 E 交互入口保留不变。**不影响冻结签名** | 用户需求：进入背包后可按特殊键直接合成 | P1 |
| 2026-08-02 | **§8 裁决规则修订 + ui_manager 分组共存**（FR-G-05 AC5，场景层）：§8「同一时刻只允许一个模态面板」修订为「默认互斥，`register_panel` 第四参 `group` 相同且非空的面板可同屏并列」（当前仅背包+合成台 `crafting` 组）；`ui_manager` 内部由单一 `_active` 改为 `_open_order` 栈，`register_panel` 增可选参 `group`、新增 `close_all()`，Esc 逐层关最上面板（旧三参调用与跨组互斥行为不变）。背包靠左（51%×83%）、合成台靠右（34%×89%）同屏并列（FR-U-06 AC1 口径同步）；两面板根改 `mouse_filter=IGNORE` 互不遮挡点击，craft_panel 可见区域 `set_drag_forwarding` 转发拖放——背包材料可直接拖到合成界面入格；world 接线 `craft_requested → toggle("craft")`、合成台 E 交互同时打开背包+合成台。**不影响冻结签名**（ui_manager 非 autoload） | 用户需求：合成台不遮背包、背包材料直接拖入合成 | P1 |
| 2026-08-02 | **导师室独立页 + 区域黑洞过渡（取代 D2）**（场景层，不属冻结面）：①学院建筑与学院区背景从世界移除，`main_menu.open_academy()` 改为整页加载新场景 `scenes/mentor/mentor_room.tscn`（教室场景图 `assets/art/mentor_room/room_bg.png` + 四导师立绘卡 `portrait_<id>.png`，卡数据驱动 mentors.json，点卡开聊内嵌 chat_panel），D2 出生点覆盖元数据机制（`world_spawn_override`/`academy_gate`）与 world `_resolve_spawn_point` 一并删除；②世界内新增输入动作 `mentor_room`（T 键），导师室注册为 ui_manager 模态面板（`blocks_input=true`，聊天框内嵌不再单列注册，FR-M-02 AC1「世界不暂停」由不暂停树保持）；③新增 `scenes/gameplay/black_hole.tscn`（黑核+紫环程序化视觉，Area2D 双向触发→自建黑屏覆盖层渐黑→传送对侧落点→渐亮，`traveled` 信号），world 摆 4 实例封三条区域边界（盐湖↔草原 ×1、草原↔营地 ×2 封学院缺口两端、营地↔矿洞 ×1），落点经 ZoneTrigger 自动切区；④白盒四区背景由平铺改为单张完整 UV（学院紫色块删除）。`academy.tscn`/`mentor_npc` 保留未删（test_academy 独立实例仍可用，赛后可作导师室内景复用）。**不影响冻结签名** | 用户要求：删背景里的导师室做独立页、场景间黑洞黑屏过场 | P1 |
