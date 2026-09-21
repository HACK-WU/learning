#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
O="$R/子教程/运维专项"
DATE=2026-09-20

echo "===== 1. overview.md 课清单：课4/课5 加链接 ====="
python3 - <<PYEOF
import re
p = "$O/overview.md"
s = open(p, encoding='utf-8').read()
s = s.replace(
  "| **课 4：证书与密钥生命周期** |",
  "| **课 4：证书与密钥生命周期**（✅ [讲义](lessons/lesson-04-证书与密钥生命周期.md)） |"
)
s = s.replace(
  "| **课 5：备份、恢复与灾备演练** |",
  "| **课 5：备份、恢复与灾备演练**（✅ [讲义](lessons/lesson-05-备份、恢复与灾备演练.md)） |"
)
open(p, 'w', encoding='utf-8').write(s)
print("  已更新课清单链接")
PYEOF

echo
echo "===== 2. 学习进度：勾选课4/课5 ====="
python3 - <<PYEOF
p = "$O/overview.md"
s = open(p, encoding='utf-8').read()
s = s.replace(
  "- [ ] 课 4：证书与密钥生命周期",
  "- [x] 课 4：证书与密钥生命周期（✅ $DATE 交付，实测三类凭证独立 / CA 三级 TTL / keyring empty / 改配置≠轮换）"
)
s = s.replace(
  "- [ ] 课 5：备份、恢复与灾备演练",
  "- [x] 课 5：备份、恢复与灾备演练（✅ $DATE 交付，实测全毁重建 CA 复活 / 快照含 CA 私钥 / 全量覆盖）"
)
open(p, 'w', encoding='utf-8').write(s)
print("  已勾选课4、课5")
PYEOF

echo
echo "===== 3. 确认写入结果 ====="
grep -n '课 4：证书与密钥生命周期\|课 5：备份、恢复与灾备演练' "$O/overview.md" | sed 's/^/  /'
