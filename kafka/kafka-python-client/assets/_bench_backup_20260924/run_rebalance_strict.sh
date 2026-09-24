#!/bin/bash
# 课 5 严格复验：4 独立进程 + 严格重叠判定
set -u
NET=stage6-observability_kafka-net
W=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
IMG=python:3.12-slim
T=l5-verify2

echo "########## 1. 主控建 topic ##########"
docker run --rm --network "$NET" -v "$W:/w" "$IMG" \
  bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_rebalance_strict.py 0 1' 2>&1 \
  | grep -v -e 'rdkafka#' -e 'Unclosed'

echo ""
echo "########## 2. 启动 4 个独立进程消费者（各 28s） ##########"
for i in 1 2 3 4; do
  docker run -d --name "l5v$i" --network "$NET" -v "$W:/w" "$IMG" \
    bash -c "pip install -q kafka-python==3.0.11 >/dev/null 2>&1
      python /w/verify_rebalance_strict.py $i 28" >/dev/null 2>&1
  echo "  #$i 已启动"
  sleep 4
done

echo ""
echo "########## 3. 等待收敛（20s） ##########"
sleep 20

echo ""
echo "########## 4. 收集结果 + 严格判定 ##########"
for i in 1 2 3 4; do
  docker logs "l5v$i" 2>/dev/null | grep -E 'CONSUMER#|trajectory'
done

echo ""
python3 - <<'PY'
import re, subprocess
out = ""
for i in (1, 2, 3, 4):
    r = subprocess.run(["docker", "logs", f"l5v{i}"],
                       capture_output=True, text=True)
    out += r.stdout
finals = re.findall(r"CONSUMER#(\d+) final=\(([^)]*)\) stable=(\w+)", out)
parts, stables = [], []
for idx, p, st in finals:
    lst = [x.strip() for x in p.split(",") if x.strip()]
    parts.extend(int(x) for x in lst)
    stables.append(st == "True")
print(f"  各消费者最终分配: {[ (i, [x.strip() for x in p.split(',') if x.strip()]) for i,p,_ in finals ]}")
print(f"  全部稳定: {all(stables)}")
print(f"  合并分区列表: {sorted(parts)}")
strict = (len(parts) == 4) and (len(set(parts)) == len(parts))
print(f"  严格判定（恰好4个且无重复）: {strict}")
print("  ✓ 讲义结论成立：4 分区均分 4 消费者，零重叠" if strict
      else "  ✗ 未收敛，讲义结论需修正")
PY

echo ""
echo "########## 5. 清理 ##########"
for i in 1 2 3 4; do docker rm -f "l5v$i" >/dev/null 2>&1; done
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --delete --topic "$T" >/dev/null 2>&1
echo "  已清理"
