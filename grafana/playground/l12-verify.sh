#!/bin/bash
D=/mnt/d/projects/learning/grafana/stages/4-管得住/lessons/lesson-12-性能、高可用与升级运维.md
echo "=== A组 结构合规 ==="

echo "--- A1 五幕结构 ---"
for k in "第一幕：场景引入" "第二幕：认知冲突" "第三幕：层层揭示" "第四幕：实操验证" "第五幕：体系收束"; do
  if grep -q "$k" "$D"; then echo "  ✅ $k"; else echo "  ❌ 缺 $k"; fi
done

echo "--- A2 课尾三段式 ---"
for k in "## 📌 本课速览" "## 🧭 课程导航" "## 🚀 下一批接力提示词"; do
  if grep -q "$k" "$D"; then echo "  ✅ $k"; else echo "  ❌ 缺 $k"; fi
done

echo "--- A3 三个知识点六要素 ---"
for n in 12.1 12.2 12.3; do
  echo "  [$n]"
  for k in "一句话定义" "直觉建立" "核心原理" "示例演示" "常见误区" "一句话记住"; do
    C=$(awk "/^### $n /,/^### 12\.[23] |^## 第四幕/" "$D" | grep -c "$k")
    if [ "$C" -gt 0 ]; then echo "    ✅ $k ($C)"; else echo "    ❌ 缺 $k"; fi
  done
done

echo "--- A4 类比失效边界 ---"
grep -c "类比失效的边界" "$D" | xargs echo "  出现次数:"

echo
echo "=== B组 数据事实 ==="

echo "--- B1 反斜杠续行检查（课4 P0，必须为0）---"
N=$(grep -c '\\$' "$D")
echo "  代码块外续行数: $N"
if [ "$N" -eq 0 ]; then echo "  ✅ 无续行"; else echo "  ❌ 发现续行，需修"; grep -n '\\$' "$D" | head -10; fi

echo "--- B2 bash 代码块数 ---"
grep -c '^```bash' "$D" | xargs echo "  bash 块:"

echo "--- B3 关键实测数字自洽性 ---"
for num in "0.031880" "4.907415" "983508" "14302396" "0.095895" "719" "731" "91" "e34d89904e5fdabbd35b" "SQLITE_BUSY"; do
  C=$(grep -c "$num" "$D")
  echo "  $num : 出现 $C 次"
done

echo "--- B4 未实测声明 ---"
grep -c "未实测" "$D" | xargs echo "  ⚠️ 未实测标注数:"

echo "--- B5 单机边界标注 ---"
grep -c "单机边界" "$D" | xargs echo "  单机边界标注数:"

echo
echo "=== C组 链接可达性 ==="
python3 - "$D" <<'PYEOF'
import re,sys,os
d=os.path.dirname(sys.argv[1])
txt=open(sys.argv[1],encoding='utf-8').read()
links=re.findall(r'\[([^\]]*)\]\((\.\.?/[^)]+)\)',txt)
print(f"  相对链接总数: {len(links)}")
bad=0
for name,link in links:
    p=os.path.normpath(os.path.join(d,link))
    if os.path.exists(p):
        print(f"  ✅ {name} -> {link}")
    else:
        print(f"  ❌ 死链 {name} -> {link}")
        bad+=1
print(f"  死链数: {bad}")
PYEOF
