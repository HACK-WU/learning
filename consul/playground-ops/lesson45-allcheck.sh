#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
echo "===== 全目录 md 链接校验 ====="
BAD=0; TOT=0
while IFS= read -r f; do
  dir=$(dirname "$f")
  while IFS= read -r link; do
    TOT=$((TOT+1))
    tgt="$dir/${link%%#*}"
    [ -f "$tgt" ] || { echo "  ❌ $f → $link"; BAD=$((BAD+1)); }
  done < <(grep -oE '\]\(([^)]+\.md)\)' "$f" | sed 's/](\(.*\))/\1/')
done < <(find "$R" -name '*.md' -not -path '*/node_modules/*')
echo "  总计 $TOT 条 md 链接，断链 $BAD 条"

echo
echo "===== 课4/课5 讲义自检 ====="
B="$R/子教程/运维专项/lessons"
for f in lesson-04-证书与密钥生命周期.md lesson-05-备份、恢复与灾备演练.md; do
  echo "  --- $f ---"
  echo "    行数: $(wc -l < "$B/$f")"
  echo "    含⚠️实测边界标注: $(grep -c '实测边界' "$B/$f")"
  echo "    小测答案折叠: $(grep -c '<details>' "$B/$f")"
  echo "    核心结论条数: $(sed -n '/## .*核心结论/,/^## /p' "$B/$f" | grep -c '^[0-9]\.')"
done

echo
echo "===== SVG 合法性 ====="
N=0; S=0
for f in $(find "$R" -name '*.svg'); do
  N=$((N+1))
  head -c 200 "$f" | grep -q '<svg' && S=$((S+1)) || echo "  ❌ $(basename $f)"
done
echo "  $N 个 SVG，合法 $S 个"

echo
echo "===== 环境清理 ====="
pkill -f 'consul agent' 2>/dev/null
sleep 2
echo "  剩余 consul 进程 = $(pgrep -fc 'consul agent' 2>/dev/null || echo 0)"
rm -rf /tmp/consul-ops/tls/*.pem /tmp/consul-ops/tls/*.csr /tmp/consul-ops/tls/*.srl 2>/dev/null
echo "  已清理临时证书文件"
