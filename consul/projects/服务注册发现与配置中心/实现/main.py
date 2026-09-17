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
from stage34_ext import (CapabilityGap, DiscoveryBackend,
                         explain_read_mode, pick_read_mode,
                         run_preflight_checks, validate_acl_rules)

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
        #
        # 2026-09-17 修复（首次运行热更新失效）：
        # 原先这里只调用 wait_update **一次**。但前缀为空时拿不到起始 index
        # （空前缀查询返回 404，且 404 响应头的 X-Consul-Index 未被保留），
        # wait_update 会以 index=None 发起查询，而缺少 ?index 时 Consul
        # **立即返回**（实测 2ms）——这一次等待机会瞬间用完，
        # 之后主线程写入的变更就再也没有人接收了。
        #
        # 正确写法是**循环重试**：只要没检测到变更就重新挂起，直到总时限。
        # 这同时也是生产代码的正确形态——阻塞查询本就可能因超时正常返回。
        deadline = time.time() + 30
        while time.time() < deadline:
            changed = cc.wait_update(wait='5s')
            if changed:
                result['changed'] = True
                break
        result.setdefault('changed', False)
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


def step_7_backend_portability():
    hr('第 7 步：注册后端可移植性（阶段 3 · 课 9/10）')
    print('  课 10 结论：四家不在同一赛道——成品（Consul/Nacos/Eureka）vs 零件（etcd/ZK）')
    print()
    print(DiscoveryBackend.compare(['consul', 'etcd', 'nacos']))
    print()
    print('  把这条结论做成代码的意义：切换后端时，缺失能力在【第一次调用】就暴露，')
    print('  而不是像课 08 故障模式 8 那样，迁移到一半才发现健康检查没了。')
    print()
    _backend = DiscoveryBackend('consul')
    print(f'  当前后端（consul）健康检查：{_backend.register_with_health_check()}')

    _etcd = DiscoveryBackend('etcd')
    for _label, _fn in [
        ('健康检查', _etcd.register_with_health_check),
        ('DNS 解析', _etcd.resolve_by_dns),
        ('服务网格', _etcd.enable_mesh),
    ]:
        try:
            _fn()
            print(f'    etcd {_label}：未拦截（异常）')
        except CapabilityGap as _e:
            print(f'    etcd {_label}：已拦截 → {str(_e)[:46]}…')


def step_8_preflight(consul):
    hr('第 8 步：上线前运维自检（阶段 4 · 课 11/12）')
    print('  课 11「运维五问」+ 课 12「POC 验收点」的可执行版本。')
    print('  注意：本演示跑在 dev 单节点上，quorum 与 ACL 项会如实报未通过/跳过——这是预期结果。')
    print()
    print(run_preflight_checks(consul).render())


def step_9_read_modes(consul):
    hr('第 9 步：三种读模式与「有多旧」的可观测性（吸收实战篇 A）')
    print('  实战篇 A 在三节点集群上实测：stale 写后立即读稳定落后 1 个版本（10/10 次），')
    print('  leader 被强杀后的约 9.5 秒内 default/consistent 全部 500，只有 stale 仍能返回。')
    print()

    print('  【按场景选读模式】')
    for scenario, label in [('discovery', '服务发现'), ('config', '读配置'),
                            ('lock', '分布式锁选主'), ('failover', '故障时仍需响应')]:
        mode = pick_read_mode(scenario)
        print(f'    {label:14s} -> {mode:11s} {explain_read_mode(mode).split(":", 1)[1].strip()}')

    print()
    print('  【实测 LastContact：这份数据落后 leader 多久（毫秒，0=最新）】')
    key = f'{KV_PREFIX}/_readmode_probe'
    consul.kv_put(key, 'v0')
    for mode in [None, 'consistent', 'stale']:
        got = consul.kv_get(key, consistency=mode)
        name = mode or 'default'
        lc = got.get('last_contact')
        print(f'    {name:11s} LastContact={lc}')
    consul.kv_delete(key)
    print()
    print('    注：上面三个都是 0，因为 dev 单节点本地读本就没有落后——')
    print('       LastContact 只有在"多节点 + 持续写入"时才会拉开。')
    print('       实战篇 A 的三节点实测值为：default/consistent 恒 0，stale 15~45ms。')
    print('    所以本项演示的是"接口能取到这个头"，不是"复现落后"——')
    print('       要复现落后需要三节点集群，见 practices/实战A-读模式实测/。')
    print()
    print('  → 服务发现改用 stale 可换取 leader 选举期间的可用性；')
    print('    但别把它用在阻塞查询上（stale 不保证单调，可能错过变更）。')
    print('  → 也别把 stale 当灾备：quorum 丢失时（三节点挂两个）stale 同样不可用。')

    print()
    print('  【真实用一次 stale 做服务发现】')
    try:
        res = consul.health_service(SERVICE_NAME, passing=True, consistency='stale')
        body = res.get('body') if isinstance(res, dict) else res
        print(f'    stale 模式发现 {len(body or [])} 个健康实例')
    except Exception as e:
        print(f'    stale 发现失败：{type(e).__name__}: {e}')


def step_10_acl_and_mesh_guard(consul):
    hr('第 10 步：吸收实战篇 B/C 的两条硬边界')
    print('  这两条都不是"优化建议"，是踩过才知道的硬边界。')
    print()

    print('  【边界 1 · 实战篇 C】ACL 规则写错时，Consul 不报错，权限静默失效')
    bad_rules = '''
key_prefix "web/" { policy = "write" }
operator_prefix "" { policy = "read" }
acl_prefix "" { policy = "read" }
'''
    problems = validate_acl_rules(bad_rules)
    print(f'    扫描一段错误规则，发现 {len(problems)} 处：')
    for p in problems:
        print(f'      - {p}')
    good_rules = '''
key_prefix "web/" { policy = "write" }
operator = "read"
'''
    print(f'    扫描正确写法：{validate_acl_rules(good_rules) or "无问题"}')
    print('    → 不带 label 的资源（operator/acl/keyring/mesh/peering）'
          '必须写 `operator = "read"`；')
    print('      写成 operator_prefix 时创建 policy/token 都返回 200，但权限不生效。')

    print()
    print('  【边界 2 · 实战篇 B】Connect 加密的是"进 sidecar 的流量"，不是应用端口')
    print('    实测：绕过 sidecar 直连应用端口返回明文 200，mTLS 形同虚设。')
    print('    → 应用必须只监听 127.0.0.1，并用网络策略封住端口。')
    print('    → 本项目 demo_service 监听地址（见 demo_service.py）即按此约束设置。')

    print()
    print('  【边界 3 · 实战篇 C】递归读越权返回 404 而非 403，会被当成"空配置"')
    print('    本项目 config_center.load_all() 已加归因：404 后用裸路径单键读复核，')
    print('    拿到 403 就抛 PermissionError，而不是静默返回空配置。')


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
        step_7_backend_portability()
        step_8_preflight(consul)
        step_9_read_modes(consul)
        step_10_acl_and_mesh_guard(consul)
        hr('全部演示完成（已覆盖阶段 1–4 + 三份实战篇）')
    finally:
        for stop in stops:
            stop.set()
        for reg in regs[:1]:
            reg.deregister()
        print('已清理注册的实例')


if __name__ == '__main__':
    main()
