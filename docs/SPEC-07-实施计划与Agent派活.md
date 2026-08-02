# SPEC-07｜实施计划与 Agent 派活

> 计划管"谁在什么时间交出什么"，三份 spec（02/03/04）管"做出来的东西长什么样"。
> 本文件同时是 **多子 Agent 派活手册**——任务包（§4）可以直接复制成子 Agent 的 prompt。

---

## 1. 五人分工

原则：AI 写代码初稿，人负责提需求、整合、验收。每人一个"责任目录"（[SPEC-03](SPEC-03-系统与接口契约.md) §1 与 `CLAUDE.md` 目录表），合并冲突最小化。

| 角色 | 责任人 | 负责内容 | 交付物 |
|---|---|---|---|
| **P1 主程/架构** | 编程最强者 | 项目骨架、Autoload 与接口冻结、玩家控制器、相机、三值、昼夜、主菜单、世界地图页、构建导出、功能冻结裁决 | 可运行主干 + Windows exe |
| **P2 玩法程序** | 次之 | 采集/背包、配方引擎、合成台、知识卡片、怪物 AI ×2、氢气爆炸事件、道具、营地设施、死亡掉落、图鉴 | 全部玩法机制 |
| **P3 AI 与内容** | 文字能力强者 | 导师系统（LLM + 调度 + 离线兜底）、字幕引擎、全部数据表与文案 | 导师聊天可用 + 数据表填完 |
| **P4 美术** | 有审美者 | 生成素材（含 4 位导师立绘 idle/talk ×8）、免费素材包筛选、切片导入、UI 界面、地图页底图、调色板终审 | 全部可见美术资产 |
| **P5 整合/QA/视频** | 细心者 | TileMap 地图搭建、测试执行、bug 台账、断网测试、演示视频、PPT/讲稿 | 测试报告 + 3 分钟视频 + PPT |

**结对**：P1 带 P2（代码互相 review）；P3 的内容表由 P5 帮忙录入（H8 后 P5 转入测试与视频）。

---

## 2. 时刻表（H0 = 现在，共 20 小时）

每个整点：`git push` + 本地构建一次，确认能跑。**构建挂了优先修构建。**

### 第一阶段：启动与底座（H0–H4）

| 时段 | 全员动作 |
|---|---|
| H0–H1 | 启动会 30 分钟对齐 `docs/` 全套；建分支规范；P1 建项目骨架 + **装 GUT + Autoload 接口冻结**；P3 建 10 个空数据文件 + 校验器；**P4 立刻发出第一批生成提示词**（网页生成要排队，见 [SPEC-08 §4](SPEC-08-美术与音频管线.md)） |
| H1–H2 | P1：玩家控制器 + 相机 + 白盒地图；P2：背包数据结构 + 采集原型；P3：字幕引擎 + tips.json 框架；P4：筛选免费像素素材包；P5：画地图白盒布局（四区 + 学院位置） |
| H2–H4 | P1：三值 + HUD + 昼夜；P2：配方引擎 + 合成台；P3：聊天 UI + LLMClient 打通第一条真实回复；P4：处理第一批生成图；P5：TileMap 铺草原与营地 |

**H4 检查点**：玩家能在白盒地图上跑、捡东西、打开合成台合成出硫火把（无美术也行）。

### 第二阶段：核心闭环（H4–H12）

| 时段 | 全员动作 |
|---|---|
| H4–H6 | P1：区域判定 + 分区氧气 + 电解器剧情点 + **世界地图页**；P2：知识卡片 + CO 幽灵；P3：4 位导师 prompt 调通 + 班主任调度；P4：矿洞/盐湖/怪物素材 + 地图页底图；P5：铺矿洞与盐湖 + 搭测试清单 |
| H6–H8 | P1：床 + 主菜单三个门；P2：**氢气爆炸事件** + 酸雾怪；P3：离线兜底 + 断网开关 + **底部聊天框**；P4：爆炸动画 + 卡片 UI + 导师小人切片；P5：铺导师学院四房间 + 录屏存素材 |
| H8–H10 | P1：死亡/复活/掉落；P2：道具生效 + 粗盐提纯；P3：填字幕与卡片文案；P4：导师立绘两帧 + 图鉴 UI；P5：第一轮全流程跑通，开 bug 台账 |
| H10–H12 | 全员整合联调。P3/P5 填图鉴文案；P1 修阻塞性 bug；**H12 末：功能冻结** |

