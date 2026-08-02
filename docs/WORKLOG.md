# 工作日志｜《元素炼金物语》MVP

> **本文件是续作入口。** 新会话开工顺序：读本文件 → `docs/SPEC.md`（Checklist 与索引）→ 任务涉及的分册。
> 状态口径：✅ = 实现 + 自动化测试全绿；⚠️ = 实现但有人工/实机验证缺口；❌ = 未做。

- 最近更新：2026-08-02（FR-U-06 面板自适应布局落地，IT-U06 新增 6 项）
- 测试基线：`./run_tests.sh` **666/666 全绿**（2026-08-02 复验，含 IT-U06 新增 6 项）；`./validate_data.sh` **DATA OK**（仅 P4 美术未交付的路径警告）
- 冒烟基线：主场景与 `world.tscn` headless 各跑 120/180 帧零 script error（2026-08-02 复验）
- 本机约束：**godot_mcp 未注册**（可见行为无法实机截图验证）；**superpowers/godot-prompter 技能未注册**（按同等纪律手动执行 SSD+TDD）

---

## 1. 已完成（✅，全部 TDD 落地）

| 包 | 内容 | 测试 |
|---|---|---|
| TP-01 | 骨架 + 5 autoload 冻结 + balance.json + GUT + run/validate 脚本 | UT-C09/UT-D08/IT-C01 |
| TP-02 | 10 个数据表 + 校验器（10 类检查） | UT-D01..07 |
| TP-03 | 三值/区域/昼夜（tick 注入式） | UT-C02/C03/C04 |
| TP-04 | 玩家控制器 + 交互 + 相机 + 照明逻辑 | IT-P01/02/03 |
| TP-05 | 字幕引擎 + `tip_layer` 渲染层（bubble/banner/warning） | UT-U01 + 渲染层 6 项 |
| TP-06 | 背包/发现集合 + `collectable` 采集物 + `inventory_panel` 背包界面 | UT-G02/G03、IT-G01 9 项、IT-U05 9 项 |
| TP-07 | 配方引擎 + `craft_panel` 合成台 + `card_popup` 卡片 | UT-G04/G07、IT-G05 14 项、IT-G06 6 项 |
| TP-08 | 氢气爆炸事件 + 表现层 | IT-G08/G09 |
| TP-09 | CO 幽灵/酸雾怪/八种道具效果 | IT-G10/G11、UT-G12 |
| TP-10 | 营地设施 ×6 + 粗盐提纯 | IT-G13/G14、IT-C05 |
| TP-11 | 死亡/复活/掉落包 | IT-C06 |
| TP-12 | HUD/主菜单/世界地图页/暂停菜单 | IT-C07/C08、IT-U03 |
| TP-13 | 学院四房间 + 聊天框 | IT-M01/M02 |
| TP-14 | 班主任调度链 | UT-M03..M06 |
| TP-15 | LLM 接入 + 离线兜底 + 配置面板 | UT-M08/M09、IT-M07/M10 |
| TP-16 | 图鉴 | IT-U04 |
| TP-17 | **白盒地图 + world.tscn 总装**（区域触发/采集生成与刷新/刷怪/掉落包/复活回床/昼夜 tint/睡觉渐黑/ui_manager/use_item 热键/河边引导/学院接入） | test_world.gd 16 项 |
| 主 Agent 补 | 导师问氢气 → 验纯解锁接线（关键词读 qa_fallback 表） | test_chat_purity_unlock.gd 3 项 |
| 批 1（A/B 缺口） | A1 碳口罩落地（items.json + 白盒试剂架标记 + 幽灵 AC5 免疫）、A5 电解器灌装氧气瓶、A3 矿洞 low_oxygen 点燃 + warn_co、A4 营地路牌开地图页、A2 学院门传送（D2）、B1 氧气 70 教程提示（sys_oxygen_tutorial）、B2 拾取音效挂载点、B3 unlock_tip 消费、B4 学院驱怪、B5/B6 字幕触发、B7 ViewLight 兜底纹理、B8 HUD 语义色、B9 SPEC-08 一行 | 目标文件全绿；全量 547/547 |
| 批 3（交付骨架） | D-2 README.txt、D-1 export_presets.cfg（windows_demo 嵌入 PCK Release）、D-3 docs/BUGS.md 台账 | 纯文档/配置 |
| 对标优化 包A（世界与玩家手感） | 暂停菜单真暂停、热键尊重 `input_blocked`、采集物漂浮 Tween 顺序、相机 `snap_to_target`、coyote time/jump buffer/下落重力倍数（@export）、区域触发器缝隙补齐、模态面板隐藏交互气泡、相机震动 juice、拾取音效延迟 free | 包内目标测试全绿 |
| 对标优化 包B（生存数值与玩法逻辑） | 装备前校验持有、extinguisher/soap_water 零效果修复、掉落包 leftover 保留、篝火每日限 3 次（`items.campfire_daily_limit`）、酸雾怪撞墙重锁定 + `monsters.acid_mist_lifetime_seconds`(200s) 出界自销毁 | 包内目标测试全绿 |
| 对标优化 包C（导师与界面文案） | offline 标记透传（`set_reply_provider` 兼容 `{text, offline}`）、氢气关键词缓存、once 字幕 `_shown` 移至开播（被 warning 抢占可重播）、打字机点击跳过、死亡界面三键丰富化（`death_info`/`death_day`/`death_hint`）、隐藏配置面板死 UI 滑块 | 包内目标测试全绿 |
| 对标优化 包D（数据内容与图鉴） | qa_fallback 扩充（monitor/think/assistant 各 3-5 条）、fail_messages 扩至 9 条分类轮换、物品/物质 `obtain` 来源字段 + 图鉴展示 | 包内目标测试全绿 |
| 对标优化 包E（HUD 与面板细节） | 血条受伤闪烁 Tween、面板互斥裁决收口 ui_manager（Esc 关最上面板）、背包占位纹理缓存 | 包内目标测试全绿 |
| Wave 2 收口（三代理并行） | W1 代码集成（爆炸震屏统一 B-034）、W2 nahco3 产出途径（B-031）、W3 文档同步（SPEC/SPEC-02/03/05、BUGS、WORKLOG、PLAN、plan/ 废弃标注） | W3：validate_data DATA OK + test_validator 全绿 |
| 审计修复批次（包A/B/C/D） | A1..A7 七项 spec 偏差修复 + spec 九册口径回写 + FR-G-16 入册 | 650/650 全绿、DATA OK |
| 面板自适应（FR-U-06） | 合成/背包/卡片模态面板由固定像素改为锚点比例铺开（宽 76%/70%/80%、高 60%/70%/70%）并居中；主菜单/暂停菜单按钮组中心锚点；死亡画面文案垂直中心锚点（IT-U06 6 项）；`project.godot` 显式补 `stretch/aspect=keep`，并恢复会话中被 Godot 进程改写丢失的 640×360 视口行（FR-C-01 AC1） | IT-U06 6 项全绿 + 全量回归 |

