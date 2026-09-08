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
    ms=(time.time()-t0)*1000
    return r.status, r.headers.get('Content-Type',''), len(raw), ms, raw

metric='rr_bench'; dur=${1:-3600}; N=${2:-7}
print(f'metric={metric} duration={dur}s runs={N}')
res={}
for name,acc in [('SAMPLES',[]),('STREAMED_XOR_CHUNKS',[1])]:
    sizes=[]; times=[]; fr=[]; ct=''
    for k in range(N):
        st,ct,sz,ms,raw=ask(metric,dur,acc)
        sizes.append(sz); times.append(ms)
        if 'streamed' in ct: fr.append(frames(raw))
        time.sleep(0.4)
    med_s=statistics.median(sizes); med_t=statistics.median(times)
    res[name]=(med_s,med_t,min(sizes),max(sizes))
    extra=f' frames_median={int(statistics.median(fr))}' if fr else ''
    print(f'{name}: bytes_median={int(med_s)} (min={min(sizes)} max={max(sizes)}) ms_median={med_t:.1f} ctype={ct}{extra}')
a=res['SAMPLES']; b=res['STREAMED_XOR_CHUNKS']
print(f'--- size ratio SAMPLES/STREAMED = {a[0]/b[0]:.2f}x')
print(f'--- time ratio SAMPLES/STREAMED = {a[1]/b[1]:.2f}x')
" 2>&1
