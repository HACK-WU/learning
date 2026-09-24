#!/bin/bash
# 档案回写：在评审记录表第 2 行后插入课 9 记录（表格按日期倒序，9-22 应在最前）
set -u
F=/mnt/d/projects/learning/kafka/kafka-python-client/00-评审清单.md
TMP=/tmp/newrow.md
cat > "$TMP" <<'EOF'
| 2026-09-22 | 课 9 序列化与 Schema Registry | 主 agent 独立复审（数字重跑 5 次采样核验 + 结构检查 + 引用完整性） | **P0 清零**（复审后修 1 个 P0）。复审检出：讲义把单次采样值 `430,059/504,354` 当确定值写出，重跑 5 次得 JSON 420,013~443,395、Avro 490,367~529,664 —— 已改为区间并加「5 次采样」说明。复验同时确认 Avro 5 次全胜且区间不重叠（Avro 最低 490k > JSON 最高 443k），故「Avro 编码快于 JSON」结论成立、非单次偶然。另**推翻 3 个课程预设**：① `schema_registry` 子包"不存在"实为依赖缺失（探路脚本 mock 只剥 4 层的 bug）②「Avro 比 JSON 慢」实测证伪 ③「long→int 缩窄静默损坏」实测证伪（真静默的是改字段名）。策略矩阵经历 3 轮纠错才拿到真结果：dict → `ServerConfig` 静默不生效（返回 `{}` 但策略没设上）→ REST 直连 + 设完回读确认。脚本级踩坑另 2 个：`str.encode` 签名不符、fastavro 1.12 的 `write/parse_schema` 是模块非函数 | 已修并复验：7 脚本引用全在、51 行表格、零模糊表述、诚实标注段齐 |
EOF
# 找到表头分隔行 |----| 的行号，在其后插入
LN=$(grep -n '^|------|----------|----------|----------|------|$' "$F" | head -1 | cut -d: -f1)
if [ -z "$LN" ]; then echo "未找到表格分隔行"; exit 1; fi
echo "分隔行在 $LN，其下一行插入课 9 记录"
sed -i "${LN}r $TMP" "$F"
echo "--- 插入后前 3 条记录 ---"
grep -n '^| 2026-09-2' "$F" | head -3 | cut -c1-120
