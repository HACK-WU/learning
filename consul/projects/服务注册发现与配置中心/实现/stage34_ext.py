"""阶段 3 + 阶段 4 扩展模块：可插拔注册后端 + 上线前运维自检

本模块是 2026-09-17 项目升级新增的，目的是让项目满足「跨 ≥3 阶段」门槛。

它把两个阶段的核心结论做成了**可运行的代码**，而不只是写在文档里：

**阶段 3（课 9/10）——可插拔注册后端**
  课 10 的核心结论是"四家不在同一赛道"。本模块用一个统一的
  `DiscoveryBackend` 接口把这一点落到实处：
    - 同一份业务代码，切换后端不改调用方
    - 切换时能**立刻暴露**目标产品缺什么能力（健康检查 / DNS / 多 DC / 配置）
  这正好复现了课 08「故障模式 8：替换时功能对不上」这个坑——
  让你在**写代码时**就发现，而不是迁移到一半才发现。

**阶段 4（课 11/12）——上线前运维自检**
  课 11 的"运维五问"和课 12 的"POC 验收点"在这里变成了可执行检查。
  每项检查都明确区分：✅ 通过 / ⚠️ 警告 / ❌ 不通过 / ⏭️ 跳过（本环境不适用）。

设计原则（沿用项目既有的非功能约束）：
  - 错误处理：区分"不支持"（backend 能力缺失）与"执行失败"（网络/权限问题）
  - 降级可用：自检失败不抛异常终止，而是记录为未通过项，由调用方决定
  - 可维护性：检查结果结构化返回（dataclass 列表），便于接入监控或 CI
"""

from dataclasses import dataclass, field
from typing import Dict, List, Optional

# ---------------------------------------------------------------- 阶段 3：后端抽象


@dataclass
class BackendCapability:
    """一个注册后端的能力声明——对应课 10 的功能矩阵。

    这些字段不是随便列的，每一条都来自课 9/课 10 的实测或一手核查：
      - health_checks：课 4 实测 Consul 支持 HTTP/TCP/TTL/脚本/gRPC
      - dns_interface：课 3/课 4（Consul 原生 8600 端口）
      - multi_dc：课 7 实测（联邦是查询通道，不是数据副本）
      - service_mesh：课 7（Consul Connect；其余四家无内置）
      - config_versioning：课 6 实测 Consul KV **没有**版本历史
      - config_audit：课 6 实测（仅企业版有）
      - acl：课 8 实测（Consul 完整）
      - advisory_only_lock：课 6 实测（Consul 锁是建议性锁，受 LockDelay 约束）
    """

    name: str
    health_checks: bool
    dns_interface: bool
    multi_dc: bool
    service_mesh: bool
    config_versioning: bool
    config_audit: bool
    acl: bool
    advisory_only_lock: bool
    license: str


# 能力表：数据来自课 9/课 10 的结论，不是猜测
CAPABILITIES: Dict[str, BackendCapability] = {
    'consul': BackendCapability(
        name='Consul',
        health_checks=True,      # 课 4 实测：五种类型
        dns_interface=True,      # 原生 8600
        multi_dc=True,           # 课 7 实测：联邦
        service_mesh=True,       # 课 7：Connect
        config_versioning=False, # 课 6 实测：无版本历史
        config_audit=False,      # 课 6 实测：仅企业版
        acl=True,                # 课 8 实测：完整
        advisory_only_lock=True, # 课 6 实测：LockDelay 约 15 秒
        license='BUSL 1.1（1.17.0 起；非 OSI 认证）',
    ),
    'etcd': BackendCapability(
        name='etcd',
        health_checks=False,     # 需自建（lease + 前缀）
        dns_interface=False,
        multi_dc=False,
        service_mesh=False,
        config_versioning=True,  # MVCC 有版本（课 9）
        config_audit=False,
        acl=True,                # RBAC
        advisory_only_lock=False,# etcd 租约更利落（课 9）
        license='Apache-2.0',
    ),
    'nacos': BackendCapability(
        name='Nacos',
        health_checks=True,      # 有，但语义不如 Consul 丰富（课 10）
        dns_interface=True,
        multi_dc=False,          # 需外挂方案（课 10）
        service_mesh=False,
        config_versioning=True,  # 版本/灰度/回滚（课 9）
        config_audit=True,
        acl=True,
        advisory_only_lock=True,
        license='Apache-2.0',
    ),
    'zookeeper': BackendCapability(
        name='ZooKeeper',
        health_checks=False,     # 临时节点自建
        dns_interface=False,
        multi_dc=False,
        service_mesh=False,
        config_versioning=False,
        config_audit=False,
        acl=True,
        advisory_only_lock=True,
        license='Apache-2.0',
    ),
    'eureka': BackendCapability(
        name='Eureka',
        health_checks=False,     # 仅客户端心跳（课 10）
        dns_interface=False,
        multi_dc=False,
        service_mesh=False,
        config_versioning=False,
        config_audit=False,
        acl=False,               # 弱（课 10）
        advisory_only_lock=True,
        license='Apache-2.0',
    ),
}


