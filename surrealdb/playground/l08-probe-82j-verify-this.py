#!/usr/bin/env python
"""版本归因：讲义 2026-09-02 记录 `rid = $this.id` 输出为 "order:o1"，
今天（2026-09-03）同一探针 82g 重跑却拿不到 rid/pid。

要排除的解释：
  a) 服务端版本变了  → 查 surreal version
  b) 库里有脏数据/脏事件干扰 → 用全新 NS/DB 重试
  c) 语句本身在不同上下文表现不同 → 用最小复现

本脚本用全新的 ns/db 跑最小复现，排除 (b)。
"""
import asyncio
import json
import uuid

import websockets

URL = "ws://127.0.0.1:8000/rpc"
NS = "verify_this"
DB = "v1"


async def call(ws, m, p, t=20):
    rid = str(uuid.uuid4())
    await ws.send(json.dumps({"id": rid, "method": m, "params": p}))
    while True:
        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=t))
        if msg.get("id") == rid:
            return msg


def rows_of(r):
    res = r.get("result") or []
    if res and isinstance(res[0], dict):
        return res[0].get("result", res)
    return res


async def trial(ws, label, setter):
    """在全新表上跑一次，返回日志行。"""
    await call(ws, "query", ["REMOVE TABLE IF EXISTS src;"])
    await call(ws, "query", ["REMOVE TABLE IF EXISTS log;"])
    await call(ws, "query", ["DEFINE TABLE src SCHEMALESS;"])
    await call(ws, "query", ["DEFINE TABLE log SCHEMALESS;"])
    await call(ws, "query", ["CREATE src:s1 SET amount = 100;"])
    await call(ws, "query", ["REMOVE EVENT IF EXISTS ev ON TABLE src;"])
    r = await call(ws, "query", [
        f"DEFINE EVENT ev ON TABLE src WHEN $event = 'UPDATE' "
        f"AND $after.amount != $before.amount THEN ( CREATE log {setter} );"])
    if r.get("error"):
        return f"DEFINE 报错: {r['error'].get('message','')[:80]}"
    await call(ws, "query", ["UPDATE src:s1 SET amount = 250;"])
    rows = rows_of(await call(ws, "query", ["SELECT * FROM log;"]))
    return json.dumps(rows, ensure_ascii=False) if rows else "日志为空"


async def main():
    async with websockets.connect(URL, max_size=None) as ws:
        await call(ws, "signin", [{"user": "root", "pass": "root"}])
        # 全新 NS/DB，彻底排除脏数据
        await call(ws, "query", [f"DEFINE NAMESPACE IF NOT EXISTS {NS};"])
        await call(ws, "use", [NS, DB])
        await call(ws, "query", [f"DEFINE DATABASE IF NOT EXISTS {DB};"])
        await call(ws, "use", [NS, DB])

        print(f"=== 全新命名空间 {NS}/{DB} 下的最小复现 ===\n")
        cases = [
            ("讲义写法 rid=$this.id", "SET rid = $this.id, action = $event"),
            ("裸 $this", "SET rid = $this, action = $event"),
            ("$after.id", "SET rid = $after.id, action = $event"),
            ("$before.id", "SET rid = $before.id, action = $event"),
            ("type::of($this)", "SET rid = type::of($this), action = $event"),
        ]
        for label, setter in cases:
            out = await trial(ws, label, setter)
            print(f"  {label:24s} → {out}")

        await call(ws, "query", ["REMOVE TABLE IF EXISTS src;"])
        await call(ws, "query", ["REMOVE TABLE IF EXISTS log;"])

        # 顺带确认服务端版本
        r = await call(ws, "query", ["RETURN version()();"]) if False else None
        print("\n  服务端版本请用终端 `surreal version` 查看")


asyncio.run(main())