**H8 检查点**：爆炸事件 + 联网导师问答跑通——这是演示的高潮，优先级最高。
**H12 检查点（冻结点）**：完整闭环能从头到尾玩一遍，允许丑、允许有小 bug，**不允许缺环节**。

### 第三阶段：打磨与交付（H12–H20）

| 时段 | 全员动作 |
|---|---|
| H12–H14 | 数值调参（[SPEC-02 §4](SPEC-02-游戏设计.md) 参数表；目标：评委 10 分钟体验全部环节）；bug bash 第一轮 |
| H14–H16 | P4 美术终审；P3 文案终审；P1 导出 exe；**P5 断网测试（MT-B02）** |
| H16–H18 | P5 按脚本录制 + 剪辑视频；P3 写 PPT/讲稿；其余人第二轮 bug bash + 彩排演示路径（每人玩两遍） |
| H18–H19 | 最终打包：exe + 视频 + PPT → U 盘 ×2 + 云盘；演示机环境确认 |
| H19–H20 | **缓冲。什么都不加。** 累了轮流睡 |

---

## 3. 多子 Agent 协作规则

### 3.1 派活前的检查（主 Agent 负责）

1. 目标 FR 在 [SPEC-01](SPEC-01-需求与验收.md) 中存在且 AC 完整。
2. 依赖的 FR 已完成（看 [SPEC.md](SPEC.md) Checklist）。
3. 本轮并行的任务包**文件范围无重叠**；有重叠改串行或用 worktree 隔离。
4. Autoload 接口已冻结（P0-4 完成）——否则所有依赖 autoload 的任务都要等。

### 3.2 并行安全矩阵

| 可安全并行的组合 | 原因 |
|---|---|
| P1 核心（`scripts/autoload/`、`scenes/main/`）+ P3 导师（`scenes/mentor/`）+ P4 美术（`assets/`） | 目录不相交 |
| P2 玩法（`scenes/gameplay/`）+ P3 数据表（`data/`） | 玩法只读数据表，不写 |
| 多个数据表任务（substances / recipes / tips / qa） | 一表一文件，各自独立 |

| 必须串行的组合 | 原因 |
|---|---|
| Autoload 接口变更 vs 任何调用方 | 接口是全局契约，只能主 Agent 改 |
| `balance.json` 的多方写入 | 单文件多写者必冲突，改动集中给 P1 |
| 同一场景树节点的增删（`world.tscn`） | `.tscn` 文本合并极易坏 |

### 3.3 子 Agent 交付格式（强制）

每个子 Agent 完成后必须报告：

```
FR-ID:      FR-G-04
改动文件:    scripts/gameplay/recipe_db.gd, tests/unit/test_recipe_db.gd
测试命令:    ./run_tests.sh -gtest=res://tests/unit/test_recipe_db.gd
测试结果:    23 passed / 0 failed
AC 覆盖:     AC1..AC5 全部自动化验证
未能验证:    无
SPEC 同步:   无需变更（实现与 spec 一致）
```

未能验证的项必须写清原因，不许留空、不许写"应该没问题"。

### 3.4 子 Agent 禁止事项

- 越出指定目录写文件。
- 修改 `docs/SPEC-03-系统与接口契约.md`（接口只能主 Agent 改）。
- 修改 `.gitignore`、`project.godot` 的 autoload 段（P1 专属）。
- 创建 commit（提交由用户确认）。
- 为了让测试通过而放宽 AC。
- 在逻辑代码里写中文文案或裸数值（走数据表）。

---

## 4. 任务包（可直接复制成子 Agent prompt）

每个任务包格式统一。派活时把 `【】` 里的内容替换后发出。

### 4.0 通用 prompt 头（每个任务包都要带）

```
你在 Godot 4.6.3 项目 D:/Github/games/test 中工作，用 GDScript。

开工前必读：
- CLAUDE.md（开发规范、SSD/TDD 铁律、编码规范）
- docs/SPEC-01-需求与验收.md 中的【FR-ID】条目及其全部 AC
- docs/SPEC-03-系统与接口契约.md（接口契约，只读不改）
- docs/SPEC-04-数据模型.md（如涉及数据表）
- docs/SPEC-06-测试计划.md（测试命名与运行方式）

工作方式（严格 TDD）：
1. 先在【测试文件路径】写测试覆盖每条 AC，运行并确认断言失败（RED）
2. 写最少实现让测试通过（GREEN）
3. 清理后跑全量测试（REFACTOR）

约束：
- 只允许修改这些文件：【文件白名单】
- 不改 autoload 接口签名，不改 docs/SPEC-03
- 逻辑代码中不许出现中文文案（走 KnowledgeTip + tips.json）和裸数值（走 balance.json）
- 不创建 git commit

完成后按 SPEC-07 §3.3 格式报告。
```

