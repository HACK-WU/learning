import base64
import json
import os
import sys
import urllib.error
import urllib.request

HOST = os.environ.get("SDB_HOST", "http://127.0.0.1:8000")


def _req(url, data=None, headers=None, method=None, timeout=20):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8")
            code = r.getcode()
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8")
        code = e.code
    try:
        return code, json.loads(raw)
    except Exception:
        return code, raw


_ENSURED = set()


def ensure_nsdb(ns, db):
    """确保 ns/db 存在（3.x 下 USE NS 会自动创建 NS，但 DB 需要显式 DEFINE 或 USE DB）。"""
    key = (ns, db)
    if ns is None or db is None or key in _ENSURED:
        return
    _ENSURED.add(key)
    auth = {
        "Accept": "application/json",
        "Authorization": "Basic " + base64.b64encode(b"root:root").decode(),
    }
    _req(
        HOST + "/sql",
        data=f"DEFINE NAMESPACE IF NOT EXISTS {ns};\nUSE NS {ns};\nDEFINE DATABASE IF NOT EXISTS {db};\n".encode("utf-8"),
        headers=dict(auth, **{"surreal-ns": ns}),
    )
    _req(
        HOST + "/sql",
        data=f"USE NS {ns};\nDEFINE DATABASE IF NOT EXISTS {db};\n".encode("utf-8"),
        headers=dict(auth, **{"surreal-ns": ns, "surreal-db": db}),
    )


def sql(q, ns=None, db=None, user="root", pw="root", token=None):
    """执行 SurrealQL。默认 root 基础认证；传 token 则用 Bearer。"""
    ensure_nsdb(ns, db)
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    else:
        headers["Authorization"] = "Basic " + base64.b64encode(
            f"{user}:{pw}".encode()
        ).decode()
    if ns:
        headers["surreal-ns"] = ns
    if db:
        headers["surreal-db"] = db
    url = HOST + "/sql"
    if ns and db:
        url += f"?ns={ns}&db={db}"
    return _req(url, data=q.encode("utf-8"), headers=headers)


def signin(ns, db, ac, vars=None, timeout=20):
    """访问 /signin 端点，返回 (code, body)。成功时 body 为 dict 含 token。"""
    ensure_nsdb(ns, db)
    body = {"ns": ns, "db": db, "ac": ac}
    if vars:
        body.update(vars)
    return _req(
        HOST + "/signin",
        data=json.dumps(body).encode("utf-8"),
        headers={"Accept": "application/json", "Content-Type": "application/json"},
        timeout=timeout,
    )


def signup(ns, db, ac, vars=None):
    ensure_nsdb(ns, db)
    body = {"ns": ns, "db": db, "ac": ac}
    if vars:
        body.update(vars)
    return _req(
        HOST + "/signup",
        data=json.dumps(body).encode("utf-8"),
        headers={"Accept": "application/json", "Content-Type": "application/json"},
    )


def show(label, code, data, maxlen=420):
    s = json.dumps(data, ensure_ascii=False, default=str)
    if len(s) > maxlen:
        s = s[:maxlen] + f"...(+{len(s) - maxlen})"
    print(f"  {label}: HTTP {code} {s}")


def short(data):
    """把 /sql 的返回压成一行摘要。"""
    if isinstance(data, list):
        out = []
        for r in data:
            out.append("%s=%s" % (r.get("status"), json.dumps(r.get("result"), ensure_ascii=False, default=str)))
        return " | ".join(out)
    return json.dumps(data, ensure_ascii=False, default=str)


def brief(data, maxlen=300):
    s = short(data)
    if len(s) > maxlen:
        s = s[:maxlen] + f"...(+{len(s) - maxlen})"
    return s


def run_sql(label, q, ns=None, db=None, token=None, user="root", pw="root", maxlen=300):
    code, data = sql(q, ns=ns, db=db, token=token, user=user, pw=pw)
    print(f"  {label}: HTTP {code} {brief(data, maxlen)}")
    return code, data
