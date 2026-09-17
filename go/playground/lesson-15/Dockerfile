# Builder stage: contains the toolchain, source code, and no runtime state.
FROM golang:1.27-bookworm AS build

WORKDIR /src
COPY go.mod ./
COPY cmd ./cmd
COPY internal ./internal

ARG VERSION=dev
ARG COMMIT=unknown
ARG BUILD_TIME=unknown
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
	go build -trimpath -ldflags="-s -w -X main.version=${VERSION} -X main.commit=${COMMIT} -X main.buildTime=${BUILD_TIME}" \
	-o /out/productiondemo ./cmd/productiondemo

# Runtime stage: only the statically linked executable is shipped.
FROM scratch
COPY --from=build /out/productiondemo /productiondemo
ENTRYPOINT ["/productiondemo"]
