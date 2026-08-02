# SPEC-04｜数据模型

> 本文件定义 `data/` 下 **10 个 JSON 文件**的 Schema 与约束：`substances` / `recipes` / `fail_messages` / `tips` / `mentors` / `qa_fallback` / `worldmap` / `balance` / `items` / `ui_strings`。文案内容在 [SPEC-05](SPEC-05-内容数据表.md)。
> 程序只认字段名；P3 填内容时字段名一个字母都不许改。
> 全部表格由 `FR-D-07 数据校验器` 统一校验，校验不过不许提交。

---

## 1. 通用约定

- 位置：`res://data/*.json`，UTF-8 无 BOM，两空格缩进。
- 顶层结构：**数组**（`[...]`），不用带包装的对象，方便追加与 diff。
- id 命名：全小写蛇形，与化学式对应时用小写无下标（`h2o`、`caco3`、`cuso4`）。
- 化学式/方程式在文案字段中用 Unicode 下标（`O₂`、`H₂O`、`CaCO₃`），**不用 LaTeX**。
- 资源路径一律 `res://` 绝对路径；缺资源时指向占位图 `res://assets/art/placeholder.png`。
- 布尔字段缺省视为 `false`；数值字段缺省由代码常量兜底并输出警告。
- **禁止在数据表中写游戏逻辑**（无表达式、无脚本路径求值）。

---

## 2. substances.json（17 条，HUD 计数集合 16 → FR-D-01）

```json
[
  {
    "id": "o2",
    "name": "氧气",
    "formula": "O₂",
    "category": "单质",
    "tip_id": "tip_o2",
    "zone": ["grassland"],
    "icon": "res://assets/art/icons/o2.png",
    "codex_line": "生命与燃烧都离不开它，但它自己不会燃烧。",
    "stackable": true,
    "count_in_hud": true
  }
]
```

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | String | ✅ | 全表唯一，小写蛇形 |
| `name` | String | ✅ | 中文名 |
| `formula` | String | ✅ | Unicode 下标；混合物可写"NaCl（含杂质）" |
| `category` | String | ✅ | 枚举：`单质/化合物/氧化物/酸/碱/盐` |
| `tip_id` | String | ✅ | 必须存在于 `tips.json`（交叉校验） |
| `zone` | Array[String] | ✅ | 元素取自 `grassland/camp/saltlake/mine/academy`；合成产物用 `[]` |
| `icon` | String | ✅ | 存在的 `res://` 路径 |
| `codex_line` | String | ✅ | 图鉴一句话（[SPEC-05 §6](SPEC-05-内容数据表.md)） |
| `stackable` | bool | ⬜ | 默认 true |
| `count_in_hud` | bool | ⬜ | 默认 true；仅 `co2` 为 false（[SPEC-05 §1](SPEC-05-内容数据表.md) 计数口径） |

校验规则：
- 恰好 17 条；`count_in_hud != false` 的恰好 16 条（HUD「已收集 N/16」的计数集合）。
- `category` 值在枚举内。
- `tip_id` 在 tips 表存在。
- `icon` 路径存在。

---

## 3. recipes.json（12 条 → FR-D-02）

```json
[
  {
    "id": "r_sulfur_torch",
    "inputs": ["stick", "s"],
    "tool": "portable",
    "condition": "ignite",
    "outputs": ["sulfur_torch"],
    "equation": "S + O₂ =点燃= SO₂",
    "card_title": "硫的燃烧",
    "card_body": "硫在空气中燃烧发出淡蓝色火焰，生成有刺激性气味的二氧化硫。",
    "card_application": "硫火把：夜晚照明与驱虫",
    "unlock_tip": "tip_mass_conservation",
    "requires_pure_check": false,
    "is_physical": false
  }
]
```

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | String | ✅ | 唯一，`r_` 前缀 |
| `inputs` | Array[String] | ✅ | 2~3 项；每项存在于 substances 或道具表 |
| `tool` | String | ✅ | 枚举：`portable/alcohol_lamp/bench/electrolyzer/filter` |
| `condition` | String | ✅ | 枚举：`none/ignite/heat/electrify/catalyst/low_oxygen/three_step` |
| `outputs` | Array[String] | ✅ | ≥1 项；每项存在于 substances 或道具表 |
| `equation` | String | ✅ | 物理过程写 `"（物理过程，无化学方程式）"` |
| `card_title` | String | ✅ | 卡片标题 |
| `card_body` | String | ✅ | 现象描述（课本原句优先） |
| `card_application` | String | ✅ | 现实应用一句话 |
| `unlock_tip` | String | ⬜ | 存在于 tips 表 |
| `requires_pure_check` | bool | ⬜ | 仅 R4 为 true |
| `is_physical` | bool | ⬜ | 物理过程配方为 true（R11 粗盐提纯、R12 碳活化，卡片提示"物理变化"） |

