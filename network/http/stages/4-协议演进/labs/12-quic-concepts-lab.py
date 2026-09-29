#!/usr/bin/env python3
"""HTTP/3 / QUIC 的教学模型实验。

这个脚本不实现 QUIC，也不发送网络包；它用确定性事件重放三个边界：
1. HTTP/2 的 TCP 共享有序交付；
2. HTTP/3 的 QUIC 分流交付、连接 ID 与路径迁移；
3. 0-RTT 的重放风险与方法筛选。
"""

from __future__ import annotations

import argparse


def tcp_shared_order() -> None:
    print("[12.1] HTTP/2 over TCP: shared ordered delivery")
    packets = [
        (1, "stream 1", "A1", False),
        (2, "stream 3", "B1", False),
        (3, "stream 1", "A2", True),
        (4, "stream 3", "B2", False),
    ]
    for number, stream, chunk, lost in packets:
        if lost:
            print(f"packet {number}: {stream} {chunk} LOST")
        elif number == 4:
            print(f"packet {number}: {stream} {chunk} arrived, but held behind missing A2")
        else:
            print(f"packet {number}: {stream} {chunk} delivered")
    print("application receives: A1, B1")
    print("boundary: TCP must recover A2 before later shared bytes are delivered")


def quic_streams_and_migration() -> None:
    print("[12.2] HTTP/3 over QUIC: per-stream delivery")
    events = [
        ("stream A", "A1", "delivered"),
        ("stream A", "A2", "LOST -> retransmit only on stream A"),
        ("stream B", "B1", "delivered"),
        ("stream B", "B2", "delivered while A2 is missing"),
    ]
    for stream, chunk, result in events:
        print(f"{stream} {chunk}: {result}")
    print("boundary: congestion control is still shared by the connection")

    connection_id = "q-demo-01"
    print("[12.2] connection migration model")
    print(f"connection_id={connection_id} path=wifi-a")
    print(f"connection_id={connection_id} path=wifi-b -> same logical connection, new path needs validation")


def early_data_gate() -> None:
    print("[12.2] 0-RTT replay-safety gate")
    safe_methods = {"GET", "HEAD", "OPTIONS", "TRACE"}
    for method in ("GET", "HEAD", "POST"):
        decision = "candidate: still requires application replay analysis" if method in safe_methods else "do not assume safe: replay can repeat a side effect"
        print(f"{method}: {decision}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run deterministic HTTP/3 / QUIC teaching models")
    parser.add_argument("--section", choices=("12.1", "12.2", "all"), default="all")
    args = parser.parse_args()

    print("teaching model only: no QUIC packets are sent")
    if args.section in ("12.1", "all"):
        tcp_shared_order()
    if args.section in ("12.2", "all"):
        quic_streams_and_migration()
        early_data_gate()


if __name__ == "__main__":
    main()
