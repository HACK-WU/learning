#!/bin/bash
# 课 9 收尾：清理实验实例与临时目录（只动本轮创建的端口与 /tmp/redis-l09）
echo "=== 清理实验实例 7101-7106 ==="
for p in 7101 7102 7103 7104 7105 7106; do
  r=$(redis-cli -p $p ping 2>/dev/null)
  if [ "$r" = "PONG" ]; then
    redis-cli -p $p shutdown nosave 2>/dev/null
    echo "  $p -> 已关闭"
  else
    echo "  $p -> 未运行"
  fi
done
sleep 1
rm -rf /tmp/redis-l09
echo "  /tmp/redis-l09 -> 已删除"

echo ""
echo "=== 确认 6379 默认实例未受影响 ==="
redis-cli -p 6379 ping 2>&1 | head -1
redis-cli -p 6379 info server 2>/dev/null | grep -E "redis_version|uptime_in_seconds"
ps aux | grep -E "[r]edis-server" | awk '{print $NF}' | head

echo ""
echo "=== 课 9 讲义校验 ==="
F=/mnt/d/projects/learning/redis/stages/4-分布式与生产实践/lessons/lesson-09-生产实践与选型.md
echo "  大小: $(du -h $F | cut -f1)"
echo "  行数: $(wc -l < $F)"
echo "--- 必备段落 ---"
for s in "## 本课要解决的三个问题" "## 第一幕" "## 第二幕" "## 第三幕" "## 第四幕" "## 第五幕" "## 常见误区" "## 小测" "🚀 下一批接力提示词" "🧭 课程导航"; do
  if grep -q "$s" "$F"; then echo "  ✅ $s"; else echo "  ❌ $s 缺失"; fi
done

echo ""
echo "=== 三个知识点小节 ==="
for s in "知识点 1：性能诊断" "知识点 2：安全与运维基线" "知识点 3：生态与选型"; do
  if grep -q "$s" "$F"; then echo "  ✅ $s"; else echo "  ❌ $s 缺失"; fi
done

echo ""
echo "=== 文档同步校验 ==="
echo -n "  学习档案课9完成数: "
grep -c "课 9 生产实践与选型 | .* | ✅ 已完成" /mnt/d/projects/learning/redis/00-学习档案.md
echo -n "  课目录课9链接: "
grep -c "lesson-09-生产实践与选型.md" /mnt/d/projects/learning/redis/02-课程目录.md
echo -n "  评审清单课9勾选: "
grep -c "^- \[x\] 阶段 4·课 9" /mnt/d/projects/learning/redis/00-评审清单.md
echo -n "  overview课9产出: "
grep -c "lesson-09-生产实践与选型.md.*完成" /mnt/d/projects/learning/redis/stages/4-分布式与生产实践/overview.md
