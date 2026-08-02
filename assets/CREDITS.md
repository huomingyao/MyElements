# 素材授权登记（SPEC-08 §4.3 强制）

## 占位美术（当前生效）

- 内容：物质图标 ×17、道具图标 ×10、导师立绘 idle/talk ×8、导师像素小人 ×4、通用占位图 ×1。
- 来源：**程序生成**，无外部素材、无第三方授权负担。
- 生成器：`scripts/tools/gen_placeholders.gd`（运行 `./gen_placeholders.sh`，确定性输出，可复跑）。
- 规格：16×16 图标 / 240×320 立绘 / 32×32 小人，仅使用 SPEC-08 §2 的 32 色调色板。
- 状态：**占位资产，P4 正式美术交付后替换**。

## 字体

- 名称：缝合怪像素字体（Fusion Pixel Font）12px 比例宽度简体中文版
  （`fusion-pixel-12px-proportional-zh_hans.ttf`）。
- 作者：TakWolf，项目主页 https://github.com/TakWolf/fusion-pixel-font 。
- 许可：SIL Open Font License 1.1（OFL-1.1），许可文本见 `assets/fonts/OFL.txt`
  （上游 ark-pixel / cubic-11 / galmuri 许可副本在 `assets/fonts/LICENSES/`）。
- 用在哪：`project.godot` 的 `gui/theme/custom_font`，全局 UI 默认字体。
- 状态：**已交付（B-004 fixed 2026-08-02）**。

## 音频

- 状态：**音频未交付，MVP 无声**。按 SPEC-08 §5 约定，缺失时静默处理，不因找不到文件抛错。

## 外部素材包

- 暂无。每引入一个外部素材包，必须在此追加一行「包名 / 作者 / 授权 / 来源链接 / 用在哪」；
  CC-BY 素材另需在 `README.txt` 与 PPT 末页署名。授权不明的一律不用。
