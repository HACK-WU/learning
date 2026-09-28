#!/usr/bin/env bash
BASE="/mnt/d/projects/learning/bk-blueking-72"
ST="$BASE/stages/2-存储层攻坚"
cd "$BASE" || exit 1

echo "=== 修正 stages 下文档的相对路径层级 ==="
# lessons/ 下的文件：lessons -> 2-存储层攻坚 -> stages -> 根，需 ../../../
for f in "$ST"/lessons/*.md; do
  sed -i \
    -e 's#(\.\./\.\./02-课程目录\.md)#(../../../02-课程目录.md)#g' \
    -e 's#(\.\./\.\./08-实战经验\.md)#(../../../08-实战经验.md)#g' \
    -e 's#(\.\./\.\./09-排障速查手册\.md)#(../../../09-排障速查手册.md)#g' \
    -e 's#(\./assets/#(../assets/#g' \
    "$f"
  echo "    已修 lessons: $(basename "$f")"
done

# overview.md：2-存储层攻坚 -> stages -> 根，需 ../../
for f in "$ST"/overview.md; do
  [ -f "$f" ] && sed -i \
    -e 's#(\.\./\.\./08-实战经验\.md)#(../../08-实战经验.md)#g' \
    -e 's#(\.\./\.\./09-排障速查手册\.md)#(../../09-排障速查手册.md)#g' \
    "$f" && echo "    已修: overview.md"
done

echo ""
echo "=== 非链接的裸文本 '未落盘，见 00-学习档案.md' 改为可跳转 ==="
for f in "$ST"/lessons/*.md; do
  sed -i 's#(未落盘，见 00-学习档案\.md)#(../../../00-学习档案.md)#g' "$f"
done
echo "    已处理"

echo ""
echo "=== 复检：stages 下链接 ==="
python3 - "$BASE" <<'PY'
import re,os,sys
base=sys.argv[1]
files=[os.path.join(r,f) for r,d,fs in os.walk(os.path.join(base,'stages')) for f in fs if f.endswith('.md')]
total=bad=0
for p in files:
    txt=open(p,encoding='utf-8').read()
    for l in re.findall(r'\]\(([^)]+)\)',txt):
        if l.startswith(('http','#','mailto')): continue
        t=l.split('#')[0]
        if not t: continue
        total+=1
        if not os.path.exists(os.path.normpath(os.path.join(os.path.dirname(p),t))):
            bad+=1; print("    断链: %s -> %s"%(os.path.relpath(p,base),l))
print("    stages 链接 %d 条，断链 %d"%(total,bad))
PY
