# -*- coding: utf-8 -*-
"""deploy_logic.py —— 部署逻辑下推产物（函数 + 端点 + 审计表）并做真实 HTTP 验证

⚠️ 端点必须用真实 HTTP 验证。api::invoke() 会把 500 伪装成 200
   （课 9 教训，本项目 cap-probe2 复现）。
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402
from pushdown import (ALL, FN_SEARCH_KW, FN_SEARCH_SCOPED, AUDIT,  # noqa: E402
                      API_QA_GET, API_QA_POST_ONLY, API_ASK)
from seed import DEFAULT_PASSWORD  # noqa: E402


def main():
    conn = Conn()
    print("=" * 74)
    print("部署逻辑下推产物")
    print("=" * 74)

    for i, block in enumerate(ALL):
        # ⚠️ 整体执行，不要按分号切分：DEFINE FUNCTION / DEFINE API 的函数体
        #    内部含分号（LET ...; RETURN ...;），切开会得到不完整的语句，
        #    报 "Unexpected end of file, expected an expression"。
        stmts = [block.strip()]
        label = block.strip().split("\n")[0].replace("\n", " ")[:70]
        ok_all = True
        for s in stmts:
            ok, payload, err = conn.sql(s)
            if not ok:
                ok_all = False
                print("  ✗ %s" % label)
                print("      %s" % str(payload)[:260])
                break
        print("  %s %s" % ("✓" if ok_all else "✗", label))

    print()
    print("=" * 74)
    print("验证 1：函数能否调用")
    print("=" * 74)
    for fn, desc, n_args in [
        ("RETURN fn::qa_kw('索引', '加速', '查询', 3);", "fn::qa_kw 多 term 检索", 4),
        ("RETURN fn::qa_scoped('权限', '隔离', '租户', 3, 'beta');", "fn::qa_scoped 租户过滤", 5),
        ("RETURN fn::qa_scoped('权限', '隔离', '租户', 3, 'acme');", "fn::qa_scoped 另一租户", 5),
        ("RETURN fn::qa_kw('索引怎么加速查询', '', '', 3);", "对照：整串查询（老写法）", 4),
    ]:
        ok, payload, err = conn.sql(fn)
        if ok:
            res = payload[-1].get("result") if isinstance(payload, list) else None
            n = len(res) if isinstance(res, list) else 0
            print("  ✓ %-28s 返回 %d 条" % (desc, n))
            if isinstance(res, list) and res:
                for r in res[:2]:
                    print("      %s  %s" % (r.get("id"),
                                            (r.get("text") or "")[:44]))
        else:
            print("  ✗ %-28s %s" % (desc, str(payload)[:200]))

    print()
    print("=" * 74)
    print("验证 1.5：同一路径 GET/POST 分两条定义 → 互相覆盖（反例复现）")
    print("=" * 74)
    # 先按错误写法重新定义（只 POST），看 GET /qa 是否被覆盖成 404
    ok, payload, err = conn.sql(API_QA_POST_ONLY.strip())
    if ok:
        c_get, b_get = conn.api("/qa", "GET")
        c_post, b_post = conn.api("/qa", "POST", json.dumps({"q": "索引", "k": 1}))
        print("  错误写法（只 FOR POST）部署后：")
        print("      GET  /qa → HTTP %s   %s" % (c_get, "404 即被覆盖" if c_get == 404 else "仍可用"))
        print("      POST /qa → HTTP %s" % c_post)
    else:
        print("  ✗ 反例部署失败 %s" % str(payload)[:200])

    # 恢复正确写法（FOR GET, POST 一条），两者应当都可用
    ok, payload, err = conn.sql(API_QA_GET.strip())
    if ok:
        c_get, b_get = conn.api("/qa", "GET")
        print("  恢复合并定义（FOR GET, POST）后：")
        print("      GET  /qa → HTTP %s  %s" % (c_get, b_get[:60]))
    else:
        print("  ✗ 恢复失败 %s" % str(payload)[:200])

    print()
    print("=" * 74)
    print("验证 2：端点走真实 HTTP（不是 api::invoke）")
    print("=" * 74)
    code, body = conn.api("/qa", "GET")
    print("  GET  /qa       → HTTP %s  %s" % (code, body[:100]))

    code, body = conn.api("/qa", "POST", json.dumps({"q": "索引", "k": 3}))
    print("  POST /qa       → HTTP %s" % code)
    if code == 200:
        try:
            j = json.loads(body)
            print("      q=%r count=%s" % (j.get("q"), j.get("count")))
            for h in (j.get("hits") or [])[:3]:
                print("      %s  %s" % (h.get("id"), (h.get("text") or "")[:44]))
        except Exception as e:
            print("      解析失败 %s：%s" % (e, body[:200]))
    else:
        print("      %s" % body[:300])

    print()
    print("=" * 74)
    print("验证 3：/ask 端点写入审计（用记录用户身份，验证 $auth.tenant）")
    print("=" * 74)
    ok, payload, err = conn.sql("SELECT count() FROM ask_audit GROUP ALL;")
    before = payload[-1]["result"][0]["count"] if ok else "?"
    print("  调用前 ask_audit 条数：%s" % before)

    for email in ["alice@acme.io", "bob@beta.io"]:
        try:
            token = conn.signin("app", email=email, password=DEFAULT_PASSWORD)
        except RuntimeError as e:
            print("  ✗ %s 登录失败 %s" % (email, e))
            continue
        uc = Conn(token=token)
        code, body = uc.api("/ask", "POST", json.dumps({"q": "权限", "k": 3}))
        if code == 200:
            j = json.loads(body)
            print("  ✓ %-14s → HTTP 200 tenant=%r count=%s"
                  % (email, j.get("tenant"), j.get("count")))
        else:
            print("  ✗ %-14s → HTTP %s %s" % (email, code, body[:160]))

    ok, payload, err = conn.sql(
        "SELECT q, tenant, who, n, at FROM ask_audit ORDER BY at DESC LIMIT 5;")
    if ok:
        rows = payload[-1].get("result") or []
        print()
        print("  审计表最近记录：")
        for r in rows:
            print("      tenant=%-6s who=%-10s q=%-6s n=%s"
                  % (r.get("tenant"), r.get("who"), r.get("q"), r.get("n")))
    else:
        print("  ✗ 读审计表失败 %s" % str(payload)[:200])

    print()
    print("=" * 74)
    print("验证 4：审计表也受权限约束（alice 只能看到 acme 的审计）")
    print("=" * 74)
    try:
        token = conn.signin("app", email="alice@acme.io", password=DEFAULT_PASSWORD)
        uc = Conn(token=token)
        ok, payload, err = uc.sql("SELECT tenant, q FROM ask_audit;")
        if ok:
            rows = payload[-1].get("result") or []
            tenants = sorted({r.get("tenant") for r in rows})
            print("  alice 可见审计条数 %d，涉及租户 %s" % (len(rows), tenants))
            print("  %s" % ("✓ 正确：只看到 acme" if tenants in ([], ["acme"])
                            else "✗ 越权：看到了其它租户"))
        else:
            print("  ✗ %s" % str(payload)[:200])
    except RuntimeError as e:
        print("  ✗ 登录失败 %s" % e)
    return 0


if __name__ == "__main__":
    sys.exit(main())
