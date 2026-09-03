#!/usr/bin/env bash
# 课 5 步骤 1：打开磁盘目录，看 VM 存储引擎的真实结构
set -u
DATA=/mnt/d/projects/learning/victoriametrics/playground/data

echo "########## 1. 数据目录顶层结构 ##########"
ls -la "$DATA/" | sed 's/^/  /'

echo
echo "########## 2. 各顶层目录占用 ##########"
du -sh "$DATA"/* 2>/dev/null | sort -rh | sed 's/^/  /'

echo
echo "########## 3. data 目录（原始样本）##########"
echo "  --- data/ 下 ---"
ls -la "$DATA/data/" 2>/dev/null | sed 's/^/  /'
echo
echo "  --- data/small/ 下的月份分区 ---"
ls -la "$DATA/data/small/" 2>/dev/null | sed 's/^/  /'
echo
echo "  --- data/big/ 下的月份分区 ---"
ls -la "$DATA/data/big/" 2>/dev/null | sed 's/^/  /'

echo
echo "########## 4. 月份分区内部：parts.json + 各个 part 目录 ##########"
PARTITION=$(ls -d "$DATA/data/small"/2* 2>/dev/null | head -1)
if [ -n "$PARTITION" ]; then
  echo "  分区目录: $PARTITION"
  ls -la "$PARTITION/" | head -20 | sed 's/^/  /'
  echo
  echo "  --- parts.json 内容（part 清单）---"
  cat "$PARTITION/parts.json" 2>/dev/null | python3 -m json.tool 2>/dev/null | head -30 | sed 's/^/  /'
fi

echo
echo "########## 5. 单个 part 目录内部的文件 ##########"
PART=$(ls -d "$PARTITION"/[0-9]*_* 2>/dev/null | head -1)
if [ -n "$PART" ]; then
  echo "  part 目录: $(basename "$PART")"
  ls -la "$PART/" | sed 's/^/  /'
  echo
  echo "  --- metadata.json（part 的元数据）---"
  cat "$PART/metadata.json" 2>/dev/null | python3 -m json.tool 2>/dev/null | sed 's/^/  /'
fi

echo
echo "########## 6. indexdb 目录（倒排索引）##########"
echo "  --- indexdb/ 顶层 ---"
ls -la "$DATA/indexdb/" 2>/dev/null | sed 's/^/  /'
echo
echo "  --- indexdb 各 table 目录 ---"
for t in $(ls -d "$DATA/indexdb"/[0-9A-F]* 2>/dev/null | head -5); do
  echo "  table: $(basename "$t")"
  ls -la "$t/" | head -8 | sed 's/^/    /'
done

echo
echo "########## 7. indexdb 单个 part 的文件（与 data part 对比）##########"
for t in $(ls -d "$DATA/indexdb"/[0-9A-F]* 2>/dev/null); do
  IP=$(ls -d "$t"/[0-9A-F]*_* 2>/dev/null | head -1)
  if [ -n "$IP" ]; then
    echo "  --- $(basename "$t")/$(basename "$IP") ---"
    ls -la "$IP/" | sed 's/^/    /'
    echo "    metadata.json:"
    cat "$IP/metadata.json" 2>/dev/null | python3 -m json.tool 2>/dev/null | sed 's/^/      /'
    break
  fi
done

echo
echo "########## 8. 其他目录 ##########"
for d in metadata tmp snapshots flock.lock; do
  if [ -e "$DATA/$d" ]; then
    echo "  $d: $(du -sh "$DATA/$d" 2>/dev/null | cut -f1)  ($(ls "$DATA/$d" 2>/dev/null | wc -l) 项)"
  fi
done
