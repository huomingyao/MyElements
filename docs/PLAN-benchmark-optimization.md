# 对标优化实施计划（2D-Mining-Sandbox 对标 + 现存问题修复）

> 依据 6 路并行调研报告（docs/scripts/scenes/ui-data/对标玩法架构/对标表现层）。
> 原则：MVP 功能冻结不加新大系统；区块化挖矿/熔炉实体/材质声音矩阵等对标大件记入赛后清单；
> 本计划聚焦 **真实 bug 修复 + 手感/Juice 对标 + 内容数据补厚 + 文档同步**。

**进度总览（2026-08-02 更新）**：Wave 1 五包 ✅ 全部落地（代码/数据已提交工作区，各包目标测试全绿）；Wave 2 收口进行中——包F 文档同步 ✅（SPEC 至 v1.3），W1 爆炸震屏统一（BUGS B-034）与 W2 nahco3 产出途径（BUGS B-031）施工中，赛后清单输出 ✅（包D spec 回写，SPEC-07 §6 已收录七条对标大件），全量回归待收口代理汇合后执行。Wave 1 新发现 8 条已登记 BUGS.md B-031..B-038（4 条记赛后清单）。

## Wave 1 — 五个并行实施包（文件零重叠）✅ 已完成（2026-08-02）

### 包A「世界与玩家手感」✅ 9/9 完成
文件：scenes/main/world.gd、world.tscn、pause_menu.tscn、scenes/player/player.gd、player.tscn、player_camera.gd、scenes/gameplay/collectable.gd + 对应测试
1. ✅ 暂停菜单真暂停（get_tree().paused + process_mode=ALWAYS）（BUGS B-005）
2. ✅ 快捷栏/热键尊重 input_blocked（B-006）
3. ✅ 采集物漂浮 Tween 拉回 Y=0 的生成顺序 bug（B-007）
4. ✅ 复活/传送后相机 reset_smoothing（snap_to_target，B-008）
5. ✅ 手感：coyote time / jump buffer / 下落重力倍数（@export 参数）（B-009）
6. ✅ world.tscn 区域触发器缝隙补齐（草原↔营地↔矿洞）（B-010）
7. ✅ 模态面板打开时隐藏交互提示气泡（B-011）
8. ✅ 相机震动（受伤/爆炸，对标 juice，超越点——对标项目没有）（B-012；爆炸震屏统一收口见 B-034，W1 施工中）
9. ✅ 拾取音效延迟 free（B-013）

### 包B「生存数值与玩法逻辑」✅ 5/5 完成
文件：scripts/gameplay/item_effects.gd、scenes/gameplay/drop_bag.gd、facility_campfire.gd、monster_acid_mist.gd、data/balance.json + 对应测试
1. ✅ 装备前校验持有（隔空装备漏洞）（BUGS B-014）
2. ✅ extinguisher/soap_water 消耗但零效果漏洞（B-015）
3. ✅ 掉落包 leftover 丢失物品 bug（B-016）
4. ✅ 篝火无限免费进食 → 每日限次（balance.json `items.campfire_daily_limit`=3，SPEC-02 §4.1 已同步）（B-017）
5. ✅ 酸雾怪撞墙重锁定 + 出界自销毁（`monsters.acid_mist_lifetime_seconds`=200，SPEC-02 §4.6 已同步）（B-018；顶墙局限记赛后清单 B-035）

### 包C「导师与界面文案」✅ 6/6 完成
文件：scripts/mentor/mentor_router.gd、scripts/gameplay/hydrogen_event.gd、scripts/autoload/knowledge_tip.gd、scenes/mentor/chat_panel.gd、scenes/ui/death_screen.gd/.tscn、scenes/mentor/config_panel.tscn、data/ui_strings.json + 对应测试
1. ✅ 导师回复 offline 标记透传（离线角标漏显）（BUGS B-019；chat_panel 渲染侧契约补齐登记 B-032）
2. ✅ 氢气关键词逐消息磁盘 IO → 缓存（B-020）
3. ✅ once 字幕被 warning 顶掉后永久丢失 → _shown 移至 _start（B-021；SPEC-03 §9 已记）
4. ✅ 聊天打字机点击跳过（B-022）
5. ✅ 死亡界面丰富化（复活提示/损失说明，ui_strings 新增 `death_info`/`death_day`/`death_hint`，SPEC-05 §9 已登记）（B-023；Esc 裁决登记 B-033）
6. ✅ 隐藏配置面板死 UI 性格滑块（B-024）

### 包D「数据内容与图鉴」✅ 3/3 完成
文件：data/qa_fallback.json、fail_messages.json、items.json、substances.json、scenes/ui/codex_cell.gd、codex_panel.gd + tests/data
1. ✅ qa_fallback 扩充（monitor/think/assistant 各 3-5 条，离线人设不崩）（BUGS B-025）
2. ✅ fail_messages 扩至 9 条分类轮换（no_match 5 + wrong_condition 4）（B-026；wrong_tool 类与 schema 对齐问题记赛后清单 B-036）
3. ✅ 物品/物质 obtain 来源字段 + 图鉴展示（B-027；nahco3 产出途径 W2 施工中 B-031；道具类图鉴格子记赛后清单 B-038）

### 包E「HUD 与面板细节」✅ 3/3 完成
文件：scenes/main/hud.gd、ui_manager.gd、scenes/ui/inventory_panel.gd + 对应测试
1. ✅ 血条受伤闪烁 Tween（对标 player_ui.hurt_effect）（BUGS B-028）
2. ✅ 面板互斥裁决收口 ui_manager（Esc 关最上面板，防叠开；不动 world.gd）（B-029；DeathScreen Esc 语义裁决登记 B-033）
3. ✅ 背包占位纹理缓存（B-030）

## Wave 2 — 串行收口（进行中，2026-08-02）
- ✅ 包F「文档同步」（本批 W3 收口代理执行）：SPEC.md 状态行更正（v1.3）、SPEC-02 §4.10 tips 条数 47→51、BUGS.md 更新（B-005..B-038）、SPEC-03 §9 变更记录补记（once 标记时机 / warning 打断 banner 回写 / set_reply_provider {text,offline} 扩展 / reply_chunk 不发射 / worldmap 静态解锁）、SPEC-05 §9 补登 death_* 三键、WORKLOG 追加、plan/ 四份草案标注废弃
- ⏳ 全量回归：run_tests.sh 全绿 + validate_data.sh DATA OK（待 W1/W2 收口汇合后执行；W3 侧 validate_data + test_validator 已验证，见 WORKLOG）
- ⏳ W1 代码集成收口：爆炸震屏统一（B-034 修复中）
- ⏳ W2 数据收口：nahco3 产出途径补齐（B-031 修复中）
- ✅ 赛后清单输出：区块挖矿/熔炉实体/材质声音矩阵/粒子颜色数据驱动/声明式设置系统/Tag 资源分类/组件库沉淀七条已追加 SPEC-07 §6 停车场（每条含价值与 MVP 不做原因）；B-035..B-038 四条新发现已在 BUGS.md 标注「已转赛后清单」（2026-08-02 包D spec 回写）

## 通用约束（每包必守）
- 文件白名单外一律不改；不改 SPEC-03 冻结接口；不创建 git commit
- TDD：先改/加测试（RED）→ 实现（GREEN）→ 回归（REFACTOR）
- 静态类型、无魔法数字（调参进 balance.json 或 @export）、无硬编码中文（走 ui_strings.json）
- 改完必跑：`./run_tests.sh -gtest=<相关测试>` 至少相关测试全绿
