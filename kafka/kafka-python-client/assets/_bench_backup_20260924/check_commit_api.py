"""核验两个库的位移提交 API 是否存在（只读，不连集群）。"""
from kafka import KafkaConsumer

for m in ["commit", "commit_async", "committed", "commitSync"]:
    print(m, hasattr(KafkaConsumer, m))

import kafka
print("version", kafka.__version__)
