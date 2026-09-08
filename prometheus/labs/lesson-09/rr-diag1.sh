#!/usr/bin/env bash
echo "=== basic HTTP from client to prom-1 ==="
docker exec l9-rrclient python -c "
import urllib.request
try:
    r=urllib.request.urlopen('http://l9-prom-1:9090/api/v1/query?query=up',timeout=10)
    print('OK',r.status,r.read()[:200])
except Exception as e:
    print('ERR',e)
"
echo "=== raw snappy body test (uncompressed body) ==="
docker exec l9-rrclient python -c "
import urllib.request,cramjam
# ReadRequest: query{start=1,end=2,matchers=3}
def varint(n):
    o=b''
    while True:
        b=n&0x7f; n>>=7
        if n: o+=bytes([b|0x80])
        else: o+=bytes([b]); return o
def ld(f,p): return varint((f<<3)|2)+varint(len(p))+p
def vi(f,n): return varint((f<<3)|0)+varint(n)
m=vi(1,0)+ld(2,b'__name__')+ld(3,b'app_requests_total')
import time
end=int(time.time()*1000); start=end-3600000
q=vi(1,start)+vi(2,end)+ld(3,m)
body=ld(1,q)
print('body len',len(body))
for ct,enc,b in [
  ('application/x-protobuf','snappy',bytes(cramjam.snappy.compress_raw(body))),
  ('application/x-protobuf','',body),
]:
    req=urllib.request.Request('http://l9-prom-1:9090/api/v1/read',data=b,method='POST',
        headers={'Content-Type':ct,'Content-Encoding':enc,'X-Prometheus-Remote-Read-Version':'0.1.0'})
    try:
        r=urllib.request.urlopen(req,timeout=20)
        print(enc or 'identity','->',r.status,len(r.read()),r.headers.get('Content-Type'))
    except Exception as e:
        print(enc or 'identity','-> ERR',e)
"
