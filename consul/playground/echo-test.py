import ssl, socket

CERT = 'D:/projects/learning/consul/playground/echo-cert.pem'
KEY = 'D:/projects/learning/consul/playground/echo-key.pem'

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.load_cert_chain(CERT, KEY)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE
try:
    with socket.create_connection(('127.0.0.1', 21000), timeout=5) as sock:
        with ctx.wrap_socket(sock, server_hostname='api') as ssock:
            ssock.sendall(b'GET / HTTP/1.1\r\nHost: api\r\nConnection: close\r\n\r\n')
            data = ssock.recv(4096)
            print('OK', len(data), 'bytes:', data[:60])
except Exception as e:
    print('REJECTED:', type(e).__name__, str(e)[:100])
