set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03

echo "########## 步骤 4（去掉 head 管道，避免 SIGPIPE） ##########"
rm -rf "$BASE/vblocks" && mkdir -p "$BASE/vblocks"

docker run --rm \
  -v "$BASE/blocks-input":/in -v "$BASE/vblocks":/out \
  --entrypoint /bin/promtool prom/prometheus:v3.14.0 \
  tsdb create-blocks-from openmetrics /in/samples.om /out > "$BASE/vblocks-out.txt" 2>&1

echo "=== block 数量（应为 61） ==="
ls "$BASE/vblocks" | wc -l

echo "=== 输出前 3 行 ==="
head -3 "$BASE/vblocks-out.txt"
