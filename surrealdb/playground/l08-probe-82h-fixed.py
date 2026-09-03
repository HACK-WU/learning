#!/usr/bin/env python
"""修正版：每个变体都清空日志表，逐变体独立判定。

原探针 l08-probe-82h.py 的缺陷：ph2 结果表在 5 个变体之间从不清空，
判定逻辑又是「只要任意一行有 pid 就算这个变体成功」，
于是第一个成功变体（$after.id）的行会被后面所有变体复用，
把裸 $this 和 $this.id 都误判成「正常」。
"""
import asyncio
import json
import uuid

import websockets

URL = "ws://127.0.0.1:8000/rpc"


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


VARIANTS = [
    ("裸 $this", "SET pid = $this"),
    ("$this.id", "SET pid = $this.id"),
    ("$after.id", "SET pid = $after.id"),
    ("$before.id", "SET pid = $before.id"),
    ("<字面量> prod3:x1", "SET pid = prod3:x1"),
    ("type::string($this)", "SET pid = type::string($this)"),
]


async def run_event(ws, setter):
    """针对 UPDATE 事件跑一个变体，返回 (ok, detail)。"""
    for s in ["REMOVE TABLE IF EXISTS prod3;", "REMOVE TABLE IF EXISTS ph3;",
              "DEFINE TABLE prod3 SCHEMALESS;", "DEFINE TABLE ph3 SCHEMALESS;",
              "CREATE prod3:x1 SET price = 1;"]:
        await call(ws, "query", [s])
    r = await call(ws, "query", [
        f"DEFINE EVENT ev3 ON TABLE prod3 WHEN $event = 'UPDATE' "
        f"AND $after.price != $before.price THEN ( CREATE ph3 {setter} );"])
    if r.get("error"):
        return None, f"DEFINE 报错: {r['error'].get('message','')[:80]}"
    r2 = await call(ws, "query", ["UPDATE prod3:x1 SET price = 100;"])
    if r2.get("error"):
        return None, f"UPDATE 报错: {r2['error'].get('message','')[:80]}"
    rows = rows_of(await call(ws, "query", ["SELECT * FROM ph3;"]))
    if not rows:
        return False, "日志表为空（事件未触发）"
    row = dict(rows[0])
    row.pop("id", None)
    return ("pid" in row), json.dumps(row, ensure_ascii=False)


async def main():
    async with websockets.connect(URL, max_size=None) as ws:
        await call(ws, "signin", [{"user": "root", "pass": "root"}])
        await call(ws, "use", ["learn", "kp8"])

        print("=== UPDATE 事件：THEN 里写记录 ID，哪种写法有效（修正版）===\n")
        for label, setter in VARIANTS:
            ok, detail = await run_event(ws, setter)
            flag = "✅ 有 pid" if ok is True else ("❌ 无 pid（静默丢失）" if ok is False else "⚠️ ")
            print(f"  {label:22s} {flag:18s} {detail[:90]}")

        print("\n=== 补充：CREATE 事件里 $this 是否为 NONE ===\n")
        for s in ["REMOVE TABLE IF EXISTS prod4;", "REMOVE TABLE IF EXISTS ph4;",
                  "DEFINE TABLE prod4 SCHEMALESS;", "DEFINE TABLE ph4 SCHEMALESS;"]:
            await call(ws, "query", [s])
        for label, setter in [("裸 $this", "SET pid = $this"),
                              ("$after.id", "SET pid = $after.id")]:
            await call(ws, "query", ["REMOVE TABLE IF EXISTS ph4;"])
            await call(ws, "query", ["DEFINE TABLE ph4 SCHEMALESS;"])
            await call(ws, "query", ["REMOVE EVENT IF EXISTS ev4 ON TABLE prod4;"])
            await call(ws, "query", [
                f"DEFINE EVENT ev4 ON TABLE prod4 WHEN $event = 'CREATE' "
                f"THEN ( CREATE ph4 {setter} );"])
            await call(ws, "query", ["CREATE prod4:c1 SET price = 7;"])
            rows = rows_of(await call(ws, "query", ["SELECT * FROM ph4;"]))
            if not rows:
                print(f"  CREATE 事件 {label:14s} → 日志表为空")
            else:
                row = dict(rows[0]); row.pop("id", None)
                print(f"  CREATE 事件 {label:14s} → {json.dumps(row, ensure_ascii=False)}")

        for t in ["prod3", "ph3", "prod4", "ph4"]:
            await call(ws, "query", [f"REMOVE TABLE IF EXISTS {t};"])


asyncio.run(main())
