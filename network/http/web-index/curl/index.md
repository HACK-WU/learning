# curl 官方手册索引

> 用途：课 7–8 的命令行缓存、响应头和请求计时实验；具体语义以 curl 当前手册为准。

| 我要解决的问题 | 先看 | 课程落点 |
|---|---|---|
| 用 `-w/--write-out` 输出请求计时 | [curl `--write-out`](https://curl.se/docs/manpage.html#-w) | 8.2 `curl -w` 时间线 |
| 看 `time_namelookup` / `time_connect` / `time_appconnect` | [curl write-out 时间变量](https://curl.se/docs/manpage.html#time_namelookup) | 8.2 分段计算 |
| 让 curl 按响应编码自动解压 | [curl `--compressed`](https://curl.se/docs/manpage.html#--compressed) | 8.1 压缩验证 |
| 强制或尝试 HTTP/1.1、HTTP/2 | [curl HTTP 版本选项](https://curl.se/docs/manpage.html#--http1.1) | 8.3 协议与域名分片对照 |

> 核查日期：2026-09。命令输出受本机 curl 版本、TLS 后端和网络环境影响；课程中的数字只代表明确标注的本机实测。
