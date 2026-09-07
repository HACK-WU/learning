#!/usr/bin/env bash
# 复核（字段名已修正）：resource 表 = Grafana 13 的 dashboard 真实存储
set -u
cat > /tmp/l03-diag-res2.py <<'PYEOF'
import sqlite3, json
con=sqlite3.connect('/tmp/l03db/grafana.db'); cur=con.cursor()

print("=== 1. resource 表内容（group / resource / namespace / name） ===")
cur.execute("SELECT guid, \"group\", resource, namespace, name, resource_version, folder FROM resource ORDER BY resource, name")
rows=cur.fetchall()
print(f"  共 {len(rows)} 行")
for r in rows:
    print(f"    group={r[1]} | resource={r[2]} | ns={r[3]} | name={r[4]} | v{r[5]} | folder={r[6]}")

print()
print("=== 2. 读出 l03-timefrom 的 value，确认 timeFrom 持久化 ===")
cur.execute("SELECT name, value FROM resource WHERE CAST(value AS TEXT) LIKE '%l03-timefrom%'")
for name, val in cur.fetchall():
    j=json.loads(val)
    print(f"  name={name}")
    print("  metadata.name =", j.get('metadata',{}).get('name'))
    for p in j.get('panels',[]) or []:
        print(f"    panel[{p.get('id')}] {p.get('title')!r}  timeFrom={p.get('timeFrom','<未设置>')}")

print()
print("=== 3. 全库时序特征复核（课 1 论断是否仍成立） ===")
cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
tables=[r[0] for r in cur.fetchall()]
print("  当前总表数 =", len(tables), "（课 1 记录 92）")
pat=('sample','chunk','block','series','metric','tsdb','wal','index')
hit=[t for t in tables if any(p in t.lower() for p in pat)]
print("  时序特征表命中:", hit if hit else "无 → 零命中，课 1『不存时序』论断仍成立 ✅")

print()
print("=== 4. 新增表：课 1 之后多了哪些与存储相关的表 ===")
new=[t for t in tables if t in ('resource','resource_history','kv_store','kv_leases','entity')]
print("  ", new)

print()
print("=== 5. resource_history 行数 ===")
cur.execute("SELECT count(*) FROM resource_history"); print("  行数 =", cur.fetchone()[0],
            "（每次保存都留一份历史 → 可回滚，课 10 伏笔）")
PYEOF
python3 /tmp/l03-diag-res2.py
