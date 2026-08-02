# SPEC-10｜网页版移植方案

> 本文件管"把《元素炼金物语》做成浏览器里点开即玩的网页版"：技术路线、系统映射、架构、LLM 浏览器方案、数据复用、部署与阶段计划。
> 本文件**不新增玩法 FR**——网页版的功能边界以 [SPEC-01](SPEC-01-需求与验收.md) 为准，数值以 [SPEC-02 §4](SPEC-02-游戏设计.md) 与 `data/balance.json` 为准，接口语义以 [SPEC-03](SPEC-03-系统与接口契约.md) 为准。本册只回答"同一套规格怎么在浏览器里落地"。

- 版本：v1.0
- 日期：2026-08-02
- 状态：**草案待评审**
- 前置阅读：[SPEC.md](SPEC.md) → [SPEC-01](SPEC-01-需求与验收.md) → [SPEC-03](SPEC-03-系统与接口契约.md)

---

## 1. 目标与范围

### 1.1 目标

1. **点开链接即玩**：评委/玩家在浏览器打开一个 URL，无需下载、无需安装任何运行时，直接开始游戏（对标 FR-B-03「双击即可运行」在浏览器语境下的等价物）。
2. **同一套内容**：10 个 JSON 数据文件、SPEC-05 全部文案、SPEC-08 美术音频资产**零改动或最小改动复用**（§6）。
3. **断网可玩性等价**：首次加载完成后拔网线，导师问答走离线兜底（`qa_fallback`），全流程可玩——对齐 FR-B-02 的验收口径（§7.4）。
4. **不影响 Godot 主线**：网页版是独立目录（`web/`）的平行工程，Godot 版继续按 SPEC-09 交付 Windows exe。两份实现共用 `data/` 内容源（单一事实来源）。

### 1.2 做（纳入网页版）

[SPEC-01 §2.1](SPEC-01-需求与验收.md) 的 MVP 全量：三值系统 · 昼夜循环 · 采集与背包（17 种物质，HUD 计 16）· 盐湖安全收集区 · 世界地图页（13 区域，8 个灰色剪影）· 合成台 + 12 条配方 + 知识卡片 · **氢气不验纯爆炸事件** · 怪物 ×2（CO 幽灵、酸雾怪）· 导师学院（4 位具名 AI 导师 + 班主任统一调度 + LLM 与本地兜底）· 图鉴简版 · 死亡复活与掉落可捡回 · 字幕引擎（51 条）· 原住民交易 · 主菜单三个门。

### 1.3 不做（沿用赛后清单 + 网页版新增不做项）

- [SPEC-01 §2.2](SPEC-01-需求与验收.md) 赛后清单全部条目**照旧不做**（自由建造、存档读档、未解锁区域内部场景、联机、手柄等）。
- 网页版**额外不做**：移动端触控适配（虚拟摇杆/触屏交互，列为 P2 观察项，见 §9-2）；多人/分享战绩等任何网络玩法；账号系统。

### 1.4 网页版范围新增项（范围变更记录，依 SPEC-01 §2.3 登记）

| 项 | 说明 | 裁决 |
|---|---|---|
| 轻量本地存档（localStorage） | Godot MVP 的「存档读档」在不做清单（SPEC-01 §2.2）；网页版为防浏览器刷新丢失进度，仅持久化三值/背包/发现集合/解锁标记/天数，不做多存档位 | 本册 §4.5，待评审确认 |
| LLM key 的两层浏览器方案 | FR-M-07 AC3 的 `user://config.cfg` 在浏览器无对应物，替换为 §5 方案 | 本册 §5，待评审确认 |

---

## 2. 技术路线决策

### 2.1 路线 A：Godot 4 HTML5（WebAssembly）导出

