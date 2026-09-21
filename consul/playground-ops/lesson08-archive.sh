#!/usr/bin/env bash
python3 - <<'PYEOF'
import io,os,sys
R = "/mnt/d/projects/learning/consul"

# ---------- 1. overview.md ----------
p = f"{R}/子教程/运维专项/overview.md"
s = open(p, encoding='utf-8').read()
s = s.replace(
  "| **课 8：多机房与 K8s 运维视角** |",
  "| **课 8：多机房与 K8s 运维视角**（✅ [讲义](lessons/lesson-08-多机房与K8s运维视角.md)） |"
)
s = s.replace(
  "- [ ] 课 8：多机房与 K8s 运维视角",
  "- [x] 课 8：多机房与 K8s 运维视角（✅ 2026-09-20 交付，实测：联邦=查询通道非数据副本 / 故障域隔离 / WAN检测40s / leave vs kill-9 / left状态须重新join）"
)
open(p,'w',encoding='utf-8').write(s)
print("  ✅ overview 已更新")

# ---------- 2. 02-课程目录.md ----------
p = f"{R}/02-课程目录.md"
s = open(p, encoding='utf-8').read()
anchor = "  - [课 7 版本升级与迁移](./子教程/运维专项/lessons/lesson-07-版本升级与迁移.md)（✅ 2026-09-20｜实测：gossip 与 Raft 两种 protocol / 停2台写失败 HTTP 000 / 回滚=全量回退，升级窗口内新数据全丢）"
add = anchor + "\n  - [课 8 多机房与 K8s 运维视角](./子教程/运维专项/lessons/lesson-08-多机房与K8s运维视角.md)（✅ 2026-09-20｜实测：联邦是查询通道非数据副本 / 故障域隔离 / WAN 检测 40s / leave 立即 left vs kill-9 40s 盲区 / left 须重新 join）"
if anchor in s and "课 8 多机房与 K8s 运维视角" not in s:
    s = s.replace(anchor, add)
    open(p,'w',encoding='utf-8').write(s)
    print("  ✅ 课程目录已加课8")
else:
    print("  ⚠️ 课程目录锚点未命中或已存在")

# ---------- 3. 01-学习路径总览.md ----------
p = f"{R}/01-学习路径总览.md"
s = open(p, encoding='utf-8').read()
s = s.replace("｜**进度：课 7 / 8 已交付（课 1、2、3、4、5、6、7）**",
              "｜**进度：课 8 / 8 已交付（课 1、2、3、4、5、6、7、8 · 运维专项全部完成）**")
a = "[课 7 版本升级与迁移](子教程/运维专项/lessons/lesson-07-版本升级与迁移.md)"
b = a + "、[课 8 多机房与 K8s 运维视角](子教程/运维专项/lessons/lesson-08-多机房与K8s运维视角.md)"
if a in s and "课 8 多机房与 K8s 运维视角" not in s:
    s = s.replace(a, b)
open(p,'w',encoding='utf-8').write(s)
print("  ✅ 路径总览已更新")
PYEOF
