import socket, threading, time

got = threading.Event()

def listen(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.bind(("127.0.0.1", port))
    s.settimeout(20)
    try:
        while True:
            data, addr = s.recvfrom(1024)
            print("PORT %d got %d bytes from %s: %s" % (port, len(data), addr, data[:48].hex()))
            got.set()
    except socket.timeout:
        pass

t = threading.Thread(target=listen, args=(53,), daemon=True)
t.start()
print("listening on 127.0.0.1:53 for up to 20s ...")
time.sleep(20)
print("done")