| 维度 | 评估 |
|---|---|
| 代码重写量 | 基本为零：`export_presets.cfg` 加一个 Web 预设即可导出 |
| 导出体积 | Godot 4 Web 导出运行时 wasm 约 30~40MB（gzip 后仍 >10MB），首次加载慢，与 NFR-02「首启 ≤5 秒」的精神冲突 |
| 移动端兼容性 | Godot 4 Web 导出在移动端浏览器（尤其 iOS Safari）兼容性差，官方亦标注为限制项 |
| 网络请求 | GDScript `HTTPRequest` 在浏览器内受 CORS 与混合内容约束；调 DeepSeek 端点需目标站放行跨域 |
| key 安全 | API key 打包进前端 wasm/pck，任何人可从浏览器开发者工具中提取——**直接违反 NFR-05 的精神**（key 不进公开产物） |
| 调试与迭代 | 浏览器内 GDScript 调试链弱，问题定位成本高 |

### 2.2 路线 B：Web 原生重写（TypeScript + Phaser 3，Vite 构建）

| 维度 | 评估 |
|---|---|
| 定位 | 真正的网页程序：HTML/JS/WASM 静态产物，浏览器原生运行 |
| 包体 | Phaser 3 运行时 gzip 后约 1MB 量级；加美术音频后整包目标 ≤ 20MB，首屏快 |
| 部署 | `dist/` 是纯静态文件，可直接挂 GitHub Pages / itch.io / 任意静态服务器（§7） |
| 逻辑移植 | 按 [SPEC-03](SPEC-03-系统与接口契约.md) 接口契约逐方法重写为 TypeScript；**纯逻辑类**（MentorRouter / QaFallback / RecipeDB 匹配 / Inventory / Discovery / HydrogenEvent / ItemEffects / PromptSuffix）本就是「不依赖场景、可独立实例化」的设计（SPEC-06 §3），移植是直译而非重设计 |
| 渲染 | Phaser 3（Arcade Physics + 相机 + Tilemap 足够覆盖横版像素场景）；PixiJS 为备选（更轻的渲染层，但物理与场景管理需自建，评审默认 Phaser 3） |
| 测试 | GUT → Vitest（纯逻辑/数据校验）+ Playwright（E2E 全流程），见 §7.4 |
| 代价 | 场景层（交互、动画、UI 面板）需要按 §3 映射表重写；估工作量见 §8 |

### 2.3 推荐结论

**以路线 B（Web 原生重写：TypeScript + Phaser 3 + Vite）为主线；路线 A（Godot Web 导出）仅作为"快速验证备选"保留——若比赛现场只需一个能跑起来的网页演示且时间不足 4 小时，可用路线 A 应急出包，但不作为正式网页版交付。**

理由：

1. **用户目标就是"网页版程序"**——路线 A 产物是"能在浏览器里跑的 Godot 包"，体积大、移动端差、key 必泄露，三个硬伤都踩在 MVP 已确立的非功能需求（NFR-02/NFR-05）上。
2. **移植成本被架构压到最低**：SPEC-06 §3 的可测性约束（纯逻辑与场景分离、时间可注入、网络可替换、数据可注入）使全部核心逻辑天然是"可搬走的纯类"；24 个单元测试文件的行为断言可近乎逐条翻译为 Vitest。
3. **内容与资产零成本复用**：10 个 JSON、全部文案、PNG/调色板/音频都是引擎中立的（§6），重写的只是"引擎胶水层"。

---

## 3. 系统映射表（Godot → Web）

### 3.1 引擎机制映射

