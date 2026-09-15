FROM alpine:3.20
# 静态二进制 + alpine 足够；显式装 ca-certificates 便于容器内自测 TLS
RUN apk add --no-cache ca-certificates curl
COPY aggregator-apiserver /usr/local/bin/aggregator-apiserver
EXPOSE 8443
ENTRYPOINT ["/usr/local/bin/aggregator-apiserver"]