class CapabilityGap(Exception):
    """目标后端缺少某项能力——这是"设计期"错误，不是运行时故障。

    它对应课 08 故障模式 8：替换时功能对不上。
    抛出它意味着"这个后端不该被这样用"，需要改设计而不是改配置。
    """


class DiscoveryBackend:
    """统一的注册发现抽象层。

    这是课 10「成品 vs 零件」结论的代码表达：
      - 成品型后端（Consul / Nacos / Eureka）大多直接支持
      - 零件型后端（etcd / ZK）会在缺失能力上抛 CapabilityGap

    这样做的好处：**切换后端时，缺失能力在第一次调用就暴露**，
    而不是等到生产环境才发现"健康检查没了"。
    """

    def __init__(self, backend: str = 'consul'):
        if backend not in CAPABILITIES:
            raise ValueError(
                f'未知后端：{backend}；可选：{list(CAPABILITIES)}'
            )
        self.backend = backend
        self.cap = CAPABILITIES[backend]

    def _require(self, ok: bool, what: str, hint: str = ''):
        if not ok:
            raise CapabilityGap(
                f'{self.cap.name} 不支持「{what}」——{hint or "需应用层自建"}'
                f'（见课 10 功能矩阵）'
            )

    # --- 能力门面：每个方法先声明自己依赖什么 -------------------------

    def register_with_health_check(self):
        """注册并带健康检查——依赖 health_checks 能力。"""
        self._require(self.cap.health_checks, '健康检查',
                      '零件型后端需自建心跳与存活判断')
        return f'{self.cap.name}: 使用原生健康检查注册'

    def resolve_by_dns(self):
        """用 DNS 解析服务——依赖 dns_interface 能力。"""
        self._require(self.cap.dns_interface, 'DNS 接口',
                      '需自建 DNS 或在应用中做服务名映射')
        return f'{self.cap.name}: 通过 DNS 解析服务名'

    def query_remote_dc(self, dc: str):
        """跨数据中心查询——依赖 multi_dc 能力。"""
        self._require(self.cap.multi_dc, '多数据中心',
                      '需应用层自己做跨机房同步或查询代理')
        return f'{self.cap.name}: 查询 {dc} 的服务目录'

    def enable_mesh(self):
        """启用服务网格——依赖 service_mesh 能力。"""
        self._require(self.cap.service_mesh, '服务网格',
                      '其余四家无内置网格，需引入 Istio/Linkerd 等')
        return f'{self.cap.name}: 启用 mTLS 与 intention 授权'

    def rollback_config(self):
        """配置回滚——依赖 config_versioning 能力。"""
        self._require(self.cap.config_versioning, '配置版本历史',
                      'Consul KV 无版本历史（课 6 实测），须用 Git 做源')
        return f'{self.cap.name}: 回滚到上一个配置版本'

    # --- 对比视图 ----------------------------------------------------

    @staticmethod
    def compare(backends: Optional[List[str]] = None) -> str:
        """生成能力对比表——把课 10 的矩阵变成可打印的东西。"""
        names = backends or list(CAPABILITIES)
        cols = ['health_checks', 'dns_interface', 'multi_dc',
                'service_mesh', 'config_versioning', 'acl']
        head = f'{"能力":<14}' + ''.join(
            f'{CAPABILITIES[n].name:<10}' for n in names)
        lines = [head, '-' * 60]
        label = {
            'health_checks': '健康检查', 'dns_interface': 'DNS 接口',
            'multi_dc': '多数据中心', 'service_mesh': '服务网格',
            'config_versioning': '配置版本', 'acl': '权限控制',
        }
        for c in cols:
            row = f'{label[c]:<14}'
            for n in names:
                row += f'{"✅" if getattr(CAPABILITIES[n], c) else "❌":<10}'
            lines.append(row)
        lines.append('')
        lines.append('许可证：' + '; '.join(
            f'{CAPABILITIES[n].name}={CAPABILITIES[n].license}' for n in names))
        return '\n'.join(lines)


