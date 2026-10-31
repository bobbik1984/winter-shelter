#!/usr/bin/env bash
# 导出独立可执行版本（需要先安装 Godot 4.3 stable 导出模板：
#   编辑器 Editor → Manage Export Templates → Download，或把 4.3.stable 模板解压到
#   ~/.local/share/godot/export_templates/4.3.stable/）。
# 用法：tools/build.sh [linux|windows|all]   产物在 build/<平台>/
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
TPL="$HOME/.local/share/godot/export_templates/4.3.stable"
if [ ! -d "$TPL" ]; then
  echo "未找到导出模板：$TPL" >&2
  echo "请先安装 Godot 4.3.stable 导出模板（见脚本开头说明）。" >&2
  exit 2
fi
target="${1:-all}"
"$GODOT" --headless --path . --import >/dev/null
if [ "$target" = "linux" ] || [ "$target" = "all" ]; then
  mkdir -p build/linux
  "$GODOT" --headless --path . --export-release "Linux" build/linux/SnowShelterChallenge.x86_64
fi
if [ "$target" = "windows" ] || [ "$target" = "all" ]; then
  mkdir -p build/windows
  "$GODOT" --headless --path . --export-release "Windows Desktop" build/windows/SnowShelterChallenge.exe
fi
echo "完成：build/"
