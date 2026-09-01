#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
课 9 实验 3：心跳协商的三角验证（服务端视角）
==============================================
背景：客户端侧 pika 读到的协商值为 heartbeat=600 → _send_interval=300，
     但 rabbitmqctl environment 显示服务端 heartbeat=60。
     "取两端较小值"的规则在此似乎不成立，需要服务端视角交叉验证。

方法：保持两个长连接（heartbeat=30 与 600），在连接存活期间
     通过 HTTP API 查询服务端记录的心跳值。

⚠️ 课 7 教训：取数方式本身要验证。rabbitmqctl list_connections
   不支持 heartbeat 列（实测报 Info key(s) heartbeat are not supported），
   改用 Management HTTP API。
"""
import json
import subprocess
import sys
import time

import pika

HOST, PORT = 'localhost', 5672
CRED = pika.PlainCredentials('learn', 'learn123')
API = 'http://localhost:15672/api/connections?columns=name,heartbeat,timeout'


def query_api():
    """从宿主机直连已映射的 15672 端口查询 HTTP API。

    注意：容器内无 curl（课 3 已记录），15672 已映射到宿主，
    因此直接在宿主机调用 curl 即可。
    """
    r = subprocess.run(
        ['curl', '-s', '-u', 'learn:learn123',
         'http://localhost:15672/api/connections'],
        capture_output=True, text=True, timeout=30)
    return r.stdout


def main():
    print("=" * 72)
    print("课 9 实验 3：心跳协商的服务端视角验证")
    print("=" * 72)

    c1 = c2 = None
    try:
        c1 = pika.BlockingConnection(pika.ConnectionParameters(
            host=HOST, port=PORT, credentials=CRED, heartbeat=30))
        c2 = pika.BlockingConnection(pika.ConnectionParameters(
            host=HOST, port=PORT, credentials=CRED, heartbeat=600))
        c1.channel()
        c2.channel()
        time.sleep(2)   # 给服务端时间登记连接

        raw = query_api()
        try:
            data = json.loads(raw)
        except Exception as e:
            print("解析失败: %s" % e)
            print("原始输出前 500 字符:\n%s" % raw[:500])
            return 1

        print("")
        print("| 连接 | 服务端 heartbeat | 服务端 timeout |")
        print("|------|------------------|----------------|")
        if not data:
            print("| （无连接数据） | - | - |")
        for c in data:
            print("| %s | %s | %s |" % (c.get('name'), c.get('heartbeat'),
                                       c.get('timeout')))
        print("")
        print("判定：若 heartbeat=600 的连接在服务端也显示 600，")
        print("      说明本环境【未】执行'取较小值'压缩，客户端值主导；")
        print("      若显示 60，说明服务端确实做了上限压缩。")

    finally:
        for c in (c1, c2):
            if c:
                try:
                    c.close()
                except Exception:
                    pass
    return 0


if __name__ == '__main__':
    sys.exit(main())