---

### TP-01 项目骨架与 Autoload 契约
`P1` · 依赖：无 · FR-C-01、FR-C-09、FR-D-08

- 文件白名单：`project.godot`、`scripts/autoload/*.gd`、`data/balance.json`、`tests/unit/test_autoload_contract.gd`、`tests/unit/test_balance.gd`、`run_tests.sh`、`validate_data.sh`
- 内容：配置视口与输入映射；建五个 autoload 骨架（方法齐全、可返回占位值、不抛异常）；建 `balance.json`；装 GUT 并让 headless 跑通；封装两个脚本。
- 完成标准：UT-C09、UT-D08、IT-C01 通过；`./run_tests.sh` 能跑。
- **完成后接口冻结**，在 SPEC-03 §9 记一行。

### TP-02 数据表与校验器
`P3` · 依赖：TP-01 · FR-D-01..07

- 文件白名单：`data/*.json`、`scripts/tools/validate_data.gd`、`tests/data/*.gd`
- 内容：按 [SPEC-05](SPEC-05-内容数据表.md) 填 10 个数据文件（substances / recipes / fail_messages / tips / mentors / qa_fallback / worldmap / items / ui_strings，balance 由 P1 建）；实现校验器 10 类检查（[SPEC-04 §12](SPEC-04-数据模型.md)）。
- 完成标准：UT-D01..D07 通过；`./validate_data.sh` 输出 `DATA OK` 退出码 0。
- 注意：文案一字不改地誊抄 SPEC-05，发现文案问题回报主 Agent 改 spec，不自行改写。

### TP-03 三值、昼夜与区域
`P1` · 依赖：TP-01 · FR-C-02、FR-C-03、FR-C-04

- 文件白名单：`scripts/autoload/game_manager.gd`、`tests/unit/test_game_manager_stats.gd`、`test_game_manager_zone.gd`、`test_daynight.gd`
- 内容：三值结算 + 信号；区域判定与分区氧气；昼夜时钟（`delta` 可注入）。
- 完成标准：UT-C02、UT-C03、UT-C04 通过。
- 注意：昼夜与消耗必须接受 `delta` 参数推进（可测性约束，[SPEC-06 §3](SPEC-06-测试计划.md)）。

### TP-04 玩家控制器与交互
`P1` · 依赖：TP-01 · FR-P-01、FR-P-02、FR-P-03

- 文件白名单：`scenes/player/**`、`tests/integration/test_player_*.gd`
- 内容：移动/跳跃/重力/朝向；统一交互键 E + 提示气泡 + 最近目标选择；相机跟随与边界；火把视野。
- 完成标准：IT-P01、IT-P02、IT-P03 通过。
- 注意：交互只调 [SPEC-03 §5](SPEC-03-系统与接口契约.md) 的三个方法，新增交互物不改玩家代码。

### TP-05 字幕引擎
`P3` · 依赖：TP-01、TP-02 · FR-U-01

- 文件白名单：`scripts/autoload/knowledge_tip.gd`、`scenes/ui/tip_*.tscn`、`tests/unit/test_knowledge_tip.gd`
- 内容：三种 style、队列串行、`warning` 打断、`show_once`、缺 id 不崩溃。
- 完成标准：UT-U01 通过。

### TP-06 采集与背包
`P2` · 依赖：TP-02、TP-04 · FR-G-01、FR-G-02、FR-G-03、FR-U-05

- 文件白名单：`scenes/gameplay/collectable*`、`scripts/gameplay/inventory.gd`、`scenes/ui/inventory_panel.tscn`、`tests/unit/test_inventory.gd`、`test_discovery.gd`、`tests/integration/test_collect_*.gd`
- 内容：数据驱动采集物；8 格快捷栏 + 堆叠 99；发现集合（16 计数口径见 [SPEC-05 §1](SPEC-05-内容数据表.md)）；背包界面。
- 完成标准：UT-G02、UT-G03、IT-G01、IT-U05 通过。

### TP-07 配方引擎与合成台
`P2` · 依赖：TP-02 · FR-G-04、FR-G-05、FR-G-06、FR-G-07

