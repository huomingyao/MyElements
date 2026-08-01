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

---

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

### 6.3 离线兜底（`scripts/mentor/qa_fallback.gd`）

| 签名 | 说明 |
|---|---|
| `answer(question: String) -> String` | 关键词命中最多者胜；平票取表中先出现者；零命中返回班主任固定话术 |
| `match_score(question: String, keywords: Array) -> int` | 命中关键词数（供测试直接断言） |

离线回答由调用方统一追加「（离线模式）」后缀，**不在数据表里写这个后缀**。

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
- UI 面板互斥（同一时刻只允许一个模态面板），由 `scenes/main/ui_manager.gd`（P1）统一裁决。
- 面板打开时屏蔽玩家输入，**但聊天框例外**（FR-M-02 AC1：世界不暂停）。
- 节点引用一律用唯一名 `%Name`，不用长路径。

---

## 9. 接口变更记录

| 日期 | 变更 | 原因 | 批准 |
|---|---|---|---|
| 2026-08-01 | 初版定稿 | 规格阶段 | 待 P1 在 H1 确认冻结 |
