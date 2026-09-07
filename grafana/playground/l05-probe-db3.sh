#!/usr/bin/env bash
# 修正 group 保留字问题，并深入诊断 value 编码
set -u
WORK=/tmp/l05db

echo "=========================================="
echo " resource.value 编码诊断（修正版）"
echo "=========================================="

echo ""
echo "--- [1] 逐行看 value 的原始字节 ---"
python3 -c "
import sqlite3
c=sqlite3.connect('$WORK/grafana2.db')
rows=c.execute('SELECT name, value FROM resource LIMIT 4').fetchall()
for name, v in rows:
    print('  name=%s' % name)
    print('    类型=%s 长度=%s' % (type(v).__name__, (len(v) if v is not None else 0)))
    if isinstance(v, bytes):
        print('    hex前24: %s' % v[:24].hex())
        print('    repr前32: %r' % v[:32])
    print()
"

echo ""
echo "--- [2] 判断是否 protobuf / msgpack / snappy / zstd ---"
python3 -c "
import sqlite3
c=sqlite3.connect('$WORK/grafana2.db')
rows=c.execute('SELECT name, value FROM resource').fetchall()
import collections
sig=collections.Counter()
for name, v in rows:
    if not isinstance(v, bytes): 
        sig['非bytes']+=1; continue
    sig['前1字节:%02x'%v[0]]+=1
print('  首字节分布：')
for k,n in sig.most_common(10):
    print('    %-16s %d 行' % (k,n))
"

echo ""
echo "--- [3] 试 zstd / snappy / msgpack（若已安装）---"
python3 -c "
import sqlite3
c=sqlite3.connect('$WORK/grafana2.db')
rows=c.execute('SELECT name, value FROM resource').fetchall()
v=[x for _,x in rows if isinstance(x,bytes)]
if not v: print('  无 bytes 数据'); raise SystemExit
s=v[0]
for mod in ('zstandard','snappy','msgpack','lz4'):
    try:
        m=__import__(mod)
        print('  %s 已安装' % mod)
    except ImportError:
        print('  %s 未安装' % mod)
"

echo ""
echo "--- [4] 关键结论：不管什么编码，用 API 读回才是可靠判据 ---"
echo "  → value 是 Grafana 内部序列化格式（13.x 起 k8s 风格存储）"
echo "  → 对学习者而言，【不需要】直接读库"
echo "  → 可靠的判据是 API 读回：GET /api/dashboards/uid/xxx"
echo ""
echo "  用 API 验证 transform 持久化（这才是学员该用的方法）："
python3 -c "
import json,urllib.request,base64,urllib.error
GF='http://localhost:3001'
AUTH=base64.b64encode(b'admin:admin').decode()
def req(m,p,b=None):
    d=json.dumps(b).encode() if b is not None else None
    r=urllib.request.Request(GF+p,data=d,method=m)
    r.add_header('Authorization','Basic '+AUTH)
    r.add_header('Content-Type','application/json')
    try:
        with urllib.request.urlopen(r,timeout=30) as x:
            return x.status, json.loads(x.read().decode() or '{}')
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or '{}')
TF=[{'id':'reduce','options':{'reducers':['mean'],'mode':'reduceFields'}}]
dash={'uid':'l05-api-probe','title':'L05 API probe','schemaVersion':41,
 'panels':[{'id':1,'type':'table','title':'p','gridPos':{'h':8,'w':12,'x':0,'y':0},
   'datasource':{'type':'prometheus','uid':'afx7x6dx803y8e'},
   'targets':[{'refId':'A','datasource':{'type':'prometheus','uid':'afx7x6dx803y8e'},'expr':'up'}],
   'transformations':TF}],
 'time':{'from':'now-1h','to':'now'}}
st,_=req('POST','/api/dashboards/db',{'dashboard':dash,'overwrite':True})
st2,body=req('GET','/api/dashboards/uid/l05-api-probe')
p=body['dashboard']['panels'][0]
print('    保存 HTTP %s / 读回 HTTP %s' % (st,st2))
print('    transformations = %s' % json.dumps(p.get('transformations'),ensure_ascii=False))
print('    逐字节一致 = %s' % ('是' if p.get('transformations')==TF else '否'))
req('DELETE','/api/dashboards/uid/l05-api-probe')
print('    已清理')
"

echo ""
echo "=========================================="
