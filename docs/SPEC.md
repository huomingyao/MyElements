# SPEC 总索引｜《元素炼金物语》MVP

> **本文件是事实来源入口。** 任何开工前先读这里，再读对应分册。
> 代码与 spec 冲突时，以 spec 为准；实现要改行为，先改 spec 再改码（同一 commit）。

- 版本：v1.0（MVP / 20 小时比赛版）
- 引擎：Godot 4.6.3-stable + GDScript
- 开发方式：SSD（规格驱动）+ TDD（测试驱动）+ 多子 Agent 并行
- 状态：**规格阶段完成，实现未开始**

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
- [~] P1-1 玩家控制器 + 相机 + 白盒地图（FR-P-01..03）（TP-04：`player.tscn` 按 SPEC-03 §5.1 结构落地，移动/跳跃/重力/朝向 + 低能量 ×0.5 全读 balance，交互只调 §5 三方法 + 最近目标 + 气泡走 `get_ui_string`，相机 `set_map_bounds` 四条 limit + 火把半径 80↔220 切换，IT-P01 7 项 + IT-P02 5 项 + IT-P03 6 项全绿；白盒地图铺图归 P5 `maps/`，ViewLight 纹理待 P4）
- [x] P1-2 三值系统 + HUD（FR-C-02、FR-C-07）（TP-03：三值结算与信号，UT-C02 10 项全绿；TP-12：HUD 三条数值条纯信号驱动无 `_process` 轮询 + 已收集计数 + 时间指示 + 低氧闪烁/一次字幕，IT-C07 7 项全绿）
- [x] P1-3 昼夜循环（FR-C-04）（TP-03：`tick(delta)` 时钟，UT-C04 10 项全绿；CanvasModulate 变暗待 TP-12）
- [~] P1-4 采集与背包（FR-G-01..03）（TP-06：`inventory.gd` 8 格×99 堆叠 + 溢出/退回/全或无扣减，UT-G02 18 项全绿；`discovery.gd` 首次收集统计 + 16 计数集合数自数据表，UT-G03 13 项全绿。采集物场景 FR-G-01 与背包界面 FR-U-05 待 P4 出图 / TP-11）
- [~] P1-5 配方引擎 + 合成台（FR-G-04..05）（TP-07：`try_craft` 规则 1~5 + 11 条配方逐条正例，UT-G04 18 项全绿；合成台 UI 待 TP-11）
- [x] P1-6 字幕引擎（FR-U-01）（TP-05：串行队列 + warning 打断 + once 去重，UT-U01 15 项全绿；渲染层 `scenes/ui/tip_*.tscn` 待 P4 出图）
- [~] P1-7 LLMClient 打通第一条真实回复（FR-M-07）（TP-15：`build_request_body` 组 OpenAI 兼容请求体（system 人设+后缀 / 历史按轮展开 / 本轮 user 经 `sanitize_input`）+ `max_tokens`/`temperature` 读 balance.json + `set_transport` 单一发包点，IT-M07 9 项全绿。**真实 DeepSeek 往返未验证**：测试全程注入传输层不发真实请求，需配 key 后人工跑一次（MT-B02 同批）；聊天框 UI 待 TP-13）
- [ ] **H4 检查点**：白盒地图上跑动、拾取、合成出硫火把

