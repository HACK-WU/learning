#!/usr/bin/env bash
# 修正探针：日志必须写到"宿主机可见"的地方。
# 问题：echo 容器内的 /tmp/l03-echo-log.txt ≠ 宿主机 /tmp/l03-echo-log.txt（之前看错了文件）
# 修法：让容器把日志写到 bind mount 的目录，实验结束再从该目录读
set -u
mkdir -p /tmp/l03probe
rm -f /tmp/l03probe/log.txt

cat > /tmp/l03probe/echo.py <<'PYEOF'
import http.server, json
LOG='/shared/log.txt'
class H(http.server.BaseHTTPRequestHandler):
    def _log(self, method):
        body=''
        ln=int(self.headers.get('Content-Length') or 0)
        if ln: body=self.rfile.read(ln).decode('utf-8','replace')
        with open(LOG,'a') as f:
            f.write(json.dumps({'method':method,'path':self.path,'body':body},ensure_ascii=False)+"\n")
        resp=json.dumps({"status":"success","data":{"resultType":"vector","result":[]}}).encode()
        self.send_response(200); self.send_header('Content-Type','application/json')
        self.send_header('Content-Length',str(len(resp))); self.end_headers(); self.wfile.write(resp)
    def do_GET(self): self._log('GET')
    def do_POST(self): self._log('POST')
    def log_message(self,*a): pass
http.server.HTTPServer(('0.0.0.0',9299),H).serve_forever()
PYEOF

docker rm -f l03-echo >/dev/null 2>&1
docker run -d --name l03-echo --network grafana-net -p 9299:9299 \
  -v /tmp/l03probe:/shared python:3.12-alpine python /shared/echo.py >/dev/null 2>&1
sleep 4
curl -s --max-time 3 http://localhost:9299/ping >/dev/null
echo "探针自检：宿主机 /tmp/l03probe/log.txt 内容 ="
cat /tmp/l03probe/log.txt 2>/dev/null || echo "  （空）"
echo

cat > /tmp/l03probe/run.py <<'PYEOF'
import json, urllib.request, http.cookiejar, time, os
GF='http://localhost:3001'
LOG='/tmp/l03probe/log.txt'
cj=http.cookiejar.MozillaCookieJar()
op=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
op.open(urllib.request.Request(GF+'/login',
    data=json.dumps({"user":"admin","password":"admin"}).encode(),
    headers={'Content-Type':'application/json'}))

newds={"name":"L03Probe","type":"prometheus","url":"http://l03-echo:9299",
       "access":"proxy","isDefault":False,"jsonData":{"httpMethod":"POST"}}
r=op.open(urllib.request.Request(GF+'/api/datasources',
    data=json.dumps(newds).encode(), headers={'Content-Type':'application/json'}))
j=json.load(r); puid=j.get('datasource',{}).get('uid') or j.get('uid')
print("探针数据源 uid =", puid)

def probe(expr, scoped, label):
    open(LOG,'w').close()
    now=int(time.time()*1000)
    qq={"refId":"A","datasource":{"type":"prometheus","uid":puid},
        "expr":expr,"instant":True,"range":False}
    if scoped: qq["scopedVars"]=scoped
    payload={"queries":[qq],"from":str(now-3600000),"to":str(now)}
    try:
        d=json.load(op.open(urllib.request.Request(GF+'/api/ds/query',
            data=json.dumps(payload).encode(), headers={'Content-Type':'application/json'})))
        st=d['results']['A'].get('status')
    except Exception as e:
        st='EXC:'+str(e)[:100]
    print(f"\n--- {label} ---")
    print(f"  查询 status = {st}")
    lines=[l for l in open(LOG,encoding='utf-8') if l.strip()]
    if not lines:
        print("  探针未收到请求"); return
    for l in lines[:4]:
        rec=json.loads(l)
        print(f"  {rec['method']} {rec['path'][:180]}")
        if rec['body']: print(f"     body = {rec['body'][:260]}")

probe('up{instance="$host"}', None, "① expr 含 $host，不传 scopedVars")
probe('up{instance="$host"}',
      {"host":{"text":"grafana-node2:9100","value":"grafana-node2:9100"}},
      "② expr 含 $host，传 scopedVars")
probe('rate(prometheus_http_requests_total[$__rate_interval])', None, "③ expr 含 $__rate_interval（内置）")

# 清理
urllib.request.Request(GF+f'/api/datasources/uid/{puid}', method='DELETE')
try:
    print("\n清理临时数据源 HTTP =", op.open(urllib.request.Request(
        GF+f'/api/datasources/uid/{puid}', method='DELETE')).status)
except Exception as e: print("清理:", str(e)[:100])
PYEOF
python3 /tmp/l03probe/run.py
