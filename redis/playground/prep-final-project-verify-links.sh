#!/bin/bash
# 评审辅助：验证知识点地图里的回指链接是否真实存在
set -u
cd /mnt/d/projects/learning/redis/projects/电商大促数据层

LINKS=(
"../../stages/1-为什么需要Redis/lessons/lesson-02-跑起来第一个Redis.md"
"../../stages/2-数据结构与命令/lessons/lesson-03-List与Hash.md"
"../../stages/2-数据结构与命令/lessons/lesson-04-Set、ZSet与特殊类型.md"
"../../stages/3-持久化与高可用/lessons/lesson-05-RDB与AOF持久化.md"
"../../stages/3-持久化与高可用/lessons/lesson-06-主从复制与哨兵.md"
"../../stages/4-分布式与生产实践/lessons/lesson-07-分片与集群.md"
"../../stages/4-分布式与生产实践/lessons/lesson-08-缓存设计.md"
"../../stages/4-分布式与生产实践/lessons/lesson-09-生产实践与选型.md"
)

echo "===== 回指链接存在性校验 ====="
for f in "${LINKS[@]}"; do
  if [ -f "$f" ]; then
    echo "  OK   $(basename "$f")"
  else
    echo "  MISS $f"
  fi
done

echo
echo "===== 本项目自身文件 ====="
for f in README.md 设计决策.md 反例对照.md 验收清单.md 实现/main.py 实现/redislib.py 实现/cache_layer.py 实现/inventory.py 实现/diagnostics.py; do
  if [ -f "$f" ]; then
    echo "  OK   $f"
  else
    echo "  MISS $f"
  fi
done

echo
echo "===== 验收清单里引用的排障手册（尚未生成） ====="
for f in ../../09-排障速查手册.md ../../08-实战经验.md; do
  if [ -f "$f" ]; then
    echo "  OK   $f"
  else
    echo "  MISS $f  ← 将在 Phase 5 生成"
  fi
done
