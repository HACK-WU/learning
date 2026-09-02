#!/bin/bash
# 最终确认：删除一次性卫生检查脚本 + 复核档案回写 + 环境终态
set -u
cd /mnt/d/projects/learning

echo "########## 1. 删除一次性卫生检查脚本（保留可复用的验证/清理脚本）##########"
cd /mnt/d/projects/learning/redis/playground
for f in prep-phase4-hygiene.sh prep-phase4-gitignore-check.sh prep-phase4-residue.sh \
         prep-phase4-procs.sh prep-phase4-untracked.sh prep-phase4-cleanup.sh \
         prep-phase4-cleanup-7201.sh prep-phase4-append-record.py; do
  if [ -f "$f" ]; then rm -f "$f" && echo "  已删除: $f"; fi
done

echo
echo "  保留的可复用脚本（环境搭建/验证，README 有引用）:"
ls -1 prep-final-project-*.sh prep-phase5-verify.sh 2>/dev/null | sed 's/^/    /'

echo
echo "########## 2. 复核档案回写 ##########"
cd /mnt/d/projects/learning
echo "  评审清单 - 卫生检查条目:"
grep -n '卫生检查与环境清理' redis/00-评审清单.md | sed 's/^/    /'
echo "  学习档案 - 卫生检查记录:"
grep -c '卫生检查与清理' redis/00-学习档案.md | sed 's/^/    匹配行数: /'

echo
echo "########## 3. 环境终态 ##########"
echo "  实验端口:"
for p in 7201 7202 7203; do
  echo "    $p => $(redis-cli -p $p ping 2>&1 | head -1)"
done
echo "  6379 用户实例: $(redis-cli -p 6379 ping 2>&1 | head -1)（数据量 $(redis-cli -p 6379 dbsize 2>&1 | head -1)）"
echo "  剩余 redis-server:"
ps -eo pid,etime,comm 2>/dev/null | grep redis-server | sed 's/^/    /'

echo
echo "########## 4. 最终残留复扫 ##########"
FOUND=0
while IFS= read -r f; do
  echo "  残留: $f"; FOUND=1
done < <(find redis -name '__pycache__' -o -name '*.pyc' -o -name '*.rdb' -o -name '*.aof' \
              -o -name 'appendonlydir' -o -name 'nodes-*.conf' -o -name '*.log' 2>/dev/null)
[ "$FOUND" = "0" ] && echo "  ✅ 无残留"

echo
echo "########## 5. 教学产物完整性（应全部存在）##########"
for f in redis/final-课程手册.md redis/08-实战经验.md redis/09-排障速查手册.md redis/10-场景解法库.md \
         redis/projects/电商大促数据层/README.md redis/projects/电商大促数据层/实现/main.py; do
  [ -f "$f" ] && echo "  ✅ $f" || echo "  ❌ 缺失 $f"
done
