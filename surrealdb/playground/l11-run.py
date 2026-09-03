"""课 11 块级运行器：按 `-- ##` 切块，每块独立 POST，单块报错不阻断后续。

沿用课 9 l09-run.py / 课 10 l10-run.py 的设计（课 4 教训的工程化落地：
整文件一次 POST 会被一条坏语句炸掉，且报错定位困难）。

用法：
  python3 -u l11-run.py <script.surql> [ns] [db] [port]
默认 ns=learn db=kp11 port=8000
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from l11lib import sql, short  # noqa


def first(obj):
    return obj[0] if isinstance(obj, list) and obj else {}


def main():
    args = sys.argv[1:]
    if not args:
        print("用法: python3 -u l11-run.py <script.surql> [ns] [db] [port]")
        return 2
    path = args[0]
    ns = args[1] if len(args) > 1 else "learn"
    db = args[2] if len(args) > 2 else "kp11"
    port = int(args[3]) if len(args) > 3 else 8000

    with open(path, encoding="utf-8") as f:
        content = f.read()

    # 按 `-- ##` 分块
    blocks = []
    cur = []
    for line in content.splitlines():
        if line.strip().startswith("-- ##"):
            if cur:
                blocks.append("\n".join(cur))
            cur = [line]
        else:
            cur.append(line)
    if cur:
        blocks.append("\n".join(cur))

    if not blocks:
        blocks = [content]

    print("=" * 74)
    print("文件: %s   共 %d 块   ns=%s db=%s port=%d" % (path, len(blocks), ns, db, port))
    print("=" * 74)

    nerr = 0
    for i, b in enumerate(blocks, 1):
        title = ""
        for line in b.splitlines():
            if line.strip().startswith("-- ##"):
                title = line.strip().lstrip("-").strip().lstrip("#").strip()
                break
        body = "\n".join(l for l in b.splitlines() if not l.strip().startswith("-- ##"))
        if not body.strip():
            continue
        q = "USE NS %s DB %s;\n%s" % (ns, db, body)
        st, obj = sql(q, ns=ns, db=db, port=port, timeout=120)
        f0 = first(obj)
        status = f0.get("status")
        print("\n--- 块 %d%s ---" % (i, (" · " + title) if title else ""))
        # 跳过 USE 那条
        rest = obj[1:] if isinstance(obj, list) and len(obj) > 1 else obj
        if isinstance(rest, list):
            for r in rest:
                s = r.get("status")
                res = r.get("result")
                if s == "ERR":
                    nerr += 1
                    print("  ERR | %s" % short(res, 300))
                else:
                    print("  %-4s| %s" % (s, short(res, 300)))
        else:
            print("  HTTP %s %s" % (st, short(obj, 300)))

    print("\n" + "=" * 74)
    print("完成：%d 块，其中 %d 条语句报 ERR" % (len(blocks), nerr))
    return 0


if __name__ == "__main__":
    sys.exit(main())
