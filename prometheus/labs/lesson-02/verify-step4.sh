set -x

echo "=== 复现讲义步骤4原写法（反斜杠转义引号） ==="
for job in metric-relabel-demo honor-normal; do
  curl -s "http://localhost:9097/api/v1/query?query=app_debug_user_id{job=\"$job\"}" \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']['result']
print('  $job ->', ('有 %d 条' % len(d)) if d else '无结果（已被 drop）')"
done

echo "=== 上面若报 KeyError，说明 URL 里的反斜杠没被吃掉 ==="
echo "=== 先看看裸 curl 到底返回了什么 ==="
curl -s 'http://localhost:9097/api/v1/query?query=app_debug_user_id' | head -c 300
