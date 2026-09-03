#!/bin/bash
L=/mnt/d/projects/learning/victoriametrics/stages
echo "=== 历史课程中提到 vmagent / vmalert / alertmanager / relabel 的行 ==="
grep -rn "vmagent\|vmalert\|alertmanager\|Alertmanager" $L --include=*.md | head -40

echo
echo "=== relabel / 基数治理 相关标题 ==="
grep -rn "^#.*relabel\|^#.*基数\|relabel_configs" $L --include=*.md | head -30