文档状态：SPEC-03 §9 变更记录已同步至 2026-08-02 全部批次；SPEC.md v1.2；SPEC-01 FR-G-10 增 AC5、FR-C-08 AC1 记 D2；SPEC-04 §10 effect 枚举增 immune_co；SPEC-05 §1/§3.2/§8、SPEC-02 §4.4/§5、SPEC-08 §6、SPEC-09 §3.1 已同步。

---

## 2. 裁决记录（已拍板，实现时同步进对应 spec 册）

| # | 日期 | 裁决 | 实现要点 |
|---|---|---|---|
| D1 | 2026-08-02 | 试剂三物（hcl/naoh/caoh2）营地试剂架可拾取 | **已落地**（substances.json zone=camp，SPEC-05 §1 已记） |
| D2 | 2026-08-02 | **主菜单「导师学院」门改为加载 world.tscn 并把玩家传送到学院门口**（用户拍板） | `main_menu.open_academy()` 导航目标仍为 world，需带"出生点=学院门口"参数；world 支持非默认出生点；SPEC-03 §9 与 TP-12 交付约定同步 |
| D3 | 2026-08-02 | **R3「缺氧」口径 = 矿洞内点燃即缺氧**（用户拍板） | craft_panel `ignite()` 在 `GameManager.current_zone()=="mine"` 时按 `low_oxygen` 匹配；矿洞外为 `ignite`；产出 CO 时应触发 `warn_co` 类警示；SPEC-05 §2 R3 行与 SPEC-02 §4.4 同步口径 |
| D4 | 2026-08-02 | **活性炭口罩**：主 Agent 裁——放营地试剂架可拾取（与 D1 同法，不改 12 条配方）；**氧气瓶**：电解器交互额外灌装 1 个（"氧气可以制备"，按 SPEC-02 §5 字面）；**葡萄糖**：不做来源（用户：食物恢复走篝火进食，葡萄糖不单独显示），items.json 条目保留（UT-G12 不破坏），来源登记赛后清单 | SPEC-05 §1 试剂裁决段与 SPEC-02 §5 道具表同步；电解器输出变化需同步 IT-G13 |
| D5 | 2026-08-02 | 死亡画面维持「任意键确认」，不加「回床按钮」 | 以 SPEC-01 FR-C-06 为准，改 SPEC-08 §6 描述 |
| D6 | 2026-08-02 | B1 氧气 70 教程提示**新增** `sys_oxygen_tutorial`（once banner），不复用 `sys_oxygen_low`——后者保留为 30 低氧反复警示，语义不混 | SPEC-05 §3.2 已增行；tips.json 51 条 |
| D7 | 2026-08-02 | `carbon_mask` 使用字幕复用 `sys_carbon`（`sys_mask` 已删，同为吸附原理）；幽灵 AC5 免疫以 SPEC-02 §4.1/SPEC-05 §8 为准，FR-G-10 增 AC5 | SPEC-05 §8、SPEC-01 已同步 |