### Phase 2 — 核心闭环（H4–H12）
- [x] P2-1 区域判定 + 分区氧气消耗（FR-C-03）（TP-03：五区域净速率 + 首次进入字幕，UT-C03 8 项全绿）
- [x] P2-2 营地设施：过滤器/电解器/篝火/床（FR-G-13、FR-C-05）（TP-10：`facility_base.gd` 基类统一 §5 三方法 + 四设施 + 实验台 + 湖水，IT-G13 9 项 + IT-C05 3 项全绿；`resources_respawned` 仅断言信号，采集物实体接线归 FR-G-01 线；睡觉渐黑过场属 UI 层未做）
- [x] P2-3 世界地图页 13 区域（FR-U-03）（TP-12：13 热区全部按 worldmap.json 构建，5 彩 + 8 剪影 + 角标 + 未解锁抖动，IT-U03 6 项全绿；肉眼效果归 MT）
- [~] P2-4 知识卡片弹窗 + 失败反馈（FR-G-06..07）（TP-07：卡片五字段组装 + 失败文案按 reason 分池确定性轮转，UT-G07 13 项全绿；弹窗 UI 待 TP-11）
- [x] P2-5 CO 幽灵 + 酸雾怪（FR-G-10..11）（TP-09：幽灵追踪 8/s + 口罩免疫 + `warn_co` 单次字幕，IT-G10 9 项；酸雾怪夜晚刷 2~3 只 + 冲撞单次 -10 + 喷雾消灭，IT-G11 7 项全绿；实机追踪/刷新接线待世界场景）
- [x] P2-6 **氢气爆炸事件 + 验纯解锁**（FR-G-08..09）（TP-08：`hydrogen_event.gd` 纯逻辑 + `explosion.tscn` 表现层，精确 -50 + warning 字幕 5 秒 + 置标记 + 生命 <50 死亡路径，IT-G08 12 项 + IT-G09 5 项全绿；合成界面「点燃」按钮可见部分待 TP-07 craft_*，导师侧自动解锁接线待 P3）
- [x] P2-7 导师四房间 + 聊天框 + 立绘（FR-M-01..03）（TP-13：`academy.tscn` 四房间 + ZoneTrigger + `chat_panel` 世界不暂停/逐字打字/idle-talk 切换，IT-M01 6 项 + IT-M02 12 项全绿；立绘为确定性纯色占位，待 P4；学院接入 world.tscn 归 TP-17）
- [~] P2-8 班主任调度链 + @ 终止约束（FR-M-04..06）（TP-14：`mentor_router.gd` 四类分类器按 dispatch 数组顺序判优先级 + `route_targets` 查表 + `parse_mentions` 最长句柄匹配 + `handle_message` 首条必 monitor/≤3 条/只解析 monitor 的 @/调度计数硬上限 1，UT-M04 9 项 + UT-M05 12 项全绿；`prompt_suffix.gd` 通用后缀拼接，UT-M06 7 项全绿；`sanitize_input` 锁定，UT-M03 7 项全绿。真实 LLM 回复来源待 TP-15，聊天框 UI 待 TP-13）
- [~] P2-9 离线兜底 + 超时切换（FR-M-08..10）（TP-15：四种失败（超时/网络错/非 200/畸形 body）统一收口成空串再兜底 + 重试上限 `retry_count` + 失败即转离线 + `mode_changed` 只在真变化时发，UT-M08 13 项全绿；`qa_fallback.gd` 命中最多者胜/平票取先/零命中取表中兜底行 + 角标由调用方追加，UT-M09 9 项全绿；`config_panel.tscn` key 只转发给 `set_api_key`（`secret=true`、不回显不记录）+ 手动离线开关 + 滑块可拖不生效，IT-M10 11 项全绿。**未能实机验证**：滑块手感与面板排版归 MT-M10 人工确认，godot_mcp 本会话未注册；拔网线全流程归 MT-B02）
- [x] P2-10 道具生效（FR-G-12）（TP-09：`item_effects.gd` 八种道具效果按 `effect_value_key` 动态读 balance，装备不消耗/消耗品 -1/无目标不消耗，UT-G12 14 项全绿；装备 UI 接线待背包界面）
- [x] P2-11 死亡/复活/掉落（FR-C-06）（TP-11：死亡画面 + `drop_bag` 掉落包快照/替换语义 + 复活三值回满，IT-C06 11 项全绿；世界场景生成掉落包的一行接线归 TP-17）
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

---

## 5. 追溯矩阵入口

FR → 验收标准 → 测试用例 → Checklist 项 的完整映射见
[SPEC-06 §6 追溯矩阵](SPEC-06-测试计划.md)。新增 FR 时必须同时补该矩阵一行，否则视为规格未完成。

---

## 6. 变更记录

| 日期 | 版本 | 变更 | 触发人 |
|---|---|---|---|
| 2026-08-01 | v1.0 | 由 `plan/` 三份草案重写为九册规格文档集，引入 FR/AC/测试编号体系 | 用户 |
