# SPEC-06｜测试计划（TDD 约定）

> 本文件定义"怎么证明它是对的"。每条 FR 至少一个自动化测试；测试编号与 FR 一一对应。
> **RED → GREEN → REFACTOR 顺序不许颠倒**：先写测试并看到它按预期失败，再写实现。

---

## 1. 测试栈与运行方式

| 项 | 选择 |
|---|---|
| 框架 | GUT（Godot Unit Test），装到 `addons/gut/` |
| 目录 | `tests/unit/`（纯逻辑）、`tests/integration/`（场景交互）、`tests/data/`（数据表校验） |
| 命名 | 文件 `test_<模块>.gd`；方法 `test_<行为>_<期望>()` |
| 运行 | headless，见下 |

**headless 运行命令**（Windows / Git Bash）：

```bash
# 全部测试
"C:/path/to/Godot_v4.6.3-stable_win64.exe" --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit

# 只跑单元测试
"...Godot.exe" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit

# 只跑一个文件
"...Godot.exe" --headless --path . -s addons/gut/gut_cmdln.gd \
  -gtest=res://tests/unit/test_recipe_db.gd -gexit

# 数据表校验（独立于 GUT）
"...Godot.exe" --headless --path . -s scripts/tools/validate_data.gd
```

约定：P1 在 H1 把上述命令封成 `run_tests.sh` 与 `validate_data.sh`，之后所有人只敲脚本名。

---

## 2. TDD 循环的可操作定义

每个任务包（[SPEC-07 §4](SPEC-07-实施计划与Agent派活.md)）都按这个走：

1. **读 FR** — 拿到 FR-ID 与 AC 列表。
2. **RED** — 为每条 AC 写一个测试方法；跑一遍，确认**断言失败**（不是脚本报错、不是找不到文件）。这一步没看到红色就不算 RED。
3. **GREEN** — 写最少的实现让测试变绿。不顺手重构、不提前抽象。
4. **REFACTOR** — 清理命名与重复；再跑**全量**测试确认没弄坏别的。
5. **报告** — 输出：改了哪些文件 / 跑了什么命令 / 通过多少条 / 哪条 AC 没能自动化验证（说明原因）。

**不允许的做法**：
- 先写实现再补测试（这不是 TDD，是补作业）。
- 用 `pass` 空测试占位换绿。
- `assert_true(true)` 之类的假测试。
- 为了让测试通过而修改 AC（AC 要改必须先改 [SPEC-01](SPEC-01-需求与验收.md) 并说明理由）。

---

## 3. 可测性设计约束（这是能 TDD 的前提）

| 约束 | 原因 |
|---|---|
| 纯逻辑与场景分离：`MentorRouter`、`RecipeDB` 匹配逻辑、`qa_fallback` 匹配、背包结算、数值结算全部是**可独立实例化的类**，不依赖 `get_tree()` | 单测能直接 `new()` 出来跑 |
| 时间可注入：昼夜与三值消耗接受 `delta` 参数推进，不直接读 `Time` | 测试可以一次推进 600 秒 |
| 网络可替换：`LLMClient._generate_reply()` 是唯一网络出口，测试用 stub 替换 | 测试不发真实请求、不烧 token |
| 随机可控：失败文案轮换用确定性轮转（计数取模），不用 `randi()` | 结果可复现 |
| 数据可注入：各 DB 类支持 `load_from(array)` 喂假数据 | 不依赖真实数据表的完整度 |
| 配置可覆盖：`balance.json` 的值在测试中可被覆写 | 超时 8 秒在测试里调成 0.1 秒 |

**违反可测性约束的代码视为未完成**，即使功能能跑。

---

## 4. 单元测试清单（tests/unit/ + tests/data/）

### 4.1 核心系统

