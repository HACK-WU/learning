#!/usr/bin/env bash
# 课 4 · 4.1 前端代码层验证（路径已修正）
set -u

MOD=/usr/share/grafana/data/plugins-bundled/prometheus/module.js
DIR=/usr/share/grafana/data/plugins-bundled/prometheus

echo "=========================================================="
echo " 4.1 前端代码层验证：Explain 的真实身份"
echo "=========================================================="

echo ""
echo "--- [0] 插件文件与版本 ---"
docker exec grafana-lab ls -la $MOD | awk '{print "  "$5" bytes  "$9}'
docker exec grafana-lab cat $DIR/plugin.json 2>/dev/null | python3 -c "
import sys,json
d=json.load(sys.stdin)
print('  plugin.json: id=%s version=%s type=%s'%(d.get('id'),d.get('info',{}).get('version'),d.get('type')))
" 2>&1 | head -3

echo ""
echo "--- [1] 搜 Explain 相关字符串 ---"
echo "  不区分大小写的 explain 家族："
docker exec grafana-lab grep -o -i 'explain[A-Za-z]*' $MOD 2>/dev/null | sort | uniq -c | sort -rn | head -12

echo ""
echo "--- [2] editorMode 的合法取值 ---"
echo "  搜 \"code\" / \"builder\" / \"explain\" 字面量："
docker exec grafana-lab grep -o '"\(code\|builder\|explain\)"' $MOD 2>/dev/null | sort | uniq -c | sort -rn

echo ""
echo "--- [3] 关键结构：是 Tab 还是 Toggle ---"
echo "  RadioButtonGroup（tab 形态常用）："
printf "    %s 次\n" "$(docker exec grafana-lab grep -o 'RadioButtonGroup' $MOD 2>/dev/null | wc -l)"
echo "  Switch / Toggle："
printf "    Switch %s 次 / Toggle %s 次\n" \
  "$(docker exec grafana-lab grep -o 'Switch' $MOD 2>/dev/null | wc -l)" \
  "$(docker exec grafana-lab grep -o 'Toggle' $MOD 2>/dev/null | wc -l)"

echo ""
echo "--- [4] 搜 mode 相关的 label（Builder/Code/Explain 显示名） ---"
docker exec grafana-lab grep -o 'label:"[A-Za-z]*"' $MOD 2>/dev/null | sort | uniq -c | sort -rn | head -12

echo ""
echo "--- [5] 搜 editorMode 字段本身 ---"
printf "  editorMode 出现 %s 次\n" "$(docker exec grafana-lab grep -o 'editorMode' $MOD 2>/dev/null | wc -l)"
echo "  上下文片段（前 3 处，每处取 120 字符）："
docker exec grafana-lab grep -o '.\{60\}editorMode.\{60\}' $MOD 2>/dev/null | head -3

echo ""
echo "--- [6] 搜 Builder 的核心数据结构（visualQuery / operations） ---"
for kw in 'visualQuery' 'operations' 'PromQueryBuilder' 'EXPLAIN'; do
  printf "  %-18s %s 次\n" "$kw" "$(docker exec grafana-lab grep -o "$kw" $MOD 2>/dev/null | wc -l)"
done

echo ""
echo "--- [7] 结论用的对照：Grafana 主程序里的同名概念 ---"
echo "  在主程序 build 目录搜 editorMode（确认是通用概念而非 Prometheus 特有）："
docker exec grafana-lab bash -c "grep -l 'editorMode' /usr/share/grafana/public/build/*.js 2>/dev/null | head -5"

echo ""
echo "=========================================================="
