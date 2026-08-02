# SPEC 总索引｜《元素炼金物语》MVP

> **本文件是事实来源入口。** 任何开工前先读这里，再读对应分册。
> 代码与 spec 冲突时，以 spec 为准；实现要改行为，先改 spec 再改码（同一 commit）。

- 版本：v1.0（MVP / 20 小时比赛版）
- 引擎：Godot 4.6.3-stable + GDScript
- 开发方式：SSD（规格驱动）+ TDD（测试驱动）+ 多子 Agent 并行
- 状态：**Phase 0–2 收口 + 审计偏差修复完成（包A/B/C 七项 A1..A7 全 fixed，650/650 全绿），Phase 3 打磨交付进行中（CuSO₄ 池/占位美术施工）**

---

## 1. 分册索引

| 文件 | 管什么 | 主要读者 |
|---|---|---|
| [SPEC-01-需求与验收.md](SPEC-01-需求与验收.md) | 全部 FR 条目、验收标准 AC、优先级、依赖 | 所有人（开工前必读） |
| [SPEC-02-游戏设计.md](SPEC-02-游戏设计.md) | 玩起来什么样：循环、地图、数值、事件、引导、演示路径 | P1/P2/P5 |
| [SPEC-03-系统与接口契约.md](SPEC-03-系统与接口契约.md) | Autoload 接口、信号、场景树、模块边界（**H1 后冻结**） | 所有写码的人 |
| [SPEC-04-数据模型.md](SPEC-04-数据模型.md) | 10 个 JSON 数据文件的 Schema、字段约束、校验规则 | P2/P3 |
| [SPEC-05-内容数据表.md](SPEC-05-内容数据表.md) | 物质/配方/字幕/导师人设/兜底问答/地图文案的最终文案 | P3/P5 |
| [SPEC-06-测试计划.md](SPEC-06-测试计划.md) | TDD 循环约定、GUT 用法、UT/IT 清单与 FR 映射 | 所有人 |
| [SPEC-07-实施计划与Agent派活.md](SPEC-07-实施计划与Agent派活.md) | 20 小时时刻表、五人分工、子 Agent 任务包与派活模板 | 主 Agent / P1 |
| [SPEC-08-美术与音频管线.md](SPEC-08-美术与音频管线.md) | 像素规格、调色板、命名、生成流程、素材来源 | P4/P5 |
| [SPEC-09-构建与交付.md](SPEC-09-构建与交付.md) | 导出预设、演示包、断网验证、视频与 PPT 交付 | P1/P5 |
| [SPEC-10-网页版移植方案.md](SPEC-10-网页版移植方案.md) | 网页版技术路线、系统映射、LLM 浏览器方案、部署与阶段计划 | 所有要参与网页版的人 |
| [SPEC-WEB-网页版完整规格.md](SPEC-WEB-网页版完整规格.md) | 网页版唯一事实来源：需求/设计/接口/数据/文案/测试/计划/管线/交付全合集 | 网页版开发者（只读此册） |

规范与纪律（会话规则、SSD/TDD 铁律、目录责任、编码规范、Git）见仓库根 `CLAUDE.md`。

---

## 2. 一句话范围

> 草原收集 → 营地合成 → 氢气爆炸 → 导师问答 → 夜晚生存 → 睡觉复活，
> 10~15 分钟闭环；地图 = 草原 + 营地 + 盐湖 + 矿洞一层 + 导师学院。

做与不做的完整边界见 [SPEC-01 §2 范围边界](SPEC-01-需求与验收.md)。

---

## 3. FR 模块编号规则

