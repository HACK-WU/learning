#!/usr/bin/env bash
# 修正：WSL 内必须用 /mnt/d/ 路径，不能用 D:/
BASE="/mnt/d/projects/learning/bk-blueking-72"
echo "########## 核验 8（修正路径）：报告文件存在性 ##########"
for f in 16-分批启动验证方案.md 09-排障速查手册.md 12-WSL内存调优与集群稳定性.md \
         13-配置备份与离线复现档案.md README-验证报告索引.md 21-分批验证总报告.md \
         22-第7批验证报告-监控告警链路.md 23-收尾补遗-探针还原与终态.md \
         24-第8批验证报告-权限与网关异步链路.md 25-部署验收总报告-全8批合并.md; do
  p="$BASE/$f"
  if [ -f "$p" ]; then printf "    %-44s 存在 %4s 行\n" "$f" "$(wc -l < "$p")"
  else printf "    %-44s 缺失!!\n" "$f"; fi
done

echo ""
echo "########## 核验 9：generic 为什么出现两行（是否多容器）##########"
kubectl get deploy -n blueking bk-repo-bkrepo-generic -o json 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
cs=d['spec']['template']['spec']['containers']
print('    容器数:',len(cs))
for c in cs:
    lp=c.get('livenessProbe')
    print('    - %-22s liveness=%s'%(c['name'], ('init=%s fail=%s'%(lp.get('initialDelaySeconds'),lp.get('failureThreshold'))) if lp else '无'))
"

echo ""
echo "########## 核验 10：报告内链接可达性 ##########"
cd "$BASE" || exit 1
grep -oE '\]\([0-9a-zA-Z一-鿿._-]+\.md\)' 25-部署验收总报告-全8批合并.md | tr -d ']()' | sort -u | while read -r l; do
  if [ -f "$BASE/$l" ]; then echo "    OK   $l"; else echo "    断链 $l"; fi
done
