#!/bin/bash
# 探路：protobuf 7.x 的 message_factory API（老教程的 GetPrototype 已废弃）
set -u
cat > /tmp/pb_api.py <<'PYEOF'
import inspect
from google.protobuf import message_factory as mf
print("message_factory 公开符号:")
print("  ", [x for x in dir(mf) if not x.startswith('_')])
print()
for n in ["GetMessageClass", "GetPrototype"]:
    if hasattr(mf, n):
        try: print(f"  {n}{inspect.signature(getattr(mf,n))}")
        except Exception as e: print(f"  {n}: {e}")
    else:
        print(f"  {n}: 不存在（已移除）")
PYEOF
docker run --rm -v /tmp/pb_api.py:/a.py kafka-pybench:3.12 \
  /app/.venv/bin/python /a.py 2>&1 | grep -v -e Authlib -e 'from ._compat' | head -14
