#!/usr/bin/env bash
# S7：每章 × 第 1/5/10 阶 × 图 → 目标路线（full / basic）+ 做错的路线。结果写到 $1（默认 /tmp/s7.txt）。
# 用法：tools/s7_matrix.sh [输出文件] [并行数]
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/s7.txt}"; JOBS="${2:-3}"; GODOT="${GODOT:-godot}"
cases=$(mktemp)
for ch in 1 2 3 4 5; do for st in 1 5 10; do for map in 0 1; do
  for care in full basic; do echo "$ch $st $map target $care" >> "$cases"; done
done
  echo "$ch $st 0 none basic" >> "$cases"
  case $ch in
    1) echo "$ch $st 0 intowind:BasicCave full" >> "$cases"; echo "$ch $st 0 BasicCave full" >> "$cases";;
    2) echo "$ch $st 0 BasicCave full" >> "$cases"; echo "$ch $st 0 intowind:TreeWell full" >> "$cases";;
    3) echo "$ch $st 0 BasicCave full" >> "$cases"; echo "$ch $st 0 FallenLog full" >> "$cases"; echo "$ch $st 0 intowind:LeanTo full" >> "$cases";;
    4) echo "$ch $st 0 Quinzhee full" >> "$cases"; echo "$ch $st 0 intowind:SnowTrench full" >> "$cases";;
    5) echo "$ch $st 0 RockOverhang full" >> "$cases"; echo "$ch $st 0 LeanTo full" >> "$cases"; echo "$ch $st 0 SnowTrench full" >> "$cases";;
  esac
done; done
: > "$OUT"
xargs -a "$cases" -P "$JOBS" -L 1 bash -c 'timeout 170 '"$GODOT"' --headless --path . -s res://tools/chapter_bot.gd -- --ch=$0 --st=$1 --map=$2 --route=$3 --care=$4 2>&1 | grep -E "^S7 |SCRIPT ERROR" | head -3 | sed "s/^SCRIPT/ERR ch=$0 st=$1 route=$3: SCRIPT/" >> '"$OUT"
rm -f "$cases"
echo DONE >> "$OUT"
