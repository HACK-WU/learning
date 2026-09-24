#!/bin/bash
# 课13 测试运行器：规避 WSL/Windows 管道中文乱码
# 手法：容器内跑测试 -> 结果写文件 -> 宿主机用 python 以 utf-8 读入并打印
docker exec -w /app/capstone l11 env PYTHONIOENCODING=utf-8 \
  /app/.venv/bin/python -m unittest discover -s tests -t . -v 2>&1 | tail -60
