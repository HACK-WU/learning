#!/usr/bin/env bash
# 用途：确认 137 真凶 = livenessProbe 在 redis 启动完成前就 kill
set -uo pipefail
NS=blueking
POD=bk-redis-cluster-2

echo "===== 1. 时间线：容器启动 → 被 kill 的间隔 ====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='{range .status.containerStatuses[*]}startedAt={.lastState.terminated.startedAt}{"\n"}finishedAt={.lastState.terminated.finishedAt}{"\n"}exitCode={.lastState.terminated.exitCode}{"\n"}{end}' 2>&1

echo ""
echo "===== 2. livenessProbe 完整参数 ====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].livenessProbe}' 2>&1
echo ""
echo "关键：initialDelaySeconds=5 意味着容器启动 5 秒后就开始探活"
echo "      failureThreshold=5 × periodSeconds=5 = 最多 25 秒容忍"
echo ""

echo "===== 3. 对比 readinessProbe（通常更宽松）====="
kubectl get pod "$POD" -n "$NS" -o jsonpath='{.spec.containers[0].readinessProbe}' 2>&1
echo ""

echo ""
echo "===== 4. 日志最后一行时间戳 vs 启动时间（看撑了多久）====="
echo "容器日志显示 07:50:09 开始 Setting Redis config file"
echo "终止时间见上，计算存活秒数"

echo ""
echo "===== 5. 镜像拉取耗时（本次实测，判断是否值得调大探针）====="
kubectl get events -n "$NS" --field-selector involvedObject.name="$POD" 2>&1 | grep -i pulled | head -3
