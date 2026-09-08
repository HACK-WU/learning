#!/usr/bin/env bash
docker exec l9-rrclient python -c "
import urllib.request,cramjam,time,statistics
def varint(n):
    o=b''
    while True:
        b=n&0x7f; n>>=7
        if n: o+=bytes([b|0x80])
        else: o+=bytes([b]); return o
def ld(f,p): return varint((f<<3)|2)+varint(len(p))+p
def vi(f,n): return varint((f<<3)|0)+varint(n)
def frames(raw):
    n,i=0,0
    while i<len(raw):
        shift,size=0,0
        while True:
            b=raw[i]; i+=1
            size|=(b&0x7f)<<shift; shift+=7
            if not (b&0x80): break
        if i+4>len(raw): break
        i+=4; i+=size; n+=1
        if size==0: break
    return n
def ask(matchers,dur,acc):
    end=int(time.time()*1000); start=end-dur*1000
    q=vi(1,start)+vi(2,end)
    for k,v in matchers:
        q+=ld(3, vi(1,0)+ld(2,k.encode())+ld(3,v.encode()))
    body=ld(1,q)
    for a in acc: body+=vi(2,a)
    b=bytes(cramjam.snappy.compress_raw(body))
    req=urllib.request.Request('http://l9-prom-1:9090/api/v1/read',data=b,method='POST',
        headers={'Content-Type':'application/x-protobuf','Content-Encoding':'snappy',
                 'X-Prometheus-Remote-Read-Version':'0.1.0',
                 'Accept':'application/x-protobuf,application/x-streamed-protobuf'})
    t0=time.time()
    r=urllib.request.urlopen(req,timeout=120)
    raw=r.read()
    return len(raw),(time.time()-t0)*1000,r.headers.get('Content-Type',''),raw

cases=[
 ('3 序列   app_requests_total', [('__name__','app_requests_total')]),
 ('18 序列  duration_bucket',     [('__name__','app_request_duration_seconds_bucket')]),
 ('500 序列 rr_bench route=/',    [('__name__','rr_bench'),('route','/')]),
 ('1000 序列 rr_bench route!=/api/detail', [('__name__','rr_bench')]),
 ('1500 序列 rr_bench 全部',       [('__name__','rr_bench')]),
]
print(f\"{'场景':34s} {'SAMPLES':>10s} {'STREAMED':>10s} {'frames':>7s} {'ratio':>7s}  结论\")
print('-'*90)
for label,mt in cases:
    o={}
    for name,acc in [('SAMPLES',[]),('STREAMED',[1])]:
        sz=[];fr=[];ct=''
        for k in range(5):
            try:
                s,ms,c,raw=ask(mt,3600,acc)
            except Exception as e:
                print(f'{label}: ERR {e}'); break
            sz.append(s); ct=c
            if 'streamed' in c: fr.append(frames(raw))
            time.sleep(0.25)
        if not sz: continue
        o[name]=(statistics.median(sz), int(statistics.median(fr)) if fr else 0)
    if 'SAMPLES' not in o or 'STREAMED' not in o: continue
    a,b2=o['SAMPLES'],o['STREAMED']
    v='SAMPLES更省' if a[0]<b2[0] else 'STREAMED更省'
    print(f'{label:34s} {int(a[0]):10d} {int(b2[0]):10d} {b2[1]:7d} {a[0]/b2[0]:6.2f}x  {v}')
" 2>&1
