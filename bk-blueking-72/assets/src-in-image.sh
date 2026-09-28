#!/usr/bin/env bash
set -uo pipefail
{
echo "===== 验证：镜像里能否拿到源码 ====="
echo ""
echo "===== 1. 开源型组件（Python/Django，源码直装）====="
NP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-nodeman-' | grep Running | awk '{print $1}' | head -1)
if [ -n "$NP" ]; then
  kubectl exec "$NP" -n blueking -- sh -c '
    echo "  [nodeman] 应用目录:"
    ls /app 2>/dev/null | head -8 | sed "s/^/    /"
    echo "  [nodeman] .py 源码数量:"
    find /app -name "*.py" 2>/dev/null | wc -l | sed "s/^/    /"
    echo "  [nodeman] 抽样源码文件:"
    find /app -name "*.py" 2>/dev/null | head -3 | sed "s/^/    /"
    echo "  [nodeman] 是否有 .git:"
    find / -maxdepth 3 -name ".git" -type d 2>/dev/null | head -2 | sed "s/^/    /"
  ' 2>&1 | sed 's/^/  /'
fi

echo ""
echo "===== 2. 编译型组件（GSE，C++ 二进制）====="
GP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-gse-data-' | grep Running | awk '{print $1}' | head -1)
if [ -n "$GP" ]; then
  kubectl exec "$GP" -n blueking -c bk-gse-data -- sh -c '
    echo "  [gse] bin 目录（全是编译好的二进制）:"
    ls -la /data/gse/bin/ 2>/dev/null | head -10 | sed "s/^/    /"
    echo "  [gse] 源码文件(.cc/.cpp/.h/.py/.go) 数量:"
    find /data/gse \( -name "*.cc" -o -name "*.cpp" -o -name "*.h" -o -name "*.py" -o -name "*.go" \) 2>/dev/null | wc -l | sed "s/^/    /"
    echo "  [gse] gse_data 二进制类型:"
    file /data/gse/bin/gse_data 2>/dev/null | sed "s/^/    /"
  ' 2>&1 | sed 's/^/  /'
fi

echo ""
echo "===== 3. 监控（bk-monitor，Python 系）====="
MP=$(kubectl get pods -n blueking --no-headers 2>/dev/null | grep -E 'bk-monitor' | grep -v grafana | grep Running | awk '{print $1}' | head -1)
if [ -n "$MP" ]; then
  kubectl exec "$MP" -n blueking -- sh -c '
    echo "  [monitor] 目录:"
    ls / 2>/dev/null | head -15 | sed "s/^/    /"
    echo "  [monitor] .py 数量:"
    find / -maxdepth 4 -name "*.py" 2>/dev/null | wc -l | sed "s/^/    /"
  ' 2>&1 | sed 's/^/  /'
fi

echo ""
echo "===== 4. 结论 ====="
echo "  - Python/Django 类（nodeman/monitor/iam/user）：镜像内直接是 .py 源码，可读可改"
echo "  - C++ 编译类（GSE）：镜像内只有二进制，无源码"
echo "  - 但编译型也能反编译/strings 看部分字符串，只是拿不到可读源码"
} > /root/src-in-image.txt 2>&1
cat /root/src-in-image.txt
