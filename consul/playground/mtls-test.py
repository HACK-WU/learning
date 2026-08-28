import ssl, socket, sys, re

HOST, PORT = '127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 21000
CERT = 'D:/projects/learning/consul/playground/web-cert.pem'
KEY = 'D:/projects/learning/consul/playground/web-key.pem'

ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
ctx.load_cert_chain(CERT, KEY)
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE  # 只验证握手可达性，不校验服务端证书链

label = sys.argv[2] if len(sys.argv) > 2 else 'test'
print(f'--- [{label}] connecting with web identity to {HOST}:{PORT} ---')
try:
    with socket.create_connection((HOST, PORT), timeout=5) as sock:
        with ctx.wrap_socket(sock, server_hostname='api') as ssock:
            print('RESULT: HANDSHAKE OK  (intention allowed the connection)')
            print('TLS version:', ssock.version(), '| cipher:', ssock.cipher()[0])
            der = ssock.getpeercert(binary_form=True)
            m = re.search(rb'spiffe://[!-~]+', der)
            if m:
                print('Server cert SPIFFE ID:', m.group().decode())
except ssl.SSLError as e:
    print(f'RESULT: HANDSHAKE REJECTED (intention denied): {e.reason}')
except ConnectionResetError as e:
    print(f'RESULT: CONNECTION RESET BY PEER (intention denied at TLS layer): {e}')
except socket.timeout:
    print('RESULT: TIMEOUT')