| 编号 | FR | 文件 | 关键断言 |
|---|---|---|---|
| UT-C02 | FR-C-02 | `test_game_manager_stats.gd` | 三值上限/初值；三个信号参数正确；氧气归零后生命按 5/s 掉；能量归零速度倍率 0.5；生命归零发一次 `player_died`（同帧多次伤害不重复发） |
| UT-C03 | FR-C-03 | `test_game_manager_zone.gd` | `current_zone()` 返回正确；重复 `set_zone` 不发信号；五区域氧气速率与 balance 表一致；首次进入触发一次区域字幕 |
| UT-C04 | FR-C-04 | `test_daynight.gd` | 推进 360s 进夜、再 180s 回昼；`day_started/night_started` 各一次；`day_count` 递增；清晨发 `resources_respawned`；时长读自 balance |
| UT-C09 | FR-C-09 | `test_autoload_contract.gd` | 五个 autoload 存在；[SPEC-03](SPEC-03-系统与接口契约.md) 列出的每个方法名存在且参数数量一致（反射断言） |
| UT-D08 | FR-D-08 | `test_balance.gd` | SPEC-02 §4 每个参数键存在；缺键返回默认值 + 警告不崩溃；`debug.*` 默认 false |

### 4.2 玩法

| 编号 | FR | 文件 | 关键断言 |
|---|---|---|---|
| UT-G02 | FR-G-02 | `test_inventory.gd` | 堆叠到 99 后溢出新格；背包满时返回未装入数量；`remove_item` 数量不足返回 false 且状态不变；8 格快捷栏边界 |
| UT-G03 | FR-G-03 | `test_discovery.gd` | 重复拾取只计一次；`is_discovered` 正确；计数集合恰好 16（`co2` 不计入） |
| UT-G04 | FR-G-04 | `test_recipe_db.gd` | **12 条配方逐条正例 + 至少一反例**；材料顺序无关；`wrong_condition` 与 `no_match` 区分正确；`requires_pure_check` 未解锁时返回 `needs_purity_check`；返回字典字段齐全；无歧义三元组 |
| UT-G07 | FR-G-07 | `test_fail_messages.gd` | 三类失败文案不混用；连续两次同类失败文案不同（确定性轮转） |
| UT-G12 | FR-G-12 | `test_items.gd` | 每个道具效果值读自 balance；装备型不消耗、消耗型 -1；氧气瓶 +50、活性炭砸幽灵 |

### 4.3 导师

| 编号 | FR | 文件 | 关键断言 |
|---|---|---|---|
| UT-M03 | FR-M-03 | `test_input_sanitize.gd` | >200 字符被截断；控制字符与换行被清理；空输入不发起请求 |
| UT-M04 | FR-M-04 | `test_mentor_router_classify.gd` | 四类各 ≥3 个样例判定正确；**混合样例按 combat→learning→chemistry→other 优先级归类**；`route_targets` 映射正确（learning 返回两位） |
| UT-M05 | FR-M-05 | `test_mentor_router_flow.gd` | 首条消息 `mentor_id=="monitor"`；返回长度 ≤3；非 monitor 消息中的 @ 被忽略；构造循环 @ 不递归不卡死；调度计数硬上限 1 |
| UT-M06 | FR-M-06 | `test_mentor_prompts.gd` | 代码中无人设字符串（grep 式扫描 `scripts/`）；三位非班主任 prompt 含"绝不出现 @"；通用后缀被拼接 |
| UT-M08 | FR-M-08 | `test_llm_fallback.gd` | 四种失败（超时/网络错/非 200/畸形 body）都走兜底且不抛异常；重试 1 次；离线回答含「（离线模式）」；手动开关立即生效 |
| UT-M09 | FR-M-09 | `test_qa_fallback.gd` | 命中数最多者胜；**平票取表中先出现者**；零命中返回班主任话术；离线与联网用同一分类器 |

### 4.4 UI 与字幕

| 编号 | FR | 文件 | 关键断言 |
|---|---|---|---|
| UT-U01 | FR-U-01 | `test_knowledge_tip.gd` | 三种 style 的时长正确；不存在的 id 不崩溃且有警告；队列串行不重叠；`warning` 可打断 `bubble`；`show_once` 只显示一次 |

### 4.5 数据表（tests/data/）

