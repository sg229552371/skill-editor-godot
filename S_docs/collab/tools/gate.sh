#!/usr/bin/env bash
# 批量门禁：编译检查 + GUT，一次输出所有指定测试文件的结论（审核方专用）
# 用法：bash S_docs/collab/tools/gate.sh tests/test_a.gd tests/test_b.gd ...
#       bash S_docs/collab/tools/gate.sh --all            # 全量回归
set -u
GD471="${GD471:-/c/Users/Administrator/AppData/Roaming/Ryko.GodotHub/godot-versions/4.7.1-stable/Godot_v4.7.1-stable_win64.exe}"
cd "$(dirname "$0")/../../.." || exit 1

FILES=("$@")
if [ "${1:-}" = "--all" ] || [ $# -eq 0 ]; then
  FILES=()
  for f in tests/test_*.gd; do
    case "$f" in *_diag_*) continue;; esac
    FILES+=("$f")
  done
fi

T=0; A=0; BAD=""; N=0
for f in "${FILES[@]}"; do
  [ -f "$f" ] || { echo "MISSING $f"; BAD="$BAD $f"; continue; }
  N=$((N+1))
  OUT=$(GODOT_DISABLE_LEAK_CHECKS=1 "$GD471" --headless --path . -s res://addons/gut/gut_cmdln.gd -gtest="res://$f" -gexit 2>&1)
  n=$(echo "$OUT" | grep -E "^Tests +[0-9]+" | grep -oE "[0-9]+" | head -1)
  a=$(echo "$OUT" | grep -E "^Asserts +[0-9]+" | grep -oE "[0-9]+" | head -1)
  T=$((T + ${n:-0})); A=$((A + ${a:-0}))
  if echo "$OUT" | grep -q "All tests passed"; then
    printf "GREEN %-46s tests=%-4s asserts=%-6s\n" "$(basename "$f")" "${n:-0}" "${a:-0}"
  else
    printf "RED   %-46s tests=%-4s asserts=%-6s  <<<\n" "$(basename "$f")" "${n:-0}" "${a:-0}"
    echo "$OUT" | grep -E "Failed\]|Parse Error|SCRIPT ERROR|Unexpected Errors" | sed -E 's/实际=.*//' | head -6
    BAD="$BAD $(basename "$f")"
  fi
done
echo "---------------------------------------------------------------"
echo "FILES=$N TESTS=$T ASSERTS=$A"
echo "FAILED:${BAD:- (none)}"
