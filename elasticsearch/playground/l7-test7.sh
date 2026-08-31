#!/bin/bash
ES="https://localhost:9200"
PW="ESlearn2026"
C="curl.exe -s -k -u elastic:$PW"

echo "########## 诊断 function_score 手算与实测的差异 ##########"
echo "=== 对 doc6 用 function_score 跑 explain ==="
$C -X POST "$ES/l7_news/_explain/6" -H "Content-Type: application/json" -d '{
  "query":{"function_score":{
    "query":{"match":{"content":"苹果"}},
    "field_value_factor":{"field":"views","modifier":"log1p","factor":0.5},
    "boost_mode":"multiply"}}}' > /tmp/fs.json
python -c "
import json
d=json.load(open('/tmp/fs.json'))
if 'error' in d: print('  ERROR:',json.dumps(d['error'],ensure_ascii=False)[:400])
else:
    def walk(exp,depth=0):
        pad='  '*(depth+2)
        v=exp.get('value'); vs=round(v,6) if isinstance(v,(int,float)) else v
        print(f\"{pad}{exp.get('description')}  →  {vs}\")
        for c in exp.get('details',[]): walk(c,depth+1)
    walk(d['explanation'])"
echo ""

echo "=== 计算：实测基础分 × factor 是否等于实测最终分 ==="
python -c "
import json,math
d=json.load(open('/tmp/fs.json'))
final=d['explanation']['value']
# 找基础分
base=d['explanation']['details'][0]['value'] if d['explanation'].get('details') else None
print('  最终分:',final)
if base is not None:
    print('  基础分:',base)
    fac=1+0.5*math.log1p(6000)
    print('  factor = 1 + 0.5*log1p(6000) =',round(fac,6))
    print('  基础分 × factor =',round(base*fac,6))
    print('  比值 最终/(基础*factor) =',round(final/(base*fac),6))
"
echo ""

echo "=== 验证：把所有文档的 (基础分, 最终分, 比值) 列出来 ==="
for id in 6 1 4 5; do
  $C -X POST "$ES/l7_news/_explain/$id" -H "Content-Type: application/json" -d '{
    "query":{"function_score":{
      "query":{"match":{"content":"苹果"}},
      "field_value_factor":{"field":"views","modifier":"log1p","factor":0.5},
      "boost_mode":"multiply"}}}' > /tmp/fs_$id.json
  $C -X POST "$ES/l7_news/_explain/$id" -H "Content-Type: application/json" -d '{
    "query":{"match":{"content":"苹果"}}}' > /tmp/base_$id.json
done
python -c "
import json,math
views={'6':6000,'1':5000,'4':3000,'5':20000}
print('  doc  原match分   function_score分   factor      比值')
for i in ['6','1','4','5']:
    b=json.load(open('/tmp/base_%s.json'%i))['explanation']['value']
    f=json.load(open('/tmp/fs_%s.json'%i))['explanation']['value']
    fac=1+0.5*math.log1p(views[i])
    print('  %-4s %-10s %-17s %-11s %s'%(i,round(b,4),round(f,4),round(fac,4),round(f/(b*fac),6)))
"
echo ""
echo "=== 结论：如果比值恒定，说明只是乘了个常数（归一化），排序不变 ==="
echo "########## DONE-L7-7 ##########"