| Godot 4 概念 | 网页版对应 | 改造要点 |
|---|---|---|
| Autoload 单例 ×5（FR-C-09） | TS 模块单例（`src/core/*.ts` 导出唯一实例） | 保持同名：`GameManager` / `KnowledgeTip` / `RecipeDB` / `LLMClient` / `WorldMap` |
| `signal` / `emit_signal` | 类型化事件总线（`src/core/event_bus.ts`，tiny emitter） | 信号名原样保留（`oxygen_changed` 等，SPEC-03 §2.3）；参数形状不变 |
| 场景树（`.tscn`） | Phaser Scene（`BootScene/MenuScene/WorldScene/UIScene`） | SPEC-03 §8 的 UILayer 各面板映射为 UIScene 内的容器，互斥裁决保留 `ui_manager` 等价物 |
| `_process(delta)` | Scene `update(time, delta)` | `GameManager.tick(delta)` 仍是**唯一时间推进入口**（SPEC-03 §2.2），delta 可注入的测试口径不变 |
| `Area2D` 区域触发 | Arcade Physics `overlap` | ZoneTrigger ×5 + `set_zone` 去重语义不变（FR-C-03） |
| `CharacterBody2D` 玩家 | Arcade Sprite + 自写平台移动 | 移动参数读 `balance.json`：`player.move_speed/jump_velocity/gravity`（SPEC-04 §9） |
| `CanvasModulate` 昼夜 tint | 全屏半透明矩形 overlay | `daynight.night_brightness` 0.35 不变（SPEC-02 §4.2） |
| `PointLight2D` 视野 | 径向渐变遮罩（RenderTexture/mask） | `dark_view_radius` 80 / `torch_view_radius` 220 不变 |
| `HTTPRequest` | `fetch` + `AbortController` | 超时/重试语义对齐 FR-M-08（§5.3） |
| `user://config.cfg` | `localStorage` | 仅存 API key 与手动离线开关；不回显、不进日志（NFR-05 沿用） |
| `res://` 资源路径 | `/assets/` URL 路径 | 数据表中的 `res://` 前缀由 DataLoader 统一替换（§6.2） |
| GUT（`tests/unit|integration|data/`） | Vitest（`web/tests/unit|data/`）+ Playwright（`web/tests/e2e/`） | UT/IT 编号沿用（§7.4） |
| `validate_data.gd` | `scripts/validate_data.ts`（Node 运行） | 10 类检查逐条移植（SPEC-04 §12），输出 `DATA OK` 不变 |

### 3.2 FR 模块映射（FR → 网页版模块）

| FR 模块 | Godot 实现位置 | 网页版模块 | 移植方式 |
|---|---|---|---|
| FR-C-02..06 三值/区域/昼夜/睡觉/死亡 | `scripts/autoload/game_manager.gd` | `core/game_manager.ts` | **直译**：方法签名语义对齐 SPEC-03 §2.2，UT-C02/C03/C04 → Vitest 同名用例 |
| FR-C-07 HUD / FR-C-08 主菜单 | `scenes/main/` | `scenes/ui/hud.ts`、`scenes/menu.ts` | 重写：三条数值条保持信号驱动、无轮询（FR-C-07 AC1） |
| FR-P-01..03 玩家/交互/相机 | `scenes/player/` | `scenes/world/player.ts` | 重写：IInteractable 三方法约定（SPEC-03 §5）改为 TS `interface Interactable` |
| FR-G-02/G-03 背包/发现 | `scripts/gameplay/inventory.gd`、`discovery.gd` | `gameplay/inventory.ts`、`discovery.ts` | **直译**：8 格/堆叠 99/计数集合 16 口径不变 |
| FR-G-04..07 配方/失败反馈 | `recipe_db.gd` | `core/recipe_db.ts` | **直译**：`try_craft` 返回结构字段名一字不改（SPEC-03 §4）；确定性轮转不许用 `Math.random()` |
| FR-G-08/G-09 爆炸/验纯 | `scripts/gameplay/hydrogen_event.gd` | `gameplay/hydrogen_event.ts` | **直译**：精确 -50（`damage.hydrogen_explosion`）、置标记、生命 <50 死亡路径 |
| FR-G-10/G-11/G-16 怪物与溶液池 | `scenes/gameplay/monster_*` | `scenes/world/monsters/` | 重写：8/s、单次 -10、2~3 只夜刷、5/s 浸泡等数值全部读 balance |
| FR-G-12..15 道具/设施/提纯/交易 | `item_effects.gd`、`facility_*` | `gameplay/item_effects.ts`、`scenes/world/facilities/` | 效果按 `effect_value_key` 动态读 balance 的机制保留 |
| FR-M-03..06 输入清理/调度/人设 | `scripts/mentor/mentor_router.gd`、`prompt_suffix.gd` | `mentor/mentor_router.ts`、`prompt_suffix.ts` | **直译**：四契约方法签名对齐 SPEC-03 §6.1；截断 200 字符不变 |
| FR-M-07..10 LLM/兜底/配置面板 | `llm_client.gd`、`qa_fallback.gd`、`config_panel.*` | `core/llm_client.ts`、`mentor/qa_fallback.ts`、设置页 | 直译 + 网络层替换（§5）；8s 超时 + 1 重试 + 四种失败收口不变 |
| FR-U-01 字幕引擎 | `knowledge_tip.gd`、`tip_layer.*` | `core/knowledge_tip.ts` + UIScene 渲染层 | **直译**：串行队列 + warning 抢占 + once 去重语义不变 |
| FR-U-03/U-04 地图页/图鉴 | `world_map_panel.*`、`codex_*` | UIScene 面板 | 重写：13 热区按 `worldmap.json` 构建、17 格剪影零泄露 |
| FR-D-01..08 数据 | `data/*.json` + `validate_data.gd` | `web/public/data/*.json` + `validate_data.ts` | **零改动复用**（§6） |
| FR-B-01..04 构建交付 | SPEC-09 | 本册 §7 | 重新定义为 Web 构建与部署 |

