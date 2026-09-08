#!/usr/bin/env bash
docker run --rm --entrypoint sh quay.io/prometheus/prometheus:v3.14.0 -c 'grep -a -o "xorbased_chunked\|streamedChunks\|streamedXorChunks\|SAMPLES\|STREAMED_XOR_CHUNKS\|STREAMED_CHUNKS" /bin/prometheus | sort | uniq -c'