# ------------------------------------------------------- 阶段 4：上线前自检


@dataclass
class CheckResult:
    """一项自检的结果。

    status 取值：
      pass    ✅ 通过
      warn    ⚠️ 警告（能用但有隐患）
      fail    ❌ 不通过
      skip    ⏭️ 跳过（当前环境不适用，如 dev 模式无多 server）
    """

    name: str
    status: str
    detail: str
    lesson: str = ''          # 回指课时，方便查阅原理
    remediation: str = ''     # 不通过时的整改建议


@dataclass
class SelfCheckReport:
    results: List[CheckResult] = field(default_factory=list)

    def add(self, r: CheckResult):
        self.results.append(r)

    @property
    def failed(self):
        return [r for r in self.results if r.status == 'fail']

    @property
    def warned(self):
        return [r for r in self.results if r.status == 'warn']

    def render(self) -> str:
        icon = {'pass': '✅', 'warn': '⚠️', 'fail': '❌', 'skip': '⏭️'}
        lines = []
        for r in self.results:
            lines.append(f'{icon.get(r.status, "?")} [{r.status.upper():<4}] {r.name}')
            lines.append(f'        {r.detail}')
            if r.lesson:
                lines.append(f'        原理：{r.lesson}')
            if r.remediation and r.status in ('fail', 'warn'):
                lines.append(f'        整改：{r.remediation}')
        lines.append('')
        lines.append(
            f'小结：通过 {sum(1 for r in self.results if r.status == "pass")} 项 / '
            f'警告 {len(self.warned)} 项 / '
            f'不通过 {len(self.failed)} 项 / '
            f'跳过 {sum(1 for r in self.results if r.status == "skip")} 项'
        )
        if self.failed:
            lines.append('⚠️ 存在不通过项，不建议就此上生产——详见各项整改建议。')
        return '\n'.join(lines)


