# SPEC｜《元素炼金物语》技术与数据规格（MVP 版）

> 本文件定义"代码怎么搭、数据怎么存、AI 怎么接、素材怎么来"。
> 面向 5 人团队（含初学者），所有步骤按傻瓜式写。

---

## 1. 技术栈

| 项 | 选择 | 说明 |
|---|---|---|
| 引擎 | Godot 4.6（GDScript） | 已确定，不讨论 |
| 数据 | JSON 数据表（res://data/*.json） | 改内容不改代码（铁律 4） |
| LLM | DeepSeek API（OpenAI 兼容格式），HTTPRequest 调用 | key 存 user://config.cfg，不进 git |
| 版本管理 | git + GitHub/Gitee 私有仓库 | 整点 push（铁律 3） |
| 导出 | Windows Desktop（exe + pck） | 演示机为准 |
| 分辨率 | 视口 640×360，整数倍缩放到 1080p | 像素游戏标准做法 |

---

## 2. 目录结构与责任划分（合并冲突最小化）

```
res://
├── scenes/
│   ├── main/            # P1：主菜单、世界、昼夜、HUD、世界地图页
│   ├── player/          # P1：玩家控制器
│   ├── gameplay/        # P2：采集物、合成台、怪物、道具、爆炸
│   ├── mentor/          # P3：导师学院场景、聊天 UI
│   └── ui/              # P4 美术资源 + P3/P2 逻辑：卡片、图鉴、背包界面
├── scripts/
│   ├── autoload/        # P1 建骨架：GameManager / KnowledgeTip / RecipeDB / LLMClient
│   ├── gameplay/        # P2
│   └── mentor/          # P3
├── data/                # P3 负责填：substances / recipes / tips / mentors / qa_fallback.json
├── assets/
│   ├── art/             # P4（含 generated/ 与 freepack/ 两个子目录）
│   └── audio/           # P5 找免费音效
└── maps/                # P5：TileMap 场景与 tileset
```

规则：**只改自己目录**；autoload 接口在 H1 由 P1 定义后冻结，别人只调用不修改。

## 3. Autoload 清单（P1 在 H1 搭好骨架）

| Autoload | 职责 | 关键接口 |
|---|---|---|
| `GameManager` | 三值、昼夜时钟、死亡/复活、区域判定 | `stats.oxygen` / `is_night()` / `current_zone()` |
| `KnowledgeTip` | 字幕引擎 | `KnowledgeTip.show("tip_id")` |
| `RecipeDB` | 读 recipes.json，配方匹配 | `RecipeDB.try_craft(items, tool) -> Dictionary` |
| `LLMClient` | DeepSeek 调用 + 超时 + 兜底切换 | `LLMClient.ask(mentor_id, question) -> String` |
| `WorldMap` | 世界地图页：13 区域热区、已解锁/未解锁状态 | `WorldMap.open()` / `WorldMap.is_unlocked(zone_id)` |

## 4. 数据表 Schema（P3 填内容，程序只认字段名）

### 4.1 substances.json（16 种物质）
```json
{
  "id": "o2",
  "name": "氧气",
  "formula": "O₂",
  "category": "单质",
  "tip_id": "tip_o2",
  "zone": ["grassland"],
  "icon": "res://assets/art/icons/o2.png"
}
```

### 4.2 recipes.json（10 条反应）
```json
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
  "unlock_tip": "tip_mass_conservation"
}
```
特殊字段：`"requires_pure_check": true`（氢气点燃专用，触发验纯流程）；失败统一返回 `fail_tip_id`。

### 4.3 tips.json（约 30 条字幕）
```json
{ "id": "tip_o2", "style": "bubble", "duration": 3,
  "text": "氧气 O₂——空气中的氧气约占 21%，动植物呼吸都需要它" }
```
`style` 三选一：`bubble`（头顶气泡 3 秒）/ `banner`（底部横幅 4 秒）/ `warning`（红色警示 5 秒）。

