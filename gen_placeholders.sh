#!/usr/bin/env bash
# 占位美术生成入口（包 E2）。生成物为占位资产，P4 正式美术交付后替换。
# 用法：./gen_placeholders.sh   全成功打印 GEN OK 且退出码 0。
# Godot 可执行文件可用环境变量 GODOT_BIN 覆盖。
set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_godot() {
  if [[ -n "${GODOT_BIN:-}" && -x "${GODOT_BIN}" ]]; then
    printf '%s' "${GODOT_BIN}"
    return 0
  fi
  local candidates=(
    "/d/Program Files/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
    "/c/Program Files/Godot_v4.6.3-stable_win64.exe/Godot_v4.6.3-stable_win64_console.exe"
  )
  local c
  for c in "${candidates[@]}"; do
    [[ -x "$c" ]] && printf '%s' "$c" && return 0
  done
  for c in godot godot4 Godot; do
    command -v "$c" >/dev/null 2>&1 && printf '%s' "$c" && return 0
  done
  return 1
}

GODOT="$(find_godot)" || {
  echo "ERROR: 找不到 Godot 可执行文件。请设置 GODOT_BIN=/path/to/Godot_console.exe" >&2
  exit 127
}

"$GODOT" --headless --path "$PROJECT_DIR" -s scripts/tools/gen_placeholders.gd
exit $?