校验规则：
- 恰好 12 条；id 唯一。
- 有且仅有一条 `requires_pure_check == true`（R4）。
- `tool`/`condition` 在枚举内。
- `inputs`/`outputs` 中所有 id 可解析（substances 或道具表）。
- 不存在两条配方拥有完全相同的 `(inputs 排序, tool, condition)` 三元组（否则匹配歧义）。

### 3.1 失败文案池（`recipes.json` 同目录 `fail_messages.json`）

```json
[
  { "id": "fail_physical_mix", "reason": "no_match", "text": "没有新物质生成——这只是物理混合，不是化学反应" },
  { "id": "fail_no_product",   "reason": "no_match", "text": "没有生成沉淀、气体或水，所以不反应" },
  { "id": "fail_condition",    "reason": "wrong_condition", "text": "条件不够——有些反应需要点燃、加热、通电或催化剂" },
  { "id": "fail_wrong_tool",   "reason": "wrong_condition", "text": "器材不对——便携格、酒精灯、实验台和电解器能做的反应各不相同" }
]
```

（示例节录；实际表共 **9 条**：`no_match` 5 条 + `wrong_condition` 4 条，全量见 [SPEC-05 §2](SPEC-05-内容数据表.md) 失败反馈表。其中 `fail_copper_acid` 为彩蛋条目：仅铜+酸类组合触发，不参与通用 `no_match` 轮转。）

约束：
- `reason` 取 `no_match/wrong_condition`；id 唯一，`fail_` 前缀。
- **每个 reason 池至少 2 条**（硬约束，2026-08-02 补）：`try_craft` 按 reason 做确定性轮转取用，池内只有 1 条时 FR-G-07 AC2「连续两次同类失败文案不同」不可满足。判定口径见 [SPEC-01 FR-G-07](SPEC-01-需求与验收.md)。
- 这些 id **不进 `tips.json`**（失败池与 51 条字幕表互不重叠）；显示时由调用方 `RecipeDB.get_fail_message(id)` 取 text 再走 `KnowledgeTip.show_custom()`。

---

## 4. tips.json（51 条 → FR-D-03）

```json
[
  {
    "id": "tip_o2",
    "style": "bubble",
    "duration": 3.0,
    "once": true,
    "text": "氧气 O₂——空气中的氧气约占 21%，动植物呼吸都需要它"
  }
]
```

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | String | ✅ | 唯一 |
| `style` | String | ✅ | 枚举：`bubble`(3s 头顶) / `banner`(4s 底部) / `warning`(5s 红字) |
| `duration` | float | ⬜ | 缺省按 style 默认（3/4/5） |
| `once` | bool | ⬜ | 默认 false；区域字幕与首次拾取为 true |
| `text` | String | ✅ | 非空；课本原句优先 |

校验规则：
- id 唯一，`style` 在枚举内，`text` 非空。
- [SPEC-05 §3](SPEC-05-内容数据表.md) 列出的每个 id 都存在。
- substances 表引用的所有 `tip_id` 都存在。

---

## 5. mentors.json（4 条 → FR-D-04）

```json
[
  {
    "id": "chem",
    "name": "袁仲衡",
    "title": "化学老师",
    "room": "化学实验室",
    "avatar_idle": "res://assets/art/mentors/chem_idle.png",
    "avatar_talk": "res://assets/art/mentors/chem_talk.png",
    "sprite": "res://assets/art/mentors/chem_pixel.png",
    "route_class": "chemistry",
    "catchphrases": ["配平了吗？", "万物皆由元素构成。"],
    "system_prompt": "你是袁仲衡，57 岁……（见 SPEC-05 §4.2）"
  }
]
```

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | String | ✅ | 固定四个：`chem/monitor/assistant/think` |
| `name` | String | ✅ | 具名 |
| `title` | String | ✅ | 职称（聊天框显示） |
| `room` | String | ✅ | 四个房间之一，与场景摆放一致 |
| `avatar_idle` / `avatar_talk` | String | ✅ | 半身立绘路径（存在或占位图） |
| `sprite` | String | ✅ | 房间内 32×32 像素小人路径 |
| `route_class` | String | ✅ | `chemistry/dispatch/planning/thinking`（仅供查阅，实际调度由班主任逻辑执行） |
| `catchphrases` | Array[String] | ⬜ | 口头禅（离线模式拼接用） |
| `system_prompt` | String | ✅ | 人设段，运行时后接通用后缀（§6） |
| `mention` | String | ✅ | @ 句柄（**不含 `@`**），如 `化学老师`；唯一 |
| `dispatch` | Array[Dictionary] | ⬜ | **仅 `monitor` 有**：班主任调度表，见下 |