| 编号 | FR | 文件 | 关键断言 |
|---|---|---|---|
| UT-D01 | FR-D-01 | `test_data_substances.gd` | 17 条记录、id 唯一；HUD 计数集合恰好 16；`category` 在枚举内；`tip_id` 在 tips 表存在；icon 路径存在 |
| UT-D02 | FR-D-02 | `test_data_recipes.gd` | 12 条、id 唯一；有且仅有一条 `requires_pure_check`；`tool`/`condition` 枚举合法；inputs/outputs 可解析；三元组无歧义 |
| UT-D03 | FR-D-03 | `test_data_tips.gd` | id 唯一；style 枚举；文案非空；SPEC-05 §3 列出的每个 id 存在 |
| UT-D04 | FR-D-04 | `test_data_mentors.gd` | 恰好 4 条且 id 集合正确；必填字段齐全；monitor prompt 含三个 @ 关键字；其余三位含"绝不出现 @" |
| UT-D05 | FR-D-05 | `test_data_qa.gd` | ≥20 条（当前 34 条）；keywords/answer 非空（兜底行 `qa_no_match` 的 keywords 允许为空）；涉及反应的答案含方程式（含 `=` 或 `→`） |
| UT-D06 | FR-D-06 | `test_data_worldmap.gd` | 13 条；恰好 5 条 unlocked；解锁项 brief 非空、未解锁项 teaser 非空；热区不越出 640×360 |
| UT-D07 | FR-D-07 | `test_validator.gd` | 喂入 10 类坏数据（见 [SPEC-04 §12](SPEC-04-数据模型.md)）逐类必须报错；好数据退出码 0 |

**单元测试合计 24 个文件**（核心 5 + 玩法 5 + 导师 6 + UI 1 + 数据表 7）。这批测试必须能在 headless 下 10 秒内跑完（跑得慢就没人跑）。

---

## 5. 集成测试清单（tests/integration/）

集成测试用 GUT 的场景加载 + 输入模拟；涉及肉眼可见效果的用 `godot_mcp` 截图补充人工确认。

