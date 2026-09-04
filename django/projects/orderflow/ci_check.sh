#!/usr/bin/env bash
# ============================================================
# CI 门禁：提交后、部署前必须过的四道关
#
# 用法：bash ci_check.sh
# 退出码非 0 即拦住，不允许进入部署阶段。
#
# 四道关与对应的课：
#   1. 语法/配置检查   —— 课 22（check --deploy）
#   2. 团队约定检查     —— 课 21（自定义 System checks）
#   3. 测试            —— 课 20（先量后改）
#   4. 文档同步        —— 课 20（文档与代码一致）
# ============================================================
set -uo pipefail

PY="${PYTHON:-python}"
export PYTHONIOENCODING=utf-8
export PYTHONUTF8=1
export DJANGO_SETTINGS_MODULE="${DJANGO_SETTINGS_MODULE:-config.settings}"

cd "$(dirname "$0")"

FAILED=0
step() {
  echo ""
  echo "=========================================="
  echo "▶ $1"
  echo "=========================================="
}

ok()   { echo "✅ $1"; }
bad()  { echo "❌ $1"; FAILED=1; }

# ---------- 1. 配置检查（生产必查项）----------
step "1/4　配置检查（check --fail-level ERROR）"
if $PY manage.py check --fail-level ERROR 2>&1; then
  ok "配置检查通过"
else
  bad "配置检查失败"
fi

# ---------- 2. 团队约定检查（自定义 checks）----------
step "2/4　团队约定检查（自定义 System checks）"
# 只跑本项目的 tag，避免把 Django 自带的 warning 也算进来
OUT=$($PY manage.py check --tag orderflow_routes --tag orderflow_meta --tag orderflow_docs 2>&1)
echo "$OUT"
if echo "$OUT" | grep -qE "^\?*: \(orderflow\.[EW]"; then
  bad "团队约定检查发现 Error/Warning"
else
  ok "团队约定检查通过（无 E/W）"
fi

# ---------- 3. 测试 ----------
step "3/4　测试"
if $PY manage.py test apps.shop.tests_e2e --verbosity 1 2>&1; then
  ok "测试通过"
else
  bad "测试失败"
fi

# ---------- 4. 文档同步 ----------
step "4/4　文档与代码同步"
if $PY manage.py exportdocs --file schema.yaml --check 2>&1; then
  ok "文档与代码同步"
else
  bad "文档已过期——请重新导出并提交 schema.yaml"
fi

echo ""
echo "=========================================="
if [ "$FAILED" -eq 0 ]; then
  echo "🎉 全部门禁通过，可以进入部署阶段"
  exit 0
else
  echo "🚫 门禁未通过，禁止部署"
  exit 1
fi
