set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
NET=v3-net

echo "########## 步骤 4：生成真实 block ##########"
cd "$BASE"
python3 "$BASE/gen-openmetrics.py"
cp /tmp/samples.om "$BASE/blocks-input/samples.om" 2>/dev/null || true
cp "$BASE/blocks-input/samples.om" /tmp/samples.om 2>/dev/null || true
ls -la "$BASE/blocks-input/samples.om"

rm -rf "$BASE/vblocks" && mkdir -p "$BASE/vblocks"
docker run --rm \
  -v "$BASE/blocks-input":/in -v "$BASE/vblocks":/out \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  tsdb create-blocks-from openmetrics /in/samples.om /out 2>&1 | head -4

echo "=== block 数量 ==="
ls "$BASE/vblocks" | wc -l

echo "=== 首个 block 结构 ==="
FIRST=$(ls "$BASE/vblocks" | head -1)
find "$BASE/vblocks/$FIRST" -type f | sort
cat "$BASE/vblocks/$FIRST/meta.json"