---

## 4. 架构设计

### 4.1 目录结构

```
web/
├── index.html                 # 640×360 逻辑视口，整数倍缩放（对齐 FR-C-01 AC1）
├── vite.config.ts
├── package.json
├── public/
│   ├── data/                  # 10 个 JSON 从仓库 data/ 构建期拷贝（§6.1）
│   └── assets/                # 美术/音频（§4.6）
├── src/
│   ├── main.ts                # Phaser Game 启动、Scene 注册
│   ├── core/                  # 五个"autoload"等价单例（SPEC-03 §1 依赖铁律沿用）
│   │   ├── event_bus.ts       # 类型化信号总线
│   │   ├── game_manager.ts    # 三值/昼夜/区域/死亡复活/全局标记/get_balance/get_ui_string
│   │   ├── knowledge_tip.ts   # 字幕引擎
│   │   ├── recipe_db.ts       # 配方匹配 + 失败文案池
│   │   ├── llm_client.ts      # LLM 调用/超时/离线兜底（§5）
│   │   └── world_map.ts       # 13 区域状态
│   ├── gameplay/              # 纯逻辑类（不 import Phaser，可 Vitest 直接 new）
│   │   ├── inventory.ts  discovery.ts  item_effects.ts
│   │   └── hydrogen_event.ts  salt_purifier.ts
│   ├── mentor/
│   │   ├── mentor_router.ts  qa_fallback.ts  prompt_suffix.ts
│   ├── scenes/
│   │   ├── boot.ts  menu.ts  world.ts  ui.ts
│   │   └── world/             # player/monsters/facilities/collectables/zones
│   ├── save/
│   │   └── save_store.ts      # localStorage 存档（§4.5）
│   └── data/
│       └── data_loader.ts     # 唯一数据表读取口（对齐 SPEC-03 §1「场景不自读表」）
├── scripts/
│   ├── validate_data.ts       # 校验器移植（§6.3）
│   └── copy_data.ts           # 构建期 data/ → public/data/ 同步
└── tests/
    ├── unit/                  # Vitest：UT-* 等价
    ├── data/                  # Vitest：UT-D01..D08 等价
    └── e2e/                   # Playwright：全流程回归（§7.4）
```

**依赖方向铁律沿用**（SPEC-03 §1）：`core/` 不 import `scenes/`；场景间不横向直连，跨模块通信一律走 `event_bus`；数据表只经 `data_loader` 读取。

### 4.2 渲染与输入

- 渲染：Phaser 3 WebGL（失败自动回退 Canvas）；`pixelArt: true` + `roundPixels`，禁止抗锯齿与非整数缩放——等价于 Godot 导入设置 `Filter=Off`（SPEC-08 §1）。
- 视口：逻辑分辨率 640×360，整数倍放大居中（`Scale.FIT` + 整数缩放系数自算）。
- 输入映射：沿用 [SPEC-02 §8](SPEC-02-游戏设计.md)：A/D/←/→ 移动、空格跳跃、E 交互、Tab 背包、M 地图页、C 图鉴、Esc 暂停、1–8 快捷栏。
- 音频：浏览器 Autoplay 策略要求首次用户交互后才能出声——`boot.ts` 挂一次性 pointerdown/keydown 监听解锁 AudioContext；音频缺失静默处理（SPEC-08 §5 口径）。

### 4.3 存档方案（localStorage，对应 §1.4 登记项）

