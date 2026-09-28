#!/usr/bin/env bash
# 只读验证：blueking chart repo 是否可达（不添加，只探测）
set -uo pipefail
export PATH=/root/bk72/install/bin:$PATH
URL=https://hub.bktencent.com/chartrepo/blueking

echo "===== 1. repo index 可达性 ====="
curl -s -o /dev/null -w "  HTTP %{http_code}  大小 %{size_download} bytes  耗时 %{time_total}s\n" \
  --max-time 20 "$URL/index.yaml"

echo ""
echo "===== 2. 拉取 index 看有哪些 chart ====="
curl -s --max-time 30 "$URL/index.yaml" -o /tmp/bk-index.yaml
echo "  大小: $(wc -c < /tmp/bk-index.yaml) bytes"
python3 - <<'PY'
try:
    import yaml
    d=yaml.safe_load(open('/tmp/bk-index.yaml'))
    ents=d.get('entries',{})
    print(f"  chart 总数: {len(ents)}")
    for k in ['bkrepo','bkauth','bk-apigateway','bk-user','bkiam']:
        if k in ents:
            vs=[e['version'] for e in ents[k]]
            print(f"  ✅ {k}: {vs[:4]}")
        else:
            print(f"  ❌ {k}: 不在 index 中")
except Exception as e:
    print("  解析失败:", e)
PY

echo ""
echo "===== 3. 需要的三个 chart 版本是否匹配 ====="
grep -iE 'bkrepo|bkauth|bk-apigateway' /tmp/bk-index.yaml 2>/dev/null | head -3
python3 - <<'PY'
try:
    import yaml
    d=yaml.safe_load(open('/tmp/bk-index.yaml'))
    ents=d.get('entries',{})
    need={'bkrepo':'3.3.1-beta.1','bkauth':'1.0.2','bk-apigateway':'1.13.28'}
    for k,v in need.items():
        vs=[e['version'] for e in ents.get(k,[])]
        print(f"  {k} 需要 {v} -> {'✅ 存在' if v in vs else '❌ 缺失 (有: '+str(vs[:3])+')'}")
except Exception as e:
    print("  解析失败:", e)
PY