| 前缀 | 模块 | 责任人 | 责任目录 |
|---|---|---|---|
| `FR-C-*` | 核心系统（三值/昼夜/死亡/HUD/菜单/Autoload 骨架） | P1 | `scenes/main/`、`scripts/autoload/` |
| `FR-P-*` | 玩家（移动/交互/相机/照明） | P1 | `scenes/player/` |
| `FR-G-*` | 玩法（采集/背包/合成/事件/怪物/道具/设施） | P2 | `scenes/gameplay/`、`scripts/gameplay/` |
| `FR-M-*` | 导师（学院/聊天/调度/LLM/离线） | P3 | `scenes/mentor/`、`scripts/mentor/` |
| `FR-U-*` | UI 与展示（字幕/地图页/图鉴/背包界面/引导） | P2+P3+P4 | `scenes/ui/` |
| `FR-D-*` | 数据表与校验 | P3 | `data/` |
| `FR-B-*` | 构建与交付 | P1+P5 | 根目录 / `export/` |

测试编号：单元 `UT-<FR尾号>`、集成 `IT-<FR尾号>`、手工验收 `MT-*`。

---

## 4. Phase Checklist（唯一进度看板，改动必须同步）

状态记号：`[ ]` 未开始 ｜ `[~]` 进行中 ｜ `[x]` 完成并测试通过 ｜ `[!]` 阻塞

### Phase 0 — 规格与骨架（H0–H1）
- [x] P0-1 规格文档集完成（docs/ 九册 + CLAUDE.md）
- [x] P0-2 Git 分支规范建立（main + dev-p1..p5）
- [x] P0-3 GUT 安装并 headless 跑通空测试（GUT 9.4.0 + `run_tests.sh` / `validate_data.sh`）
- [x] P0-4 Autoload 骨架建立、接口冻结（FR-C-09）（TP-01：UT-C09/UT-D08/IT-C01 全绿，冻结已记入 SPEC-03 §9）
- [x] P0-5 10 个 JSON 数据文件建立 + 校验器测试（FR-D-01..07）（`validate_data.sh` 输出 DATA OK，仅 P4 美术未交付的 icon/avatar 路径警告；UT-D01..07 随全套 322 项全绿）
- [ ] P0-6 美术第一批生成提示词已发出（SPEC-08 §4）

### Phase 1 — 底座（H1–H4）
- [x] P1-1 玩家控制器 + 相机 + 白盒地图（FR-P-01..03）（TP-04 全绿同前；TP-17：`maps/whitebox_map.tscn` 四区+学院白盒布局落地、采集物标记撒布；ViewLight 纹理与美术待 P4）
- [x] P1-2 三值系统 + HUD（FR-C-02、FR-C-07）（TP-03：三值结算与信号，UT-C02 10 项全绿；TP-12：HUD 三条数值条纯信号驱动无 `_process` 轮询 + 已收集计数 + 时间指示 + 低氧闪烁/一次字幕，IT-C07 7 项全绿）
- [x] P1-3 昼夜循环（FR-C-04）（TP-03：`tick(delta)` 时钟，UT-C04 10 项全绿；TP-17：CanvasModulate 昼夜 tint 接线，test_world 覆盖）
- [x] P1-4 采集与背包（FR-G-01..03）（TP-06：`inventory.gd` UT-G02 18 项、`discovery.gd` UT-G03 13 项全绿；TP-06 补：`collectable.*` 采集物场景 IT-G01 9 项全绿 + `inventory_panel.*` 背包界面 IT-U05 9 项全绿）
- [x] P1-5 配方引擎 + 合成台（FR-G-04..05）（TP-07：`try_craft` UT-G04 18 项全绿；TP-07 补：`craft_panel.*` 合成界面 IT-G05 14 项全绿，含拖入/取消回包/失败不耗料/三器材）
- [x] P1-6 字幕引擎（FR-U-01）（TP-05：串行队列 + warning 打断 + once 去重，UT-U01 15 项全绿；TP-05 补：`tip_layer.*` 渲染层 bubble 头顶/banner 底部/warning 红字 6 项全绿）
- [~] P1-7 LLMClient 打通第一条真实回复（FR-M-07）（TP-15：`build_request_body` 组 OpenAI 兼容请求体（system 人设+后缀 / 历史按轮展开 / 本轮 user 经 `sanitize_input`）+ `max_tokens`/`temperature` 读 balance.json + `set_transport` 单一发包点，IT-M07 9 项全绿。**真实 DeepSeek 往返未验证**：测试全程注入传输层不发真实请求，需配 key 后人工跑一次（MT-B02 同批）；聊天框 UI 待 TP-13）
- [x] **H4 检查点**：白盒地图上跑动、拾取、合成出硫火把（test_world.gd 16 项覆盖：白盒地图 + 采集 + 合成台成功合成硫火把弹卡片）

