echo "########## 步骤 4（修复后） ##########"
for job in metric-relabel-demo honor-normal; do
  curl -s -G 'http://localhost:9096/api/v1/query' \
    --data-urlencode "query=app_debug_user_id{job=\"$job\"}" \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']['result']
print('  $job ->', ('有 %d 条' % len(d)) if d else '无结果（已被 drop）')"
done

echo "--- scraped_by ---"
curl -s -G 'http://localhost:9096/api/v1/query' \
  --data-urlencode 'query=app_build_info{job="metric-relabel-demo"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print('  ', json.dumps(r['metric'], ensure_ascii=False, sort_keys=True))"

echo
echo "########## 步骤 5 honor-false（修复后） ##########"
curl -s -G 'http://localhost:9096/api/v1/query' \
  --data-urlencode 'query=app_build_info{job="honor-false"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print(json.dumps(r['metric'], ensure_ascii=False, sort_keys=True))"

echo
echo "########## 步骤 5 honor-true 按 job 查（修复后） ##########"
curl -s -G 'http://localhost:9096/api/v1/query' \
  --data-urlencode 'query=app_build_info{job="honor-true"}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin)['data']['result']; print('  ', d if d else '空结果')"

echo
echo "########## 步骤 5 honor-true 按自带 instance 查（修复后） ##########"
curl -s -G 'http://localhost:9096/api/v1/query' \
  --data-urlencode 'query=app_build_info{instance="i-am-the-real-instance:9999"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print('  ', json.dumps(r['metric'], ensure_ascii=False, sort_keys=True))"

echo
echo "########## 步骤 5 up（修复后） ##########"
curl -s -G 'http://localhost:9096/api/v1/query' \
  --data-urlencode 'query=up{job=~"honor-.*"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    m=r['metric']
    print('  job=%-14s instance=%-24s -> %s' % (m.get('job'), m.get('instance'), r['value'][1]))"
