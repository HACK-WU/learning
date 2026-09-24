import os

BOOTSTRAP = "kafka-1:9092,kafka-2:9092,kafka-3:9092"

# --- 固定变量（两库一致） ---
MSG_SIZE = int(os.getenv("MSG_SIZE", "1024"))
NUM_MESSAGES = int(os.getenv("NUM_MESSAGES", "100000"))
NUM_PARTITIONS = 6
REPLICATION_FACTOR = 3
ACKS = os.getenv("ACKS", "all")
COMPRESSION = os.getenv("COMPRESSION", "none")
LINGER_MS = int(os.getenv("LINGER_MS", "10"))
BATCH_SIZE = int(os.getenv("BATCH_SIZE", str(64 * 1024)))


def payload(seq: int) -> bytes:
    """生成固定 MSG_SIZE 消息体。

    刻意同时包含"高熵"与"低熵"两种成分：
    - seq 变化部分：天然不可压缩
    - pad 重复字符：天然高压缩比
    这样压缩对照才不会退化成"全是随机字节、怎么压都压不动"的极端情形，
    也更接近真实业务消息（JSON 有固定字段名 + 变化的值）。
    """
    body = '{"seq":%d,"ts":0,"src":"bench","pad":"' % seq
    pad = MSG_SIZE - len(body) - 2
    if pad < 0:
        pad = 0
    return (body + "x" * pad + '"}').encode()[:MSG_SIZE]


def topic_name(lib: str, run: str) -> str:
    return f"bench-{lib}-{run}"
