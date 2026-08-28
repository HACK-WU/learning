import socket, struct, sys

def build_query(qid, name, qtype):
    header = struct.pack(">HHHHHH", qid, 0x0100, 1, 0, 0, 0)
    q = b"".join(bytes([len(p)]) + p.encode() for p in name.split(".")) + b"\x00"
    q += struct.pack(">HH", qtype, 1)
    return header + q

def query_udp(name, qtype=1):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(3)
    s.sendto(build_query(0x1234, name, qtype), ("127.0.0.1", 8600))
    data, _ = s.recvfrom(1024)
    flags = struct.unpack(">H", data[2:4])[0]
    ancount = struct.unpack(">H", data[6:8])[0]
    print("%s type=%d -> flags=0x%04x rcode=%d answers=%d bytes=%d" % (name, qtype, flags, flags & 0xF, ancount, len(data)))
    # try to pull first A record rdata from answer section (skip question)
    if ancount:
        # walk: header(12) + question
        i = 12
        while data[i] != 0:
            i += data[i] + 1
        i += 5  # null + qtype + qclass
        for _ in range(ancount):
            if data[i] & 0xC0 == 0xC0:
                i += 2
            else:
                while data[i] != 0:
                    i += data[i] + 1
                i += 1
            rtype, rclass, ttl, rdlen = struct.unpack(">HHIH", data[i:i+10])
            rdata = data[i+10:i+10+rdlen]
            i += 10 + rdlen
            if rtype == 1:
                print("  A record: %s" % ".".join(str(b) for b in rdata))
            else:
                print("  record type=%d len=%d" % (rtype, rdlen))

def query_tcp(name, qtype=1):
    q = build_query(0x4321, name, qtype)
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect(("127.0.0.1", 8600))
    s.sendall(struct.pack(">H", len(q)) + q)
    ln = struct.unpack(">H", s.recv(2))[0]
    data = b""
    while len(data) < ln:
        data += s.recv(ln - len(data))
    flags = struct.unpack(">H", data[2:4])[0]
    ancount = struct.unpack(">H", data[6:8])[0]
    print("[TCP] %s -> flags=0x%04x rcode=%d answers=%d" % (name, flags, flags & 0xF, ancount))

query_udp("web.service.consul")
query_udp("web.service.consul", qtype=28)  # AAAA
query_tcp("web.service.consul")
query_udp("consul.service.consul")  # consul's own service
