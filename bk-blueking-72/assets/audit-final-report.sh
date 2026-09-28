#!/usr/bin/env bash
# 复审：逐条核验 25-部署验收总报告 里的硬数字
NS=blueking
R="D:/projects/learning/bk-blueking-72/25-部署验收总报告-全8批合并.md"

echo "########## 核验 1：节点 3 全 Ready ##########"
kubectl get nodes --no-headers 2>/dev/null | awk '{print "    "$1" "$2}' | tee /tmp/r1.txt
echo "    报告写: 3 个全 Ready | 实测 Ready 数: $(grep -c Ready /tmp/r1.txt)"

echo ""
echo "########## 核验 2：Pod 95 Running / 12 Completed ##########"
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | awk '{printf "    %-12s %s\n",$2,$1}'

echo ""
echo "########## 核验 3：workloads 109/62/47, sts 19, ds 4, cj 7 ##########"
printf "    deploy 总数=%s 在跑=%s 未起=%s\n" \
  "$(kubectl get deploy -n $NS --no-headers 2>/dev/null | wc -l)" \
  "$(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2!="0/0"' | wc -l)" \
  "$(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"' | wc -l)"
printf "    sts=%s ds=%s cj=%s\n" \
  "$(kubectl get sts -n $NS --no-headers 2>/dev/null | wc -l)" \
  "$(kubectl get ds -n $NS --no-headers 2>/dev/null | wc -l)" \
  "$(kubectl get cronjob -n $NS --no-headers 2>/dev/null | wc -l)"

echo ""
echo "########## 核验 4：探针残留 0（报告称有 liveness 容器 80 个）##########"
kubectl get deploy,sts -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); tot=0; bad=0
for it in d['items']:
    for c in (it['spec']['template']['spec'].get('containers') or []):
        if c.get('livenessProbe'):
            tot+=1
            lp=c['livenessProbe']
            if lp.get('initialDelaySeconds')==180 or lp.get('failureThreshold')==12: bad+=1
print('    有 liveness 容器数=%d  残留=%d'%(tot,bad))
"

echo ""
echo "########## 核验 5：kafka 探针原值 init=10 fail=3 ##########"
kubectl get sts -n $NS bk-kafka -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); c=d['spec']['template']['spec']['containers'][0]
lp=c.get('livenessProbe') or {}; rp=c.get('readinessProbe') or {}
print('    kafka liveness : init=%s fail=%s period=%s'%(lp.get('initialDelaySeconds'),lp.get('failureThreshold'),lp.get('periodSeconds')))
print('    kafka readiness: init=%s fail=%s period=%s'%(rp.get('initialDelaySeconds'),rp.get('failureThreshold'),rp.get('periodSeconds')))
"

echo ""
echo "########## 核验 6：bkrepo 探针原值 init=120/60 fail=5 ##########"
kubectl get deploy -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
for it in d['items']:
    n=it['metadata']['name']
    if not n.startswith('bk-repo-bkrepo'): continue
    for c in it['spec']['template']['spec']['containers']:
        lp=c.get('livenessProbe')
        if lp: print('    %-28s init=%s fail=%s'%(n,lp.get('initialDelaySeconds'),lp.get('failureThreshold')))
        else:  print('    %-28s 无 livenessProbe'%n)
"

echo ""
echo "########## 核验 7：47 个未起 deploy 的账目 ##########"
kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"{print $1}' > /tmp/z.txt
for p in bk-repo- bk-nodeman-backend- bk-monitor-alarm- bk-monitor-web-worker-resource bkiam-saas- bk-apigateway-dashboard-; do
  printf "    %-34s %s\n" "$p" "$(grep -c "^$p" /tmp/z.txt)"
done
printf "    %-34s %s\n" "合计(去重)" "$(sort -u /tmp/z.txt | wc -l)"

echo ""
echo "########## 核验 8：报告文件存在且非空 ##########"
for f in 16-分批启动验证方案.md 09-排障速查手册.md 12-WSL内存调优与集群稳定性.md 13-配置备份与离线复现档案.md README-验证报告索引.md; do
  p="D:/projects/learning/bk-blueking-72/$f"
  if [ -f "$p" ]; then printf "    %-42s 存在 %s 行\n" "$f" "$(wc -l < "$p")"; else printf "    %-42s 缺失!!\n" "$f"; fi
done
