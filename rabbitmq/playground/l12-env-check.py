#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""课 12 环境自检：pika 版本 + broker 队列/连接状态。"""
import subprocess

import pika

print("pika version:", pika.__version__)

r = subprocess.run(['docker', 'exec', 'rmq1', 'rabbitmqctl',
                    'list_queues', 'name', 'messages', 'consumers',
                    '--quiet'], capture_output=True, text=True, timeout=90)
print("\n--- queues on rmq1 ---")
print((r.stdout or '').strip() or '(none)')