| 键 | 内容 | 对应 Godot 状态 |
|---|---|---|
| `ea_save_v1.stats` | 三值 + `day_count` + `time_of_day` | `GameManager` 状态（SPEC-03 §2.1） |
| `ea_save_v1.inventory` | 背包格子快照 | `inventory` |
| `ea_save_v1.discovery` | 已发现物质集合 | `discovery` |
| `ea_save_v1.flags` | `explosion_happened` / `purity_check_unlocked` | 全局标记 |
| `ea_save_v1.unlocked_recipes` | 已解锁配方 id 列表 | `RecipeDB.unlocked_recipes()` |
| `ea_config` | API key + 手动离线开关 | `user://config.cfg`（与进度存档分键存放，对齐「key 只写不读回显」） |

约束：存档版本号内嵌（`v1`），结构变更时旧档作废重开不迁移；localStorage 不可用（隐私模式/iframe 限制）时降级为内存存档 + 一次性提示，不崩溃（NFR-06 精神）。**死亡掉落包不持久化**——刷新页面视为新开局，与 MVP「死亡是唯一关卡」的设计不冲突。

### 4.4 素材复用

- PNG 原样拷贝：`assets/art/` 目录结构、命名规则、调色板（32 色）与占位图机制（SPEC-08 §2/§3）原样适用；数据表中的 `res://assets/...` 由 `data_loader` 统一改写为 `assets/...` 相对 URL。
- 像素规格不变：图标 16×16、角色 32×32、立绘 240×320、特效 64×64（SPEC-08 §1）。
- 音频 `.ogg` 直接用；BGM 三首（白天/夜晚/学院）与关键音效清单不变（SPEC-08 §5）。
- 授权登记 `assets/CREDITS.md` 随网页包一起发布，CC-BY 署名要求不变（SPEC-08 §4.3）。

---

## 5. 导师 LLM 在浏览器中的方案

### 5.1 问题

FR-M-07 AC3 规定 key 只从 `user://config.cfg` 读取；浏览器里没有 `user://`。而**任何打进前端产物的 key 都等于公开**——直接违反 NFR-05。同时 `fetch` 调第三方 API 受 CORS 与混合内容（HTTPS 页面调 HTTP 端点被拦）约束。

### 5.2 两层方案

**第一层（默认，无后端）——用户自备 key：**

1. 设置页提供 key 输入框（`type="password"`，不回显——对齐 SPEC-03 §6.4 配置面板约束）。
2. key 存 `localStorage` 的 `ea_config`，**仅本人浏览器可见**，不进 git、不进任何网络请求体之外的地方、不进日志。
3. 请求直连 OpenAI 兼容端点（默认 `https://api.deepseek.com/chat/completions`，模型 `deepseek-chat`，与 SPEC-03 §6.2 网络常量一致）。
4. 未填 key → 自动离线模式，体验完整（FR-M-07 AC3 语义不变）。
5. **W0 必须实测**：目标端点是否返回允许跨域的 CORS 响应头；若不放行浏览器跨域，第一层退化为「必须走第二层代理」，设置页仅接受自建代理 URL。

**第二层（可选，轻量代理）——Cloudflare Workers 转发：**

1. 一个约 50 行的 Worker：接收前端请求 → 从**服务端环境变量**取 key → 转发 OpenAI 兼容请求 → 回传。
2. Worker 配置 Origin 白名单（仅放行部署域名）+ 简单限流，防止被当免费代理刷量。
3. 前端 key 输入框改填（或默认内置）**代理 URL 而非真实 key**；真实 key 永不出服务端环境变量。
4. 代理成本：Cloudflare Workers 免费额度对演示量级足够；不引入账号/数据库。

**离线兜底（两条路径共用）**：`qa_fallback.json`（34 条，FR-D-05）原样复用；命中最多者胜、平票取先、零命中取兜底行、`（离线模式）`角标由调用方追加——UT-M09 语义逐条保留。

### 5.3 与 FR-M-07..10 的对齐口径

