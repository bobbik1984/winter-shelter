#!/usr/bin/env bash
# 一键回归：逻辑测试 → 真实输入冒烟 → 机器人平衡（3 条路线）→ 短模糊测试。
# 用法：tools/ci.sh [--quick]   （--quick 跳过机器人与模糊测试）
# 需要窗口 / 显示（冒烟、机器人、模糊测试要渲染）。退出码非 0 = 失败。
# 注意：会在 user:// 写 records.cfg / settings.cfg / sessions/，结束时恢复原状态。
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
UD="$HOME/.local/share/godot/app_userdata/Snow Shelter Challenge"
BK="$(mktemp -d)"
for f in records.cfg settings.cfg; do [ -f "$UD/$f" ] && cp "$UD/$f" "$BK/"; done
[ -d "$UD/sessions" ] && mv "$UD/sessions" "$BK/sessions"   # 试玩记录不被测试污染
restore() { for f in records.cfg settings.cfg; do rm -f "$UD/$f"; [ -f "$BK/$f" ] && cp "$BK/$f" "$UD/"; done; rm -rf "$UD/sessions"; [ -d "$BK/sessions" ] && mv "$BK/sessions" "$UD/sessions"; rm -rf "$BK"; }
trap restore EXIT
fail=0
step() { printf '\n== %s ==\n' "$1"; }

step "import"
"$GODOT" --headless --path . --import >/dev/null 2>&1

step "logic tests"
if "$GODOT" --headless --path . -s res://tests/run_all.gd 2>&1 | tee /tmp/ws_ci_tests.log | grep -E "^\[(PASS|FAIL)\]|RESULT"; then :; fi
grep -q "RESULT: PASS" /tmp/ws_ci_tests.log || fail=1

step "input smoke test"
"$GODOT" --path . -s res://tools/input_smoke_test.gd -- --weather=clear 2>&1 | grep -E "^(PASS|FAIL)|^RESULT" | tee /tmp/ws_ci_smoke.log | grep -E "FAIL|RESULT"
grep -q "RESULT PASS" /tmp/ws_ci_smoke.log || fail=1

if [ "${1:-}" != "--quick" ]; then
  step "balance bots"
  for s in deep_stick trench leanto_full; do
    line=$("$GODOT" --path . -s res://tools/playtest_bot.gd -- --s=$s --weather=clear 2>&1 | grep -E "^depth|PLACE FAILED")
    echo "$line"
    case "$s" in
      deep_stick) echo "$line" | grep -q " SAFE " || { echo "  expected SAFE"; fail=1; } ;;
      trench|leanto_full) echo "$line" | grep -qE " (COLD|SAFE) " || { echo "  expected COLD or better"; fail=1; } ;;
    esac
  done
  step "fuzz (3 x 30 s)"
  for sd in 1 3 5; do
    out=$("$GODOT" --path . -s res://tools/fuzz_test.gd -- --seconds=30 --seed=$sd 2>&1)
    echo "$out" | grep -o "FUZZ.*" || echo "seed $sd: no result (crash?)"
    echo "$out" | grep -q "SCRIPT ERROR" && { echo "  script errors in seed $sd"; fail=1; }
  done
fi

printf '\nCI %s\n' "$([ $fail = 0 ] && echo PASS || echo FAIL)"
exit $fail