| 编号 | FR | 关键验证 |
|---|---|---|
| IT-C01 | FR-C-01 | 主场景加载零 ERROR；视口 640×360；七个输入动作存在 |
| IT-C05 | FR-C-05 | 床交互后 `is_night()` 为 false、`day_count`+1、生命满、采集物恢复、`sys_sleep` 触发 |
| IT-C06 | FR-C-06 | 生命归零 → 死亡画面 → 床复活；掉落包含死亡时全部物品；拾取后数量一致；下次死亡前掉落不消失 |
| IT-C07 | FR-C-07 | 三条数值条随信号更新（非轮询）；计数显示正确；氧气 <30 闪烁且触发一次字幕 |
| IT-C08 | FR-C-08 | 三个门分别加载正确场景；Esc 暂停可回主菜单；加载 ≤3 秒 |
| IT-P01 | FR-P-01 | 移动/跳跃/落地不抖不穿墙；能量归零速度 ×0.5；参数读自 balance |
| IT-P02 | FR-P-02 | 提示气泡进出范围正确；多目标取最近；新交互物不改玩家代码即可识别 |
| IT-P03 | FR-P-03 | 相机不越界；持火把视野半径变化可断言 |
| IT-G01 | FR-G-01 | 采集物只配 `substance_id`；拾取入包 + 消失 + 音效；首次弹 bubble 字幕；不存在 id 不崩溃 |
| IT-G05 | FR-G-05 | 拖入材料 → 取消回背包不丢失；成功入包 + 弹卡片；**失败不消耗材料**；三种器材选项 |
| IT-G06 | FR-G-06 | 卡片文字全来自数据表；底行为 `card_footer`；可跳过；跳过后进图鉴 |
| IT-G08 | FR-G-08 | 未验纯点燃 → 爆炸动画 + 生命精确 -50 + `sys_explosion_warn`；标记 `explosion_happened`；生命 <50 时走死亡流程不卡死 |
| IT-G09 | FR-G-09 | 问过导师后出现验纯步骤；验纯播放音效 + `sys_purity_ok`；验纯后点燃成功不扣血、卡片正确；debug 开关可强制解锁 |
| IT-G10 | FR-G-10 | 矿洞全天/草原仅夜晚生成；接触 8/s；活性炭砸中销毁 + `sys_carbon`；首次接近触发 `warn_co` |
| IT-G11 | FR-G-11 | 仅夜晚刷 2~3 只、白天清除；冲撞 -10；喷雾命中销毁 + `sys_spray` |
| IT-G13 | FR-G-13 | 过滤器水→纯净水 + 四步字幕；电解器 1:2 产量 + 字幕；篝火 +40 能量与旁边回血；床走 IT-C05 |
| IT-G14 | FR-G-14 | 三步必须顺序完成、跳步无产物；完成得 `nacl` + 物理变化卡片；肥皂水对湖水出 `sys_hardwater` |
| IT-G15 | FR-G-15 | E 进交易态 + prompt 字幕；数字键卖出道具 +20 能量；已装备先卸下；空格/物质不卖不扣；取消与走远退出 |
| IT-G16 | FR-G-16 | 池内生命按 `damage.cuso4_pool_per_second`（5/s）下降、离开停止；首次接近触发一次 `warn_cuso4`；池内致死走正常死亡流程 |
| IT-M01 | FR-M-01 | 四房间各一位导师且 `room` 与数据表一致；学院内不耗氧、怪物不入；走近出提问气泡 |
| IT-M02 | FR-M-02 | 聊天框打开时世界不暂停不切场景；逐字打字期间立绘为 talk、结束回 idle；记录可滚动；Esc 收起恢复操作 |
| IT-M07 | FR-M-07 | stub 断言请求体含 system+user、`max_tokens≈300`、`temperature=0.7`；历史仅 4 轮；无 key 时进离线不崩溃；**key 不出现在日志中** |
| IT-M10 | FR-M-10 | 配置面板**接线**部分（可见部分仍归 MT-M10）：`apply_api_key()` 把非空 key 转发给 `LLMClient.set_api_key()`、空串不转发；离线开关转发 `set_offline()` 且打开时按 `is_offline()` 同步；滑块拖动后 `personality()` 变化但**无任何模块消费它**（grep 式扫描）；说明文字取自 `ui_strings.config_note`；**测试注入假客户端，不碰真实 `user://config.cfg`、不回显 key** |
| IT-U03 | FR-U-03 | 主菜单与 M 键均可打开；13 热区齐全且状态与数据表一致；解锁项显示 brief、未解锁抖动 + teaser 且不可进入 |
| IT-U04 | FR-U-04 | 网格 17 格齐全；已收集彩色 + 分类标签；未收集剪影不泄露名称；卡片可翻页；主菜单与游戏内数据一致 |
| IT-U05 | FR-U-05 | 打开时玩家输入被屏蔽；图标缺失显示占位不崩溃 |
| IT-U06 | FR-U-06 | 合成/背包/卡片模态面板按视口比例铺开（宽 76%/70%/80%、高 60%/70%/70%）且居中；主菜单/暂停菜单按钮组居中；死亡画面文案垂直中心锚点 |

**集成测试合计 27 项。**

---

## 6. 追溯矩阵（FR ↔ AC ↔ 测试 ↔ Checklist）

新增 FR 必须同时补这张表一行，否则视为规格未完成。

