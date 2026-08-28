import ssl, socket, sys

HOST, PORT = '127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 21000
CERT = 'D:/projects/learning/consul/playground/web-cert.pem'
KEY = 'D:/projects/learning/consul/playground/web-key.pem'

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.load_cert_chain(CERT, KEY)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

label = sys.argv[2] if len(sys.argv) > 2 else 'test'
print(f'--- [{label}] full request test: web identity -> {HOST}:{PORT} ---')
try:
    with socket.create_connection((HOST, PORT), timeout=5) as sock:
        with ctx.wrap_socket(sock, server_hostname='api') as ssock:
            print('TLS handshake: OK')
            ssock.sendall(b'GET / HTTP/1.1\r\nHost: api\r\nConnection: close\r\n\r\n')
            ssock.settimeout(5)
            chunks = []
            try:
                while True:
                    data = ssock.recv(4096)
                    if not data:
                        break
                    chunks.append(data)
            except socket.timeout:
                print('recv: TIMEOUT (no response, connection stalled)')
            except (ConnectionResetError, ssl.SSLError) as e:
                print(f'recv: ABORTED by peer: {type(e).__name__}: {e}')
            body = b''.join(chunks)
            if body:
                print(f'recv: {len(body)} bytes')
                print('---- response head ----')
                print(body[:300].decode('utf-8', 'replace'))
            else:
                print('recv: 0 bytes (empty reply)')
except ssl.SSLError as e:
    print(f'RESULT: HANDSHAKE REJECTED: {e.reason}')
except ConnectionResetError as e:
    print(f'RESULT: CONNECTION RESET: {e}')
