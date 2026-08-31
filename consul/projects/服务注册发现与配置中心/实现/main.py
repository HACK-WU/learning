"""演示主程序：注册两个实例 → 发现 → 调用 → 制造故障 → 观察自愈 → 配置热更新

运行前：确保本地 Consul agent 已启动（consul agent -dev）。
运行：python main.py
"""

import subprocess
import sys
import threading
import time

from config_center import ConfigCenter
from consul_client import Consul, ConsulError
from lock import LeaderElection
from service_registry import ServiceRegistry, discover, discover_and_call

CONSUL_ADDR = 'http://127.0.0.1:8500'
SERVICE_NAME = 'demo-svc'
KV_PREFIX = 'demo'


def hr(title):
    print(f'\n{"=" * 60}\n{title}\n{"=" * 60}')


def step_1_register_two_instances(consul):
    hr('第 1 步：注册两个服务实例（课 1/3/4）')
    regs = []
    stops = []
    for i, port in enumerate([18081, 18082], start=1):
        reg = ServiceRegistry(consul, f'{SERVICE_NAME}-{i}', SERVICE_NAME, port,
                              tags=[f'v{i}'], ttl='15s')
        reg.register()
        stop = threading.Event()
        threading.Thread(target=reg.keep_alive, args=(stop,), daemon=True).start()
        regs.append(reg)
        stops.append(stop)
        print(f'  已注册 {SERVICE_NAME}-{i} @ 127.0.0.1:{port}')

    time.sleep(1)
    instances = discover(consul, SERVICE_NAME)
    print(f'  发现结果：{[i["id"] for i in instances]}')
    return regs, stops


def step_2_discover_and_call(consul):
    hr('第 2 步：按名字发现并调用（课 1 客户端发现模式）')
    try:
        body, inst = discover_and_call(consul, SERVICE_NAME, '/')
        print(f'  选中实例：{inst["id"]}')
        print(f'  响应内容：{body}')
    except Exception as e:
        print(f'  调用失败（预期，实例未真正监听端口）：{type(e).__name__}: {e}')


def step_3_health_failover(consul, regs):
    hr('第 3 步：制造实例故障，观察健康检查摘除（课 4）')
    print('  注销 demo-svc-2 并停止其心跳（模拟实例宕机）')
    regs[1].deregister()
    time.sleep(2)
    instances = discover(consul, SERVICE_NAME)
    print(f'  剩余健康实例：{[i["id"] for i in instances]}')
    print('  → 消费方无需改代码，发现结果自动收敛到存活实例')


def step_4_kv_hot_reload(consul):
    hr('第 4 步：KV 配置热更新（课 6 阻塞查询）')
    cc = ConfigCenter(consul, KV_PREFIX)
    cc.load_all()
    print(f'  初始配置：{cc.config}')

    # 起一个后台线程等变更
    result = {}

    def waiter():
        t0 = time.time()
        # 注意：wait='30s' 时客户端超时必须大于 30 秒，否则客户端先超时（本项目实测踩坑）
        changed = cc.wait_update(wait='30s')
        result['changed'] = changed
        result['elapsed_ms'] = int((time.time() - t0) * 1000)
        result['config'] = dict(cc.config)

    t = threading.Thread(target=waiter)
    t.start()
    time.sleep(1)

    # 主线程改配置——阻塞查询应在毫秒级被唤醒。
    # 注意：必须写入**不同**的值。实测确认：同值重写不会推进前缀查询的 index
    # （index 136 写同值仍是 136），阻塞查询因而永远不返回——本项目踩到的真坑。
    consul.kv_put(f'{KV_PREFIX}/feature_flag', f'on-{time.strftime("%H%M%S")}')
    t.join(timeout=35)

    if result.get('changed'):
        print(f'  阻塞查询在 {result["elapsed_ms"]}ms 内检测到变更')
        print(f'  新配置：{result["config"]}')
    else:
        print('  未检测到变更（异常，请检查 agent 状态）')


def step_5_leader_election(consul):
    hr('第 5 步：用会话+KV 做领导者选举（课 6 分布式锁）')
    # 两个候选者竞争同一把锁（dev 模式只有一个 agent，这里用两个会话模拟）
    try:
        e1 = LeaderElection(consul, 'demo/leader', 'worker-1', ttl='10s')
        e2 = LeaderElection(consul, 'demo/leader', 'worker-2', ttl='10s')
        print(f'  worker-1 抢占：{e1.try_acquire()}')
        print(f'  worker-2 抢占：{e2.try_acquire()}（预期 False，锁已被占）')
        print(f'  worker-1 是否 leader：{e1.is_leader()}')
        e1.release()
        print(f'  worker-1 释放后，worker-2 抢占：{e2.try_acquire()}')
        e2.release()
    except Exception as e:
        print(f'  选举演示失败：{type(e).__name__}: {e}')


def step_6_cluster_health(consul):
    hr('第 6 步：集群健康观测（课 5 Raft）')
    try:
        leader = consul.leader()
        peers = consul.peers()
        print(f'  当前 leader：{leader or "(无 leader，quorum 可能已丢失)"}')
        print(f'  集群成员：{peers}')
    except ConsulError as e:
        print(f'  查询失败：{e}')


def main():
    consul = Consul(CONSUL_ADDR)
    try:
        consul.leader()
    except Exception as e:
        print(f'无法连接 Consul（{CONSUL_ADDR}）：{e}')
        print('请先启动：consul agent -dev')
        sys.exit(1)

    regs, stops = step_1_register_two_instances(consul)
    try:
        step_2_discover_and_call(consul)
        step_3_health_failover(consul, regs)
        step_4_kv_hot_reload(consul)
        step_5_leader_election(consul)
        step_6_cluster_health(consul)
        hr('全部演示完成')
    finally:
        for stop in stops:
            stop.set()
        for reg in regs[:1]:
            reg.deregister()
        print('已清理注册的实例')


if __name__ == '__main__':
    main()