- 文件白名单：`scripts/gameplay/recipe_db.gd`（或 autoload 实现体）、`scenes/gameplay/craft_*`、`scenes/ui/card_popup.tscn`、对应测试
- 内容：12 条配方匹配（顺序无关、条件区分、`needs_purity_check`）；合成界面；知识卡片；三类失败文案确定性轮换。
- 完成标准：UT-G04（12 条正例 + 反例）、UT-G07、IT-G05、IT-G06 通过。
- 注意：**失败不消耗材料**（[SPEC-02 §4.4](SPEC-02-游戏设计.md)）。

### TP-08 氢气爆炸与验纯
`P2` · 依赖：TP-07、TP-03 · FR-G-08、FR-G-09

- 文件白名单：`scenes/gameplay/explosion*`、`scripts/gameplay/hydrogen_event.gd`、对应测试
- 内容：未验纯点燃 → 爆炸动画 + 精确 -50 + 警示字幕 + 置标记；问过导师后解锁验纯；验纯后点燃成功。
- 完成标准：IT-G08、IT-G09 通过。
- **这是全场核心记忆点，优先级高于一切美术打磨。** 生命 <50 时的死亡路径必须测。

### TP-09 怪物与道具
`P2` · 依赖：TP-03、TP-06 · FR-G-10、FR-G-11、FR-G-12

- 文件白名单：`scenes/gameplay/monster_*`、`scripts/gameplay/item_effects.gd`、对应测试
- 内容：CO 幽灵（追踪、8/s、口罩免疫）；酸雾怪（夜晚 2~3 只、冲撞 -10、喷雾消灭）；八种道具效果。
- 完成标准：IT-G10、IT-G11、UT-G12 通过。
- 注意：AI 保持最简，不做寻路与状态机分层。

### TP-10 营地设施与粗盐提纯
`P2` · 依赖：TP-07 · FR-G-13、FR-G-14、FR-C-05

- 文件白名单：`scenes/gameplay/facility_*`、对应测试
- 内容：过滤器/电解器/篝火/床/合成台；粗盐三步顺序流程；肥皂水试湖水。
- 完成标准：IT-G13、IT-G14、IT-C05 通过。

### TP-11 死亡复活与掉落
`P1` · 依赖：TP-03、TP-06 · FR-C-06

- 文件白名单：`scripts/autoload/game_manager.gd`（死亡段）、`scenes/gameplay/drop_bag*`、`scenes/ui/death_screen.tscn`、对应测试
- 完成标准：IT-C06 通过。

### TP-12 HUD、主菜单与世界地图页
`P1` · 依赖：TP-03、TP-02 · FR-C-07、FR-C-08、FR-U-03

- 文件白名单：`scenes/main/hud*`、`scenes/main/main_menu*`、`scenes/main/world_map_panel*`、`scripts/autoload/world_map.gd`、对应测试
- 内容：三条数值条（信号驱动）+ 计数 + 时间；三个门；13 区域热区（5 彩 + 8 剪影 + 抖动 + 角标）。
- 完成标准：IT-C07、IT-C08、IT-U03 通过。

### TP-13 导师学院场景与聊天框
`P3` · 依赖：TP-02、TP-04 · FR-M-01、FR-M-02

- 文件白名单：`scenes/mentor/**`、对应测试
- 内容：四房间四位小人；走近提问气泡；底部聊天框（世界不暂停）；逐字打字 + idle/talk 切换。
- 完成标准：IT-M01、IT-M02 通过。

### TP-14 班主任调度链
`P3` · 依赖：TP-02 · FR-M-03、FR-M-04、FR-M-05、FR-M-06

- 文件白名单：`scripts/mentor/mentor_router.gd`、`scripts/mentor/prompt_suffix.gd`、对应测试
- 内容：输入清理；四类分类器（优先级 combat→learning→chemistry→other）；`route_targets`；@ 解析与**只有班主任能 @**；调度硬上限 1 次。
- 完成标准：UT-M03、UT-M04、UT-M05、UT-M06 通过。
- 注意：`MentorRouter` 必须是**不依赖场景的可独立实例化类**，否则单测跑不了。

### TP-15 LLM 接入与离线兜底
`P3` · 依赖：TP-14 · FR-M-07、FR-M-08、FR-M-09、FR-M-10