### 4.4 mentors.json（4 位导师人设，即代码中的 AGENTS 常量）
```json
{ "id": "chem", "name": "袁仲衡", "title": "化学老师", "room": "化学实验室",
  "avatar_idle": "res://assets/art/mentors/chem_idle.png",
  "avatar_talk": "res://assets/art/mentors/chem_talk.png",
  "route_class": "chemistry",
  "system_prompt": "见内容数据表 spec 第 4 节" }
```
四个 id 固定为：`chem`（袁仲衡/化学老师）、`monitor`（苏婉清/班主任/调度中心）、`assistant`（周启明/助理）、`think`（曲嫣然/思维老师）。`route_class` 仅供查阅，实际调度由班主任完成（见第 6 节）。人设与 prompt 改动只改 mentors.json，不碰代码。

### 4.5 qa_fallback.json（离线兜底问答，≥20 条）
```json
{ "keywords": ["氢气","爆炸","验纯"],
  "answer": "氢气中混有空气（氧气）时，点燃会在极短时间内剧烈燃烧，体积骤胀引发爆炸。所以点燃前必须验纯：用排水法收集一小试管氢气，移近火焰，只发出轻微'噗'声才是纯净氢气。方程式：2H₂+O₂=点燃=2H₂O。" }
```
匹配规则：问题命中 keywords 最多者胜出；零命中 → 助教固定话术「这个问题超出我的离线知识库啦，联网后再问我一次吧」。

## 5. LLM 接入规格

- **Endpoint**：`https://api.deepseek.com/chat/completions`（OpenAI 兼容），model 用 `deepseek-chat`。
- **请求**：system = mentors.json 中的 system_prompt + 通用后缀（见下）；user = 玩家问题；max_tokens ≈ 300；temperature 0.7。
- **通用 system 后缀**（拼在每个人设后面）：
  > 你是初中化学游戏《元素炼金物语》中的导师。规则：1）只用初中化学范围回答，超纲就说"这是高中内容，先记住现象"；2）回答不超过 120 字，口语化，像老师对初一学生说话；3）涉及反应必须在末尾给标准化学方程式；4）绝不透露自己是 AI 语言模型；5）不知道就建议查图鉴或问化学老师。
- **超时与兜底**：8 秒超时 + 1 次重试 → 仍失败自动切离线模式（qa_fallback.json），回答末尾加「（离线模式）」。聊天 UI 上有全局开关可手动切离线（演示保险）。
- **key 管理**：`user://config.cfg`（用户目录，不进 git）；准备主备两个 key。
- **成本控制**：每局对话历史只带最近 4 轮；演示日预计 token 消耗 < 1 元，不心疼。
- **唯一入口 `_generate_reply()`**：接真实 API 的唯一入口。模拟版＝班主任内部关键词路由 + 本地兜底（不联网也能跑）；真实版＝HTTP 请求（正式接 DeepSeek endpoint，联调期可用本地 `http://127.0.0.1:5000/chat` 替代）。班主任的回复文本里带 @xx 才走调度，其他老师不带 @ 即终止。

## 6. 路由逻辑（班主任统一调度，P3 实现）

**协作链：班主任统筹 → 调度分配 → 化学老师教学 / 助理规划 / 思维老师开脑洞。**

1. `handle_message()` 入口：学生不能 @ 任何老师，**任何输入统一先给班主任（monitor）**，最多 2 轮（班主任 + 被调度者），班主任调度最多 1 次——不会死循环。
2. 班主任判断（模拟版用关键词分类器，真实版由班主任的 system prompt 自行判断并输出 @）：
   - `_is_combat`（怪、敌人、危险、攻击、掉血…）→ @思维老师
   - `_is_learning`（怎么学、记不住、考试…）→ @思维老师 + @助理
   - `_is_chemistry`（水、氢气、方程式、合成…）→ @化学老师
   - 兜底 → @助理
