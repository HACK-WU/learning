echo "########## 步骤 3（讲义原样） ##########"
curl -s 'http://localhost:9096/api/v1/targets?state=active' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    if t['labels']['job']=='file-sd-demo':
        print(t['scrapeUrl'], json.dumps(t['labels'], ensure_ascii=False))"

echo
echo "########## 步骤 5 honor-false（讲义原样：反斜杠转义） ##########"
curl -s 'http://localhost:9096/api/v1/query?query=app_build_info{job=\"honor-false\"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print(json.dumps(r['metric'], ensure_ascii=False, sort_keys=True))"

echo
echo "########## 步骤 5 honor-true 按自带 instance 查（讲义原样） ##########"
curl -s 'http://localhost:9096/api/v1/query?query=app_build_info{instance=\"i-am-the-real-instance:9999\"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    print('  ', json.dumps(r['metric'], ensure_ascii=False, sort_keys=True))"

echo
echo "########## 步骤 5 up（讲义原样） ##########"
curl -s 'http://localhost:9096/api/v1/query?query=up{job=~\"honor-.*\"}' \
  | python3 -c "
import json,sys
for r in json.load(sys.stdin)['data']['result']:
    m=r['metric']
    print('  job=%-14s instance=%-24s -> %s' % (m.get('job'), m.get('instance'), r['value'][1]))"
