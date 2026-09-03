#!/bin/bash
# 核查四份收尾产物的同源数字一致性（B1/B4：防止双源漂移）
cd /mnt/d/projects/learning/surrealdb || exit 1

echo "===== 关键实测数字在四份产物中的出现情况 ====="
printf "%-14s %6s %6s %6s %8s\n" "数字" "08" "09" "10" "final"
printf "%-14s %6s %6s %6s %8s\n" "----------" "----" "----" "----" "------"

for n in '5.59' '1.04' '5.35' '6.7 s' '153 s' '22 倍' '940 倍' '104 ms' '33 块' '15 块' '48 块' '31 块' '24/48' '8.3x' '第 5 跳' '8 万行' '7.27' '60.2'; do
  a=$(grep -cF -- "$n" 08-实战经验.md)
  b=$(grep -cF -- "$n" 09-排障速查手册.md)
  c=$(grep -cF -- "$n" 10-场景解法库.md)
  d=$(grep -cF -- "$n" final-课程手册.md)
  printf "%-14s %6s %6s %6s %8s\n" "$n" "$a" "$b" "$c" "$d"
done

echo ""
echo "===== 跨文件编号引用一致性 ====="
echo "-- 08 → 09 症状引用（应覆盖 1-10）:"
grep -o '09 症状 [0-9]*' 08-实战经验.md | sort -u -t' ' -k3 -n | tr '\n' ' '
echo ""
echo "-- 09 → 08 故障模式引用（应覆盖 1-10）:"
grep -o '故障模式 [0-9]*$' 09-排障速查手册.md | sort -u -t' ' -k2 -n | tr '\n' ' '
echo ""
echo "-- 10 → 08 故障模式引用:"
grep -o '故障模式 [0-9]*' 10-场景解法库.md | sort -u -t' ' -k2 -n | tr '\n' ' '
echo ""

echo ""
echo "===== 反向核验：09 症状编号与 08 故障模式编号的映射是否一一对应 ====="
awk '/^> \*\*原理\*\*/{match($0,/故障模式 [0-9]+/); if(RSTART>0) print "  症状→故障模式: " substr($0,RSTART,RLENGTH)}' 09-排障速查手册.md
