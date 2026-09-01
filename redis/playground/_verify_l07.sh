#!/usr/bin/env bash
# 课 7 交付前校验：脚本存在性 + 必查项（不自我删除）
OUT=/tmp/l07-verify.out
{
echo "=== 1. 清理脚本是否已移除 ==="
CL=/mnt/d/projects/learning/redis/playground/_cleanup_l07.sh
if [ -f "$CL" ]; then rm -f "$CL"; echo "  已删除 _cleanup_l07.sh"; else echo "  不存在（已清理）"; fi

echo ""
echo "=== 2. 课 7 脚本清单 ==="
ls -1 /mnt/d/projects/learning/redis/playground/ | grep 'lesson-07'

echo ""
echo "=== 3. 讲义引用的脚本存在性校验 ==="
for f in cluster-setup crc16-verify reshard ask lua lua2 verify2 scan; do
  t="/mnt/d/projects/learning/redis/playground/prep-lesson-07-$f.sh"
  if [ -f "$t" ]; then echo "  OK    prep-lesson-07-$f.sh"; else echo "  MISSING prep-lesson-07-$f.sh"; fi
done

echo ""
echo "=== 4. 讲义必查项 ==="
DOC=/mnt/d/projects/learning/redis/stages/4-分布式与生产实践/lessons/lesson-07-分片与集群.md
echo "  文件大小: $(wc -c < "$DOC") bytes, $(wc -l < "$DOC") 行"
grep -q '🚀 下一批接力提示词' "$DOC" && echo "  [OK] 含下一批接力提示词" || echo "  [MISS] 缺下一批接力提示词"
grep -q '🧭 课程导航' "$DOC" && echo "  [OK] 含课程导航" || echo "  [MISS] 缺课程导航"
grep -q '核查于 2026-09' "$DOC" && echo "  [OK] 已标注核查时间" || echo "  [MISS] 缺核查时间标注"

echo ""
echo "=== 5. 评审修复项复核 ==="
echo "  -- P0-1: 3.6 节应含 'numkeys=0 导致脚本无路由依据' --"
grep -q 'numkeys=0.*路由依据\|路由依据' "$DOC" && echo "  [OK] 已修复" || echo "  [MISS]"
echo "  -- P0-1 复核: 不应再有 '即使同槽也要声明' --"
grep -q '即使同槽也要声明' "$DOC" && echo "  [MISS] 矛盾表述仍在" || echo "  [OK] 矛盾表述已移除"
echo "  -- P0-2: Q2 应改为反向提问 --"
grep -q '不\*\*落在同一个槽\|不\*\*落在' "$DOC" && echo "  [OK] 已改为反向提问" || echo "  [MISS]"
echo "  -- P0-2 复核: 不应再有 '本题 B 和 D 都正确' --"
grep -q '本题 B 和 D 都正确' "$DOC" && echo "  [MISS] 错题补丁仍在" || echo "  [OK] 错题补丁已移除"
echo "  -- P1-1: 2.6 节应含单槽分支 --"
grep -q 'elif tok.isdigit' "$DOC" && echo "  [OK] 已补单槽分支" || echo "  [MISS]"
echo "  -- P1-2: 困境一不应再有 512 GB --"
grep -q '512 GB' "$DOC" && echo "  [MISS] 未核实数字仍在" || echo "  [OK] 已移除"

echo ""
echo "=== 6. 环境最终状态 ==="
echo "  700x 端口监听数: $(ss -tlnp 2>/dev/null | grep -cE ':(700[0-9])')"
echo "  /tmp/redis-l07* 残留: $(ls -d /tmp/redis-l07* 2>/dev/null | wc -l)"
echo "  6379 用户实例: $(redis-cli -p 6379 ping 2>/dev/null || echo '未运行')"

echo ""
echo "=== 校验完成 ==="
} > "$OUT" 2>&1
cat "$OUT"
