#!/usr/bin/env bash
# 诊断 2：确认 5.6.3 里 soft shutdown 的真实配置项名与默认值
set -u

cd /mnt/d/projects/learning/celery-django/playground/l9demo

/tmp/l9venv/bin/python - <<'PYEOF'
from celery import Celery
from celeryapp import app

print("celery 版本相关配置探测")
print("=" * 50)

# 1. 直接查 app.conf 里所有含 soft 的键
soft_keys = [k for k in app.conf if 'soft' in k.lower()]
print("① app.conf 里含 'soft' 的键：")
for k in sorted(soft_keys):
    print(f"   {k} = {app.conf[k]!r}")

print()
# 2. 查 shutdown 相关
shut_keys = [k for k in app.conf if 'shutdown' in k.lower()]
print("② app.conf 里含 'shutdown' 的键：")
for k in sorted(shut_keys):
    print(f"   {k} = {app.conf[k]!r}")

print()
# 3. 查 acks_late
print("③ task_acks_late =", repr(app.conf.task_acks_late))

print()
# 4. 检查 WorkController 的 shutdown 相关方法
from celery.worker import worker as w
methods = [m for m in dir(w.WorkController) if 'shutdown' in m.lower() or 'term' in m.lower()]
print("④ WorkController 的 shutdown 相关方法：", methods)

print()
# 5. 检查 signals
import celery.signals as sig
ssig = [s for s in dir(sig) if 'shutdown' in s.lower()]
print("⑤ 信号里含 shutdown 的：", ssig)
PYEOF
