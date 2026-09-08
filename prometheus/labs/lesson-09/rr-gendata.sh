#!/usr/bin/env bash
echo "=== does l9-prom-1 accept remote write? (3.x default on) ==="
docker exec l9-rrclient python -c "
import urllib.request,cramjam,time,random
def varint(n):
    o=b''
    while True:
        b=n&0x7f; n>>=7
        if n: o+=bytes([b|0x80])
        else: o+=bytes([b]); return o
def ld(f,p): return varint((f<<3)|2)+varint(len(p))+p
def vi(f,n): return varint((f<<3)|0)+varint(n)
def f64(x):
    import struct; return struct.pack('<d',x)
# build WriteRequest v1: timeseries=1
# TimeSeries{labels=1, samples=2}; Label{name=1,value=2}; Sample{value=1,timestamp=2}
def mk(name,val,ts):
    labs = ld(1, ld(1,b'__name__')+ld(2,name.encode()))
    s = ld(2, ld(1,f64(val))+vi(2,ts))   # NOTE: Sample.value is double -> fixed64 (wt 1), ts varint (wt 0)
    return ld(1, labs+s)
now=int(time.time()*1000)
wr = mk('rr_bench_metric',1.0,now)
body = wr
b=bytes(cramjam.snappy.compress_raw(body))
req=urllib.request.Request('http://l9-prom-1:9090/api/v1/write',data=b,method='POST',
    headers={'Content-Type':'application/x-protobuf','Content-Encoding':'snappy','X-Prometheus-Remote-Write-Version':'0.1.0'})
try:
    r=urllib.request.urlopen(req,timeout=20)
    print('WRITE OK',r.status)
except Exception as e:
    print('WRITE ERR',e)
"
echo "=== verify ==="
docker exec l9-prom-1 wget -q -O - 'http://localhost:9090/api/v1/query?query=rr_bench_metric' 2>&1 | head -c 300