- 文件白名单：`scripts/autoload/llm_client.gd`、`scripts/mentor/qa_fallback.gd`、`scenes/mentor/config_panel.tscn`、对应测试
- 内容：DeepSeek 调用（唯一出口 `_generate_reply()`）；8 秒超时 + 1 重试 + 四种失败兜底；关键词兜底（命中最多、平票取先）；离线标记；手动开关；配置面板占位。
- 完成标准：UT-M08、UT-M09、IT-M07 通过；MT-M10 手工确认。
- **安全约束**：key 只读 `user://config.cfg`；不进日志、不进 `res://`、不进 git。测试用 stub，不发真实请求。

### TP-16 图鉴
`P2` · 依赖：TP-06、TP-07 · FR-U-04

- 文件白名单：`scenes/ui/codex_*`、对应测试
- 内容：17 格网格（展示全部物质卡；HUD 进度按 16 计，见 [SPEC-05 §1](SPEC-05-内容数据表.md)）+ 未收集剪影不泄露名称 + 分类标签 + 已解锁卡片翻页。
- 完成标准：IT-U04 通过。

### TP-17 地图搭建
`P5` · 依赖：TP-04 · 无独立 FR（服务 FR-C-03）

- 文件白名单：`maps/**`
- 内容：一张连续地图，四区 + 学院，按 [SPEC-02 §3](SPEC-02-游戏设计.md) 的相对位置；区域触发器交给 P1 挂。
- 完成标准：全流程回归脚本（[SPEC-06 §8](SPEC-06-测试计划.md)）步骤 1–16 路线可走通。

### TP-18 构建与交付
`P1`+`P5` · 依赖：全部 · FR-B-01..04

- 文件白名单：`export_presets.cfg`、`README.txt`、`docs/BUGS.md`
- 完成标准：MT-B01..B04 全部打勾；[SPEC-09](SPEC-09-构建与交付.md) 检查项清零。

---

## 5. 风险与对策

| 风险 | 概率 | 对策 |
|---|---|---|
| 现场断网，导师变哑巴 | 高 | 离线兜底 ≥20 条 + H14 断网全流程测试；演示话术准备"离线模式也能答" |
| DeepSeek key 失效/额度用尽 | 中 | 备两个 key；一键切离线开关；手机热点备用 |
| 5 人合并冲突 | 高 | 责任目录制；整点 push；P1 统一合并；`.tscn` 同文件不并行改 |
| Autoload 接口反复改 | 高 | H1 冻结 + 只有主 Agent/P1 能改 + 变更记在 SPEC-03 §9 |
| 素材风格不统一 | 中 | 一套调色板 + 固定像素规格；P4 一人终审，不统一就压调色板重导 |
| 范围蔓延 | 极高 | 一律记进 §6 停车场；P1 有独裁权；H12 后只修不加 |
| 初学者卡壳阻塞 | 中 | 结对（P1↔P2）；卡住 30 分钟必须喊人；AI 先出原型再改 |
| 测试拖慢进度 | 中 | 单测限定在纯逻辑（跑完 <10 秒）；UI 用集成 + MCP 截图，不追求 100% 覆盖 |
| 演示视频来不及 | 低 | H6 起 P5 随手录屏存素材；分镜已定，照拍即可 |

---

## 6. 赛后清单（停车场）

自由建造 · 存档系统 · 深层矿洞与工具分层（木→钢镐）· 火山口/其余 8 个未解锁区域实装 · 铁锈虫 · 化肥农田 · 溶解度与配平校验玩法 · 技能树 UI · 导师性格滑块实装 · 12 单元全覆盖（MVP 覆盖 7 单元）· 从化学扩到多知识领域的数据驱动架构重构 · 音效原创化 · 联机 · 多语言 · 手柄 · Steam/移动端发行评估。

**对标优化大件**（2026-08-02 包D 赛后清单输出，来源 PLAN-benchmark-optimization）：
- **区块资源化挖矿**：对标项目的核心深度玩法，价值高但属新大系统，MVP 功能冻结不做。
- **熔炉等 block entity 机制**：拓展合成/冶炼维度，需新建实体-方块架构，MVP 不做。
- **材质声音矩阵**（材质×动作音效库）：显著提升手感反馈，依赖完整音频资产管线，MVP 不做。
- **粒子颜色数据驱动**：表现层调优项，需粒子系统改造，MVP 不做。
- **声明式设置系统**（ConfigFile 默认值+集中派发）：架构债清理，现状可用，MVP 不做。
- **Tag 资源分类系统**：资源管理规模化后的方案，MVP 体量用不上。
- **组件库沉淀**（状态机/伤害组件）：复用性重构，MVP 优先交付不做。

**新增条目规则**：任何人提出的新想法直接追加到本节末尾，一句话即可，**不讨论、不评估**。