`mention` 于 2026-08-02 补入：`title` 不能当 @ 句柄——`think` 的 `title` 是「实用思维老师」，
而 [SPEC-05 §4.1/§4.3](SPEC-05-内容数据表.md) 与 `monitor.system_prompt` 一致使用 `@思维老师`，
用 `"@" + title` 匹配永远落空。`parse_mentions()`（[SPEC-03 §6.1](SPEC-03-系统与接口契约.md)）
以本字段做 `@句柄 → 导师 id` 的映射，句柄集合因此是数据而非代码常量。
四条取值：`化学老师` / `班主任` / `助理` / `思维老师`。

`monitor.dispatch` 每项字段（2026-08-02 补入，理由见 [SPEC-01 FR-M-04 判定口径](SPEC-01-需求与验收.md)）：

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `category` | String | ✅ | 枚举 `combat/learning/chemistry/other`，唯一 |
| `keywords` | Array[String] | ✅ | 命中即归此类；`other` 是兜底故为空数组 |
| `targets` | Array[String] | ✅ | 被派导师 id，1~2 项，均须在本表存在且不为 `monitor` |
| `line` | String | ✅ | 离线调度语模板（[SPEC-05 §4.3](SPEC-05-内容数据表.md)），须含每个 target 的 `@` + 其 `mention` |

**数组顺序即分类优先级**（`combat` → `learning` → `chemistry` → `other`），
分类器按序取首个命中项，优先级因此是数据而非代码常量。

校验规则：
- 恰好 4 条，id 集合等于 `{chem, monitor, assistant, think}`。
- `monitor` 必须有 `dispatch`，恰好 4 项，`category` 覆盖四类且顺序为 `combat/learning/chemistry/other`；非 `monitor` 不得有 `dispatch`。
- 每项 `targets` 非空且 ≤2 项、id 存在、不含 `monitor`；`learning` 恰好 2 项。
- 每项 `line` 非空，且对每个 target 都含 `"@" + 该导师 mention`。
- 除 `other` 外每项 `keywords` 非空。
- `mention` 四条齐全、非空、互不相同，且**不以 `@` 开头**。
- `monitor` 的 prompt 必须包含调度规则关键字（`@化学老师`、`@思维老师`、`@助理`）。
- **非 monitor 的三位 prompt 必须包含"绝不出现 @"约束**（FR-M-06 AC2，可自动断言）。
- 代码中不得出现任何 prompt 文本（grep 断言）。

---

## 6. 通用 system 后缀（代码常量，非数据表）

拼接在每位导师 `system_prompt` 之后，位置：`scripts/mentor/prompt_suffix.gd`。

> 你是初中化学游戏《元素炼金物语》中的导师。规则：
> 1）只用初中化学范围回答，超纲就说"这是高中内容，先记住现象"；
> 2）回答不超过 120 字，口语化，像老师对初一学生说话；
> 3）涉及反应必须在末尾给标准化学方程式；
> 4）绝不透露自己是 AI 语言模型；
> 5）不知道就建议查图鉴或问化学老师。

约束：后缀是唯一允许在代码中的 prompt 文本（因为它对全部导师一致且属于技术约束）。改动需同步本文件。

---

## 7. qa_fallback.json（≥20 条 → FR-D-05）

```json
[
  {
    "id": "qa_h2_explosion",
    "keywords": ["氢气", "爆炸", "验纯"],
    "mentor_id": "chem",
    "answer": "氢气中混有空气时点燃会剧烈燃烧引发爆炸。点燃前必须验纯：收集一小试管氢气移近火焰，只发出轻微\"噗\"声才是纯氢气。2H₂+O₂=点燃=2H₂O"
  }
]
```

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | String | ✅ | 唯一 |
| `keywords` | Array[String] | ✅ | ≥1 项，非空字符串；**唯一例外是兜底行**（见下） |
| `mentor_id` | String | ⬜ | 缺省 `chem`；用于离线时选立绘与语气 |
| `answer` | String | ✅ | 非空；涉及反应必须含方程式 |

