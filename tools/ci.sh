#!/usr/bin/env bash
# 一键回归：逻辑测试 → 真实输入冒烟 → 机器人平衡（3 条路线）→ 短模糊测试。
# 用法：tools/ci.sh [--quick]   （--quick 跳过机器人与模糊测试）
# 有显示器时冒烟、机器人、模糊测试走真实渲染，没有时走 --headless。退出码非 0 = 失败。
# 注意：会在 user:// 写 records.cfg / settings.cfg / sessions/，结束时恢复原状态。
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
# 没有显示器时（SSH / CI）不渲染：Xvfb 软件渲染只有约 1 帧 / 秒，按真实秒数按住按键的冒烟测试会假失败。
# 已有 DISPLAY 时什么都不变（真实渲染）。
win() { if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then "$GODOT" --headless "$@"; else "$GODOT" "$@"; fi; }
UD="$HOME/.local/share/godot/app_userdata/Snow Shelter Challenge"
BK="$(mktemp -d)"
for f in records.cfg settings.cfg; do [ -f "$UD/$f" ] && cp "$UD/$f" "$BK/"; done
[ -d "$UD/sessions" ] && mv "$UD/sessions" "$BK/sessions"   # 试玩记录不被测试污染
restore() { for f in records.cfg settings.cfg; do rm -f "$UD/$f"; [ -f "$BK/$f" ] && cp "$BK/$f" "$UD/"; done; rm -rf "$UD/sessions"; [ -d "$BK/sessions" ] && mv "$BK/sessions" "$UD/sessions"; rm -rf "$BK"; }
trap restore EXIT
# 被 kill / Ctrl-C 时也要恢复：bash 收到信号默认直接退出，不跑 EXIT trap（曾因此把玩家的试玩记录留在 /tmp）
trap 'exit 143' TERM INT HUP
fail=0
step() { printf '\n== %s ==\n' "$1"; }

step "import"
"$GODOT" --headless --path . --import >/dev/null 2>&1

step "logic tests"
if "$GODOT" --headless --path . -s res://tests/run_all.gd 2>&1 | tee /tmp/ws_ci_tests.log | grep -E "^\[(PASS|FAIL)\]|RESULT"; then :; fi
grep -q "RESULT: PASS" /tmp/ws_ci_tests.log || fail=1

step "touch smoke test (a whole game using touch events only)"
"$GODOT" --headless --path . -s res://tools/touch_smoke_test.gd -- --touch --touch-css=390 2>&1 | grep -E "^(PASS|FAIL)|^RESULT" | tee /tmp/ws_ci_touch.log | grep -E "FAIL|RESULT"
grep -q "RESULT PASS" /tmp/ws_ci_touch.log || fail=1
step "input smoke test"
win --path . -s res://tools/input_smoke_test.gd -- --weather=clear 2>&1 | grep -E "^(PASS|FAIL)|^RESULT" | tee /tmp/ws_ci_smoke.log | grep -E "FAIL|RESULT"
grep -q "RESULT PASS" /tmp/ws_ci_smoke.log || fail=1

if [ "${1:-}" != "--quick" ]; then
  step "balance bots"
  for s in deep_stick trench treewell leanto_full quinzhee rock fallen wind none; do
    line=$(win --path . -s res://tools/playtest_bot.gd -- --s=$s --weather=clear 2>&1 | grep -E "^depth|PLACE FAILED")
    echo "$line"
    case "$s" in
      deep_stick) echo "$line" | grep -q " SAFE " || { echo "  expected SAFE"; fail=1; } ;;
      trench|treewell|leanto_full|quinzhee|rock|fallen) echo "$line" | grep -qE " (COLD|SAFE) " || { echo "  expected COLD or better"; fail=1; } ;;
      wind|none) echo "$line" | grep -q " DANGEROUS " || { echo "  bad play must fail: expected DANGEROUS"; fail=1; } ;;
    esac
    # N5：目标路线的结局不因基础失温 ±10% 翻转
    echo "$line" | grep -q "tol=FLIP" && { echo "  outcome flips at +/-10%"; fail=1; }
  done
  step "chapter routes (S7): stage 5 of every chapter on real maps"
  for ch in 1 2 3 4 5; do
    line=$("$GODOT" --headless --path . -s res://tools/chapter_bot.gd -- --ch=$ch --st=5 --map=0 --route=target --care=full 2>&1 | grep -E "^S7 ")
    echo "$line" | grep -oE "ch=[0-9]+ st=[0-9]+|route=[A-Za-z]+|smart=[A-Z]+/[0-9]+/[0-9]+" | tr '\n' ' '; echo
    echo "$line" | grep -qE "smart=(COLD|SAFE)/" || { echo "  intended route must reach COLD or better"; fail=1; }
    line=$("$GODOT" --headless --path . -s res://tools/chapter_bot.gd -- --ch=$ch --st=5 --map=0 --route=none --care=basic 2>&1 | grep -E "^S7 ")
    echo "$line" | grep -q "smart=DANGEROUS/" || { echo "  no shelter must be DANGEROUS"; fail=1; }
  done
  step "fuzz (3 x 30 s)"
  for sd in 1 3 5; do
    out=$(win --path . -s res://tools/fuzz_test.gd -- --seconds=30 --seed=$sd 2>&1)
    echo "$out" | grep -o "FUZZ.*" || echo "seed $sd: no result (crash?)"
    echo "$out" | grep -q "SCRIPT ERROR" && { echo "  script errors in seed $sd"; fail=1; }
  done
fi

printf '\nCI %s\n' "$([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
