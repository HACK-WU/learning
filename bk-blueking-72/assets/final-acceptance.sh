#!/usr/bin/env bash
NS=blueking

echo "############ 1. 节点 ############"
kubectl get nodes --no-headers 2>/dev/null | awk '{printf "    %-28s %-8s %s\n",$1,$2,$4}'

echo ""
echo "############ 2. Pod 总况 ############"
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '{print $3}' | sort | uniq -c | sort -rn | awk '{printf "    %-14s %s\n",$2,$1}'
echo "    ---- 异常 Pod（非 Running/Completed）----"
kubectl get pods -n $NS --no-headers 2>/dev/null | awk '$3!="Running"&&$3!="Completed"{print "    "$1" "$3}' | head -20
echo "    [空 = 无异常]"

echo ""
echo "############ 3. workloads 统计 ############"
printf "    deploy 总数   : %s\n" "$(kubectl get deploy -n $NS --no-headers 2>/dev/null | wc -l)"
printf "    deploy 在跑   : %s\n" "$(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2!="0/0"' | wc -l)"
printf "    deploy 未起   : %s\n" "$(kubectl get deploy -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"' | wc -l)"
printf "    sts    总数   : %s\n" "$(kubectl get sts -n $NS --no-headers 2>/dev/null | wc -l)"
printf "    sts    未起   : %s\n" "$(kubectl get sts -n $NS --no-headers 2>/dev/null | awk '$2=="0/0"' | wc -l)"
printf "    ds     总数   : %s\n" "$(kubectl get ds -n $NS --no-headers 2>/dev/null | wc -l)"
printf "    cronjob 总数  : %s\n" "$(kubectl get cronjob -n $NS --no-headers 2>/dev/null | wc -l)"

echo ""
echo "############ 4. 探针残留（放宽值 init=180 或 fail=12）############"
kubectl get deploy,sts -n $NS -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin); bad=0; tot=0
for it in d['items']:
    for c in (it['spec']['template']['spec'].get('containers') or []):
        lp=c.get('livenessProbe') or {}
        if lp:
            tot+=1
            if lp.get('initialDelaySeconds')==180 or lp.get('failureThreshold')==12:
                bad+=1; print('    [残留]',it['metadata']['name'],lp)
print('    有 liveness 的容器数: %d   残留: %d'%(tot,bad))
"

echo ""
echo "############ 5. 内存 ############"
free -g | sed -n '2p' | awk '{printf "    used=%sG  avail=%sG  total=%sG\n",$3,$7,$2}'

echo ""
echo "############ 6. 页面入口 ############"
for d in paas.example.com bkpaas.paas.example.com bkiam.paas.example.com bkuser.paas.example.com apigw.paas.example.com bkmonitor.paas.example.com bknodeman.paas.example.com bkrepo.paas.example.com; do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 12 "http://$d/" 2>/dev/null)
  printf "    %-30s %s\n" "$d" "${c:-000}"
done

echo ""
echo "############ 7. cronjob 最近执行 ############"
kubectl get jobs -n $NS --no-headers 2>/dev/null | awk '{print "    "$1" "$2}' | head -8
