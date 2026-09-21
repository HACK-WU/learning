#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
echo "=== 表头各列 ==="
consul operator raft list-peers | awk 'NR==1{for(i=1;i<=NF;i++) printf "  col%d=[%s]\n", i, $i}'
echo
echo "=== 数据行 ==="
consul operator raft list-peers | awk 'NR>1{printf "  %s | %s | %s | %s | %s | %s | %s\n",$1,$2,$3,$4,$5,$6,$7}'
echo
echo "=== 用 \$3 和 \$4 分别试 ==="
echo "  \$3 = $(consul operator raft list-peers | awk 'NR>1{print $3}' | tr '\n' ' ')"
echo "  \$4 = $(consul operator raft list-peers | awk 'NR>1{print $4}' | tr '\n' ' ')"