---

## 3. 未完成清单（按优先级，每条含修复方案与涉及文件）

### A 级：阻断演示路径 —— ✅ 全部收口（2026-08-02 批 1）

A1 碳口罩来源、A2 学院门传送、A3 R3 低氧点燃、A4 营地路牌、A5 电解器灌装氧气瓶——全部 TDD 落地，见 §1「批 1」行与 SPEC-03 §9 变更记录。

### B 级：spec 依据的小缺口 —— ✅ 9/10 收口

B1 氧气 70 提示（D6 新增 sys_oxygen_tutorial）、B2 拾取音效挂载点、B3 unlock_tip 消费、B4 学院驱怪、B5 矿洞呼吸、B6 光合作用、B7 ViewLight 兜底、B8 HUD 语义色、B9 SPEC-08 一行、B10 中文像素字体（2026-08-02 引入 Fusion Pixel Font 12px 简体 OFL-1.1，`gui/theme/custom_font`，BUGS B-004 fixed）——全部落地，B 级 10/10 收口。

### C 级：CuSO₄ 池 / 灭火器剧情点（演示不需要，建议登记赛后或低成本补）

| # | 缺口 | 建议 |
|---|---|---|
| C1 | CuSO₄ 溶液池实体（5/s + `warn_cuso4`） | **2026-08-02 已升格为 FR-G-16**（P3 阶段补做项，SPEC-01 §5；BUGS B-001 已注明）：矿洞蓝色伤害区 Area2D（复用 zone_trigger 模式 + 每帧结算），回归脚本不涉及 |
| C2 | 灭火器火灾剧情点 | 进赛后清单（SPEC-07 §6 追加一行） |

### D 级：构建与交付（TP-18）

| # | 事项 | 负责/条件 |
|---|---|---|
| ~~D-1~~ | ✅ `export_presets.cfg` 已交付（windows_demo 嵌入 PCK Release → `build/ElementAlchemy.exe`） | 实际导出需本机装 Windows 导出模板（H0 就该装，现在立刻装） |
| ~~D-2~~ | ✅ `README.txt` 已按修正后 SPEC-09 §3.1 交付 | 素材授权段待 P4 的 CREDITS.md 填入 |
| ~~D-3~~ | ✅ `docs/BUGS.md` 台账已建（4 条 open 登记） | 随 bug bash 滚动更新 |
| D-4 | 实际导出 + 干净电脑验证（MT-B01/B03） | 需要本机 Godot + 导出模板 + 一台干净电脑 |
| D-5 | 演示视频 3 分钟 + PPT/讲稿（MT-B04，SPEC-09 §4/§5） | P5/P3 人工；AI 可代写讲稿与分镜字幕初稿 |

### E 级：美术与音频（SPEC-08，P4/P5）

- `assets/` 目录不存在：图标 ×17、导师立绘 ×8、像素小人 ×4、玩家/怪物 spritesheet、tile ×4 区、UI 面板、爆炸 6 帧、地图页底图、`placeholder.png`、`CREDITS.md`
- 音频：BGM ×3 + 关键音效 9 个 + `Master/BGM/SFX` 三条 bus（BGM -8dB）
- P0-6「第一批生成提示词已发出」未做（本是 H0 动作，SPEC-08 §4.2 提示词现成可直接发）
- 调色板终审（SPEC-08 §7 交付检查）

### F 级：验证缺口（不许拿代码推断冒充）

