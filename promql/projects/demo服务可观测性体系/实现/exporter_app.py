"""
demo 服务埋点示例 —— 产出本项目全部查询所依赖的指标

⚠️ 环境说明（诚实标注）：
    本项目备课机**未安装 Python 与 Docker**（已实测确认），因此本文件是**纸面交付物**，
    未经运行验证。代码按 prometheus-client 官方 API 编写：
      - 库版本：0.26.0（2026-07-25 发布，支持 Python >=3.9，核查于 2026-08）
      - 官方文档：https://prometheus.github.io/client_python
    在有 Python 3.9+ 的环境可直接 `pip install prometheus-client` 后运行。
    课程的查询侧能力不依赖本文件 —— 演练场已提供全部指标。

运行方式（在有 Python 的环境）：
    pip install prometheus-client==0.26.0
    python exporter_app.py
    # 然后访问 http://localhost:8000/metrics 看暴露的指标
"""

from prometheus_client import Counter, Histogram, Gauge, start_http_server
import random
import time

# ═══════════════════════════════════════════════════════════
# 一、指标定义（知识点：L3 四种指标类型的选型）
# ═══════════════════════════════════════════════════════════

# Counter（累计计数器）：只增不减，适合"次数"类
# 知识点 L3：请求总数用 Counter，查询侧必须配 rate() 才有意义（L8）
# 命名的学问：_count/_sum/_bucket 后缀由 Histogram 自动生成，此处只给基名
REQUEST_LATENCY = Histogram(
    'demo_api_request_duration_seconds',   # 基名；自动生成 _bucket/_sum/_count 三件套
    'API 请求延迟分布（秒）',
    ['method', 'path', 'status'],          # 标签维度
    # 桶边界设计（知识点：L10 桶分辨率天花板）
    # 本项目踩过的坑：×1.5 递增的桶里**没有 0.1**，导致 100ms SLO 无法精确表达。
    # 自己埋点时可以直接补一个 0.1 桶，从源头解决：
    buckets=(0.001, 0.005, 0.01, 0.025, 0.05, 0.075, 0.1, 0.25, 0.5, 1.0, 2.5, float('inf'))
)

# Counter：业务错误计数（与 HTTP status 分开记，便于区分"业务失败"与"服务异常"）
BUSINESS_ERRORS = Counter(
    'demo_business_errors_total',
    '业务错误计数',
    ['path', 'error_code']
)

# Gauge（瞬时值）：可增可减，适合"当前状态"类
# 知识点 L3/L8：Gauge **不能**套 rate()（L8 实测会算出 7000 万 bytes/s 的荒唐值）
IN_FLIGHT_REQUESTS = Gauge(
    'demo_in_flight_requests',
    '当前处理中的请求数',
    ['path']
)

MEMORY_USAGE = Gauge(
    'demo_memory_usage_bytes',
    '内存使用量（字节）',
    ['type']    # used / free / cached / buffers
)


# ═══════════════════════════════════════════════════════════
# 二、⚠️ 高基数陷阱：哪些维度绝对不能进标签
# ═══════════════════════════════════════════════════════════
#
# 知识点 L2：「path 带用户 ID 时轻松冲到几十万...历史上多次 Prometheus OOM
#            事故的根因就是某个标签基数失控」
#
# 本项目实测基线：demo_api_request_duration_seconds_count = 27 条序列
#   = 3 path × 2 method × 2 status（nonexistent 无 POST 故少几条）
#
# ❌ 绝对不能加的标签（每个都会让序列数爆炸）：
#     ['user_id']     —— 用户量 × 上面的组合 = 几十万序列
#     ['request_id']  —— 每请求一个唯一值 = 序列永不被复用
#     ['trace_id']    —— 同上
#     ['url']         —— 含查询参数时等同于 request_id
#     ['email', 'phone', 'order_no']  —— 任何业务唯一标识
#
# ✅ 可以加的标签（低基数、有聚合价值）：
#     ['method']  2~9 个取值
#     ['path']    路由模板化的路径（/api/foo，不是 /api/foo/12345）
#     ['status']  HTTP 状态码（或归并为 2xx/4xx/5xx 三档）
#     ['region', 'env', 'instance']  基础设施维度
#
# 💡 高基数信息（如用户 ID）的正确去处：**日志与链路追踪**，不是指标。
#    指标负责"聚合后回答问题"，日志负责"定位到具体某一次请求"。


# ═══════════════════════════════════════════════════════════
# 三、埋点调用
# ═══════════════════════════════════════════════════════════

def handle_request(method: str, path: str):
    """模拟一次请求处理，产出全部指标"""

    # Gauge：进入时 +1，离开时 -1（用 try/finally 保证不泄漏）
    IN_FLIGHT_REQUESTS.labels(path=path).inc()
    try:
        # 模拟业务耗时（真实场景这里是实际处理逻辑）
        duration = random.uniform(0.001, 0.3)

        # 模拟 5xx（约 2%，贴近演练场实测的错误率水位）
        status = '500' if random.random() < 0.02 else '200'

        if status == '500':
            BUSINESS_ERRORS.labels(path=path, error_code='INTERNAL').inc()
    finally:
        IN_FLIGHT_REQUESTS.labels(path=path).dec()

    # Histogram：记录延迟（自动累加 _bucket/_sum/_count）
    # 知识点 L10：一次 observe() 同时更新三个东西，
    #   查询侧的 histogram_quantile 正是靠 _bucket 的累积阶梯算分位数
    REQUEST_LATENCY.labels(method=method, path=path, status=status).observe(duration)


def update_gauges():
    """模拟 Gauge 类指标的周期性采样"""
    # 知识点 L3：Gauge 是"此刻的值"，要由应用主动 set
    MEMORY_USAGE.labels(type='used').set(random.uniform(4e9, 6e9))
    MEMORY_USAGE.labels(type='free').set(random.uniform(1e9, 2e9))
    MEMORY_USAGE.labels(type='cached').set(random.uniform(0.5e9, 1.5e9))
    MEMORY_USAGE.labels(type='buffers').set(random.uniform(0.1e9, 0.3e9))


# ═══════════════════════════════════════════════════════════
# 四、主循环
# ═══════════════════════════════════════════════════════════

if __name__ == '__main__':
    # 在 8000 端口暴露 /metrics（Prometheus 的默认抓取路径）
    start_http_server(8000)
    print('metrics 已暴露于 http://localhost:8000/metrics')

    # 模拟持续流量：path 只有 3 个固定取值（低基数！）
    PATHS = ['/api/foo', '/api/bar', '/api/nonexistent']
    METHODS = ['GET', 'POST']

    while True:
        method = random.choice(METHODS)
        path = random.choice(PATHS)

        # nonexistent 只有 GET，与演练场实测一致（27 条序列的形态来源）
        if path == '/api/nonexistent':
            method = 'GET'

        handle_request(method, path)
        update_gauges()
        time.sleep(0.01)


# ═══════════════════════════════════════════════════════════
# 五、配套抓取配置（prometheus.yml 片段）
# ═══════════════════════════════════════════════════════════
#
# scrape_configs:
#   - job_name: 'demo'
#     scrape_interval: 15s        # 知识点 L8：决定 rate 窗口下限（窗口 >= 4 倍间隔 = 60s）
#     static_configs:
#       - targets: ['localhost:8000']
#
# 💡 job_name 会作为 job 标签注入每一条序列 —— 这就是本项目所有查询
#    都带 job="demo" 的原因（收窄对象，避免算进监控组件自己）
