#!/bin/bash
# 课 5 最终核验：4 独立进程 + 充分收敛 + 严格判定
set -u
NET=stage6-observability_kafka-net
W=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
IMG=python:3.12-slim
T=l5-final
G=l5-final-g

echo "########## 1. 主控（建 topic，然后等 50s） ##########"
docker run -d --name l5f0 --network "$NET" -v "$W:/w" "$IMG" \
  bash -c "pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_rebalance_final.py 0 50" >/dev/null 2>&1
sleep 8

echo "########## 2. 4 个消费者（间隔 3s，各存活 42s） ##########"
for i in 1 2 3 4; do
  docker run -d --name "l5f$i" --network "$NET" -v "$W:/w" "$IMG" \
    bash -c "pip install -q kafka-python==3.0.11 >/dev/null 2>&1
      python /w/verify_rebalance_final.py $i 42" >/dev/null 2>&1
  echo "  #$i 启动"
  sleep 3
done

echo ""
echo "########## 3. 等待全部收敛（45s） ##########"
sleep 45

echo ""
echo "########## 4. Broker 权威 describe ##########"
docker exec l15-kafka-1 /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 --describe --group "$G" 2>/dev/null \
  | head -12

echo ""
echo "########## 5. 各消费者最终自报 ##########"
for i in 1 2 3 4; do
  docker logs "l5f$i" 2>/dev/null | grep -E 'FINAL#'
done

echo ""
echo "########## 6. 严格判定 ##########"
python3 - <<'PY'
import re, subprocess
out = ""
for i in (1, 2, 3, 4):
    out += subprocess.run(["docker", "logs", f"l5f{i}"],
                          capture_output=True, text=True).stdout
res = re.findall(r"FINAL#(\d+) assignment=\(([^)]*)\) stable=(\w+)", out)
parts, st = [], []
for idx, p, s in res:
    lst = [x.strip() for x in p.split(",") if x.strip()]
    parts.extend(int(x) for x in lst)
    st.append(s == "True")
print(f"  收集到 {len(res)} 个消费者")
for idx, p, s in res:
    print(f"    #{idx}: [{p}] stable={s}")
print(f"  合并: {sorted(parts)}")
ok = (len(parts) == 4) and (len(set(parts)) == 4)
print(f"  严格判定（4个分区、无重复）: {ok}")
print("  ✓ 讲义结论成立" if ok else "  ✗ 讲义需修正")
PY

echo ""
echo "########## 7. 清理 ##########"
for i in 0 1 2 3 4; do docker rm -f "l5f$i" >/dev/null 2>&1; done
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --delete --topic "$T" >/dev/null 2>&1
echo "  已清理"
