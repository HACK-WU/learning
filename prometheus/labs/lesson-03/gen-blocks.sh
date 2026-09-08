set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03

echo "=== 1) 生成 OpenMetrics 输入 ==="
python3 "$BASE/gen-openmetrics.py"
head -5 "$BASE/blocks-input/samples.om"

echo
echo "=== 2) 用 promtool 生成真实 block ==="
rm -rf "$BASE/blocks"
mkdir -p "$BASE/blocks"
docker run --rm \
  -v "$BASE/blocks-input":/in \
  -v "$BASE/blocks":/out \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  tsdb create-blocks-from openmetrics /in/samples.om /out

echo
echo "=== 3) 查看生成的 block 目录 ==="
ls -la "$BASE/blocks"