### Phase 2 — 核心闭环（H4–H12）
- [x] P2-1 区域判定 + 分区氧气消耗（FR-C-03）（TP-03：五区域净速率 + 首次进入字幕，UT-C03 8 项全绿）
- [x] P2-2 营地设施：过滤器/电解器/篝火/床（FR-G-13、FR-C-05）（TP-10：`facility_base.gd` 基类统一 §5 三方法 + 四设施 + 实验台 + 湖水，IT-G13 9 项 + IT-C05 3 项全绿；TP-17：采集物清晨刷新与睡觉渐黑过场已接入 world.tscn）
- [x] P2-3 世界地图页 13 区域（FR-U-03）（TP-12：13 热区全部按 worldmap.json 构建，5 彩 + 8 剪影 + 角标 + 未解锁抖动，IT-U03 6 项全绿；肉眼效果归 MT）
- [x] P2-4 知识卡片弹窗 + 失败反馈（FR-G-06..07）（TP-07：卡片五字段组装 + 失败文案按 reason 分池确定性轮转，UT-G07 13 项全绿；TP-07 补：`card_popup.*` 弹窗 IT-G06 6 项全绿，任意键跳过 + 底行 card_footer）
- [x] P2-5 CO 幽灵 + 酸雾怪（FR-G-10..11）（TP-09：幽灵追踪 8/s + 口罩免疫 + `warn_co` 单次字幕，IT-G10 9 项；酸雾怪夜晚刷 2~3 只 + 冲撞单次 -10 + 喷雾消灭，IT-G11 7 项全绿；TP-17：矿洞常驻幽灵×2 + 草原夜刷 + 营地外围 spawner 已接入 world.tscn）
- [x] P2-6 **氢气爆炸事件 + 验纯解锁**（FR-G-08..09）（TP-08：`hydrogen_event.gd` 纯逻辑 + `explosion.tscn` 表现层，精确 -50 + warning 字幕 5 秒 + 置标记 + 生命 <50 死亡路径，IT-G08 12 项 + IT-G09 5 项全绿；TP-07 补：合成界面「点燃/验纯」按钮落地；主 Agent 补：导师问氢气 → `question_mentions_hydrogen`（关键词读 qa_fallback 表）→ 解锁接线，3 项全绿）
- [x] P2-7 导师四房间 + 聊天框 + 立绘（FR-M-01..03）（TP-13：`academy.tscn` 四房间 + ZoneTrigger + `chat_panel` 世界不暂停/逐字打字/idle-talk 切换，IT-M01 6 项 + IT-M02 12 项全绿；立绘为确定性纯色占位，待 P4；TP-17：学院已实例接入 world.tscn，聊天框注册进 ui_manager 不屏蔽输入）
- [x] P2-8 班主任调度链 + @ 终止约束（FR-M-04..06）（TP-14：`mentor_router.gd` 四类分类器按 dispatch 数组顺序判优先级 + `route_targets` 查表 + `parse_mentions` 最长句柄匹配 + `handle_message` 首条必 monitor/≤3 条/只解析 monitor 的 @/调度计数硬上限 1，UT-M04 9 项 + UT-M05 12 项全绿；`prompt_suffix.gd` 通用后缀拼接，UT-M06 7 项全绿；`sanitize_input` 锁定，UT-M03 7 项全绿。回复来源 TP-15 与聊天框 TP-13 均已落地）
- [~] P2-9 离线兜底 + 超时切换（FR-M-08..10）（TP-15：四种失败（超时/网络错/非 200/畸形 body）统一收口成空串再兜底 + 重试上限 `retry_count` + 失败即转离线 + `mode_changed` 只在真变化时发，UT-M08 13 项全绿；`qa_fallback.gd` 命中最多者胜/平票取先/零命中取表中兜底行 + 角标由调用方追加，UT-M09 9 项全绿；`config_panel.tscn` key 只转发给 `set_api_key`（`secret=true`、不回显不记录）+ 手动离线开关 + 滑块可拖不生效，IT-M10 11 项全绿。**未能实机验证**：滑块手感与面板排版归 MT-M10 人工确认，godot_mcp 本会话未注册；拔网线全流程归 MT-B02）
- [x] P2-10 道具生效（FR-G-12）（TP-09：`item_effects.gd` 八种道具效果按 `effect_value_key` 动态读 balance，装备不消耗/消耗品 -1/无目标不消耗，UT-G12 14 项全绿；TP-17：use_item 1-8 热键接线，装备切换 + 消耗结算 + 火把视野已通）
- [x] P2-11 死亡/复活/掉落（FR-C-06）（TP-11：死亡画面 + `drop_bag` 掉落包快照/替换语义 + 复活三值回满，IT-C06 11 项全绿；TP-17：世界场景死亡生成掉落包 + 复活回床接线完成）
- [x] P2-12 主菜单三个门（FR-C-08）（TP-12：三门导航 world/academy/codex + Esc 暂停菜单，IT-C08 7 项全绿；加载 ≤3 秒归 MT-B01 掐表）
- [x] P2-13 图鉴（FR-U-04）（TP-16：17 格网格自数据表得出 + 剪影零泄露全量扫描 + 分类标签 + 循环翻页，IT-U04 12 项全绿；肉眼观感归 MT）
- [x] P2-14 粗盐提纯三步（FR-G-14）（TP-10：`facility_salt_purifier.gd` 顺序强制状态机 + 肥皂水试湖水，IT-G14 9 项全绿）
- [ ] **H8 检查点**：爆炸事件 + 联网导师问答跑通
- [ ] **H12 检查点（功能冻结）**：全闭环可从头玩到尾

