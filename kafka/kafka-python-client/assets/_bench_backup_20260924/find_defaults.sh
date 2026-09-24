#!/bin/bash
# 在源码里定位 kafka-python 的默认配置定义
docker run --rm python:3.12-slim bash -c 'pip install -q kafka-python==3.0.11 >/dev/null 2>&1
SP=/usr/local/lib/python3.12/site-packages/kafka
echo "=== producer/kafka.py 里的 DEFAULT/配置 dict ==="
grep -n "DEFAULT" $SP/producer/kafka.py | head -10
echo ""
echo "=== consumer/group.py 里的 DEFAULT/配置 dict ==="
grep -n "DEFAULT" $SP/consumer/group.py | head -10
echo ""
echo "=== 找含 auto_offset_reset 的赋值行 ==="
grep -rn "auto_offset_reset\s*=" $SP/ | head -10
echo ""
echo "=== 找含 acks 的赋值行 ==="
grep -rn "^\s*[\"'\x27]acks[\"'\x27]\s*:\|acks\s*=\s*1" $SP/producer/*.py | head -10'