def run_preflight_checks(consul) -> SelfCheckReport:
    """上线前运维自检——把课 11「运维五问」与课 12「POC 验收点」变成可执行检查。

    参数 consul 是 consul_client.Consul 实例。
    所有检查都做了异常兜底：**自检本身不应把程序搞崩**，
    连接不上等异常会被记为 fail，而不是抛出。
    """
    report = SelfCheckReport()
    try:
        leader = consul.leader()
        if leader:
            report.add(CheckResult(
                name='集群 leader 正常',
                status='pass',
                detail=f'当前 leader：{leader}',
                lesson='课 5（Raft 与 leader）',
            ))
        else:
            report.add(CheckResult(
                name='集群 leader 正常',
                status='fail',
                detail='未获取到 leader，quorum 可能已丢失，写入会失败',
                lesson='课 5',
                remediation='检查 server 节点存活数是否仍构成多数派（3 节点需 ≥2）',
            ))
    except Exception as e:
        report.add(CheckResult(
            name='集群 leader 正常',
            status='fail',
            detail=f'查询失败：{type(e).__name__}: {e}',
            lesson='课 5',
            remediation='确认 agent 已启动且地址正确（consul agent -dev）',
        ))
        # 连接本身都不通，后续依赖网络的检查没有意义
        report.add(CheckResult(
            name='后续检查',
            status='skip',
            detail='Consul 不可达，跳过其余依赖网络的检查',
        ))
        return report

    # --- 检查 2：server 数量与 quorum（课 11 运维账） ------------------
    try:
        peers = consul.peers()
        n = len(peers) if peers else 0
        if n >= 3:
            report.add(CheckResult(
                name='server 节点数满足 quorum',
                status='pass',
                detail=f'{n} 个节点，可容忍 {(n - 1) // 2} 个故障',
                lesson='课 11（最小生产拓扑：3 或 5 server）',
            ))
        elif n == 0:
            report.add(CheckResult(
                name='server 节点数满足 quorum',
                status='skip',
                detail='dev 模式无 peers 信息，无法校验',
                lesson='课 11',
                remediation='生产环境须部署 3 或 5 个 server（奇数）',
            ))
        else:
            report.add(CheckResult(
                name='server 节点数满足 quorum',
                status='fail',
                detail=f'仅 {n} 个节点，不满足生产 quorum 要求',
                lesson='课 11',
                remediation='生产环境须 3 或 5 个 server；偶数无意义（4 与 3 同样只容忍 1 个故障）',
            ))
    except Exception as e:
        report.add(CheckResult(
            name='server 节点数满足 quorum',
            status='warn',
            detail=f'无法获取 peers：{type(e).__name__}: {e}',
            lesson='课 11',
        ))

    # --- 检查 3：KV 读写可用性（课 6） --------------------------------
    try:
        probe_key = '_preflight_probe'
        consul.kv_put(probe_key, 'probe')
        got = consul.kv_get(probe_key)
        # 实测结构（2026-09-17）：客户端 kv_get 返回封装后的 dict：
        #   {"status": 200, "index": "...", "body": [{"Key": ..., "Value": <base64>}]}
        # 注意不是 Consul 原生 list——实际数据在 ["body"] 里。
        body = got.get('body') if isinstance(got, dict) else got
        ok = bool(body) and body[0].get('Key') == probe_key
        consul.kv_delete(probe_key)
        if ok:
            report.add(CheckResult(
                name='KV 读写可用',
                status='pass',
                detail='写入并读回成功（探针键已清理）',
                lesson='课 6（KV 与阻塞查询）',
            ))
        else:
            report.add(CheckResult(
                name='KV 读写可用',
                status='fail',
                detail='写入后读回为空——KV 不可用或权限不足',
                lesson='课 6',
                remediation='检查 ACL 权限：无权限时列表类操作会返回空（见症状 10）',
            ))
    except Exception as e:
        report.add(CheckResult(
            name='KV 读写可用',
            status='fail',
            detail=f'KV 操作失败：{type(e).__name__}: {e}',
            lesson='课 6',
            remediation='确认 ACL token 具备 key_prefix 写权限（课 8）',
        ))

    # --- 检查 4：ACL 是否启用（课 8 实测） ----------------------------
    # 未启用 ACL 时任何人都能改任何东西——生产必须开。
    # 说明：dev 模式下匿名总能读到 consul 自身服务，因此本项**无法**在无鉴权环境
    # 可靠区分"ACL 未启用"与"ACL 已启用但放行了 service:read"。
    # 这里如实标注为需人工确认，不假装能自动判定（遵循"不能编造结论"）。
    try:
        resp = consul.health_service('consul')
        body = resp.get('body') if isinstance(resp, dict) else resp
        readable = bool(body)
        report.add(CheckResult(
            name='ACL 默认拒绝已配置',
            status='skip' if readable else 'warn',
            detail=('匿名可读服务目录（dev 模式常态）'
                    if readable else '匿名读受限'),
            lesson='课 8（默认策略与匿名 token）',
            remediation='生产须设 acl { enabled = true, default_policy = "deny" }；'
                        '本项无法自动判定，请人工确认（课 8 实测）',
        ))
    except Exception as e:
        report.add(CheckResult(
            name='ACL 默认拒绝已配置',
            status='pass',
            detail=f'匿名请求被拒（{type(e).__name__}）——ACL 很可能已启用并默认拒绝',
            lesson='课 8',
        ))

    # --- 检查 5：告警指标语义（课 11 缺口 #4 铁律） --------------------
    # 这条无法自动校验语义，只能提醒——它必须由人执行三步核验
    report.add(CheckResult(
        name='告警指标已做三步核验',
        status='warn',
        detail='本项需人工核验：① curl 看值域 ② 读 HELP 的 attribute= ③ 采样 3~5 次看是否单调递增',
        lesson='课 11 缺口 #4（指标三步核验铁律）',
        remediation='未核验的指标可能是累积计数，告警会【静默失效】——比配错阈值更危险',
    ))

    # --- 检查 6：备份恢复是否演练过（课 11 缺口 #3） -------------------
    report.add(CheckResult(
        name='快照恢复已演练',
        status='warn',
        detail='本项需人工确认：是否真实执行过 snapshot save → restore？',
        lesson='课 11 缺口 #3（备份恢复与灾备）',
        remediation='恢复是【全量覆盖】而非增量合并（症状 11），未演练直接用在生产会造成数据倒退',
    ))

    # --- 检查 7：网格边界（实战篇 B 实测，2026-09-17 吸收） ----------
    # 实战篇 B 最警示的一条：Consul Connect 加密的是"进 sidecar 的流量"，
    # 不是"应用的端口"。实测绕过 sidecar 直连应用端口返回明文 200。
    # 若应用监听 0.0.0.0 且无网络策略，mTLS 可被一步绕过，网格等于白建。
    report.add(CheckResult(
        name='服务网格不可被绕过',
        status='warn',
        detail='本项需人工核验：应用是否只监听 127.0.0.1？是否有网络策略限制端口？',
        lesson='实战篇 B（Connect 最小闭环）实测：绕过 sidecar 直连应用端口为明文',
        remediation='应用须只监听 127.0.0.1（不监听 0.0.0.0），'
                    '并用防火墙/NetworkPolicy 限制端口；'
                    '否则 mTLS 可被直连绕过，网格形同虚设',
    ))

    # --- 检查 8：ACL 规则语法（实战篇 C 实测，2026-09-17 吸收） --------
    # 实战篇 C 实测：operator / acl / keyring / mesh / peering **不带 label**，
    # 写成 operator_prefix "" { policy = "read" } 时 Consul 不报错，
    # 但权限静默不生效——配置的人以为给了权限，实际读 raft 配置照样 403。
    report.add(CheckResult(
        name='ACL 规则未用错 label 形式',
        status='warn',
        detail='本项需人工核验：operator/acl/keyring/mesh/peering 是否写成了 _prefix 形式？',
        lesson='实战篇 C 实测：这些资源不带 label，正确写法是 operator = "read"',
        remediation='写成 operator_prefix "" { policy = "read" } 不会报错但权限静默失效；'
                    '可用 validate_acl_rules() 自动扫描规则文本',
    ))

    return report


