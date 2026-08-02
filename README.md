<div align="center">

# 🧪 MyElements

**世界规则就是初中化学课本：没有魔法，只有化学。**

一款 2D 横版像素开放世界化学教育游戏：收集真实物质、按真实反应条件合成道具、靠化学知识生存，卡住就去「导师学院」问 4 位 AI 导师。

[![Download](https://img.shields.io/badge/下载-Windows%20Demo%20v1.0.0-brightgreen?logo=windows)](https://github.com/huomingyao/MyElements/releases/tag/v1.0.0)
![Godot](https://img.shields.io/badge/Godot-4.6.3-478cbf?logo=godot-engine&logoColor=white)
![Phaser](https://img.shields.io/badge/Phaser-3.80-blue?logo=phaser)
![TypeScript](https://img.shields.io/badge/TypeScript-5.5-3178c6?logo=typescript&logoColor=white)
![Tests](https://img.shields.io/badge/测试-GUT%20%2B%20Vitest%2090条-6e9f18)

**🎮 [点击下载 Windows 可玩 Demo（exe 双击即玩）](https://github.com/huomingyao/MyElements/releases/download/v1.0.0/MyElements.exe)**

</div>

---

## 📖 目录

- [游戏截图](#-游戏截图)
- [双版本架构](#-双版本架构)
- [核心玩法](#-核心玩法)
- [快速开始](#-快速开始)
- [操作指南](#-操作指南)
- [通关路径（10~15 分钟）](#-通关路径1015-分钟)
- [导师学院](#-导师学院)
- [Godot 桌面版](#-godot-桌面版)
- [网页版](#-网页版)
- [数据驱动设计](#-数据驱动设计)
- [项目结构](#-项目结构)
- [测试与校验](#-测试与校验)
- [素材与许可](#-素材与许可)

---

## 📸 游戏截图

| 主菜单 | 草原探索 | 氢气爆炸事件 |
|:---:|:---:|:---:|
| ![菜单](web/scripts/_shots/01_menu.png) | ![草原](web/scripts/_shots/02_world_grassland.png) | ![爆炸](web/scripts/_shots/22_explosion.png) |

| 导师问答 | 世界地图 | 矿洞之夜 |
|:---:|:---:|:---:|
| ![导师](web/scripts/_shots/09_chat.png) | ![地图](web/scripts/_shots/06_worldmap.png) | ![夜晚](web/scripts/_shots/30_night.png) |

---

## 🏗️ 双版本架构

本仓库为 monorepo，**同一套游戏内容、两个可玩版本**，共用 `docs/` 规格与同一套 JSON 内容数据表（单一事实来源）：

| 版本 | 技术栈 | 形态 | 状态 |
|---|---|---|---|
| 🖥️ **Godot 桌面版** | Godot 4.6.3 + GDScript | Windows exe（资源内嵌，双击即玩） | ✅ [v1.0.0 已发布](https://github.com/huomingyao/MyElements/releases/tag/v1.0.0) |
| 🌐 **网页版** | TypeScript + Phaser 3 + Vite | 纯静态站点，打开 URL 即玩 | ✅ 可构建部署 |

---

## 🎮 核心玩法

> **草原收集 → 营地合成 → 氢气爆炸 → 导师问答 → 夜晚生存 → 睡觉复活**，10~15 分钟完整闭环。

- **🌬️ 三值生存系统**：氧气 / 饥饿 / 生命。矿洞等低氧区氧气加速消耗，需要电解水制氧气瓶续命
- **🧪 12 条真实化学配方**：每条都是初中课本原反应——硫燃烧、电解水、中和反应、湿法炼铜、灭火器原理、粗盐提纯……成功弹出知识卡片，失败给出化学反应级解释
- **💥 氢气验纯事件**：H₂+O₂ 未验纯直接点燃 → **爆炸 -50 HP**，经典课本实验的游戏化惩罚；去导师学院问清原理后解锁验纯
- **👻 化学驱怪**：CO 幽灵用活性炭砸（防毒面具原理）、酸雾怪用中和喷雾喷（酸碱中和），消耗品用一次少一个
- **🌙 昼夜循环**：夜晚怪物出没，硫火把照明；床睡觉跳夜并刷新资源，死亡掉落在死亡点可捡回
- **🏫 导师学院**：4 位具名 AI 导师 + 班主任统一调度，DeepSeek 在线回答，断网自动切 34 条本地兜底问答，**全程可离线通关**
- **🗺️ 世界地图**：13 大区域（草原/营地/盐湖/矿洞/导师学院已开放，火山口/气之国等 8 区剪影预告）
- **📒 图鉴收集**：17 种真实物质点亮图鉴，55 条知识字幕随探索触发

---

## 🚀 快速开始

### 玩家：直接玩

**Windows 桌面版** —— 下载 [MyElements.exe](https://github.com/huomingyao/MyElements/releases/download/v1.0.0/MyElements.exe)（96MB，资源已内嵌），双击即玩，无需安装任何环境。

### 开发者：从源码运行

**Godot 桌面版**：用 Godot 4.6.3-stable 打开 [`godot/`](godot/) 目录，运行主场景 `scenes/main/main.tscn`。

**网页版**（Node.js ≥ 18）：

```bash
cd web
npm install        # 安装依赖
npm run dev        # 开发服务器 → http://localhost:5173
npm run build      # 构建静态产物 dist/（可部署到任意静态服务器）
```

---

## ⌨️ 操作指南

| 按键 | 功能 |
|---|---|
| `A` / `D` 或 `←` / `→` | 移动 |
| `Space` | 跳跃 |
| `E` | 交互（拾取 / 设施 / 区域穿梭 / 提问 / 睡觉） |
| `F` | 打怪 —— 自动选用克制物品：活性炭砸幽灵、中和喷雾喷酸雾怪 |
| `Tab` | 背包 |
| `J` | 导师指导室 |
| `M` | 世界地图（13 区域） |
| `C` | 图鉴 |
| `1`–`8` | 快捷栏使用 / 交易卖出 |
| `Esc` | 暂停 / 关闭面板 |

---

## 🗺️ 通关路径（10~15 分钟）

1. **草原**：捡 O₂、C、木棒 —— 头顶弹出知识字幕，图鉴点亮
2. **盐湖**：捡粗盐，用肥皂水试湖水（硬水现象）；回营地实验台做**粗盐三步提纯**（溶解→过滤→蒸发）得 NaCl
3. **营地河边**：取水 → 过滤器（净水四步）→ 电解器 → 得 H₂/O₂ 和氧气瓶
4. **矿洞**：采 S、CaCO₃、Fe、Fe₂O₃ —— 氧气加速消耗，小心 CO 幽灵，CuSO₄ 溶液池别泡
5. **合成台**：木棒 + 硫 → **硫火把**（解锁知识卡片）
6. **氢气事件**：H₂+O₂ 未验纯点燃 → 💥 爆炸 -50 → 去导师学院问"为什么氢气会爆炸"（班主任苏婉清首接并 @化学老师）→ 解锁验纯 → 验纯后点燃成功
7. **夜晚生存**：火把照明、中和喷雾打酸雾怪、活性炭砸 CO 幽灵（戴口罩可免疫 CO）
8. **睡觉复活**：床睡觉跳夜（资源刷新）；死亡掉落物留在死亡点可捡回
9. **原住民交易**：收购你的装备换能量（+20）

---

## 🏫 导师学院

4 位具名 AI 导师，班主任统一调度，问题按关键词路由：

| 导师 | 身份 | 专长 | 口头禅 |
|---|---|---|---|
| **苏婉清** | 班主任（45 岁，传奇冒险家） | 一切问题首接，判断类型并 @ 对应老师 | "别慌，这件事我来安排。" |
| **袁仲衡** | 化学老师（57 岁，退休院士） | 方程式必配平、必标条件，外冷内热 | "配平了吗？" |
| **曲嫣然** | 实用思维老师（32 岁，前材料工程师） | 学习方法 + 怪物应对的元素思维 | "有趣，再想想。" |
| **周启明** | 助理（25 岁，袁老师关门弟子） | 把目标拆成 2~4 步闯关攻略 | "今天只做这一格，做到了就算赢。" |

**联网与离线**：默认离线模式全流程可玩（34 条本地兜底问答 + 班主任调度链，回答带「（离线模式）」标记）；填入 DeepSeek API key 后走在线回答。key 只存本地（桌面版存 `user://config.cfg`，网页版存浏览器 localStorage），**绝不进 git、不进日志**。

---

## 🖥️ Godot 桌面版

| 项 | 说明 |
|---|---|
| 引擎 | Godot 4.6.3-stable（GDScript），不升级不换语言 |
| 主场景 | `godot/scenes/main/main.tscn` |
| 视口 | 640×360，整数倍缩放（`canvas_items` + `keep`） |
| 导出 | Windows Desktop（exe 内嵌 pck），见 [docs/SPEC-09-构建与交付.md](docs/SPEC-09-构建与交付.md) |
| 测试 | GUT 单元测试（headless 可跑），见 [docs/SPEC-06-测试计划.md](docs/SPEC-06-测试计划.md) |
| 架构 | autoload 五大单例：GameManager / KnowledgeTip / RecipeDB / LLMClient / WorldMap |
| 实机验证 | `godot/addons/godot_mcp`：截图 / 输入注入 / 节点树查询 |

```bash
cd godot
./run_tests.sh        # GUT 全量测试（headless）
./validate_data.sh    # 数据表校验，全通过打印 DATA OK
```

**导师联网**：首次运行在存档目录生成 `config.cfg`，填入 DeepSeek API key 即走在线回答；未填或断网自动使用离线知识库。

---

## 🌐 网页版

独立 [`web/`](web/) 平行工程，与 Godot 版共用同一套内容数据表，功能与数值完全对齐。

| 项 | 说明 |
|---|---|
| 技术栈 | TypeScript + Phaser 3（世界渲染）+ DOM UI（面板）+ Vite |
| 部署 | 纯静态产物，零服务端依赖：GitHub Pages / itch.io / Netlify / Nginx 均可 |
| 测试 | Vitest 90 条单测 + puppeteer 浏览器冒烟（菜单/移动/拾取/闭环 29 项） |
| 完整文档 | [web/README.md](web/README.md) · [web/SPEC-WEB-网页版完整规格.md](web/SPEC-WEB-网页版完整规格.md) |

```bash
cd web
npm run test       # Vitest 单元测试
npm run validate   # 数据表 10 类校验（输出 DATA OK）
npm run smoke      # 浏览器冒烟测试
npm run build      # 产出 dist/，整个目录扔上静态服务器即玩
```

---

## 📊 数据驱动设计

**改内容不改代码**——全部文案、数值、配方、人设都在 JSON 数据表（两版共用）：

| 数据表 | 内容 | 规模 |
|---|---|---|
| `substances.json` | 真实物质（氧气、氢气、粗盐、硫酸铜……） | 17 种 |
| `items.json` | 道具（硫火把、中和喷雾、氧气瓶……） | 9 种 |
| `recipes.json` | 化学配方（方程式 + 知识卡片 + 条件） | 12 条 |
| `mentors.json` | 导师人设 / system prompt / 调度关键词 | 4 位 |
| `tips.json` | 知识字幕 | 55 条 |
| `qa_fallback.json` | 离线兜底问答 | 34 条 |
| `worldmap.json` | 世界区域（5 开放 + 8 预告） | 13 区 |
| `balance.json` | 数值调参（三值、伤害、LLM 参数） | 9 组 |
| `ui_strings.json` / `fail_messages.json` | 界面文案 / 失败解释 | 全量 |

---

## 📁 项目结构

```
├── godot/           # 🖥️ Godot 4.6 桌面版工程（Windows exe）
│   ├── scenes/      # main / player / gameplay / mentor / ui 五大模块场景
│   ├── scripts/     # autoload（GameManager/RecipeDB/LLMClient…）+ 各模块逻辑
│   ├── data/        # 10 个 JSON 内容数据表（单一事实来源）
│   ├── assets/      # art（图标/立绘/怪物/玩家）+ audio + fonts
│   ├── maps/        # TileMap 场景
│   └── tests/       # GUT 单元测试 + 集成测试
├── web/             # 🌐 网页版工程（TypeScript + Phaser 3 + Vite）
│   ├── src/         # core / world / gameplay / mentor / ui / scenes
│   ├── data/        # 与桌面版同源的内容数据表
│   ├── scripts/     # 素材处理 / 数据校验 / 浏览器冒烟（_shots/ 为自动截图）
│   └── tests/       # Vitest 单元测试
└── docs/            # 📐 全部规格文档（两版共同的事实来源，索引见 docs/SPEC.md）
```

**[docs/SPEC.md](docs/SPEC.md) 是总索引与事实来源入口**，分册覆盖需求验收、游戏设计、接口契约、数据模型、内容数据表、测试计划、实施计划、美术管线、构建交付、网页版方案。

---

## ✅ 测试与校验

| 版本 | 命令 | 覆盖 |
|---|---|---|
| Godot 版 | `cd godot && ./run_tests.sh` | GUT 单测 + 集成测试（headless） |
| Godot 版 | `./validate_data.sh` | 数据表校验（DATA OK） |
| 网页版 | `cd web && npm run test` | Vitest 90 条：配方引擎/背包/字幕/三值/导师调度/LLM 兜底 |
| 网页版 | `npm run validate` | 数据表 10 类校验 |
| 网页版 | `npm run smoke` / `smoke2` | puppeteer 真实浏览器冒烟：console 零错误 + 闭环 29 项 |

---

## 🎨 素材与许可

- **角色 / 导师 / 怪物 / 地图 / 音乐**：项目自有素材（`web/my chest资料库/`）
- **图标 / 占位图 / 原住民 NPC**：程序化像素生成（`web/scripts/process_assets.py`）
- **字体**：缝合怪像素字体 Fusion Pixel Font（TakWolf，OFL-1.1），明细见 [godot/assets/CREDITS.md](godot/assets/CREDITS.md)
- 代码与内容数据表版权归属项目作者所有

---

<div align="center">

Made with 🧪 & ❤️ — 没有魔法，只有化学

</div>
