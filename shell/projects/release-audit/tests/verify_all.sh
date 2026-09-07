#!/usr/bin/env bash
# 最终验收：三项检查一次跑完
set -uo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." || exit 1

overall=0

echo '═══ 1. 单元测试 ═══'
if bash tests/run_tests.sh >/tmp/ra_v_unit.log 2>&1; then
  tail -3 /tmp/ra_v_unit.log
  echo '  ✅ 单元测试通过'
else
  tail -12 /tmp/ra_v_unit.log
  echo '  ❌ 单元测试失败'
  overall=1
fi

echo
echo '═══ 2. 复杂度门槛 ═══'
if bash tests/verify_complexity.sh >/tmp/ra_v_cx.log 2>&1; then
  grep -v 'awk: warning' /tmp/ra_v_cx.log | grep -E '循环内|常量级'
  echo '  ✅ 复杂度门槛达标'
else
  grep -v 'awk: warning' /tmp/ra_v_cx.log | tail -12
  echo '  ❌ 复杂度门槛未达标'
  overall=1
fi

echo
echo '═══ 3. 语法与结构 ═══'
syn=0
while IFS= read -r f; do
  bash -n "$f" 2>/dev/null || { echo "  语法错误: $f"; syn=$((syn+1)); }
done < <(find . -name '*.sh' -type f; printf '%s\n' ./release-audit)
if [[ $syn -eq 0 ]]; then
  echo "  全部脚本语法检查通过（$(find . -name '*.sh' -type f | wc -l) 个 .sh + 主程序）"
  echo '  ✅ 语法检查通过'
else
  echo '  ❌ 存在语法错误'
  overall=1
fi

echo
echo '═══ 4. 端到端 ═══'
if bash tests/e2e_check.sh >/tmp/ra_v_e2e.log 2>&1; then
  grep -E '退出码|rc=' /tmp/ra_v_e2e.log | tail -8
  echo '  ✅ 端到端通过'
else
  tail -15 /tmp/ra_v_e2e.log
  echo '  ❌ 端到端失败'
  overall=1
fi

echo
if [[ $overall -eq 0 ]]; then
  echo '████ 全部验收通过 ████'
else
  echo '████ 存在未通过项 ████'
fi
exit "$overall"
