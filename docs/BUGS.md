# BUGS 台账｜《元素炼金物语》MVP

> 格式依据 `docs/SPEC-06-测试计划.md` §9。
> 严重度：`P0` 阻塞演示（必修）｜`P1` 影响体验（H14 前修）｜`P2` 瑕疵（有空再修）。
> **H18 前 P0/P1 必须清零**；P2 允许带着上场，但要写进演示话术回避。
> 条目来源：`docs/WORKLOG.md` §3 未完成清单。

| ID | 严重度 | 模块 | 现象 | 复现步骤 | 责任人 | 状态 |
|---|---|---|---|---|---|---|
| B-001 | P2 | gameplay | CuSO₄ 溶液池实体未做：矿洞无蓝色伤害区，无 5/s 伤害与 `warn_cuso4` 字幕 | 进入矿洞，全场无 CuSO₄ 池（WORKLOG §3 C1） | P2 | open（2026-08-02 已升格为正式需求 FR-G-16，SPEC-01 §5 / §12、SPEC-06 §6 已登记） |
| B-002 | P2 | gameplay | 灭火器火灾剧情点未做，已登记赛后清单 | 全流程无该剧情点（WORKLOG §3 C2） | P2 | open |
| B-003 | P2 | ui | 主菜单「图鉴」门进入后显示空收集（codex 独立场景自建空 Discovery，不共享游戏内收集进度） | 主菜单 → 图鉴门，图鉴网格为空（WORKLOG §3 F6，已知限制，MVP 接受） | P2 | ✅ fixed 2026-08-02：SESSION_DISCOVERY_META 会话共享 Discovery（包C） |
| B-004 | P1 | ui | 中文像素字体未配置，界面中文走引擎默认字体渲染 | 任意含中文的界面（HUD/字幕/面板）（WORKLOG §3 B10，依赖 P4 字体资产） | P4 | ✅ fixed 2026-08-02：引入 Fusion Pixel Font 12px 简体（OFL-1.1），配置为 gui/theme/custom_font，署名见 assets/CREDITS.md |

## Wave 1 对标优化修复登记（2026-08-02，详见 docs/PLAN-benchmark-optimization.md）

> 以下 26 条为 Wave 1 五包（包A~包E）修复的问题，均已 TDD 落地、相关测试全绿；状态列注明修复日期与简述。

