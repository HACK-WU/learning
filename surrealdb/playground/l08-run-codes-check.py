#!/usr/bin/env python
"""最终回归：逐条执行 l08-lesson-codes.surql，确认讲义引用的参考答案可复现。

与 p80 相同逻辑，保留为可重复执行的回归脚本（p80 已删）。
"""
import asyncio
import json
import uuid

import websockets

URL = "ws://127.0.0.1:8000/rpc"
SRC = "/mnt/d/projects/learning/surrealdb/playground/l08-lesson-codes.surql"


def strip_comments(sql: str) -> str:
    out = []
    for line in sql.split("\n"):
        t = line.strip()
        if t.startswith("//") or not t:
            continue
        out.append(line)
    return "\n".join(out)


async def call(ws, method, params, timeout=20):
    rid = str(uuid.uuid4())
    await ws.send(json.dumps({"id": rid, "method": method, "params": params}))
    while True:
        msg = json.loads(await asyncio.wait_for(ws.recv(), timeout=timeout))
        if msg.get("id") == rid:
            return msg


async def main():
    sql = strip_comments(open(SRC, encoding="utf-8").read())
    stmts = [s.strip() for s in sql.split(";") if s.strip()]

    errs = 0
    async with websockets.connect(URL, max_size=None) as ws:
        await call(ws, "signin", [{"user": "root", "pass": "root"}])
        await call(ws, "use", ["learn", "kp8"])
        for i, st in enumerate(stmts, 1):
            st = st.replace("\n", " ")
            try:
                r = await call(ws, "query", [st])
            except Exception as e:
                print(f"[{i:2d}] EXC {e}")
                errs += 1
                continue
            if r.get("error"):
                errs += 1
                print(f"[{i:2d}] ERR {json.dumps(r, ensure_ascii=False)[:200]}")
            else:
                res = r.get("result")
                if isinstance(res, dict):
                    res = res.get("result", res)
                s = json.dumps(res, ensure_ascii=False)
                # 只打印关键语句，避免刷屏
                if any(k in st for k in ("price_history", "archive", "LIVE", "post:p1")):
                    print(f"[{i:2d}] {s[:170]}")
    print(f"\nTOTAL = {len(stmts)}   ERRORS = {errs}")


asyncio.run(main())
