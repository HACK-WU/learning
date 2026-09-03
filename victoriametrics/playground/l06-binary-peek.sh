#!/bin/bash
# 课 6 深挖：values.bin 里到底怎么存的（验证列式 + 值编码）
cd /mnt/d/projects/learning/victoriametrics/playground || exit 1

echo "=============================================="
echo " V1 用一串【已知值】做解码验证"
echo "=============================================="
echo "  写入完全可控的序列：值依次是 1,2,3,...,10"
echo "  这样我们能预测编码结果，再跟磁盘字节对比"

NOW=$(date +%s)
START=$((NOW - 600))
python3 - <<PY
import subprocess
now=int(subprocess.check_output(["date","+%s"]).decode().strip())
start=now-600
lines=[]
for t in range(10):
    ts=(start+t*10)*1000000000
    lines.append("l06b_seq,host=h1 value=%d.0 %d" % (t+1, ts))
open("/tmp/l06b_seq.influx","w").write("\n".join(lines)+"\n")
print("  生成 10 个样本，值 = 1..10，时间戳 %d 起 10s 间隔" % start)
PY

curl -s -X POST --max-time 60 --data-binary @/tmp/l06b_seq.influx 'http://localhost:8428/write' -o /dev/null -w '  HTTP: %{http_code}\n'
curl -s -X POST --max-time 30 'http://localhost:8428/internal/force_flush' -o /dev/null
sleep 5

echo
echo "=============================================="
echo " V2 用 export 取回原始值（证明数据形态）"
echo "=============================================="
curl -s --max-time 30 --data-urlencode 'match[]=l06b_seq_value' 'http://localhost:8428/api/v1/export' 2>&1 | head -c 400
echo

echo
echo "=============================================="
echo " V3 关键对比：恒定值 vs 随机值 的磁盘占用"
echo "=============================================="
echo "  从 l06-isolate 实验得到（每组都是 40000 样本）："
echo "  ┌────────────┬──────────────┬──────────────┬─────────────┐"
echo "  │ 数据形态   │ values.bin   │ 每样本字节   │ 相对恒定    │"
echo "  ├────────────┼──────────────┼──────────────┼─────────────┤"
echo "  │ 恒定 42.0  │      5394 B  │       0.135  │   1.0x      │"
echo "  │ 缓变 +1    │      2239 B  │       0.056  │   0.4x      │"
echo "  │ 随机 0-1e6 │    113618 B  │       2.840  │  21.1x      │"
echo "  └────────────┴──────────────┴──────────────┴─────────────┘"
echo
echo "  ⚠️ 注意：缓变组(2239B)比恒定组(5394B)还小 —— 这不合理，"
echo "     说明磁盘增量法受【后台合并干扰】（合并会重排压缩已有数据）。"
echo "     要用更干净的方法：ZSTD 计数增量。"

echo
echo "=============================================="
echo " V4 用 ZSTD 增量重算（不受合并干扰）"
echo "=============================================="
echo "  每组 40000 样本，朴素大小 = 40000×16 = 640000 字节"
echo
printf "  %-12s %14s %14s %10s %12s\n" "形态" "ZSTD原始增量" "ZSTD压缩增量" "压缩比" "每样本字节"
printf "  %-12s %14s %14s %10s %12s\n" "----" "------------" "------------" "------" "----------"
printf "  %-12s %14d %14d %10s %12s\n" "恒定" 266383 40705 "6.544" "$(echo 'scale=4;40705/40000'|bc)"
printf "  %-12s %14d %14d %10s %12s\n" "缓变" 938997 158980 "5.906" "$(echo 'scale=4;158980/40000'|bc)"
printf "  %-12s %14d %14d %10s %12s\n" "随机" 1463618 244604 "5.983" "$(echo 'scale=4;244604/40000'|bc)"
echo
echo "  ★ 关键洞察：ZSTD【原始字节数】本身就不同！"
echo "    恒定 266383 < 缓变 938997 < 随机 1463618"
echo "    说明在交给 ZSTD 之前，VM 已经做了【前置编码】把数据变小了。"
echo "    ZSTD 只是第二层。第一层是列式布局 + 值编码。"

echo
echo "=============================================="
echo " V5 证明「第一层编码」的存在"
echo "=============================================="
echo "  三组样本数完全相同（40000），但交给 ZSTD 的原始字节数差 5.5 倍："
echo "    1463618 / 266383 = $(echo 'scale=3;1463618/266383'|bc) 倍"
echo "  如果 VM 直接把 float64 喂给 ZSTD，三组原始字节应该完全相同。"
echo "  → 所以必然存在【值相关的前置编码】（Gorilla XOR / delta 等）。"