| ID | 严重度 | 模块 | 现象 | 复现步骤 | 责任人 | 状态 |
|---|---|---|---|---|---|---|
| B-005 | P1 | main | 暂停菜单非真暂停，世界仍在跑 | 游戏中呼出暂停菜单，怪物/昼夜继续推进 | 包A | ✅ fixed 2026-08-02：`get_tree().paused` + 菜单 `process_mode=ALWAYS` |
| B-006 | P1 | main | 快捷栏/热键不尊重 `input_blocked`，面板打开时仍能切快捷栏/用道具 | 打开背包后按 1-8 热键 | 包A | ✅ fixed 2026-08-02：热键入口检查 `input_blocked` |
| B-007 | P2 | gameplay | 采集物漂浮 Tween 生成顺序 bug：生成瞬间被拉回 Y=0 | 观察新生成采集物第一帧位置 | 包A | ✅ fixed 2026-08-02：修正 Tween 建立与初始位置的先后顺序 |
| B-008 | P2 | player | 复活/传送后相机未复位平滑，画面瞬移拖拽 | 死亡复活或学院门传送后观察相机 | 包A | ✅ fixed 2026-08-02：`snap_to_target()` 传送后收敛平滑 |
| B-009 | P2 | player | 无 coyote time / jump buffer / 下落重力倍数，跳跃手感僵硬 | 平台边缘起跳、落地前按跳 | 包A | ✅ fixed 2026-08-02：三者均以 @export 参数落地 |
| B-010 | P1 | main | world.tscn 区域触发器存在缝隙（草原↔营地↔矿洞），穿过时区域判定丢失 | 在两区交界处走动看 `zone_changed` | 包A | ✅ fixed 2026-08-02：触发器缝隙补齐 |
| B-011 | P2 | ui | 模态面板打开时交互提示气泡（按 E）仍显示 | 走近采集物同时打开背包 | 包A | ✅ fixed 2026-08-02：模态面板打开时隐藏交互提示气泡 |
| B-012 | P2 | player | 受伤/爆炸无相机震动，缺 juice 反馈 | 受击或触发氢气爆炸观察画面 | 包A | ✅ fixed 2026-08-02：`player_camera.shake(intensity, duration)` |
| B-013 | P2 | gameplay | 拾取音效节点立即 free，声音播不出来 | 拾取采集物听音效 | 包A | ✅ fixed 2026-08-02：音效播放完毕后延迟 free |
| B-014 | P0 | gameplay | 隔空装备漏洞：装备前未校验持有，可装备背包里没有的道具 | 直接调用装备接口传入未持有 id | 包B | ✅ fixed 2026-08-02：装备前校验背包持有 |
| B-015 | P1 | gameplay | extinguisher/soap_water 消耗了但零效果 | 对目标使用灭火器/肥皂水 | 包B | ✅ fixed 2026-08-02：两效果按 `effect_value_key`/目标判定补齐 |
| B-016 | P1 | gameplay | 掉落包 leftover 丢失物品：替换语义下未被捡走的物品凭空消失 | 连续死亡两次再回第一个死亡点 | 包B | ✅ fixed 2026-08-02：leftover 合并/保留逻辑修正 |
| B-017 | P1 | gameplay | 篝火无限免费进食，能量经济失效 | 篝火旁反复进食 | 包B | ✅ fixed 2026-08-02：每日限 3 次（`balance.json items.campfire_daily_limit`） |
| B-018 | P1 | gameplay | 酸雾怪撞墙后不重锁定、出界不自销毁，越积越多 | 引酸雾怪撞墙观察后续行为 | 包B | ✅ fixed 2026-08-02：撞墙重锁定 + 存活上限 `monsters.acid_mist_lifetime_seconds`(200s) 出界自销毁 |
| B-019 | P1 | mentor | 导师回复 offline 标记不透传，离线角标漏显 | 断网提问，回复无「（离线模式）」角标 | 包C | ✅ fixed 2026-08-02：`set_reply_provider` 兼容 `{text, offline}`，offline 随回答来源透传（chat_panel 渲染侧见 B-032） |
| B-020 | P2 | mentor | 氢气关键词判定逐消息读盘 IO | 连续发送多条提问观察磁盘读取 | 包C | ✅ fixed 2026-08-02：关键词缓存 |
| B-021 | P1 | ui | once 字幕被 warning 顶掉后永久丢失（入队即标记 `_shown`） | 区域横幅排队中触发 warning，再回该区域 | 包C | ✅ fixed 2026-08-02：`_shown` 移至开播 `_start()` 标记，被抢占的 once 可重播（SPEC-03 §9 已记） |
| B-022 | P2 | mentor | 聊天打字机不可点击跳过，长回复只能干等 | 导师回复中点击聊天框 | 包C | ✅ fixed 2026-08-02：点击跳过打字机直接显示全文 |
| B-023 | P2 | ui | 死亡界面信息单薄，无损失说明/复活提示 | 死亡后看死亡画面 | 包C | ✅ fixed 2026-08-02：新增 ui_strings 三键 `death_info`/`death_day`/`death_hint`（SPEC-05 §9 已登记） |
| B-024 | P2 | mentor | 配置面板性格滑块是死 UI，误导玩家 | 打开配置面板拖滑块 | 包C | ✅ fixed 2026-08-02：隐藏死 UI 性格滑块（`config_note` 明示赛后可配置） |
| B-025 | P2 | mentor | qa_fallback 条数不足，离线时 monitor/think/assistant 人设易崩 | 断网问各类问题看兜底重复率 | 包D | ✅ fixed 2026-08-02：monitor/think/assistant 各扩 3-5 条 |
| B-026 | P2 | gameplay | fail_messages 分类轮换不足，同类失败文案重复 | 连续两次同类合成失败 | 包D | ✅ fixed 2026-08-02：扩至 9 条分类轮换（no_match 5 + wrong_condition 4） |
| B-027 | P2 | ui | 物品/物质缺 obtain 来源字段，图鉴不展示来源 | 打开图鉴看卡片 | 包D | ✅ fixed 2026-08-02：substances/items 全量补 `obtain` 字段 + 图鉴展示 |
| B-028 | P2 | ui | 血条受伤无闪烁反馈（对标 player_ui.hurt_effect） | 受伤观察血条 | 包E | ✅ fixed 2026-08-02：受伤闪烁 Tween |
| B-029 | P1 | ui | 面板可叠开，Esc 无互斥裁决 | 连续打开背包+图鉴+地图页 | 包E | ✅ fixed 2026-08-02：互斥裁决收口 ui_manager，Esc 关最上面板 |
| B-030 | P2 | ui | 背包占位纹理每次重建，重复加载 | 反复开关背包看资源创建 | 包E | ✅ fixed 2026-08-02：占位纹理缓存 |

## Wave 1 新发现登记（2026-08-02，各包施工报告）