**兜底行**：表中必须有且只有一行 `keywords` 为空数组，它就是零命中话术（[SPEC-05 §5](SPEC-05-内容数据表.md) 末，`mentor_id: monitor`）。空 `keywords` 永不参与包含匹配，所以它只在零命中时被取用。此约定与 `mentors.json` 的 `dispatch` 兜底类一致（[§5](#5-mentorsjson4-条--fr-d-04)：`other` 的 `keywords` 也为空），零命中话术因而**不必硬编码进代码**（NFR-04）。

匹配规则（**UT-M09 逐条断言**）：
1. 对问题文本做包含匹配，统计命中的 keyword 数量（兜底行 `keywords` 为空，命中数恒为 0）。
2. 取命中数最多者。
3. **平票取表中先出现者**（结果确定可复现，不用随机）。
4. 零命中 → 返回兜底行的 `answer`（即班主任零命中话术）。
5. 「（离线模式）」后缀由调用方追加，不写进 `answer`。

校验规则：条目数 ≥20；无重复 id；`answer` 非空；恰好一行 `keywords` 为空（兜底行），其余行 `keywords` ≥1 项且无空字符串。

---

## 8. worldmap.json（13 条 → FR-D-06）

```json
[
  {
    "id": "grassland",
    "name": "草原",
    "unlocked": true,
    "brief": "出生地。空气中氮气约 78%、氧气约 21%。",
    "teaser": "",
    "map_image": "res://assets/art/map_zones/zone_grassland.png",
    "hotspot": { "x": 180, "y": 210, "w": 64, "h": 48 }
  },
  {
    "id": "deep_mine",
    "name": "深层矿洞",
    "unlocked": false,
    "brief": "",
    "teaser": "氧气趋近于零的深处，有紫色晶体在发光……",
    "hotspot": { "x": 300, "y": 260, "w": 64, "h": 48 }
  }
]
```

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | String | ✅ | 唯一；已解锁的 5 个必须与区域 id 一致 |
| `name` | String | ✅ | 显示名 |
| `unlocked` | bool | ✅ | 5 true / 8 false |
| `brief` | String | 解锁必填 | 点击显示的区域简介 |
| `teaser` | String | 未解锁必填 | 预告语（[SPEC-05 §7](SPEC-05-内容数据表.md)） |
| `map_image` | String | 选填 | 热区场景图路径（`res://assets/art/map_zones/`）；仅已解锁区域使用，缺省或无文件时保持配色占位 |
| `hotspot` | Dictionary | ✅ | 地图页热区矩形（视口 640×360 坐标系） |

校验规则：13 条；`unlocked==true` 恰好 5 条；解锁项 `brief` 非空、未解锁项 `teaser` 非空；热区不越出 640×360。

---

## 9. balance.json（→ FR-D-08）

**所有可调数值集中在此。** [SPEC-02 §4](SPEC-02-游戏设计.md) 参数表中每个值都必须在这里有键。

```json
{
  "stats": {
    "oxygen_max": 100.0,
    "energy_max": 100.0,
    "health_max": 100.0,
    "oxygen_drain": { "grassland": 0.5, "camp": 0.5, "saltlake": 0.0, "mine": 2.0, "academy": 0.0 },
    "oxygen_regen_safe": 1.0,
    "energy_drain": 0.3,
    "health_regen_campfire": 1.0,
    "oxygen_zero_health_drain": 5.0,
    "low_energy_speed_multiplier": 0.5,
    "hud_low_oxygen_threshold": 30.0,
    "tutorial_oxygen_hint_at": 70.0
  },
  "daynight": {
    "day_duration": 120.0,
    "night_duration": 60.0,
    "night_brightness": 0.35,
    "dark_view_radius": 80.0,
    "torch_view_radius": 220.0
  },
  "damage": {
    "co_ghost_per_second": 8.0,
    "acid_mist_per_hit": 10.0,
    "hydrogen_explosion": 50.0,
    "cuso4_pool_per_second": 5.0
  },
  "player": {
    "move_speed": 110.0,
    "jump_velocity": -300.0,
    "gravity": 900.0,
    "interact_radius": 28.0
  },
  "monsters": {
    "co_ghost_speed": 28.0,
    "acid_mist_speed": 90.0,
    "acid_mist_night_count_min": 2,
    "acid_mist_night_count_max": 3
  },
  "items": {
    "oxygen_tank_restore": 50.0,
    "glucose_restore": 20.0,
    "campfire_meal_restore": 40.0
  },
  "inventory": { "hotbar_slots": 8, "stack_limit": 99 },
  "llm": { "timeout_seconds": 8.0, "retry_count": 1, "history_rounds": 4, "max_tokens": 300, "temperature": 0.7, "input_max_chars": 200 },
  "debug": { "force_purity_unlock": false, "fast_daynight": false }
}
```

约束：
- 缺键时代码用内置默认值 + 输出一条警告，**不崩溃**（FR-D-08 AC2）。
- `debug.*` 在导出正式包前必须全为 false（[SPEC-09 §2](SPEC-09-构建与交付.md) 检查项）。

---

## 10. 道具表（items.json）

配方产物中的道具需要独立表（不属于"物质"）。

```json
[
  {
    "id": "sulfur_torch",
    "name": "硫火把",
    "type": "equip",
    "icon": "res://assets/art/icons/sulfur_torch.png",
    "effect": "light",
    "effect_value_key": "daynight.torch_view_radius",
    "consumable": false,
    "tip_id": "warn_night"
  }
]
```

| 字段 | 类型 | 必填 | 约束 |
|---|---|---|---|
| `id` | String | ✅ | 唯一，与配方 `outputs` 对应 |
| `name` | String | ✅ | 中文名 |
| `type` | String | ✅ | 枚举：`equip/consume/material` |
| `icon` | String | ✅ | 路径存在或占位 |
| `effect` | String | ✅ | 枚举：`light/kill_co/kill_acid/immune_co/extinguish/restore_oxygen/restore_energy/test_hardwater/none`（2026-08-02：增 `immune_co` 活性炭口罩；`restore_energy` 随葡萄糖移出 MVP，枚举位保留赛后启用） |
| `effect_value_key` | String | ⬜ | 指向 `balance.json` 的点分键，效果数值从那里读（FR-G-12 AC1） |
| `consumable` | bool | ✅ | 使用后是否 -1 |
| `tip_id` | String | ⬜ | 使用时字幕 |

校验规则：`type`/`effect` 在枚举内；`effect_value_key` 若填写必须能在 `balance.json` 中解析到；被 recipes 引用的 id 必须存在。

---

## 11. UI 短语表（ui_strings.json）

按钮、占位符、角标等**非字幕文案**的唯一出口。不进 `tips.json`（那里只放知识字幕），也不许硬编码在场景与脚本里（NFR-04）。

顶层是**对象**（此表按 key 查询，不需要 diff 友好的数组）：

```json
{
  "prompt_interact": "按 E",
  "collected_counter": "已收集 {n}/16",
  "chat_offline_badge": "（离线模式）"
}
```

| 项 | 约束 |
|---|---|
| key | 全小写蛇形；全表唯一；[SPEC-05 §9](SPEC-05-内容数据表.md) 列出的每个 key 都必须存在 |
| value | 非空字符串 |
| 占位符 | 只允许 `{n}` 形式的具名占位；代码用 `String.format` 填充，**不做表达式求值** |

读取接口：`GameManager.get_ui_string(key: String) -> String`，缺 key 返回 key 本身 + 一条警告（不崩溃、界面上能看出是哪个 key 漏了）。

校验规则：JSON 可解析；SPEC-05 §9 的 key 全部存在；无空 value；占位符只出现 `{n}`。

---

## 12. 校验器规格（FR-D-07）

位置：`scripts/tools/validate_data.gd`，可 headless 运行。

检查项：

| # | 检查 | 失败输出 |
|---|---|---|
| 1 | 每张表 JSON 可解析 | 文件名 + 解析错误行 |
| 2 | id 全表唯一 | 表名 + 重复 id |
| 3 | 必填字段非空 | 表名 + id + 字段名 |
| 4 | 枚举值合法 | 表名 + id + 字段 + 实际值 + 允许值 |
| 5 | 交叉引用存在（tip_id / inputs / outputs / effect_value_key） | 来源表 + id + 目标表 + 缺失 id |
| 6 | 资源路径存在 | 表名 + id + 路径 |
| 7 | 条数约束（substances 17 且计数集合 16 / recipes 12 / mentors 4 / worldmap 13 且 5 解锁 / qa ≥20） | 表名 + 期望 + 实际 |
| 8 | 配方三元组无歧义 | 冲突的两个 recipe id |
| 9 | monitor prompt 含调度关键字；其余三位含"绝不出现 @"；`mention` 四条唯一非空；`monitor.dispatch` 四类齐全有序、`targets` 合法、`line` 含各 target 的 `@mention` | 导师 id + 字段名 |
| 10 | `ui_strings.json` 覆盖 [SPEC-05 §9](SPEC-05-内容数据表.md) 全部 key，占位符仅 `{n}` | 缺失/非法的 key |

行为：全部通过退出码 0 并打印 `DATA OK`；任一失败退出码 1 并逐条列出问题（FR-D-07 AC2）。
校验器自身有单测：喂入构造的坏数据必须报错（FR-D-07 AC3）。
