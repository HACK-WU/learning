#!/usr/bin/env bash
echo "########## 内存对照：官方宣称流式省内存 ##########"
mem_of() { docker stats l9-prom-1 --no-stream --format '{{.MemUsage}}' | awk '{print $1}'; }
echo "baseline: $(mem_of)"
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
def ask(acc,sec):
    end=int(time.time()*1000); start=end-sec*1000
    q=vi(1,start)+vi(2,end)+ld(3, vi(1,0)+ld(2,b'__name__')+ld(3,b'rr_bench'))
    body=ld(1,q)
    for a in acc: body+=vi(2,a)
    b=bytes(cramjam.snappy.compress_raw(body))
    req=urllib.request.Request('http://l9-prom-1:9090/api/v1/read',data=b,method='POST',
        headers={'Content-Type':'application/x-protobuf','Content-Encoding':'snappy',
                 'X-Prometheus-Remote-Read-Version':'0.1.0',
                 'Accept':'application/x-protobuf,application/x-streamed-protobuf'})
    t0=time.time()
    r=urllib.request.urlopen(req,timeout=180)
    n=len(r.read())
    return n,(time.time()-t0)*1000
import sys
mode=sys.argv[1]; secs=int(sys.argv[2]); times=int(sys.argv[3])
acc=[] if mode=='SAMPLES' else [1]
tot=0; mx=0
for i in range(times):
    n,ms=ask(acc,secs)
    tot+=n; mx=max(mx,ms)
print(f'{mode}: queries={times} range={secs}s total_bytes={tot} max_ms={mx:.0f}')
" "$1" "$2" "$3" 2>&1
echo "after:    $(mem_of)"