| 行为 | Godot 版 | 网页版 |
|---|---|---|
| 请求体 | system（人设+通用后缀）+ user + 历史最近 4 轮；`max_tokens`/`temperature` 读 `balance.json` 的 `llm.*`（默认 300 / 0.7） | **完全一致**，`build_request_body` 语义保留 |
| 超时 | 8 秒（`llm.timeout_seconds`） | `AbortController`，同一键读 balance |
| 重试 | 1 次（`llm.retry_count`） | 同上 |
| 失败收口 | 超时/网络错/非 200/畸形 body → 空串 → 离线兜底，不抛异常（FR-M-08 AC2） | 同上，新增「CORS 拦截」归入网络错一类 |
| 手动离线开关 | FR-M-08 AC4，立即生效 | 设置页开关，写 `ea_config` |
| 输入清理 | `sanitize_input`：截断 200 字符 + 清理控制字符（FR-M-03） | 逐字直译 |
| HTTPS | —（exe 无此问题） | 部署强制 HTTPS（GitHub Pages/itch.io 默认即是）；API 端点同为 HTTPS，无混合内容问题 |

---

## 6. 数据与内容复用

### 6.1 复用清单（10 个 JSON，单一事实来源）

| 文件 | 内容 | 复用方式 |
|---|---|---|
| `substances.json` | 17 物质（HUD 计 16） | 原样 |
| `recipes.json` | 12 配方 + 卡片文案 | 原样 |
| `fail_messages.json` | 9 条失败文案池（`no_match` 5 + `wrong_condition` 4） | 原样 |
| `tips.json` | 51 条字幕 | 原样 |
| `mentors.json` | 4 导师 + `monitor.dispatch` 调度表 | 原样 |
| `qa_fallback.json` | 34 条离线问答 + 兜底行 | 原样 |
| `worldmap.json` | 13 区域（5 解锁 / 8 剪影） | 原样 |
| `balance.json` | 全部可调数值 | 原样（`debug.*` 必须为 false 才可发布） |
| `items.json` | 8 道具 | 原样 |
| `ui_strings.json` | UI 短语表 | 原样 |

**规则**：网页工程**不另存一份数据**。`scripts/copy_data.ts` 在构建/开发启动时把仓库根 `data/*.json` 拷贝进 `web/public/data/`，diff 即警报；改内容永远改仓库根的 `data/`，Godot 版与网页版同时生效。SPEC-05 全部文案因此零改动复用。

### 6.2 路径适配（唯一允许的"最小改动"，且不动数据文件本身）

数据表内资源路径为 `res://` 前缀（SPEC-04 §1）。`data_loader.ts` 在加载后统一做字符串替换 `res://assets/` → `assets/`，数据文件本身一个字节不改。

### 6.3 构建期校验（CI 卡点）

`scripts/validate_data.ts` 逐条移植 [SPEC-04 §12](SPEC-04-数据模型.md) 的 10 类检查（JSON 可解析 / id 唯一 / 必填非空 / 枚举合法 / 交叉引用 / 资源路径存在（按 §4.4 的 URL 映射后检查）/ 条数约束 / 配方三元组无歧义 / 导师 prompt 约束 / `ui_strings` key 覆盖）。全过打印 `DATA OK`、退出码 0；任一失败退出码 1。接入 CI：**数据不过，构建不出包**（对齐 FR-D-07 AC2）。

---

## 7. 构建与部署

### 7.1 构建

| 项 | 值 |
|---|---|
| 构建工具 | Vite（`vite build` → `dist/` 纯静态产物） |
| 语言 | TypeScript strict |
| 包体目标 | gzip 后整包 ≤ 20MB（Phaser 运行时 ~1MB + 美术音频） |
| 发布前检查 | `validate_data.ts` 输出 `DATA OK`；`balance.json` 的 `debug.*` 全 false；`git grep -i -E "sk-[a-zA-Z0-9]{16,}"` 无结果（沿用 SPEC-09 §2 口径）；无 console 调试污染 |

### 7.2 部署目标

| 目标 | 形态 | 说明 |
|---|---|---|
| GitHub Pages | 仓库 `gh-pages` 分支推送 `dist/` | 默认 HTTPS；给评委的固定链接 |
| itch.io | `dist/` 打 zip 上传，入口 `index.html` | 比赛常用分发渠道；注意 iframe 内 localStorage 可用性检测（§4.3） |
| 任意静态服务器 | `dist/` 整目录 | 校内服务器/对象存储均可，无服务端依赖（除可选 LLM 代理） |