### Phase 3 — 打磨与交付（H12–H20）
- [ ] P3-1 数值调参（SPEC-02 §4 参数表）
- [ ] P3-2 bug bash 两轮 + bug 台账清零 P0/P1
- [ ] P3-3 美术终审统一（SPEC-08 §2）
- [ ] P3-4 文案终审（SPEC-05 全册）
- [ ] P3-5 Windows 导出 + 干净电脑验证（FR-B-01、FR-B-03）
- [ ] P3-6 断网全流程测试（FR-B-02）
- [ ] P3-7 演示视频 3 分钟 + PPT/讲稿（SPEC-09 §4..5）
- [ ] P3-8 交付打包（U 盘 ×2 + 云盘）
- [x] P3-9 UI 面板自适应布局（FR-U-06，IT-U06 6 项全绿）

---

## 5. 追溯矩阵入口

FR → 验收标准 → 测试用例 → Checklist 项 的完整映射见
[SPEC-06 §6 追溯矩阵](SPEC-06-测试计划.md)。新增 FR 时必须同时补该矩阵一行，否则视为规格未完成。

---

## 6. 变更记录

| 日期 | 版本 | 变更 | 触发人 |
|---|---|---|---|
| 2026-08-01 | v1.0 | 由 `plan/` 三份草案重写为九册规格文档集，引入 FR/AC/测试编号体系 | 用户 |
| 2026-08-02 | v1.1 | TP-17 世界总装 + 四个 UI 件（合成台/卡片/背包/字幕层）+ 导师验纯解锁接线落地；SPEC-02 §8 补 `codex` 热键、SPEC-05 §1 试剂三物来源裁决、§9 新增 7 个 ui_strings 键、SPEC-03 §9 补 8 行变更记录 | 主 Agent |
| 2026-08-02 | v1.2 | WORKLOG A/B 级缺口全收口（碳口罩落地+幽灵 AC5 免疫、电解器灌装氧气瓶、路牌开地图页、氧气 70 教程提示、矿洞呼吸/光合作用字幕、R3 低氧点燃、unlock_tip 消费、ViewLight 兜底、HUD 语义色、学院门传送 D2）；SPEC-01 FR-G-10 增 AC5、FR-C-08 AC1 记 D2；SPEC-05 §1/§3.2/§8、SPEC-02 §4.4/§5、SPEC-04 §10、SPEC-08 §6、SPEC-09 §3.1 同步；交付骨架 README.txt/export_presets.cfg/BUGS.md 落地 | 主 Agent |
| 2026-08-02 | v1.3 | 对标优化文档同步（PLAN-benchmark-optimization Wave 1 五包 27 项落地后）：头部状态行由「实现未开始」更正为真实进度；SPEC-05 §9 补登 `death_info`/`death_day`/`death_hint` 三键；SPEC-02 §4.10 tips 条数 47→51、§4.1/§4.6 补 `items.campfire_daily_limit` 与 `monsters.acid_mist_lifetime_seconds` 口径；SPEC-03 §9 补 4 行变更记录（once 标记时机+warning 打断 banner 回写、set_reply_provider {text,offline} 扩展、reply_chunk 不发射、world_map 静态解锁）；BUGS.md 登记 Wave 1 修复 26 条 + 新发现 8 条；WORKLOG.md 追加对标优化批次；plan/ 四份草案标注废弃 | 主 Agent |
| 2026-08-02 | v1.4 | 包D「spec 文档回写」（五路并行审计后，以码为准只改文档）：配方 12 / tips 51 / qa_fallback 34 / fail_messages 9 全册对齐；新增 FR-G-16 CuSO₄ 溶液池（54→55 条 FR，P1/IT-G16，P3 补做项）；SPEC-02 `night_tint`→`night_brightness`；FR-M-05 AC1 按 SPEC-03 §6.1 口径（≤3 条）；FR-M-10 AC2 按 B-024 裁决（隐藏死 UI 滑块 + config_note）；SPEC-07 §6 收录七条对标大件；BUGS.md 登记 B-039..B-045（包A/B/C 修复中）并将 B-035..B-038 转赛后清单；SPEC-03 §9 为包A/B/C 预留四行占位；WORKLOG 测试基线 547→610 | 主 Agent |
| 2026-08-02 | v1.5 | 新增 SPEC-10 网页版移植方案（路线 A/B 对比、推荐 Web 原生重写、FR→TS 模块映射、LLM key 安全方案、Phase W0–W4 计划） | 用户 |
| 2026-08-02 | v1.6 | 包E3「文档收口」：包A/B/C 七项审计偏差修复（A1..A7，BUGS B-039..B-045 标 fixed）落账 + 本收口——SPEC-03 §9 四行占位展开为正式变更记录并补 config 面板注册/ui_strings 两键两行、SPEC-05 §9 补登 `config_apply`/`chat_config`、SPEC-01 FR-M-10 AC1 补游戏内入口、WORKLOG 测试基线 610→650 并追加审计修复批次行；头部状态行更新为「Phase 0–2 收口 + 审计偏差修复完成，Phase 3 进行中」 | 主 Agent |
| 2026-08-02 | v1.7 | 新增 SPEC-WEB 网页版完整规格（九册 + SPEC-10 合并重写，55 条 FR / 10 JSON / 全文案内联，网页版开发只读此册） | 用户 |
| 2026-08-02 | v1.8 | FR-U-06 面板自适应布局落地（IT-U06）：合成/背包/卡片模态面板按视口比例铺开并居中，主菜单/暂停菜单中心锚点，死亡画面垂直居中；`project.godot` 显式补 `stretch/aspect=keep` 并恢复会话中被 Godot 进程改写丢失的 640×360 视口行；SPEC-01/03/06 同步 | 主 Agent |