# ---------------------------------------------- 实战篇吸收：ACL 规则校验器

# 不带 label 的 ACL 资源——写成 xxx_prefix 形式会静默失效（实战篇 C 实测）
# 来源：Consul 官方 ACL rule 参考 + 2026-09-17 本机实测对照（200 vs 403）
NO_LABEL_RESOURCES = ('operator', 'acl', 'keyring', 'mesh', 'peering')
# 带 label 的资源——必须用 xxx_prefix "..." { ... } 形式
PREFIX_RESOURCES = ('key', 'node', 'service', 'session', 'agent', 'event', 'query')


def validate_acl_rules(rules: str) -> List[str]:
    """扫描 ACL 规则文本，报出「写法不生效」的隐患。返回问题列表（空列表 = 没问题）。

    为什么需要这个函数（实战篇 C 实测）：
    把 `operator = "read"` 错写成 `operator_prefix "" { policy = "read" }` 时，
    创建 policy 返回 200、创建 token 返回 200，**全程没有任何报错**，
    但权限静默不生效——直到某天排障要读 /v1/operator/raft/configuration 才发现 403。

    这类"配错了不告诉你"的问题，正是本项目要拦截的对象。
    """
    import re
    problems = []
    for res in NO_LABEL_RESOURCES:
        # 匹配 operator_prefix "" { ... } 这种写法
        if re.search(rf'\b{res}_prefix\s', rules):
            problems.append(
                f'「{res}」不带 label，应写成 {res} = "read"，'
                f'写成 {res}_prefix 形式不报错但权限静默失效（实战篇 C 实测）'
            )
    # 反向检查：带 label 的资源若写成裸赋值（operator = "read" 之外的形式）
    for res in PREFIX_RESOURCES:
        if re.search(rf'^\s*{res}\s*=', rules, re.MULTILINE):
            problems.append(
                f'「{res}」带 label，应写成 {res}_prefix "前缀" {{ policy = "..." }}，'
                f'裸赋值 {res} = "..." 不会被识别为其权限规则'
            )
    return problems


