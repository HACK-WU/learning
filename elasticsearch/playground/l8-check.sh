#!/bin/bash
F="/mnt/d/projects/learning/elasticsearch/stages/3-查询与聚合/lessons/lesson-08-聚合不做搜索做统计.md"

echo "=== 1. 文件基本信息 ==="
echo "行数: $(wc -l < "$F")"
echo "字节: $(wc -c < "$F")"

echo ""
echo "=== 2. 编码检查（应为 UTF-8，无 BOM）==="
python -c "
import sys
p=r'D:\projects\learning\elasticsearch\stages\3-查询与聚合\lessons\lesson-08-聚合不做搜索做统计.md'
b=open(p,'rb').read()
print('  前3字节:',b[:3])
print('  BOM:', 'YES(需去除)' if b[:3]==b'\xef\xbb\xbf' else 'NO(正确)')
try:
    t=b.decode('utf-8'); print('  UTF-8解码: OK')
except Exception as e:
    print('  UTF-8解码失败:',e)
print('  乱码检测:', '有' if b'\xef\xbf\xbd' in b else '无')
"

echo ""
echo "=== 3. 三个知识点齐全 ==="
for k in "知识点 1：桶聚合与指标聚合" "知识点 2：子聚合与管道聚合" "知识点 3：ES|QL 入门"; do
  c=$(grep -c "$k" "$F")
  echo "  [$k] 出现 $c 次"
done

echo ""
echo "=== 4. 五幕结构 ==="
grep -n "^## 开场\|^# 知识点\|^# 综合实战\|^# 本课总结\|^## 下一课预告" "$F" | head -12

echo ""
echo "=== 5. 实测数字一致性（抽查）==="
for n in "190057" "80390" "64179" "45488" "8849.0" "10048.75" "16.7" "10398"; do
  c=$(grep -c "$n" "$F")
  echo "  [$n] 出现 $c 次"
done

echo ""
echo "=== 6. 踩坑表格完整性 ==="
grep -c "Fielddata is disabled" "$F" | xargs echo "  Fielddata报错:"
grep -c "must have a histogram" "$F" | xargs echo "  cumulative_sum报错:"
grep -c "No aggregation found for path" "$F" | xargs echo "  bucket_script报错:"
grep -c "token recognition error" "$F" | xargs echo "  ES|QL中文报错:"

echo ""
echo "=== 7. 诚实标注检查 ==="
grep -c "未实测\|诚实标注\|未测" "$F" | xargs echo "  标注数量:"

echo ""
echo "=== 8. 代码块配对检查 ==="
python -c "
import re
p=r'D:\projects\learning\elasticsearch\stages\3-查询与聚合\lessons\lesson-08-聚合不做搜索做统计.md'
t=open(p,encoding='utf-8').read()
n=len(re.findall(r'^\`\`\`',t,re.M))
print('  围栏总数:',n,'→','配对OK' if n%2==0 else '不配对!')
"

echo ""
echo "=== 9. SVG 引用检查 ==="
grep -n "assets/agg-structure.svg" "$F"

echo ""
echo "=== 10. 呼应前序课程 ==="
grep -c "课 5\|课 4\|课 6\|课 7" "$F" | xargs echo "  呼应提及:"

echo ""
echo "########## DONE-L8-CHECK ##########"
