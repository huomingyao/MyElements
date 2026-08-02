# 我的元素 (my Elements)

> 2D 横版像素开放世界化学教育游戏 —— **世界规则就是初中化学课本**：没有魔法，只有化学。

玩家收集真实物质、按真实反应条件合成道具、靠化学知识生存；卡住就去「导师学院」问 4 位 AI 导师（DeepSeek 在线 + 本地知识库离线兜底，断网可玩）。

- 引擎：Godot 4.6.3-stable（GDScript）
- 平台：Windows Desktop（exe + pck，双击即玩）；**网页版规划中，见下**
- 阶段：MVP（评委可上手 10~15 分钟的闭环 demo）

---

## 玩法特性

- **三值生存系统**：氧气 / 饥饿 / 生命，低氧区需要制氧道具
- **昼夜循环**：夜晚怪物出没，光照与危险度联动
- **采集与背包**：17 种真实物质（O₂、H₂、CO₂、NaCl、CuSO₄……）
- **合成台**：12 条真实化学配方，成功出知识卡片，失败有化学反应级解释
- **氢气不验纯爆炸事件**：经典课本实验的游戏化惩罚
- **怪物 ×2**：CO 幽灵、酸雾怪，用化学手段驱赶（肥皂水、中和喷雾）
- **导师学院**：4 位具名 AI 导师 + 班主任统一调度；LLM 在线回答，断网自动切离线兜底
- **世界地图页**：13 区域（含 8 个灰色剪影预告）
- **图鉴简版 / 死亡复活与掉落捡回 / 字幕引擎（51 条）/ 原住民交易**

## 操作

| 按键 | 功能 |
|---|---|
| A/D 或 ←/→ | 移动 |
| Space | 跳跃 |
| E | 交互 / 合成台（靠近时） |
| Tab | 背包 |
| C | 图鉴 |
| M | 世界地图 |
| 1–8 | 快捷栏使用 |
| Esc | 暂停 / 收起面板 |

## 运行与构建

**玩**：双击 `ElementAlchemy.exe`（导出包，无需安装 Godot）。

**从源码运行**：用 Godot 4.6.3-stable 打开 [`godot/`](godot/) 目录，运行主场景 `scenes/main/main.tscn`。

**导师联网**：首次运行在存档目录生成 `config.cfg`，填入 DeepSeek API key 即走在线回答；未填或断网自动使用离线知识库（回答带「（离线模式）」标记）。key 只存本地，绝不进 git。

**导出 Windows 包**：见 [docs/SPEC-09-构建与交付.md](docs/SPEC-09-构建与交付.md)。

## 测试

```bash
cd godot
./run_tests.sh        # GUT 全量测试（headless）
./validate_data.sh    # 数据表校验，全通过打印 DATA OK
```

测试计划见 [docs/SPEC-06-测试计划.md](docs/SPEC-06-测试计划.md)。

## 网页版（规划中）

本项目将有**浏览器点开即玩的网页版**：

- 独立 `web/` 平行工程，与 Godot 版**共用同一套 `godot/data/` 内容源**（10 个 JSON 数据表单一事实来源）
- 无需下载安装，打开 URL 即玩；首次加载后断网仍可走离线导师兜底
- 功能边界与数值完全对齐本仓库 SPEC-01 / SPEC-02，不新增玩法
- 方案与完整规格：[docs/SPEC-10-网页版移植方案.md](docs/SPEC-10-网页版移植方案.md)、[docs/SPEC-WEB-网页版完整规格.md](docs/SPEC-WEB-网页版完整规格.md)

## 目录结构

本仓库为 monorepo：Godot 桌面版与网页版（规划中）共存，共用 `docs/` 规格与内容源。

```
├── godot/           # Godot 4.6 桌面版工程（Windows exe）
│   ├── scenes/      # main / player / gameplay / mentor / ui 五大模块场景
│   ├── scripts/     # autoload（GameManager/RecipeDB/LLMClient…）+ 各模块逻辑
│   ├── data/        # 10 个 JSON 内容数据表（改文案不改代码，网页版共用此内容源）
│   ├── assets/      # art（图标/立绘/怪物/玩家）+ audio + fonts
│   ├── maps/        # TileMap 场景
│   └── tests/       # GUT 单元测试 + 集成测试
├── web/             # 网页版（规划中，见下文）
└── docs/            # 全部规格文档（两版共同的事实来源，索引见 docs/SPEC.md）
```

## 文档

**[docs/SPEC.md](docs/SPEC.md) 是总索引与事实来源入口**，分册覆盖需求验收、游戏设计、接口契约、数据模型、内容数据表、测试计划、实施计划、美术管线、构建交付、网页版方案。

## 素材授权

- 占位美术：程序生成，无第三方素材
- 字体：缝合怪像素字体 Fusion Pixel Font（TakWolf，OFL-1.1）
- 明细见 [godot/assets/CREDITS.md](godot/assets/CREDITS.md)

## 许可

代码与内容数据表版权归属项目作者所有。字体等第三方资产遵循各自许可证。
