set -x

echo "########## 步骤 3：服务发现输出契约 ##########"
curl -s 'http://localhost:9097/api/v1/targets?state=active' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    if t['labels']['job']=='file-sd-demo':
        print(t['scrapeUrl'], json.dumps(t['labels'], ensure_ascii=False))"

echo "########## 步骤 3b：dropped target ##########"
curl -s 'http://localhost:9097/api/v1/targets?state=dropped' | python3 -m json.tool | head -20

echo "########## 步骤 4：metric_relabel ##########"
for job in metric-relabel-demo honor-normal; do
  curl -s "http://localhost:9097/api/v1/query?query=app_debug_user_id{job=\"$job\"}" \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)['data']['result']
print('  $job ->', ('有 %d 条' % len(d)) if d else '无结果（已被 drop）')"
done

curl -s 'http://localhost:9097/api/v1/query?query=app_build_info{job="metric-relabel-demo"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print('  ', json.dumps(r['metric'], ensure_ascii=False, sort_keys=True))"

echo "########## 步骤 5：honor_labels ##########"
docker exec v-prom wget -qO- http://v-conflict:8080/metrics | head -8

curl -s 'http://localhost:9097/api/v1/query?query=app_build_info{job="honor-false"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print(json.dumps(r['metric'], ensure_ascii=False, sort_keys=True))"

echo "--- honor-true 按配置 job 查 ---"
curl -s 'http://localhost:9097/api/v1/query?query=app_build_info{job="honor-true"}' \
  | python3 -c "import json,sys; d=json.load(sys.stdin)['data']['result']; print('  ', d if d else '空结果')"

echo "--- honor-true 按自带 instance 查 ---"
curl -s 'http://localhost:9097/api/v1/query?query=app_build_info{instance=\"i-am-the-real-instance:9999\"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print('  ', json.dumps(r['metric'], ensure_ascii=False, sort_keys=True))"

echo "--- up 不受影响 ---"
curl -s 'http://localhost:9097/api/v1/query?query=up{job=~\"honor-.*\"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    m=r['metric']
    print('  job=%-14s instance=%-24s -> %s' % (m.get('job'), m.get('instance'), r['value'][1]))"
