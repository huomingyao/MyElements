#!/usr/bin/env bash
# 统一测试入口（SPEC-06 §1）。用法：
#   ./run_tests.sh                                  跑 res://tests 全部
#   ./run_tests.sh -gdir=res://tests/unit           只跑单元测试
#   ./run_tests.sh -gtest=res://tests/unit/test_x.gd 只跑一个文件
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

TARGET_ARGS=("$@")
if [[ ${#TARGET_ARGS[@]} -eq 0 ]]; then
  TARGET_ARGS=("-gdir=res://tests" "-ginclude_subdirs")
fi

"$GODOT" --headless --path "$PROJECT_DIR" \
  -s addons/gut/gut_cmdln.gd \
  "${TARGET_ARGS[@]}" -gexit
exit $?
