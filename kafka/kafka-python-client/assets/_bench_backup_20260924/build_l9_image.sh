#!/bin/bash
# 课 9 环境：重建 bench 镜像（加入 SR 客户端依赖 + 序列化库）
# 用户已授权方案 A
set -u
cd /mnt/d/projects/learning/kafka/kafka-python-client/assets/bench
docker build -t kafka-pybench:3.12 . 2>&1 | tail -25
