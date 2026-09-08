set -x
echo "=== 完整日志（最新 60 行） ==="
docker logs l3-compact 2>&1 | tail -60
