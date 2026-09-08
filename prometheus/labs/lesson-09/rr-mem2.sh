#!/usr/bin/env bash
echo "########## 内存对照（各自独立 baseline，GC 稳定后测量） ##########"
for mode in SAMPLES STREAMED SAMPLES STREAMED; do
  echo "--- waiting for GC settle ---"
  sleep 25
  BASE=$(docker stats l9-prom-1 --no-stream --format '{{.MemUsage}}' | awk '{print $1}')
  PEAK=$BASE
  docker exec l9-rrclient python -c "
import urllib.request,cramjam,time,sys
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
    return len(r.read()),(time.time()-t0)*1000
mode=sys.argv[1]; acc=[] if mode=='SAMPLES' else [1]
tot=0
for i in range(40):
    n,ms=ask(acc,21600)
    tot+=n
print(f'  {mode}: 40 queries total={tot} bytes')
" "$mode" >/dev/null 2>&1 &
  BG=$!
  # 采样峰值
  for i in $(seq 1 12); do
    sleep 0.6
    M=$(docker stats l9-prom-1 --no-stream --format '{{.MemUsage}}' | awk '{print $1}' | sed 's/MiB//')
    B=$(echo $BASE | sed 's/MiB//')
    if awk "BEGIN{exit !($M > $PEAK_NUM)}" 2>/dev/null; then :; fi
    echo "$M" >> /tmp/mem_$mode.txt
  done
  wait $BG 2>/dev/null
  AFTER=$(docker stats l9-prom-1 --no-stream --format '{{.MemUsage}}' | awk '{print $1}')
  PEAK=$(sort -g /tmp/mem_$mode.txt 2>/dev/null | tail -1)
  echo "$mode: base=$BASE after=$AFTER peak=${PEAK}MiB"
  rm -f /tmp/mem_$mode.txt
done