3. 只有班主任的回复允许带 @；解析回复文本中的 @xx → 触发对应导师回答 → 该回复**禁止再解析 @**（答完即终止）。
4. 离线模式：同一套逻辑跑本地——班主任关键词分类 + qa_fallback.json 出答案。

## 7. 美术管线（P4 主责，Image-2 网页手动生成）

### 7.1 规格（全项目统一，不满足一律返工）
- 道具/图标：**16×16**；角色/怪物/导师头像：**32×32**；场景大物件 32 的倍数。
- 调色板：一套 32 色（P4 在 H1 定好，存 `palette.png`，所有人导出前压一遍）。
- 命名：`类别_名称_状态.png`，全小写蛇形，如 `char_player_idle.png`、`item_sulfur.png`、`mob_co_ghost_move.png`；导入路径对应第 2 节目录。

### 7.2 Image-2 网页操作流程（傻瓜式）
1. 打开 Image-2 网页，粘贴提示词模板（见 7.3），风格关键词每次必带：`pixel art, 2D game sprite, 32x32, transparent background, limited palette`。
2. 生成 → 挑最好的一张下载 PNG。
3. 用 Piskel / Aseprite（免费）打开：缩放到目标像素尺寸 → 压到项目调色板 → 必要时手动修几像素。
4. 按命名规范存进 `assets/art/generated/`，git 提交。
5. **生成额度分配**：第一批 11 张关键图，按优先级排队生成——
   ① 主角 idle/走路 ×2；② 标题图 ×1；③ **导师半身立绘 ×8**（4 位导师 × idle/talk 两帧，提示词直接用内容数据表 spec 第 4 节各人"立绘提示词"，同一角色两张要保证同人同服装，只改表情/嘴部）。
   **导师房间像素小人**不进生成队列：用免费素材包的像素小人改色 + 发型区分四位即可（额度富余时才补生成）。
   地形/图标/UI 全部用免费素材包。

### 7.3 提示词模板（直接复制改括号）
- 主角：`A cute little alchemist kid with a pointed hat and robe, holding a small flask, pixel art, 2D game sprite, 32x32, transparent background, limited palette, side view`
- 导师半身立绘：直接用内容数据表 spec 第 4 节四位导师的"立绘提示词"（已是中文完整版）。同一导师生成 idle/talk 两张时，在提示词末尾分别追加 `平静表情，嘴闭着` / `说话表情，嘴微张，更有神采`，其余描述一字不改以保证同人同服
- 怪物：`a ghost made of gray toxic smoke, pixel art, 2D game sprite, 32x32, transparent background`

### 7.4 免费素材包（itch.io 筛选关键词）
`pixel fantasy tileset`、`16x16 dungeon tileset`、`pixel UI pack`、`pixel alchemy icons`。下载后存 `assets/art/freepack/`，在 PPT 末页列出来源（比赛版权分）。

## 8. 音频（P5，H14 前完成）

freesound.org / itch.io 免费音效：拾取"叮"、合成成功、爆炸、怪物叫声、篝火环境声、夜晚环境声、UI 点击。BGM 一段循环 chiptune（关键词 `free chiptune loop`）。全部注明来源。

## 9. Git 规范

- 分支：`main`（始终可运行）+ 每人一个 `dev-p1`…`dev-p5`。
- 流程：自己分支干活 → 整点提 PR 合 main → P1 过一遍就合，不搞正式 review。
- commit 信息格式：`[模块] 做了什么`，如 `[mentor] 接入DeepSeek并调通化学老师人设`。

## 10. 构建与导出

- H2 起 P1 配好 Windows 导出预设（embed pck，单 exe + 数据文件）。
- 演示包内容：`元素炼金物语.exe` + `README.txt`（操作说明：WASD 移动、E 交互、Tab 背包、Esc 菜单）。
- H18 在**干净电脑**（没装 Godot）上最终验证一次。
