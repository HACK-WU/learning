#!/usr/bin/env bash
docker exec l9-rrclient python -c "
import urllib.request,cramjam,time
def varint(n):
    o=b''
    while True:
        b=n&0x7f; n>>=7
        if n: o+=bytes([b|0x80])
        else: o+=bytes([b]); return o
def ld(f,p): return varint((f<<3)|2)+varint(len(p))+p
def vi(f,n): return varint((f<<3)|0)+varint(n)
m=vi(1,0)+ld(2,b'__name__')+ld(3,b'app_requests_total')
end=int(time.time()*1000); start=end-3600000
q=vi(1,start)+vi(2,end)+ld(3,m)
base=ld(1,q)
tests=[
 ('SAMPLES no Accept hdr', base, {}),
 ('SAMPLES with Accept', base, {'Accept':'application/x-protobuf,application/x-streamed-protobuf'}),
 ('STREAMED acc=[1]', base+vi(2,1), {'Accept':'application/x-protobuf,application/x-streamed-protobuf'}),
]
for name,body,extra in tests:
    b=bytes(cramjam.snappy.compress_raw(body))
    h={'Content-Type':'application/x-protobuf','Content-Encoding':'snappy','X-Prometheus-Remote-Read-Version':'0.1.0'}
    h.update(extra)
    req=urllib.request.Request('http://l9-prom-1:9090/api/v1/read',data=b,method='POST',headers=h)
    t0=time.time()
    try:
        r=urllib.request.urlopen(req,timeout=30)
        raw=r.read()
        print(f'{name}: {r.status} ctype={r.headers.get(\"Content-Type\")} bytes={len(raw)} ms={round((time.time()-t0)*1000,1)}')
    except Exception as e:
        print(f'{name}: ERR {e}')
" 2>&1
