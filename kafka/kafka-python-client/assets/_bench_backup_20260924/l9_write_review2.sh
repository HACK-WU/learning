#!/bin/bash
# 档案回写：课 9 第 2 轮复审记录（Protobuf 补齐后）
set -u
F=/mnt/d/projects/learning/kafka/kafka-python-client/00-评审清单.md
TMP=/tmp/row2.md
cat > "$TMP" <<'EOF'
| 2026-09-22 | 课 9 第 2 轮复审（Protobuf 补齐后） | 主 agent 独立复审（新增脚本可执行性 + 每个数字重跑核验） | **P0 清零**（复审后修 1 个 P0）。**Protobuf 吞吐测法夸大 3.1 倍**：首版复用同一 message 对象得 742 万/s，upb 对复用对象有加成；改用「新建+逐字段赋值」测法后真实值 174~208 万/s（仍比 Avro 快 2.2~2.7x，非 10x）。第 2 次犯「单点值当结论」：新增章节又写死单点吞吐，复审实测 Avro 780,501 vs 633,789（波幅 19%），已全部改为 5~10 次采样区间，并加注「不同脚本绝对值不可跨表比较」。另修正 protobuf 7.x API：`GetPrototype` 已移除，改 `GetMessageClass`。Protobuf 补齐了 SR 注册实测（409 `FIELD_SCALAR_KIND_CHANGED`）与演进模型（改 field number 会静默错位，Avro 无此风险） | 已修并复验：3 个新脚本全部正常执行、体积 88/32/37 与讲义一致、10 脚本引用全在 |
EOF
LN=$(grep -n '^|------|----------|----------|----------|------|$' "$F" | head -1 | cut -d: -f1)
[ -z "$LN" ] && { echo "未找到分隔行"; exit 1; }
sed -i "${LN}r $TMP" "$F"
echo "已插入第 2 轮复审记录"
grep -c '课 9' "$F" | xargs -I{} echo "评审清单中课9记录数: {}"
