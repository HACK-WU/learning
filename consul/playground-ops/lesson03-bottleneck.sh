#!/usr/bin/env bash
export CONSUL_HTTP_ADDR=http://127.0.0.1:8501
BASE=/tmp/consul-ops
curl -s "$CONSUL_HTTP_ADDR/v1/agent/metrics" > "$BASE/m.json"
echo "顶层键: $(python3 -c "import json;print(list(json.load(open('$BASE/m.json')).keys()))")"
python3 - <<'PYEOF'
import json
d=json.load(open('/tmp/consul-ops/m.json'))

def walk(name, obj):
    print(f"\n=== {name} ===")
    if isinstance(obj, dict):
        items=list(obj.items())
    elif isinstance(obj, list):
        items=[(s.get('Name','?'), s) for s in obj if isinstance(s,dict)]
    else:
        print("  类型",type(obj)); return
    hits=[(k,v) for k,v in items if any(p in k.lower() for p in ['raft','commit','leader','fsm','apply'])]
    if not hits:
        print(f"  共 {len(items)} 项，无 raft/commit/leader 相关"); 
        print("  样例:", [k for k,_ in items[:5]])
        return
    for k,v in hits[:15]:
        if isinstance(v,dict):
            if 'Value' in v: val=v['Value']
            elif 'Sum' in v: val=f"Sum={v.get('Sum')} Count={v.get('Count')} Mean={v.get('Mean')} Max={v.get('Max')}"
            else: val=str(v)[:60]
        else: val=v
        print(f"  {k:50s} = {val}")

for key in ['Gauges','Counters','Samples','Points']:
    if key in d: walk(key, d[key])

print("\n=== runtime / 内存 ===")
g=d.get('Gauges',{})
for k in sorted(g) if isinstance(g,dict) else []:
    if 'runtime' in k.lower() or 'mem' in k.lower():
        print(f"  {k:52s} = {g[k]}")
PYEOF
