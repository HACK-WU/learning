#!/usr/bin/env bash
D=/mnt/d/projects/learning/prometheus
L=$D/stages/3-规模化与生态/lessons
PASS=0; FAIL=0
ck(){ if [ "$2" = "$3" ]; then echo "PASS  $1"; PASS=$((PASS+1)); else echo "FAIL  $1 (expect=$3 actual=$2)"; FAIL=$((FAIL+1)); fi; }

echo "===== A. 数据底稿 vs 讲义 一致性 ====="
R=$D/labs/lesson-09/RR-DATA.md
G=$L/lesson-09-长期存储选型.md
G7=$L/lesson-07-远程读写与Agent模式.md

for n in "18 032" "5 608" "57 417" "31 791" "116 642" "124 071" "359 572" "384 243"; do
  c=$(grep -c "$n" $G); ck "讲义含体积数 [$n]" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
done
for n in 42.53 50.19 43.09 52.56; do
  c=$(grep -c "$n" $G); ck "讲义含内存数 $n" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
done

echo ""
echo "===== B. 课 7 更正已落地 ====="
c=$(grep -c "STREAMED_CHUNKS" $G7); ck "课7仍保留更正说明(说明该模式不存在)" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
c=$(grep -c "两种 + 一个分帧参数" $G7); ck "课7含两种+分帧参数表述" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
c=$(grep -c "更正说明" $G7); ck "课7含更正说明块" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"

echo ""
echo "===== C. 课 9 挂账项状态 ====="
c=$(grep -c "已于 2026-09-07 补做完成" $G); ck "课9标注挂账项已补做" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
c=$(grep -c "知识点 4" $G); ck "课9新增知识点4" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"

echo ""
echo "===== D. 链接可达 ====="
check_link(){
  f=$1; rel=$2
  dir=$(dirname "$f")
  if [ -e "$dir/$rel" ]; then echo "PASS  link $rel"; PASS=$((PASS+1));
  else echo "FAIL  link $rel in $f"; FAIL=$((FAIL+1)); fi
}
check_link "$G" "../../../labs/lesson-09/RR-DATA.md"
check_link "$G7" "../../../labs/lesson-09/RR-DATA.md"

echo ""
echo "===== E. 无残留错误表述 ====="
# 课9正文不应再出现"三种模式"作为事实陈述（更正说明除外不检查课7）
# 允许出现 1 处：已划除的历史挂账表述（~~...~~）；不应再出现未划除的
c=$(grep -c "三种模式的分模式性能差异" $G)
ck "课9仅保留已划除的旧挂账表述(<=1)" "$([ $c -le 1 ] && echo yes || echo no)" "yes"
c=$(grep -c "知识点 4：remote read" $G); ck "课9含知识点4标题" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"
c=$(grep -c "流式赢内存、不赢带宽" $G); ck "课9含一句话记住" "$([ $c -ge 1 ] && echo yes || echo no)" "yes"

echo ""
echo "=============================="
echo "PASS=$PASS  FAIL=$FAIL"