| # | 事项 | 条件 |
|---|---|---|
| F1 | godot_mcp 实机截图验证（HUD/字幕/爆炸/聊天框/地图/图鉴） | Claude Code 侧注册 MCP 服务器（`/mcp` 可见）后跑 |
| F2 | 真实 DeepSeek 往返一次 | 配 `user://config.cfg` key（MT-B02 同批） |
| F3 | SPEC-06 §8 全流程回归（含断网版）→ 勾 H8/H12 检查点 | A 级修完后人工跑 |
| F4 | NFR-01 帧率（演示机 60 FPS） | 实机 |
| F5 | MT-M10 配置面板手工项 | 实机 |
| F6 | 主菜单图鉴门显示空收集（codex 独立场景自建空 Discovery） | ✅ fixed（2026-08-02 包A/C）：`SESSION_DISCOVERY_META` 会话共享——codex_panel 经树根元数据共享 Discovery 实例，主菜单门与游戏内进度一致 |

---

## 4. 下个批次开工单（建议顺序，按依赖排）

1. ~~批 1（玩法补全）~~ ~~批 2（视觉兜底）~~ ~~批 3（交付骨架）~~ —— ✅ 2026-08-02 全部收口，547/547 全绿 + DATA OK + 双场景冒烟零错。
2. **批 4（人工为主）**：E 级美术（SPEC-08 §4.2 提示词现成可直接发）→ B10 字体兜底 → F2 联网验证 DeepSeek（配 key）→ F3 全流程回归勾 H8/H12 → F4/F5 实机项 → D-4 导出验证 → D-5 视频/PPT（AI 可代写讲稿与分镜字幕初稿）。
3. **可选低成本**：~~C1 CuSO₄ 伤害池~~（2026-08-02 已升格为 FR-G-16，P3 阶段补做项）。

**收工校验**：`./validate_data.sh` DATA OK + `./run_tests.sh` 全绿 + 两场景冒烟零错 + 同步 SPEC.md Checklist 与 SPEC-03 §9，然后才许提交。

---

## 5. 变更记录

| 日期 | 内容 |
|---|---|
| 2026-08-02 | 建日志：快照 TP-01..17 + 补包全部落地（514 测试全绿），登记 A/B/C/D/E/F 六级缺口与 D1..D5 裁决 |
| 2026-08-02 | 批 1（A1..A5+B1..B9，4 子 Agent 并行 + A2 串行）与批 3（D-1/2/3）收口：547/547 全绿、DATA OK、双场景冒烟零错；新增裁决 D6/D7；顺手修三个既有红（recipes 物理排序断言、validator 配方计数、交易能量时序断言）；SPEC 同步至 v1.2 |
| 2026-08-02 | 对标优化批次（docs/PLAN-benchmark-optimization.md）：Wave 1 五包 27 项修复与增强落地（包A 手感 9 项 / 包B 数值逻辑 5 项 / 包C 导师与文案 6 项 / 包D 数据与图鉴 3 项 / 包E HUD 与面板 3 项，另含包C 契约配套）；Wave 2 三收口代理并行（W1 代码集成、W2 nahco3 产出、W3 文档同步）。BUGS.md 登记 B-005..B-030 已修复、B-031..B-038 新发现（2 修复中、2 open、4 记赛后清单）；SPEC 同步至 v1.3 |
| 2026-08-02 | 五路并行审计 + 包D「spec 文档回写」（以码为准，只改文档）：配方 12 / tips 51 / qa_fallback 34 / fail_messages 9 条数全册对齐；新增 FR-G-16 CuSO₄ 溶液池（B-001 升格，54→55 条 FR，P1/IT-G16，P3 阶段补做）；SPEC-02 `night_tint`→`night_brightness`；FR-M-05 AC1 改按 SPEC-03 口径（≤3 条）；FR-M-10 AC2 按 B-024 裁决（隐藏死 UI 滑块 + config_note）；SPEC-05 §5 补登 9 条 qa、§2 失败池补全 9 条并标注 fail_copper_acid 彩蛋；SPEC-07 §6 收录七条对标大件（赛后清单输出 ✅）；B-035..B-038 转赛后清单；BUGS.md 登记 B-039..B-045（审计 7 项代码偏差，包A/B/C 修复中）；测试基线 547→610；SPEC 同步至 v1.4，SPEC-03 §9 为包A/B/C 预留四行占位 |
| 2026-08-02 | 包E3「文档收口」（只改文档，同步到与代码一致）：BUGS.md B-039..B-045 七条标 fixed 并补修复摘要；SPEC-03 §9 四行占位展开为正式变更记录 + 补 config 面板注册与 ui_strings 两键两行；SPEC-05 §9 补登 `config_apply`/`chat_config`；SPEC-01 FR-M-10 AC1 补游戏内入口；§1 追加审计修复批次行；F6 标 fixed；测试基线 610→650；SPEC 同步至 v1.6 |
