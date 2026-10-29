from dataclasses import dataclass

from langchain_core.tools import tool

from managed_deepagents import ManagedToolRuntime


@dataclass
class DutyContext:
    """调用方传进来的业务上下文。

    注意：这一层只用来"选行为"（用哪份值班表、走快档还是慢档），
    绝不用于判权限 —— 权限只认 runtime.server_info.principal。
    """

    team: str = "platform"
    detail_level: str = "brief"


@tool
def read_oncall_roster(team: str) -> str:
    """读取某个团队当前的值班人。team 是团队标识，如 platform / infra。"""
    # 真实场景应查内部值班系统；这里用固定数据保证项目离线可跑
    roster = {
        "platform": "值班人：小林（今日 09:00-21:00），备班：老周",
        "infra": "值班人：阿浩（今日 09:00-21:00），备班：小陈",
        "data": "值班人：未排班（今日空缺）",
    }
    return roster.get(team, f"团队 {team} 不在值班表里，请确认团队标识。")


@tool
def query_open_alerts(team: str, level: str = "all") -> str:
    """查询某团队当前未恢复的告警。level 可取 all / p1 / p2。"""
    alerts = {
        "platform": [
            ("P1", "checkout-api 5xx 比例 12%（持续 8 分钟）"),
            ("P2", "redis 连接池使用率 91%"),
        ],
        "infra": [("P2", "node-07 磁盘使用率 88%")],
        "data": [],
    }
    rows = alerts.get(team, [])
    if level != "all":
        rows = [r for r in rows if r[0].lower() == level.lower()]
    if not rows:
        return f"团队 {team} 当前没有未恢复的 {level} 告警。"
    return "\n".join(f"[{lv}] {text}" for lv, text in rows)


@tool
async def escalate_incident(
    summary: str,
    severity: str,
    runtime: ManagedToolRuntime[DutyContext],
) -> str:
    """把一条告警升级给当班负责人。属于写操作，需要已验证的身份。"""
    # 权限判断只看 principal —— 它在 token 校验通过后才存在
    principal = runtime.server_info.principal if runtime.server_info else None
    if principal is None:
        return "拒绝升级：这次调用没有已验证身份（principal 为空）。请让调用方带上身份凭证。"

    # context 只用来决定"提到哪个团队渠道"，不参与鉴权
    team = runtime.context.team if runtime.context else "platform"
    return f"已升级到 {team} 团队（操作人 {principal.id}）：[{severity}] {summary}"
