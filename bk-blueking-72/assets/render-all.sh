#!/usr/bin/env bash
# 用途：纯渲染验证——用 helmfile build 渲染全部 41 个 values 模板
# 特点：不下发集群、不拉镜像、不耗内存，只验证模板+证书能否渲染
set -uo pipefail
B=/root/bk72/install/blueking
E=$B/environments/default
HF=/root/bk72/tools/bin/helmfile
PROBE="$E/zz_render_probe.yaml.gotmpl"
LOG=/root/bk72/render_test/render.log
mkdir -p /root/bk72/render_test

echo "===== 0. 环境准备 ====="
echo "helmfile: $("$HF" version 2>&1 | head -1)"
echo "helm: $(helm version --short 2>&1)"
echo "证书目录文件数: $(ls "$E/cert" 2>/dev/null | wc -l)"

echo ""
echo "===== 1. 构造探针 helmfile（列出全部 41 个 values 模板）====="
{
  echo "bases:"
  echo "  - ../../env.yaml"
  echo "  - ../../defaults.yaml"
  echo "---"
  echo "releases:"
  echo "  - name: render-probe"
  echo "    chart: /tmp/probe-chart"
  echo "    values:"
} > "$PROBE"

n=0
for f in "$E"/*-values.yaml.gotmpl; do
  b=$(basename "$f")
  echo "      - $b" >> "$PROBE"
  n=$((n+1))
done
echo "已列出 $n 个 values 模板"

# 最小 chart，避免真实依赖
rm -rf /tmp/probe-chart
mkdir -p /tmp/probe-chart/templates
cat > /tmp/probe-chart/Chart.yaml <<'EOF'
apiVersion: v2
name: probe-chart
version: 0.1.0
EOF
cat > /tmp/probe-chart/values.yaml <<'EOF'
EOF
echo "ok" > /tmp/probe-chart/templates/ok.txt

echo ""
echo "===== 2. 执行纯渲染（helmfile build）====="
cd "$E" || exit 1
timeout 300 "$HF" -f zz_render_probe.yaml.gotmpl build > "$LOG" 2>&1
rc=$?
echo "退出码: $rc"

echo ""
echo "===== 3. 渲染结果判定 ====="
if [ $rc -eq 0 ]; then
  echo "★ 全部 $n 个模板渲染成功！"
  echo "输出大小: $(wc -c < "$LOG") 字节"
else
  echo "✗ 渲染失败，错误如下："
  grep -iE 'error|failed|cannot|no such file|not defined' "$LOG" | head -15
fi

echo ""
echo "===== 4. 清理探针文件 ====="
rm -f "$PROBE"
echo "已删除 $PROBE"
