#!/bin/bash
# 课 5 权威核验 v2：等到真正收敛
set -u
NET=stage6-observability_kafka-net
W=/mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
IMG=python:3.12-slim
T=l5-v2

for i in 0 1 2 3 4; do docker rm -f "l5w$i" >/dev/null 2>&1; done

echo "########## 1. 主控建 topic ##########"
docker run -d --name l5w0 --network "$NET" -v "$W:/w" "$IMG" \
  bash -c "pip install -q kafka-python==3.0.11 >/dev/null 2>&1
    python /w/verify_rebalance_v2.py 0 90" >/dev/null 2>&1
sleep 10

echo "########## 2. 4 个消费者（间隔 2s，各最多 80s） ##########"
for i in 1 2 3 4; do
  docker run -d --name "l5w$i" --network "$NET" -v "$W:/w" "$IMG" \
    bash -c "pip install -q kafka-python==3.0.11 >/dev/null 2>&1
      python /w/verify_rebalance_v2.py $i 80" >/dev/null 2>&1
  echo "  #$i 启动"
  sleep 2
done

echo ""
echo "########## 3. 等收敛（最多 85s） ##########"
for w in $(seq 1 17); do
  sleep 5
  done_n=$(for i in 1 2 3 4; do docker logs "l5w$i" 2>/dev/null | grep -c 'FINAL#'; done | paste -sd+ 2>/dev/null | bc 2>/dev/null || echo 0)
  if [ "$done_n" = "4" ]; then echo "  全部完成（${w}0s）"; break; fi
done

echo ""
echo "########## 4. 各消费者最终结果 ##########"
for i in 1 2 3 4; do
  docker logs "l5w$i" 2>/dev/null | grep -E 'FINAL#'
done

echo ""
echo "########## 5. 收敛轨迹（看中间态→稳态） ##########"
for i in 1 2 3 4; do
  docker logs "l5w$i" 2>/dev/null | grep -E 'TRACE#'
done

echo ""
echo "########## 6. 严格判定 ##########"
python3 - <<'PY'
import re, subprocess
out = ""
for i in (1, 2, 3, 4):
    out += subprocess.run(["docker", "logs", f"l5w{i}"],
                          capture_output=True, text=True).stdout
res = re.findall(r"FINAL#(\d+) assignment=\(([^)]*)\) converged=(\w+)", out)
parts, conv = [], []
for idx, p, cv in res:
    lst = [x.strip() for x in p.split(",") if x.strip()]
    parts.extend(int(x) for x in lst)
    conv.append(cv == "True")
print(f"  收集 {len(res)} 个消费者:")
for idx, p, cv in res:
    print(f"    #{idx}: [{p}] converged={cv}")
print(f"  合并分区: {sorted(parts)}")
ok = (len(parts) == 4) and (len(set(parts)) == 4)
print(f"  严格判定（恰好4分区且无重复）: {ok}")
print("  ✓ 讲义结论成立：4 分区均分、零重叠" if ok else "  ✗ 仍未收敛")
PY

echo ""
echo "########## 7. 清理 ##########"
for i in 0 1 2 3 4; do docker rm -f "l5w$i" >/dev/null 2>&1; done
docker exec l15-kafka-1 /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server localhost:9092 --delete --topic "$T" >/dev/null 2>&1
echo "  已清理"
