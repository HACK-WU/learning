#!/usr/bin/env bash
set -u
cd /mnt/d/projects/learning/redis

echo "===== 1. 学习档案：追加课 8 评审记录 ====="
ARCHIVE="00-学习档案.md"
ANCHOR='> ⚠️ 独立性提示'
LINE8='| 2026-09-01 | 阶段4·课8《缓存设计》批次 | 主 agent 内联（pedagogy + learner） | pedagogy：P0×1（3.5 节 samples 数据呈现 samples=1 存活 1827 却未解释，易被误读为"LRU 更准"）/ P1×1（3.3 节策略横评表未标注 volatile-* 组只给冷 key 设 TTL，表格会被误读成策略排名）；learner：P0×0 / P1×1（3.2 节定期删除实测"5 秒只回收 15 个"缺量化解释，零基础易误判为异常） | 三条均采纳并修订：3.5 节补淘汰数/写入数对照实验，证实 samples=1 是"淘汰太慢导致写入提前失败"而非精度更高，并补充"调太小会拖垮写入吞吐"的结论；3.3 节在表前加"读表前必看"、表后加"这张表不能直接用来排名"两处警示；3.2 节补充 0.2 个/次的抽样期望验算，说明 15 个与之同数量级；另主动修正 Q3 题干（原"秒杀库存选互斥锁"与冲突三"秒杀慎用互斥锁"自相矛盾，改为考察选型判据本身）；修订后复审 P0=0 |'

if grep -q "课8《缓存设计》批次" "$ARCHIVE"; then
  echo "课 8 评审记录已存在，跳过"
else
  python3 - "$ARCHIVE" "$ANCHOR" "$LINE8" <<'PYEOF'
import sys
path, anchor, newline = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()
out = []
inserted = False
for ln in lines:
    if not inserted and ln.startswith(anchor):
        out.append(newline + '\n')
        out.append('\n')
        inserted = True
    out.append(ln)
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(out)
print('已插入:', inserted)
PYEOF
fi

echo
echo "===== 2. 评审清单：追加课 8 评审记录 ====="
CHK="00-评审清单.md"
ROW8='| 2026-09-01 | 阶段4·课8《缓存设计》 | 主 agent 内联（pedagogy + learner） | 0 | P0×1 + P1×2 均采纳：3.5 节补充对照实验证实 samples=1 存活高是"淘汰太慢导致写入提前失败"而非精度更高（原数据易被误读为 LRU 更准）；3.3 节策略横评表前后各加一处警示，标明 volatile-* 组只给冷 key 设 TTL、该表不可用于策略排名；3.2 节补充抽样期望验算解释"5 秒回收 15 个"的合理性；另修正 Q3 题干与冲突三的自相矛盾 |'

if grep -q "阶段4·课8《缓存设计》" "$CHK"; then
  echo "课 8 记录已存在，跳过"
else
  python3 - "$CHK" "$ROW8" <<'PYEOF'
import sys
path, newline = sys.argv[1], sys.argv[2]
with open(path, 'r', encoding='utf-8') as f:
    lines = f.readlines()
out = []
inserted = False
for ln in lines:
    if not inserted and ln.startswith('| 2026-09-01 | 阶段4·课7《分片与集群》 |'):
        out.append(newline + '\n')
        inserted = True
    out.append(ln)
with open(path, 'w', encoding='utf-8') as f:
    f.writelines(out)
print('已插入:', inserted)
PYEOF
fi

echo
echo "===== 3. 校验结果 ====="
echo "--- 学习档案 课8 行 ---"
grep -n "课 8 缓存设计" "$ARCHIVE"
echo "--- 学习档案 评审记录 ---"
grep -c "课8《缓存设计》批次" "$ARCHIVE"
echo "--- 评审清单 待评审 ---"
grep -n "课 8\|课 9" "$CHK" | head -5
echo "--- 评审清单 记录数 ---"
grep -c "阶段4·课8《缓存设计》" "$CHK"
