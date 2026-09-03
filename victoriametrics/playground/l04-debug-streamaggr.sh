#!/usr/bin/env bash
# 排查：单节点 VM 的流式聚合为何没有输出
set -u
VM=http://localhost:8428
FMT=/mnt/d/projects/learning/victoriametrics/playground/l04-fmt.py
NOW=$(date +%s)

echo "########## 1. 确认 streamAggr 配置是否被正确解析 ##########"
echo "  --- 容器内配置文件内容 ---"
docker exec vm-learn cat /etc/victoriametrics/stream-aggr.yaml 2>&1 | sed 's/^/    /'
echo
echo "  --- 启动日志中 streamAggr 相关（完整）---"
docker logs vm-learn 2>&1 | grep -iE 'stream|aggr' | head -20 | sed 's/^/    /'

echo
echo "########## 2. 关键怀疑：单节点 VM 的 streamAggr 只对【remote write 协议】生效 ##########"
echo "  官方文档：stream aggregation 在 vmagent 中对所有协议生效；"
echo "  在单节点 VM 中，-streamAggr.config 配合 -remoteWrite.streamAggr 使用。"
echo "  也就是说：单节点上它主要作用于【Prometheus remote write 进来的数据】，"
echo "  而 /api/v1/import/prometheus（native import）可能不走这条路径。"
echo
echo "  验证：用 remote write 协议写入（我们现在正好有 Prometheus 在跑）"

echo
echo "########## 3. 改用 remote write 协议写入测试数据 ##########"
echo "  用 Python 构造 snappy 压缩的 protobuf remote write 请求"
python3 - <<'PY' > /tmp/l04_rw_test.py
print("""
import sys
# 用 VictoriaMetrics 自带的 promremotewrite 文本格式端点更简单
""")
PY

echo "  方案：给 Prometheus 加一个 static target 指向我们自己的 exporter？"
echo "  更简单：用 /api/v1/write 端点，它接受 Prometheus remote write 格式"
echo
echo "  先用最简单的方式验证：直接查 vm_streamaggr 相关计数器"
curl -s -m 15 -G "$VM/api/v1/query" \
  --data-urlencode 'query={__name__=~"vm_streamaggr.*"}' --data-urlencode "nocache=1" \
| python3 "$FMT"

echo
echo "########## 4. 检查 -streamAggr 是否也需要 -remoteWrite.streamAggr ##########"
echo "  --- VM 的 flag 帮助里 streamAggr 相关项 ---"
docker exec vm-learn /victoria-metrics-prod --help 2>&1 \
  | grep -iE 'streamAggr' | head -20 | sed 's/^/    /'

echo
echo "########## 5. 结论验证：改用 remote write 协议写入并观察 ##########"
echo "  写入 l04_highcard 走 /api/v1/write（remote write 协议）"
echo "  用 curl 直接构造：需要 snappy+protobuf，改用 VM 的 promremotewrite 导入端点"
echo
echo "  先用现成的：Prometheus 正在持续 remote write，"
echo "  把 stream-aggr.yaml 的 match 改成 Prometheus 已有的指标来验证"
echo
echo "  --- 查看当前 Prometheus remote write 进来的指标名（前 20）---"
curl -s -m 20 -G "$VM/api/v1/series" \
  --data-urlencode 'match[]={job=~"prometheus|victoriametrics"}' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)["data"]
names=sorted(set(m.get("__name__","") for m in d))
print("    共 {} 个指标名，示例:".format(len(names)))
for n in names[:20]: print("      ", n)
'