| FR | AC 数 | 自动化测试 | 手工验收 | Checklist 项 |
|---|---|---|---|---|
| FR-C-01 | 3 | IT-C01 | — | P0-4 |
| FR-C-02 | 4 | UT-C02 | 清单 5 | P1-2 |
| FR-C-03 | 3 | UT-C03 | 清单 5 | P2-1 |
| FR-C-04 | 4 | UT-C04 | 清单 11 | P1-3 |
| FR-C-05 | 3 | IT-C05 | 清单 12 | P2-2 |
| FR-C-06 | 4 | IT-C06 | 清单 12 | P2-11 |
| FR-C-07 | 3 | IT-C07 | 清单 2、5 | P1-2 |
| FR-C-08 | 3 | IT-C08 | 清单 1 | P2-12 |
| FR-C-09 | 3 | UT-C09 | — | P0-4 |
| FR-P-01 | 3 | IT-P01 | 清单 1 | P1-1 |
| FR-P-02 | 3 | IT-P02 | 清单 2 | P1-1 |
| FR-P-03 | 2 | IT-P03 | 清单 11 | P1-1 |
| FR-G-01 | 4 | IT-G01 | 清单 2 | P1-4 |
| FR-G-02 | 4 | UT-G02 | 清单 2 | P1-4 |
| FR-G-03 | 2 | UT-G03 | 清单 2 | P1-4 |
| FR-G-04 | 5 | UT-G04 | 清单 7 | P1-5 |
| FR-G-05 | 3 | IT-G05 | 清单 7 | P1-5 |
| FR-G-06 | 3 | IT-G06 | 清单 7 | P2-4 |
| FR-G-07 | 2 | UT-G07 | — | P2-4 |
| FR-G-08 | 4 | IT-G08 | 清单 8 | P2-6 |
| FR-G-09 | 4 | IT-G09 | 清单 8、10 | P2-6 |
| FR-G-10 | 4 | IT-G10 | 清单 11 | P2-5 |
| FR-G-11 | 3 | IT-G11 | 清单 11 | P2-5 |
| FR-G-12 | 3 | UT-G12 | 清单 11 | P2-10 |
| FR-G-13 | 4 | IT-G13 | 清单 6 | P2-2 |
| FR-G-14 | 3 | IT-G14 | 清单 3 | P2-14 |
| FR-G-15 | 5 | IT-G15 | 清单 11 | P2-15 |
| FR-G-16 | 3 | IT-G16 | 清单 16 | —（P3 阶段补做项） |
| FR-M-01 | 3 | IT-M01 | 清单 9 | P2-7 |
| FR-M-02 | 4 | IT-M02 | 清单 9 | P2-7 |
| FR-M-03 | 3 | UT-M03 | — | P2-7 |
| FR-M-04 | 4 | UT-M04 | 清单 10 | P2-8 |
| FR-M-05 | 3 | UT-M05 | 清单 10 | P2-8 |
| FR-M-06 | 3 | UT-M06 | — | P2-8 |
| FR-M-07 | 4 | IT-M07 | 清单 10 | P1-7 |
| FR-M-08 | 4 | UT-M08 | 清单 14 | P2-9 |
| FR-M-09 | 4 | UT-M09 | 清单 10、14 | P2-9 |
| FR-M-10 | 2 | IT-M10（接线部分） | MT-M10（可见部分） | P2-9 |
| FR-U-01 | 4 | UT-U01 | 清单 2 | P1-6 |
| FR-U-02 | 4 | — | MT-U02 | P2-4 |
| FR-U-03 | 4 | IT-U03 | 清单 4 | P2-3 |
| FR-U-04 | 4 | IT-U04 | 清单 13 | P2-13 |
| FR-U-05 | 2 | IT-U05 | 清单 2 | P1-4 |
| FR-U-06 | 4 | IT-U06 | — | P3-9 |
| FR-D-01 | 3 | UT-D01 | — | P0-5 |
| FR-D-02 | 3 | UT-D02 | — | P0-5 |
| FR-D-03 | 3 | UT-D03 | — | P0-5 |
| FR-D-04 | 3 | UT-D04 | — | P0-5 |
| FR-D-05 | 3 | UT-D05 | — | P0-5 |
| FR-D-06 | 2 | UT-D06 | — | P0-5 |
| FR-D-07 | 3 | UT-D07 | — | P0-5 |
| FR-D-08 | 2 | UT-D08 | — | P0-5 |
| FR-B-01 | 3 | — | MT-B01 | P3-5 |
| FR-B-02 | 3 | — | MT-B02 | P3-6 |
| FR-B-03 | 2 | — | MT-B03 | P3-5 |
| FR-B-04 | 3 | — | MT-B04 | P3-7 |

