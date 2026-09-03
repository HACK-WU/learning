#!/usr/bin/env python
"""精确定位 $this 的语义：语句目标位 vs 值位。

已知矛盾现象：
  - 讲义 290 行 `UPDATE $this SET ...` 会递归 23 层 → 说明它定位到了记录
  - 但 `SET pid = $this` / `$this.id` 静默丢失 → 说明作值时是 NONE

本脚本分别验证：
  A) $this 作 UPDATE 目标，能否真的改到字段
  B) $this 作值时 type::of / 各种取值
  C) 各事件类型下 $this 是否均为 NONE
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


async def reset(ws, tbl):
    for t in (tbl, tbl + "_log"):
        await call(ws, "query", [f"REMOVE TABLE IF EXISTS {t};"])
        await call(ws, "query", [f"DEFINE TABLE {t} SCHEMALESS;"])


async def main():
    async with websockets.connect(URL, max_size=None) as ws:
        await call(ws, "signin", [{"user": "root", "pass": "root"}])
        await call(ws, "use", ["learn", "kp8"])

        print("=== A) $this 作 UPDATE 目标：能否真的改到记录 ===\n")
        await reset(ws, "ta")
        await call(ws, "query", ["CREATE ta:m1 SET title = 'T1';"])
        # 用守卫条件避免递归：只在 hits 字段不存在时才写入，第二次进入即终止
        await call(ws, "query", [
            "DEFINE EVENT ev_a ON TABLE ta WHEN $event = 'UPDATE' "
            "AND $after.title != $before.title AND !($after.hits ?? false) "
            "THEN ( UPDATE $this SET hits = 1 );"])
        r = await call(ws, "query", ["UPDATE ta:m1 SET title = 'T2';"])
        err = r.get("error")
        if err:
            print("  UPDATE 报错:", json.dumps(err, ensure_ascii=False)[:150])
        rows = rows_of(await call(ws, "query", ["SELECT * FROM ta;"]))
        print("  记录终态:", json.dumps(rows, ensure_ascii=False))
        print("  → hits 出现说明 UPDATE $this 真的定位到了记录（语句目标位有效）\n")

        print("=== B) $this 作值：逐事件类型验证 ===\n")
        for ev in ("CREATE", "UPDATE", "DELETE"):
            await reset(ws, "tb")
            await call(ws, "query", ["REMOVE EVENT IF EXISTS ev_b ON TABLE tb;"])
            # 记录 $this 的类型与形态
            body = ("CREATE tb_log SET "
                    "t_of = type::of($this), "
                    "t_this = $this, "
                    "t_this_id = $this.id, "
                    "t_after_id = $after.id, "
                    "t_before_id = $before.id, "
                    "ev = $event")
            r = await call(ws, "query", [
                f"DEFINE EVENT ev_b ON TABLE tb WHEN $event = '{ev}' THEN ( {body} );"])
            if r.get("error"):
                print(f"  {ev:7s} DEFINE 报错: {r['error'].get('message','')[:80]}")
                continue
            if ev == "CREATE":
                await call(ws, "query", ["CREATE tb:b1 SET v = 1;"])
            elif ev == "UPDATE":
                await call(ws, "query", ["CREATE tb:b1 SET v = 1;"])
                await call(ws, "query", ["UPDATE tb:b1 SET v = 2;"])
            else:
                await call(ws, "query", ["CREATE tb:b1 SET v = 1;"])
                await call(ws, "query", ["DELETE tb:b1;"])
            rows = rows_of(await call(ws, "query", ["SELECT * FROM tb_log;"]))
            if not rows:
                print(f"  {ev:7s} → 日志为空（事件未触发）")
            else:
                row = dict(rows[0]); row.pop("id", None)
                print(f"  {ev:7s} → {json.dumps(row, ensure_ascii=False)}")

        for t in ("ta", "ta_log", "tb", "tb_log"):
            await call(ws, "query", [f"REMOVE TABLE IF EXISTS {t};"])


asyncio.run(main())