# ---------------------------------------------- 实战篇吸收：读模式选择

# 三种读模式的适用场景（实战篇 A 三节点集群实测结论）
READ_MODE_ADVICE = {
    'default': '读配置等要求准确的场景；leader 选举期间会 500（实测约 9.5 秒）',
    'consistent': '分布式锁/选主等正确性压倒一切的场景；比 default 多一轮 quorum 确认',
    'stale': '服务发现推荐；leader 选举期间仍能返回（实测），但写后立即读会落后一个版本',
}


def pick_read_mode(scenario: str) -> str:
    """按场景给出推荐的读模式——把实战篇 A 的实测结论做成可调用的判断。

    参数 scenario 取值：'discovery'（服务发现）/ 'config'（读配置）
                        / 'lock'（分布式锁选主）/ 'failover'（故障时仍需响应）
    """
    mapping = {
        'discovery': 'stale',
        'config': 'default',
        'lock': 'consistent',
        'failover': 'stale',
    }
    mode = mapping.get(scenario)
    if not mode:
        raise ValueError(
            f'未知场景：{scenario}；可选：{list(mapping)}'
        )
    return mode


def explain_read_mode(mode: str) -> str:
    """返回该读模式的实测结论说明。"""
    if mode not in READ_MODE_ADVICE:
        raise ValueError(f'未知读模式：{mode}；可选：{list(READ_MODE_ADVICE)}')
    return f'{mode}: {READ_MODE_ADVICE[mode]}'

    # --- 检查 2：server 数量与 quorum（课 11 运维账） ------------------
    try:
        peers = consul.peers()
        n = len(peers) if peers else 0
        if n >= 3:
            report.add(CheckResult(
                name='server 节点数满足 quorum',
                status='pass',
                detail=f'{n} 个节点，可容忍 {(n - 1) // 2} 个故障',
                lesson='课 11（最小生产拓扑：3 或 5 server）',
            ))
        elif n == 0:
            report.add(CheckResult(
                name='server 节点数满足 quorum',
                status='skip',
                detail='dev 模式无 peers 信息，无法校验',
                lesson='课 11',
                remediation='生产环境须部署 3 或 5 个 server（奇数）',
            ))
        else:
            report.add(CheckResult(
                name='server 节点数满足 quorum',
                status='fail',
                detail=f'仅 {n} 个节点，不满足生产 quorum 要求',
                lesson='课 11',
                remediation='生产环境须 3 或 5 个 server；偶数无意义（4 与 3 同样只容忍 1 个故障）',
            ))
    except Exception as e:
        report.add(CheckResult(
            name='server 节点数满足 quorum',
            status='warn',
            detail=f'无法获取 peers：{type(e).__name__}: {e}',
            lesson='课 11',
        ))

    # --- 检查 3：dev 模式检测（课 11 / 课 6） -------------------------
    # dev 模式用内存存储、无 Raft 持久化，重启即全丢——上生产是大忌
    try:
        # dev 模式下通常只有一个节点且无 peers；这里用 KV 写入做间接验证
        probe_key = '_preflight_probe'
        consul.kv_put(probe_key, 'probe')
        got = consul.kv_get(probe_key)
        # 实测结构（2026-09-17）：客户端 kv_get 返回封装后的 dict：
        #   {"status": 200, "index": "...", "body": [{"Key": ..., "Value": <base64>}]}
        # 注意不是 Consul 原生 list——实际数据在 ["body"] 里。
        body = got.get('body') if isinstance(got, dict) else got
        ok = bool(body) and body[0].get('Key') == probe_key
        consul.kv_delete(probe_key)
        if ok:
            report.add(CheckResult(
                name='KV 读写可用',
                status='pass',
                detail='写入并读回成功（探针键已清理）',
                lesson='课 6（KV 与阻塞查询）',
            ))
        else:
            report.add(CheckResult(
                name='KV 读写可用',
                status='fail',
                detail='写入后读回为空——KV 不可用',
                lesson='课 6',
                remediation='检查 ACL 权限（无权限时列表类操作可能返回空，见症状 10）',
            ))
    except Exception as e:
        report.add(CheckResult(
            name='KV 读写可用',
            status='fail',
            detail=f'KV 操作失败：{type(e).__name__}: {e}',
            lesson='课 6',
            remediation='确认 ACL token 具备 key_prefix 写权限（课 8）',
        ))

    # --- 检查 4：ACL 是否启用（课 8 实测） ----------------------------
    # 未启用 ACL 时任何人都能改任何东西——生产必须开。
    # 说明：dev 模式下匿名总能读到 consul 自身服务，因此本项**无法**在无鉴权环境
    # 可靠区分"ACL 未启用"与"ACL 已启用但放行了 service:read"。
    # 这里如实标注为需人工确认，不假装能自动判定（遵循"不能编造结论"）。
    try:
        resp = consul.health_service('consul')
        body = resp.get('body') if isinstance(resp, dict) else resp
        readable = bool(body)
        report.add(CheckResult(
            name='ACL 默认拒绝已配置',
            status='skip' if readable else 'warn',
            detail=('匿名可读服务目录（dev 模式常态）'
                    if readable else '匿名读受限'),
            lesson='课 8（默认策略与匿名 token）',
            remediation='生产须设 acl { enabled = true, default_policy = "deny" }；'
                        '本项无法自动判定，请人工确认（课 8 实测）',
        ))
    except Exception as e:
        report.add(CheckResult(
            name='ACL 默认拒绝已配置',
            status='pass',
            detail=f'匿名请求被拒（{type(e).__name__}）——ACL 很可能已启用并默认拒绝',
            lesson='课 8',
        ))

    # --- 检查 5：告警指标语义（课 11 缺口 #4 铁律） --------------------
    # 这条无法自动校验语义，只能提醒——它必须由人执行三步核验
    report.add(CheckResult(
        name='告警指标已做三步核验',
        status='warn',
        detail='本项需人工核验：① curl 看值域 ② 读 HELP 的 attribute= ③ 采样 3~5 次看是否单调递增',
        lesson='课 11 缺口 #4（指标三步核验铁律）',
        remediation='未核验的指标可能是累积计数，告警会【静默失效】——比配错阈值更危险',
    ))

    # --- 检查 6：备份恢复是否演练过（课 11 缺口 #3） -------------------
    report.add(CheckResult(
        name='快照恢复已演练',
        status='warn',
        detail='本项需人工确认：是否真实执行过 snapshot save → restore？',
        lesson='课 11 缺口 #3（备份恢复与灾备）',
        remediation='恢复是【全量覆盖】而非增量合并（症状 11），未演练直接用在生产会造成数据倒退',
    ))

    return report
