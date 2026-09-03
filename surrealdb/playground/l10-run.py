"""
课 10 运行器：文件按 "-- ## 名称" 切块，逐块单独 POST（沿用课 9 的块级运行器）。
用法： python3 l10-run.py <script.surql> [ns] [db] [maxlen] [-v]
"""
import json
import sys
import urllib.request
import base64

path = sys.argv[1]
ns = sys.argv[2] if len(sys.argv) > 2 else "learn"
db = sys.argv[3] if len(sys.argv) > 3 else "kp10"
maxlen = int(sys.argv[4]) if len(sys.argv) > 4 else 600
verbose = "-v" in sys.argv

raw = open(path, encoding="utf-8").read()

blocks = []
cur_name = "(prelude)"
cur_lines = []
for line in raw.splitlines():
    if line.startswith("-- ##"):
        if "".join(cur_lines).strip():
            blocks.append((cur_name, "\n".join(cur_lines)))
        cur_name = line[5:].strip()
        cur_lines = []
    else:
        cur_lines.append(line)
if "".join(cur_lines).strip():
    blocks.append((cur_name, "\n".join(cur_lines)))


def post(q):
    req = urllib.request.Request(
        f"http://127.0.0.1:8000/sql?ns={ns}&db={db}",
        data=q.encode("utf-8"),
        headers={
            "Accept": "application/json",
            "Authorization": "Basic " + base64.b64encode(b"root:root").decode(),
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return json.loads(e.read().decode("utf-8"))


header = f"USE NS {ns} DB {db};\n"

for name, q in blocks:
    data = post(header + q)
    print(f"\n===== {name} =====")
    if isinstance(data, dict) and "code" in data:
        print("  ERR:", data.get("code"), "-", str(data.get("information")).replace("\n", " | "))
        continue
    items = data if isinstance(data, list) else [data]
    for i, r in enumerate(items, 1):
        st = r.get("status")
        res = r.get("result")
        s = json.dumps(res, ensure_ascii=False, default=str)
        if len(s) > maxlen:
            s = s[:maxlen] + f"... (+{len(s)-maxlen})"
        prefix = f"  [{i}] {st}"
        if verbose:
            prefix += f" {r.get('time')}"
        print(f"{prefix}: {s}")
