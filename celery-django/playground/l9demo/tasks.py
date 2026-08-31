"""
课 9 验证任务集：
- cpu_task：CPU 密集（纯计算），用来体现 prefork 能绕开 GIL
- io_task ：IO 密集（sleep 模拟等待外部响应），用来体现 gevent/threads 的高并发
- slow_task / fast_task：队列隔离验证（队头阻塞）
"""
import os
import time

from celery import shared_task

# 注意：这里用 celery.shared_task 需要 app 已 finalize，
# 简单起见直接用 celeryapp.app.task，保持与课程里 @shared_task 语义一致
from celeryapp import app


@app.task(name='l9.cpu_task')
def cpu_task(n: int = 30_000_000):
    """CPU 密集任务：纯 Python 循环，全程占满一个核。"""
    acc = 0
    for i in range(n):
        acc += i * i
    return acc


@app.task(name='l9.io_task')
def io_task(seconds: float = 1.0):
    """IO 密集任务：sleep 模拟等待外部响应（HTTP / DB / 文件）。"""
    time.sleep(seconds)
    return {'pid': os.getpid(), 'slept': seconds}


@app.task(name='l9.slow_task')
def slow_task(idx: int):
    """慢任务：占住槽位不放，用来制造队头阻塞。"""
    time.sleep(2.0)
    return {'idx': idx, 'pid': os.getpid(), 'kind': 'slow'}


@app.task(name='l9.fast_task')
def fast_task(idx: int):
    """快任务：毫秒级，被堵在慢任务后面就是队头阻塞的证据。"""
    return {'idx': idx, 'pid': os.getpid(), 'kind': 'fast'}


@app.task(name='l9.long_task', bind=True)
def long_task(self, seconds: int = 30):
    """长任务：用于优雅停机验证（要能被 TERM 中断观察）。"""
    for i in range(seconds):
        time.sleep(1)
        self.update_state(state='PROGRESS', meta={'i': i + 1, 'total': seconds})
        print(f'[{self.request.id[:8]}] long_task running {i + 1}/{seconds}', flush=True)
    return {'done': True, 'seconds': seconds}
