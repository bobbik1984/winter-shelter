#!/usr/bin/env bash
# 导出包里的资源值必须和源码一致，否则退出码 1。用法：tools/check_export_values.sh <pck 文件>
set -euo pipefail
pck=$(realpath "$1")
GODOT=${GODOT:-godot}
root=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/empty"
git -C "$root" ls-files '*.tres' | sed 's#^#res://#' > "$tmp/list.txt"
[ -s "$tmp/list.txt" ] || { echo "no .tres files found" >&2; exit 1; }

"$GODOT" --headless --path "$root" -s "$root/tools/dump_resource_values.gd" -- "$tmp/source.txt" "$tmp/list.txt" >/dev/null 2>&1 || true
# 空目录里运行：否则 Godot 会打开这里的工程，而不是导出包
(cd "$tmp/empty" && "$GODOT" --headless --main-pack "$pck" -s "$root/tools/dump_resource_values.gd" -- "$tmp/pck.txt" "$tmp/list.txt" >/dev/null 2>&1) || true

[ -s "$tmp/source.txt" ] && [ -s "$tmp/pck.txt" ] || { echo "export check failed: could not read values" >&2; exit 1; }
if ! diff "$tmp/pck.txt" "$tmp/source.txt" >"$tmp/diff.txt"; then
  echo "export check failed: exported values differ from source (< export, > source)" >&2
  grep -E '^[<>]' "$tmp/diff.txt" >&2
  exit 1
fi
echo "export check ok: $(wc -l < "$tmp/source.txt") values in $(wc -l < "$tmp/list.txt") resources match source"
