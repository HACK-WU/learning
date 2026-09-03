"""课 11 HTTP 辅助库。

沿用 l10-lib.py 的接口形状，额外提供：
  - 起/停临时实例（用于切换存储后端）
  - 计时与体积测量
注意：3.x 下 `USE NS` 会自动创建 NS 但不创建 DB，必须显式建库。
"""
import base64
import json
import os
import shutil
import signal
import subprocess
import time
import urllib.request
import urllib.error

HOST = "127.0.0.1"
USER = "root"
PASS = "root"

_BASIC = base64.b64encode(("%s:%s" % (USER, PASS)).encode()).decode()


def _req(method, url, body=None, headers=None, timeout=10, auth=True):
    data = None
    hdrs = {"Accept": "application/json"}
    if auth:
        hdrs["Authorization"] = "Basic " + _BASIC
    if body is not None:
        data = body.encode("utf-8")
        hdrs["Content-Type"] = "application/json"
    if headers:
        hdrs.update(headers)
    req = urllib.request.Request(url, data=data, headers=hdrs, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode("utf-8", "replace")
            return r.status, raw
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        return e.code, raw
    except Exception as e:
        return None, repr(e)


def sql(query, ns=None, db=None, port=8000, timeout=20):
    """执行 SQL，返回 (status, 解析后的对象)。"""
    url = "http://%s:%d/sql" % (HOST, port)
    hdrs = {}
    if ns:
        hdrs["surreal-ns"] = ns
    if db:
        hdrs["surreal-db"] = db
    st, raw = _req("POST", url, body=query, headers=hdrs, timeout=timeout)
    try:
        obj = json.loads(raw)
    except Exception:
        obj = raw
    return st, obj


def sql_text(query, ns=None, db=None, port=8000, timeout=20):
    st, obj = sql(query, ns=ns, db=db, port=port, timeout=timeout)
    return st, obj


def ensure_nsdb(ns, db, port=8000):
    """3.x 下 USE NS 自动建 NS 但不建 DB，必须显式建库。"""
    sql("DEFINE NAMESPACE IF NOT EXISTS %s;" % ns, port=port)
    sql("DEFINE DATABASE IF NOT EXISTS %s;" % db, ns=ns, port=port)


def rows(obj):
    """从 /sql 返回里取 result 数组。"""
    if isinstance(obj, list) and obj:
        r = obj[0].get("result")
        return r if isinstance(r, list) else []
    return []


def err(obj):
    if isinstance(obj, list) and obj:
        return obj[0].get("status"), obj[0].get("result")
    if isinstance(obj, dict):
        return obj.get("code"), obj.get("information") or obj.get("message")
    return None, obj


def short(o, n=160):
    s = json.dumps(o, ensure_ascii=False, default=str)
    return s if len(s) <= n else s[:n] + "..."


def health(port=8000, timeout=3):
    return _req("GET", "http://%s:%d/health" % (HOST, port), timeout=timeout)


def wait_health(port, wait=15, timeout=2):
    """轮询 /health 直到 200 或超时。返回 (ok, 耗时秒)。

    ⚠️ 坑（课 11 实测）：/health 只证明「端口上有东西活着」，不证明它是
    我们的 SurrealDB。本机 84xx 段被其他服务占用，/health 返回 200 但
    /version 不是 surrealdb-*，导致探测全部打到了陌生服务上（表现为
    写入成功但 count=0、目录体积恒定）。
    因此这里改为等待 /version，并用 verify_identity 判定。
    """
    t0 = time.time()
    while time.time() - t0 < wait:
        code, body = _req("GET", "http://%s:%d/version" % (HOST, port),
                          timeout=timeout, auth=False)
        if code == 200 and "surrealdb-" in (body or ""):
            return True, round(time.time() - t0, 2)
        time.sleep(0.3)
    return False, round(time.time() - t0, 2)


def verify_identity(port, timeout=3):
    """确认端口上跑的确实是 SurrealDB，返回 (ok, version 串)。"""
    code, body = _req("GET", "http://%s:%d/version" % (HOST, port),
                      timeout=timeout, auth=False)
    if code == 200 and "surrealdb-" in (body or ""):
        return True, body.strip()
    return False, (body or "")[:80]


def pick_port(base, span=60):
    """从 base 起找一个当前未被占用的端口。"""
    import socket
    for p in range(base, base + span):
        s = socket.socket()
        s.settimeout(0.4)
        try:
            s.connect((HOST, p))
            s.close()
            continue  # 被占用
        except Exception:
            s.close()
            return p
    return None


class Inst:
    """一个临时 SurrealDB 实例。"""

    def __init__(self, path, port, log=None, extra=None):
        self.path = path
        self.port = port
        self.log_path = log or "/tmp/l11-%d.log" % port
        self.extra = extra or []
        self.p = None
        self.logf = None

    def start(self, wait=15):
        self.logf = open(self.log_path, "w")
        cmd = ["surreal", "start", "--no-banner",
               "--user", USER, "--pass", PASS,
               "--bind", "%s:%d" % (HOST, self.port),
               "--log", "info"] + self.extra + [self.path]
        self.p = subprocess.Popen(cmd, stdout=self.logf, stderr=subprocess.STDOUT)
        return wait_health(self.port, wait=wait)

    def stop(self):
        if self.p and self.p.poll() is None:
            self.p.send_signal(signal.SIGTERM)
            try:
                self.p.wait(timeout=6)
            except Exception:
                self.p.kill()
        if self.logf:
            self.logf.close()

    def log(self):
        try:
            with open(self.log_path) as f:
                return f.read()
        except Exception:
            return ""

    def loggrep(self, *keys):
        out = []
        for line in self.log().splitlines():
            low = line.lower()
            if any(k.lower() in low for k in keys):
                out.append(" ".join(line.split()))
        return out


def dirsize(path):
    """目录总字节数。"""
    if not os.path.exists(path):
        return 0
    if os.path.isfile(path):
        return os.path.getsize(path)
    tot = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                tot += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return tot


def rmtree(path):
    if os.path.exists(path):
        shutil.rmtree(path, ignore_errors=True)
