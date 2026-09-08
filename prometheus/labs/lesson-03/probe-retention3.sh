set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03
cd "$BASE/data-ret"

echo "=== 存活的 5 个 block ==="
for d in */; do
  d=${d%/}
  [ -f "$d/meta.json" ] || continue
  python3 -c "
import json
m=json.load(open('$d/meta.json'))
print('  %s  level=%d  minTime=%d  maxTime=%d  samples=%d'
      % ('$d', m['compaction']['level'], m['minTime']//1000, m['maxTime']//1000, m['stats']['numSamples']))
"
done

echo
echo "=== 删除分界对照 ==="
docker logs l3-ret 2>&1 | grep -iE 'retention updated' | head -3

echo
echo "=== 结论验证：被删的都是 maxTime 早于保留边界的整块 ==="
echo "存活 block 的 maxTime（秒）："
for d in */; do
  d=${d%/}
  [ -f "$d/meta.json" ] || continue
  python3 -c "import json;print('  ', json.load(open('$d/meta.json'))['maxTime']//1000000)"
done
