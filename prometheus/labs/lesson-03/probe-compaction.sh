set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-03

echo "=== 合并后 block 总数 ==="
ls "$BASE/data-compact" | wc -l

echo
echo "=== 找出被合并过的 block（level > 1） ==="
cd "$BASE/data-compact"
for d in */; do
  d=${d%/}
  if [ -f "$d/meta.json" ]; then
    lvl=$(python3 -c "import json;print(json.load(open('$d/meta.json'))['compaction']['level'])" 2>/dev/null)
    nsrc=$(python3 -c "import json;print(len(json.load(open('$d/meta.json'))['compaction']['sources']))" 2>/dev/null)
    if [ "$lvl" != "1" ]; then
      echo "  $d  level=$lvl  sources=$nsrc  samples=$(python3 -c "import json;print(json.load(open('$d/meta.json'))['stats']['numSamples'])")"
    fi
  fi
done

echo
echo "=== 只看 level>=2 的 block 的完整 meta.json（取第一个） ==="
for d in */; do
  d=${d%/}
  if [ -f "$d/meta.json" ]; then
    lvl=$(python3 -c "import json;print(json.load(open('$d/meta.json'))['compaction']['level'])" 2>/dev/null)
    if [ "$lvl" != "1" ]; then
      echo "--- $d ---"
      cat "$d/meta.json"
      break
    fi
  fi
done

echo
echo "=== 前 3 个 level=1 的 block（未参与合并的） ==="
for d in */; do
  d=${d%/}
  if [ -f "$d/meta.json" ]; then
    lvl=$(python3 -c "import json;print(json.load(open('$d/meta.json'))['compaction']['level'])" 2>/dev/null)
    if [ "$lvl" = "1" ]; then
      echo "  $d  level=$lvl"
    fi
  fi
done
