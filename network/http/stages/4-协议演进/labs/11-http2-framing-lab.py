#!/usr/bin/env python3
"""HTTP/2 教学实验：观察连接前言、帧头和交错的流。

本实验只用 Python 标准库，不实现完整 HTTP/2 客户端或 HPACK 解码器。
它验证的是本课的数据模型：一条连接是一串帧；帧带流编号；不同流的帧可以交错。
"""

from dataclasses import dataclass


PREFACE = b"PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
FRAME_TYPES = {
    0x0: "DATA",
    0x1: "HEADERS",
    0x4: "SETTINGS",
}
END_STREAM = 0x1
END_HEADERS = 0x4


@dataclass(frozen=True)
class Frame:
    frame_type: int
    flags: int
    stream_id: int
    payload: bytes


def encode_frame(frame_type: int, flags: int, stream_id: int, payload: bytes) -> bytes:
    """编码最小 HTTP/2 帧：9 字节帧头 + payload。"""
    if not 0 <= stream_id <= 0x7FFFFFFF:
        raise ValueError("stream_id must fit in 31 bits")
    if len(payload) >= 2**24:
        raise ValueError("payload is too large for a 24-bit length")
    header = len(payload).to_bytes(3, "big")
    header += bytes((frame_type, flags))
    header += (stream_id & 0x7FFFFFFF).to_bytes(4, "big")
    return header + payload


def decode_frames(raw: bytes):
    """逐帧读取字节串，故意只解析通用帧头，不解析各帧 payload。"""
    offset = 0
    while offset < len(raw):
        if len(raw) - offset < 9:
            raise ValueError("truncated frame header")
        length = int.from_bytes(raw[offset : offset + 3], "big")
        frame_type = raw[offset + 3]
        flags = raw[offset + 4]
        stream_id = int.from_bytes(raw[offset + 5 : offset + 9], "big") & 0x7FFFFFFF
        start = offset + 9
        end = start + length
        if end > len(raw):
            raise ValueError("truncated frame payload")
        yield Frame(frame_type, flags, stream_id, raw[start:end])
        offset = end


def describe(frame: Frame) -> str:
    name = FRAME_TYPES.get(frame.frame_type, f"0x{frame.frame_type:02x}")
    return (
        f"{name:<8} stream={frame.stream_id:<2} length={len(frame.payload):<2} "
        f"flags=0x{frame.flags:02x} payload={frame.payload[:12].hex()}"
    )


def hpack_table_model():
    """用小模型表达 HPACK 的查表思路，不冒充完整 HPACK 编码器。"""
    static = {
        2: ":method: GET",
        4: ":path: /",
        7: ":scheme: https",
    }
    dynamic = []
    dynamic.append("x-demo: one")
    return static, dynamic


def main() -> None:
    assert len(PREFACE) == 24
    print(f"[1] connection preface bytes={len(PREFACE)} value={PREFACE!r}")

    settings = b"\x00\x03\x00\x00\x00\x04"  # SETTINGS_MAX_CONCURRENT_STREAMS = 4
    # 这些 HEADERS payload 使用 HPACK 静态表索引表达常见伪字段；这里只观察帧头，
    # 不在实验脚本中实现完整 HPACK 解码。
    request_headers = bytes((0x82, 0x84, 0x87, 0x41, 0x0C)) + b"example.test"
    response_headers = bytes((0x88,))  # :status: 200 的静态表索引
    raw = b"".join(
        [
            encode_frame(0x4, 0x0, 0, settings),
            encode_frame(0x1, END_HEADERS, 1, request_headers),
            encode_frame(0x1, END_HEADERS, 3, request_headers),
            encode_frame(0x1, END_HEADERS, 3, response_headers),
            encode_frame(0x0, END_STREAM, 3, b"fast"),
            encode_frame(0x0, END_STREAM, 1, b"slow"),
        ]
    )

    frames = list(decode_frames(raw))
    print("[2] decoded frames")
    for index, frame in enumerate(frames, start=1):
        print(f"  {index}. {describe(frame)}")

    data_streams = [frame.stream_id for frame in frames if frame.frame_type == 0x0]
    assert data_streams == [3, 1]
    assert len(frames[0].payload) == 6
    assert len(encode_frame(0x0, 0x0, 1, b"x")) == 10
    print("[3] interleaving: stream 3 DATA appears before stream 1 DATA -> True")
    print("    meaning: stream 1 can be slow without forcing stream 3 to wait at HTTP layer")

    static, dynamic = hpack_table_model()
    print("[4] HPACK table model (teaching model, not a full decoder)")
    print(f"  static index 2  -> {static[2]}")
    print(f"  static index 7  -> {static[7]}")
    print(f"  first x-demo    -> literal + dynamic table: {dynamic[0]}")
    print("  repeat x-demo   -> indexed representation (dynamic table entry)")
    print("  sensitive value -> literal never-indexed (does not enter dynamic table)")

    print("[5] result: one HTTP/2 connection can carry multiple numbered streams")
    print("    boundary: TCP packet loss can still delay bytes belonging to every stream")


if __name__ == "__main__":
    main()
