#!/usr/bin/env bash
# 课 8 收尾：清理实验实例与临时文件，最终校验
set -u
echo "===== 1. 关闭课 8 实验实例 ====="
for p in 7101 7102 7103; do
  if redis-cli -p $p ping >/dev/null 2>&1; then
    echo "关闭 $p ..."
    redis-cli -p $p shutdown nosave 2>/dev/null || true
    sleep 0.3
  else
    echo "$p 未运行"
  fi
done

echo
echo "===== 2. 确认用户 6379 实例未被触碰 ====="
echo "--- 6379 进程（系统自带 7.0.15 绑 127.0.0.1 + redis-stack 8.10.1 绑 0.0.0.0）---"
pgrep -af "redis-server" | head -5
echo "--- 6379 连通性 ---"
redis-cli -p 6379 ping 2>&1 | head -2
echo "--- 6379 数据库规模 ---"
redis-cli -p 6379 dbsize 2>&1 | head -2

echo
echo "===== 3. 清理临时目录 ====="
rm -rf /tmp/redis-l08
ls -d /tmp/redis-l08 2>/dev/null || echo "/tmp/redis-l08 已删除"
ls -d /tmp/redis-l07 2>/dev/null || echo "/tmp/redis-l07 不存在（课7已清理）"

echo
echo "===== 4. 最终端口检查 ====="
ss -lntp 2>/dev/null | grep -E ':(6379|7101|7102|7103|7001|7002|7003|7004|7005|7006|7007)' || echo "无残留"
echo "--- 期望：只剩 6379 ---"

echo
echo "===== 5. 交付物校验 ====="
cd /mnt/d/projects/learning/redis
L8="stages/4-分布式与生产实践/lessons/lesson-08-缓存设计.md"
echo "课 8 讲义: $(wc -c < "$L8") 字节, $(wc -l < "$L8") 行"
echo "--- 必查项 ---"
grep -c "🚀 下一批接力提示词" "$L8" | xargs echo "接力提示词段:"
grep -c "🧭 课程导航" "$L8" | xargs echo "课程导航段:"
grep -c "核查于 2026-09" "$L8" | xargs echo "核查时间标注:"
grep -c "^## 小测（5 题）" "$L8" | xargs echo "小测段:"
echo "--- 五幕结构 ---"
grep -n "^## 第.幕\|^## 知识点" "$L8"
echo "--- 小测答案数 ---"
grep -c "^<summary>答案</summary>" "$L8"

echo
echo "===== 6. 文档同步校验 ====="
echo "--- 学习档案 课8 知识点 ---"
grep -c "课 8 缓存设计 | ✅" 00-学习档案.md
echo "--- 学习档案 评审记录 ---"
grep -c "课8《缓存设计》批次" 00-学习档案.md
echo "--- 评审清单 勾选 ---"
grep -c "\[x\] 阶段 4·课 8" 00-评审清单.md
echo "--- 评审清单 记录 ---"
grep -c "阶段4·课8《缓存设计》" 00-评审清单.md
echo "--- 课程目录 课8 链接 ---"
grep -c "lesson-08-缓存设计.md" 02-课程目录.md
echo "--- overview 课8 产出 ---"
grep -c "\[x\] \`lessons/lesson-08" stages/4-分布式与生产实践/overview.md

echo
echo "===== 7. playground 脚本（保留供复现）====="
ls /mnt/d/projects/learning/redis/playground/ | grep "lesson-08" | sort