### 7.3 断网可玩性（PWA 决策）

- **验收基线**：首次完整加载后拔网线，游戏全流程可玩、导师走离线兜底——对齐 FR-B-02 语义。仅靠浏览器 HTTP 缓存通常可满足单次会话内断网。
- **PWA（Service Worker 离线缓存）列为可选增强（P2）**：让"关掉浏览器再打开、无网也能进游戏"成立。W4 时间富余则做，不做不阻塞验收；评审默认**不纳入**首版。

### 7.4 验收口径与测试栈

- FR/AC 仍以 [SPEC-01](SPEC-01-需求与验收.md) 为唯一来源；网页版不新增 FR，测试编号沿用 UT-*/IT-*/MT-*。
- **Vitest**：UT-C02/C03/C04、UT-G02/G03/G04/G07/G12、UT-M03..M09、UT-U01、UT-D01..D08 的等价用例。可测性六约束（SPEC-06 §3）原样成立：纯逻辑可 `new`、delta 可注入、`set_transport` 等价注入点（`llm_client` 暴露传输层替换口）、失败文案确定性轮转、`load_from` 数据注入、balance 可覆写。
- **Playwright（E2E）**：覆盖 IT 类行为与 [SPEC-06 §8](SPEC-06-测试计划.md) 全流程回归脚本的 16 步（启动 → 采集 → 地图页 → 合成 → 爆炸 → 导师问答 → 验纯 → 夜晚怪物 → 死亡复活 → 睡觉 → 图鉴）。爆炸「生命精确 -50」、聊天「首条必 `monitor`、≤3 条、答完终止」等关键断言自动化。
- **手工项**：MT 类照旧人工（引导体验、面板观感、断网拔网线重跑）。

---

## 8. 实施阶段计划（Phase W0–W4）

> 风格对齐 [SPEC-07](SPEC-07-实施计划与Agent派活.md) 的 Phase 划分；每个 Phase 有明确出口标准，不达标不进下一阶段。工作量按 1~2 人 + 子 Agent 并行估算。

### Phase W0 — 脚手架与数据复用（约 0.5 天）

| 内容 | 出口标准 |
|---|---|
| Vite + TS + Phaser 3 工程骨架；`copy_data.ts` + `validate_data.ts` 移植；Vitest 骨架跑通空测试；**实测 DeepSeek 端点 CORS**（§5.2-5）；CI 接数据校验卡点 | `DATA OK` 退出码 0；CORS 结论写入 WORKLOG；CI 绿 |

### Phase W1 — 底座（约 1 天）

| 内容 | 出口标准 |
|---|---|
| `event_bus` + `GameManager` 全量（三值/区域/昼夜/睡觉/死亡/标记，`tick(delta)` 唯一时间入口）；玩家控制器 + 交互接口 + 相机与视野遮罩；白盒地图（四区 + 学院）；HUD 三条数值条（信号驱动） | UT-C02/C03/C04 等价 Vitest 全绿；白盒地图上可跑动、氧气分区净速率（矿洞 −2.0/s、草原/营地 +0.5/s、盐湖/学院 0）肉眼可验 |

### Phase W2 — 核心闭环（约 1.5 天）

| 内容 | 出口标准 |
|---|---|
| 采集/背包/发现统计；配方引擎 + 合成 UI + 知识卡片 + 失败文案轮转；**氢气爆炸与验纯解锁**；导师学院四房间 + 聊天框（世界不暂停、逐字打字）+ 班主任调度链 + LLM 两层方案 + 离线兜底 | UT-G04/G07、UT-M03..M09 等价全绿；Playwright 跑通「未验纯点燃 → -50 → 问导师 → 验纯 → 点燃成功」链条；断网问答带「（离线模式）」 |

### Phase W3 — 怪物/死亡/图鉴/地图页（约 1 天）

| 内容 | 出口标准 |
|---|---|
| CO 幽灵（8/s、口罩免疫）+ 酸雾怪（夜刷 2~3 只、冲撞 -10）+ CuSO₄ 池（5/s）；死亡/复活/掉落可捡回；营地设施 + 粗盐提纯 + 原住民交易；图鉴 17 格；世界地图页 13 区域；主菜单三个门 | IT-G10..G16、IT-C05/C06、IT-U03/U04 等价绿；全流程 E2E 16 步通过 |

