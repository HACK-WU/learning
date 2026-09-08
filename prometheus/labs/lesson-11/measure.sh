#!/usr/bin/env bash
# 用法: measure.sh <N_SERIES> <VAL_LEN> <PORT> <SAMPLES>
set -e
D=/mnt/d/projects/learning/prometheus/labs/lesson-11
NET=l11cnet
N=${1:-10000}; VL=${2:-12}; PORT=${3:-19451}; NSAMP=${4:-5}

docker rm -f l11c-prom >/dev/null 2>&1 || true
docker rm -f l11c-app  >/dev/null 2>&1 || true
rm -rf $D/data; mkdir -p $D/data
LABELS=${LABELS:-1}

docker run -d --name l11c-app --network $NET \
  -e N_SERIES=$N -e VAL_LEN=$VL -e LABELS=$LABELS l11c-app >/dev/null
sleep 2
docker run -d --name l11c-prom --network $NET -p $PORT:9090 \
  -v $D/prometheus-l11.yml:/etc/prometheus/prometheus.yml:ro \
  -v $D/data:/prometheus \
  prom/prometheus:v3.14.0 \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=2h \
  --web.enable-lifecycle --web.enable-admin-api >/dev/null

READY=0
for i in $(seq 1 60); do
  curl -sf "http://localhost:$PORT/-/ready" >/dev/null 2>&1 && { READY=1; break; }; sleep 1
done
if [ $READY -eq 0 ]; then echo "NOT_READY|0|0|0|0|0"; docker logs l11c-prom 2>&1|tail -5; exit 1; fi

# 等 4 次抓取（30s interval）确保稳态
sleep 130

# 内存测量：该镜像不暴露 process_resident_memory_bytes（已查证），
# 改用 cgroup v2 memory.current（RSS 口径，比 docker stats 更准）
mem_cgroup() {
  docker exec l11c-prom cat /sys/fs/cgroup/memory.current 2>/dev/null || echo 0
}

python3 - "$PORT" "$NSAMP" <<'PY'
import sys, time, urllib.request, json, statistics, subprocess
port, n = sys.argv[1], int(sys.argv[2])
vals=[]
for _ in range(n):
    try:
        out = subprocess.run(
            ["docker","exec","l11c-prom","cat","/sys/fs/cgroup/memory.current"],
            capture_output=True, text=True, timeout=15)
        v = int(out.stdout.strip())
        if v > 0: vals.append(v)
    except Exception as e:
        print(f"ERR|{e}|0|0|0|0"); sys.exit(1)
    time.sleep(5)
if not vals:
    print("ERR|no mem samples|0|0|0|0"); sys.exit(1)
med=statistics.median(vals)
try:
    u=f"http://localhost:{port}/api/v1/status/tsdb"
    d=json.load(urllib.request.urlopen(u,timeout=15))['data']
    ns=d['headStats']['numSeries']; nlp=d['headStats']['numLabelPairs']
except Exception:
    ns=-1; nlp=-1
print(f"{ns}|{nlp}|{med/1024/1024:.2f}|{min(vals)/1024/1024:.2f}|{max(vals)/1024/1024:.2f}")
PY
