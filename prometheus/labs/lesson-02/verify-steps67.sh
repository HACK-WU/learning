set -x
BASE=/mnt/d/projects/learning/prometheus/labs/lesson-02

echo "########## 步骤 6：SD 热刷新（讲义原样） ##########"
cd "$BASE"
python3 -c "
import json
p='sd/targets.json'
d=json.load(open(p))
d.append({'targets':['app-payment-2:8080'],'labels':{'__meta_service':'payment','__meta_env':'prod','__meta_team':'pay'}})
json.dump(d, open(p,'w'), ensure_ascii=False, indent=2)
print('已追加 app-payment-2')"

sleep 20
curl -s 'http://localhost:9096/api/v1/targets?state=active' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
print('  ', sorted(t['labels']['instance'] for t in d['data']['activeTargets'] if t['labels']['job']=='file-sd-demo'))"

echo
echo "########## 步骤 7：目标消失 vs 抓取失败（讲义原样） ##########"
docker stop app-order-1
sleep 20
curl -s 'http://localhost:9096/api/v1/targets' \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for t in d['data']['activeTargets']:
    if 'app-order-1' in t['labels'].get('instance',''):
        print('  job=%-20s health=%s' % (t['labels']['job'], t['health']))"

echo
echo "########## 恢复 ##########"
docker start app-order-1
sleep 5
