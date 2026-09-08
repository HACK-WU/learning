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
def ask(metric,dur,acc):
    m=vi(1,0)+ld(2,b'__name__')+ld(3,metric.encode())
    end=int(time.time()*1000); start=end-dur*1000
    q=vi(1,start)+vi(2,end)+ld(3,m)
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
    return dict(hdr=dict(r.headers.items()),sz=len(raw),ms=(time.time()-t0)*1000,raw=raw)

print('========== 响应头对比（关键：Content-Encoding） ==========')
for name,acc in [('SAMPLES',[]),('STREAMED',[1])]:
    r=ask('rr_bench',3600,acc)
    h=r['hdr']
    print(f\"{name}: Content-Type={h.get('Content-Type')}\")
    print(f\"          Content-Encoding={h.get('Content-Encoding')!r}  (空串=不压缩)\")
    print(f\"          bytes={r['sz']}\")

print()
print('========== 场景B：少序列 + 长历史（app_requests_total, 3序列） ==========')
for dur in [3600, 21600]:
    o={}
    for name,acc in [('SAMPLES',[]),('STREAMED',[1])]:
        sz=[];tm=[];fr=[];ct=''
        for k in range(5):
            r=ask('app_requests_total',dur,acc)
            sz.append(r['sz']);tm.append(r['ms'])
            ct=r['hdr'].get('Content-Type')
            if 'streamed' in ct: fr.append(frames(r['raw']))
            time.sleep(0.3)
        o[name]=(statistics.median(sz),statistics.median(tm))
        extra=f\" frames={int(statistics.median(fr))}\" if fr else ''
        print(f'  dur={dur}s {name}: bytes={int(statistics.median(sz))} ms={statistics.median(tm):.1f}{extra}')
    a,b2=o['SAMPLES'],o['STREAMED']
    print(f'     => SAMPLES/STREAMED size={a[0]/b2[0]:.2f}x time={a[1]/b2[1]:.2f}x')
" 2>&1
