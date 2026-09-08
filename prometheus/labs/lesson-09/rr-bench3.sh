#!/usr/bin/env bash
echo "########## 交叉点扫描：序列数 vs 模式优劣 ##########"
echo "用 required 固定 route 数，间接控制序列数：rr_bench{route=...}"
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
    qs=b''
    for k,v in matchers:
        qs+=vi(1,0)+ld(2,k.encode())+ld(3,v.encode())
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

# 用 idx 前缀匹配控制序列数：idx=~\"0000.*\" 等
import re
for label,pat in [('1 series','idx=~\"00000.*\"'),('10 series','idx=~\"0000.*\"'),
                  ('100 series','idx=~\"000.*\"'),('500 series','idx=~\"00.*\"'),
                  ('1500 series','idx=~\".*\"')]:
    m=[('__name__','rr_bench')]
    # 用 regex matcher type=4
    def mkreg(name,val):
        return vi(1,4)+ld(2,name.encode())+ld(3,val.encode())
    def ask2(mt,dur,acc):
        end=int(time.time()*1000); start=end-dur*1000
        q=vi(1,start)+vi(2,end)
        q+=ld(3, vi(1,0)+ld(2,b'__name__')+ld(3,b'rr_bench'))
        q+=ld(3, mkreg('idx',mt))
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
    o={}
    for name,acc in [('SAMPLES',[]),('STREAMED',[1])]:
        sz=[];fr=[];ct=''
        for k in range(5):
            s,ms,c,raw=ask2(pat,3600,acc)
            sz.append(s); ct=c
            if 'streamed' in c: fr.append(frames(raw))
            time.sleep(0.25)
        o[name]=(statistics.median(sz), int(statistics.median(fr)) if fr else 0)
    a,b2=o['SAMPLES'],o['STREAMED']
    verdict = 'SAMPLES更省' if a[0]<b2[0] else 'STREAMED更省'
    print(f'{label:14s} SAMPLES={int(a[0]):8d}  STREAMED={int(b2[0]):8d} (frames={b2[1]:5d})  ratio={a[0]/b2[0]:5.2f}x  -> {verdict}')
" 2>&1