覆盖统计：55 条 FR 中 **50 条有自动化测试**，5 条纯手工验收——`FR-U-02`（主观引导体验）、`FR-B-01..04`（构建/断网/干净机/视频交付）。
`FR-M-10` 为**半自动**：接线部分由 IT-M10 断言（转发、同步、滑块不生效、文案来源），肉眼可见部分（滑块能拖、文字在屏幕上）仍按 MT-M10 人工确认。
这些手工项必须在 H18 按 §7 逐条人工打勾。

---

## 7. 手工测试清单（MT-*）

| 编号 | 内容 | 执行人 | 时机 |
|---|---|---|---|
| MT-U02 | 前 3 分钟零 UI 引导：出生见光球、氧气 70 提示、河边与合成台字幕、全程无教程弹窗 | P5 | H10、H14 |
| MT-M10 | 配置面板：输入 key 立即生效；滑块可拖不生效；界面明示"赛后可配置" | P3 | H14 |
| MT-B01 | 每整点导出成功；演示包含 README.txt 操作说明 | P1 | 每整点 |
| MT-B02 | **拔网线跑完 §8 全流程**，导师走离线兜底且带「（离线模式）」，日志无未捕获异常 | P5 | H14–H16 |
| MT-B03 | 干净电脑（未装 Godot）双击运行；首启能创建 `user://config.cfg` | P5 | H18 |
| MT-B04 | 视频 2:50–3:10、1080p、六段分镜齐全、画面无调试信息 | P5 | H16–H18 |

---

## 8. 全流程回归脚本（每轮 bug bash 照这个跑，约 12 分钟）

1. 启动 exe → 主菜单三个门各点一次 → 开始冒险。
2. 草原捡 O₂、C → 确认字幕与计数 2/16。
3. 打开地图页（M）→ 确认 5 彩色 + 8 剪影 + 角标。
4. 去盐湖 → 捡粗盐 → 肥皂水试湖水 → 确认硬水字幕。
5. 回营地 → 河边取水 → 过滤器（四步字幕）→ 电解器（得 H₂/O₂）。
6. 合成台：木棒+S → 硫火把 + 知识卡片。
7. 合成台：H₂+O₂ 直接点燃 → **爆炸 + 扣 50 + 警示字幕**。
8. 去导师学院 → 问"为什么氢气会爆炸" → 确认班主任首接 + @化学老师 + 袁仲衡回答 + **答完终止**。
9. 追问"接下来该做什么" → 班主任 @助理 → 周启明三步计划。
10. 回合成台 → 验纯 → 点燃成功 → 卡片正确。
11. 下矿洞 → 确认氧气加速掉 → 捡 S/CaCO₃ → 硬挨 CO 幽灵一下 → 合成活性炭砸幽灵确认消散。
12. 等到夜晚 → 火把照明 → 酸雾怪出现 → 喷雾消灭。
13. 故意死一次 → 床复活 → 跑回死亡点捡回物品。
14. 睡觉跳夜 → 确认清晨、生命满、资源刷新。
15. 打开图鉴 → 确认收集进度与已解锁卡片。
16. 全程观察日志：**零未捕获异常**。

**断网版**：拔网线重跑 1–16，第 8/9 步确认回答带「（离线模式）」。

---

## 9. bug 台账规范（P5 维护）

台账位置：`docs/BUGS.md`（H8 起建立）。每条记录：

```
ID    | 严重度 | 模块 | 现象 | 复现步骤 | 责任人 | 状态
B-001 | P0    | gameplay | 爆炸后卡死 | 步骤7后按E | P2 | 已修/待验
```

严重度：`P0` 阻塞演示（必修）｜`P1` 影响体验（H14 前修）｜`P2` 瑕疵（有空再修）。
**H18 前 P0/P1 必须清零**；P2 允许带着上场，但要写进演示话术回避。
