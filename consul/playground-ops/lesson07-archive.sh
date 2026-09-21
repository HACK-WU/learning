#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
O="$R/子教程/运维专项"
DATE=2026-09-20

echo "===== 1. overview.md：课7 加链接 + 勾选 ====="
python3 - <<'PYEOF'
p = "/mnt/d/projects/learning/consul/子教程/运维专项/overview.md"
s = open(p, encoding='utf-8').read()
s = s.replace(
  "| **课 7：版本升级与迁移** |",
  "| **课 7：版本升级与迁移**（✅ [讲义](lessons/lesson-07-版本升级与迁移.md)） |"
)
s = s.replace(
  "- [ ] 课 7：版本升级与迁移",
  "- [x] 课 7：版本升级与迁移（✅ 2026-09-20 交付，实测 quorum 停机上限 / 停2台写失败 / 回滚代价：老数据回、新数据全丢）"
)
open(p, 'w', encoding='utf-8').write(s)
print("  ✅ overview 已更新")
PYEOF

echo
echo "===== 2. 02-课程目录.md：加课7 ====="
python3 - <<'PYEOF'
p = "/mnt/d/projects/learning/consul/02-课程目录.md"
s = open(p, encoding='utf-8').read()
anchor = "  - [课 6 监控指标与告警](./子教程/运维专项/lessons/lesson-06-监控指标与告警.md)（✅ 2026-09-20｜实测：双重命名空壳恒 0 / 静默失效 vs 永久误报 / 三步核验 / 9 组断言）"
add = anchor + "\n  - [课 7 版本升级与迁移](./子教程/运维专项/lessons/lesson-07-版本升级与迁移.md)（✅ 2026-09-20｜实测：gossip 与 Raft 两种 protocol / 停2台写失败 HTTP 000 / 回滚=全量回退，升级窗口内新数据全丢）"
if anchor in s and "课 7 版本升级与迁移" not in s:
    s = s.replace(anchor, add)
    open(p, 'w', encoding='utf-8').write(s)
    print("  ✅ 课程目录已加课7")
else:
    print("  ⚠️ 锚点未命中或已存在")
PYEOF

echo
echo "===== 3. 01-学习路径总览.md：进度 7/8 ====="
python3 - <<'PYEOF'
p = "/mnt/d/projects/learning/consul/01-学习路径总览.md"
s = open(p, encoding='utf-8').read()
s = s.replace("｜**进度：课 6 / 8 已交付（课 1、2、3、4、5、6）**",
              "｜**进度：课 7 / 8 已交付（课 1、2、3、4、5、6、7）**")
a = "[课 6 监控指标与告警](子教程/运维专项/lessons/lesson-06-监控指标与告警.md)"
b = a + "、[课 7 版本升级与迁移](子教程/运维专项/lessons/lesson-07-版本升级与迁移.md)"
if a in s and "课 7 版本升级与迁移" not in s:
    s = s.replace(a, b)
open(p, 'w', encoding='utf-8').write(s)
print("  ✅ 路径总览已更新")
PYEOF
