exec 3<>/dev/tcp/127.0.0.1/15692
printf 'GET /metrics HTTP/1.0\r\nHost: localhost\r\n\r\n' >&3
cat <&3