| ID | 严重度 | 模块 | 现象 | 复现步骤 | 责任人 | 状态 |
|---|---|---|---|---|---|---|
| B-031 | P1 | gameplay | `nahco3`（碳酸氢钠）无任何产出途径，R10 灭火器配方材料不可达 | 查 recipes.json：R10 消耗 nahco3，无一条配方/采集产出它 | W2 收口代理 | ✅ 已修复（2026-08-02：whitebox_map 新增 SpawnNahco3 营地试剂架采集标记，obtain 已更新） |
| B-032 | P1 | mentor | chat_panel 契约未补齐：mentor_router 已透传 `offline` 标记（B-019），但聊天框未消费渲染离线角标 | 断网提问，聊天框无「（离线模式）」标识 | 主 Agent | ✅ 已关闭（2026-08-02 核实为误报：`llm_client._offline_reply` 已在回复文本附加「（离线模式）」角标；router offline 标记透传已由包C落地） |
| B-033 | P1 | ui | DeathScreen Esc 裁决缺失：死亡画面「任意键复活」吞掉 Esc，与暂停菜单/ui_manager 的 Esc 语义冲突 | 死亡画面按 Esc，直接复活而非打开暂停 | W1 收口代理 | ✅ 已修复（2026-08-02：ui_manager `_death_visible()` 吞 Esc + death_screen 纵深防御，Esc 不再算「任意键复活」） |
| B-034 | P2 | gameplay | 爆炸震屏两套并存：`explosion.gd` 直改 `camera.offset`，与 `player_camera.shake()` 未统一 | 对比受伤震屏与爆炸震屏实现路径 | W1 收口代理 | ✅ 已修复（2026-08-02：explosion.gd 改调相机 `shake()` 统一出口） |
| B-035 | P2 | gameplay | 酸雾怪顶墙局限：冲到天花/高墙后行为受限，无绕行（MVP 不做寻路的代价） | 引酸雾怪撞高墙观察 | — | 已转赛后清单（SPEC-07 §6，2026-08-02） |
| B-036 | P2 | data | `wrong_tool` 失败文案类不存在于 schema：fail_messages 扩表后 reason 分类与校验 schema 未完全对齐 | 对照 fail_messages.json 与 validate 规则 | — | 已转赛后清单（SPEC-07 §6，2026-08-02） |
| B-037 | P2 | data | `h2`/`co` 的 zone 字段（camp/mine）与采集标记语义不符：二者实为反应产物而非野外采集物 | 对照 substances.json zone 与实际获取途径 | — | 已转赛后清单（SPEC-07 §6，2026-08-02） |
| B-038 | P2 | ui | 道具类条目图鉴无格子：图鉴仅 17 格物质卡，items（道具/材料）无展示位 | 打开图鉴，找不到硫火把等道具卡 | — | 已转赛后清单（SPEC-07 §6，2026-08-02） |

## 五路并行审计新发现登记（2026-08-02，代码偏差，详见 WORKLOG §5）

| ID | 严重度 | 模块 | 现象 | 复现步骤 | 责任人 | 状态 |
|---|---|---|---|---|---|---|
| B-039 | P1 | gameplay | 提纯卡片不弹（A1）：粗盐提纯三步完成后不弹知识卡片 | 实验台完成溶解→过滤→蒸发 | 包A | ✅ fixed 2026-08-02：facility_bench 新增 card_ready 信号，world 接到 CardPopup（recipes.json R11 文案） |
| B-040 | P1 | mentor | 离线调度语死路（A2）：离线模式下班主任调度语路径不可达/断裂 | 断网提问，观察班主任首接回复 | 包B | ✅ fixed 2026-08-02：离线时 monitor 首条恒用 dispatch line 调度语，qa 答案只由被派导师输出 |
| B-041 | P1 | ui | ConfigPanel 不可达（A3）：配置面板无任何入口可打开 | 游戏内寻找 API key 配置入口 | 包C | ✅ fixed 2026-08-02：academy.tscn 实例化 + 聊天框底栏「设置」按钮，经 ui_manager 模态裁决 |
| B-042 | P2 | ui | 出生区横幅不触发（A4）：出生在草原时 `zone_grass` 横幅不播（首次触发依赖跨区域边界） | 新开局直接观察出生点 | 包A | ✅ fixed 2026-08-02：game_manager._zone 初值改空串，首次定位与同区去重解耦 |
| B-043 | P2 | gameplay | 肥皂水随地可用（A5）：`soap_water` 对任意位置使用都消耗并播硬水字幕，未限定湖水目标 | 在草原/营地对空气使用肥皂水 | 包B | ✅ fixed 2026-08-02：仅 saltlake 区域生效，他处 wrong_place 不消耗 |
| B-044 | P2 | ui | 点燃按钮恒可见（A6）：合成界面未持有 H₂ 时「点燃」按钮也显示 | 背包无 H₂ 打开合成台 | 包B | ✅ fixed 2026-08-02：can_ignite() 按 H₂ 显隐，默认隐藏 |
| B-045 | P2 | gameplay | 彩蛋文案混池（A7）：`fail_copper_acid` 混入通用 `no_match` 轮转池，非铜+酸组合也会刷出 | 连续触发 no_match 失败观察文案 | 包B | ✅ fixed 2026-08-02：fail_copper_acid 移出通用轮转，仅 cu+hcl 确定性触发 |