### Phase W4 — 打磨与部署（约 0.5~1 天）

| 内容 | 出口标准 |
|---|---|
| 数值调参（只改 `balance.json`）；性能（演示机 Chrome 稳定 60 FPS，对齐 NFR-01）；美术/文案终审（调色板 32 色、无占位图残留）；部署 GitHub Pages（+ itch.io 备选）；断网验收；PWA 可选 | 手工验收清单（SPEC-01 §11 网页版改版）逐条打勾；链接可公开访问；首屏加载在演示网络下 ≤ 5 秒（对齐 NFR-02 精神） |

**总计约 4~5 天。** 关键路径：W0 的 CORS 实测结论决定 §5.2 第一层是否可用，进而决定 W2 导师模块的网络层工作量。

---

## 9. 风险与开放问题

| # | 风险/开放问题 | 等级 | 缓解措施 |
|---|---|---|---|
| 1 | **路线 A 导出体积**：Godot Web 导出 wasm 30~40MB，首屏慢、移动端基本不可用 | 高 | 本册已决策主走路线 B；路线 A 仅限应急演示，不作正式交付 |
| 2 | **移动端触控**：横版平台 + E 交互 + 数字快捷栏在触屏上无对应操作 | 中 | 网页版 MVP 明示"桌面浏览器体验"；虚拟摇杆/触屏按钮列赛后项（与手柄支持同清单，SPEC-07 §6） |
| 3 | **LLM key 安全**：任何前端内置 key 都会被提取滥用 | 高 | §5.2 两层方案：默认用户自备 key（localStorage，仅本人）；可选 Cloudflare Workers 代理（key 在服务端环境变量 + Origin 白名单 + 限流）；仓库 grep 检查沿用 NFR-05 |
| 4 | **CORS / 浏览器兼容**：DeepSeek 端点是否放行浏览器跨域未实测；Safari 对 WebGL/Audio 策略差异 | 高 | W0 第一件事实测 CORS，不通则强制走代理；兼容目标定为 Chrome/Edge/Firefox 最新两版，Safari 降级提示而非硬支持 |
| 5 | **性能**：Phaser WebGL 在低端机上的表现、整数缩放适配 | 中 | 像素管线天然轻量；W4 按 NFR-01（60 FPS，最低 30）实测调优；粒子/震屏效果预留降级开关 |
| 6 | **比赛规则是否允许网页交付**：原交付物定义为 Windows exe + 视频（SPEC-01 §1） | **待用户确认** | 网页版定位为**补充交付物**而非替代：Godot exe 按 SPEC-09 照常交付，网页链接作为加分演示渠道 |
| 7 | **音频自动播放策略**：浏览器禁止未交互前出声 | 低 | §4.2 首次交互解锁 AudioContext；缺失音频静默（SPEC-08 §5） |
| 8 | **itch.io iframe 存储限制**：localStorage 在第三方 iframe 中可能不可用 | 低 | §4.3 可用性检测 + 内存降级，不崩溃 |
| 9 | **双实现漂移**：Godot 版继续迭代导致两版行为不一致 | 中 | 单一事实来源下沉到 `data/`（§6.1）+ 本册冻结"接口语义以 SPEC-03 为准"；玩法行为变更必须先改 spec 再双实现同步 |
| 10 | **存档范围蔓延**：localStorage 存档是 SPEC-01 §2.2「不做」清单的破例 | 低 | §1.4 已按范围变更流程登记，仅限最小字段集；评审可整体砍掉该项而不影响其余章节 |

---

## 10. 变更记录

| 日期 | 版本 | 变更 | 触发人 |
|---|---|---|---|
| 2026-08-02 | v1.0 | 初版草案：路线 A/B 对比并推荐 Web 原生重写（TS + Phaser 3 + Vite）；FR→TS 模块映射；LLM 浏览器两层方案（自备 key + Cloudflare Workers 代理）；10 JSON 零改动复用与 CI 校验；Phase W0–W4 计划；10 条风险登记 | 用户 |
