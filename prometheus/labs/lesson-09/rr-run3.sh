#!/usr/bin/env bash
docker exec l9-rrclient python -c "
import sys, time
sys.path.insert(0,'/')
import importlib.util
spec=importlib.util.spec_from_file_location('rc','/rr_client.py')
rc=importlib.util.module_from_spec(spec); spec.loader.exec_module(rc)

metric='app_requests_total'; dur=3600
end=int(time.time()*1000); start=end-dur*1000
for name,acc in [('SAMPLES',[]),('STREAMED_XOR_CHUNKS',[1])]:
    body=rc.build_read_request(metric,start,end,acc)
    res=rc.post(rc.snappy_compress(body),timeout=60)
    print('---',name,'---')
    print('  code',res.get('code'),'ctype',res.get('ctype'))
    print('  bytes',res.get('bytes'),'ms',round(res.get('ms',0),1))
    if not res.get('ok'):
        print('  ERR',res.get('err')); continue
    raw=res['raw']
    if 'streamed' in res.get('ctype',''):
        print('  frames',rc.count_stream_frames(raw))
    else:
        import cramjam
        d=bytes(cramjam.snappy.decompress_raw(raw))
        print('  decompressed',len(d))
" 2>&1
