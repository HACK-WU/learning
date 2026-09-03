# -*- coding: utf-8 -*-
"""diag_method.py —— 探测 DEFINE API 里 $request 的真实结构与 method 取值

背景：GET /qa 返回了 POST 分支的结果（count=0, q=''），说明
      `IF $request.method = 'GET'` 没命中。可能原因：
      a) 字段名不叫 method
      b) 值是小写 'get'
      c) $request 在 GET 时结构不同
      用一个回声端点把 $request 原样 dump 出来，一次性查清。
"""
import sys
import os
import json

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Conn  # noqa: E402

DUMP = """
DEFINE API OVERWRITE "/_dump" FOR GET, POST THEN {
  RETURN {
    body: encoding::json::encode({
      keys: object::keys($request),
      method: $request.method,
      method_type: type::is_string($request.method),
      headers: $request.headers,
      raw: type::string($request.body),
      query: $request.query
    })
  };
};
"""


def main():
    conn = Conn()
    ok, payload, err = conn.sql(DUMP.strip())
    if not ok:
        print("定义失败：%s" % str(payload)[:300])
        return 1

    for method in ("GET", "POST"):
        code, body = conn.api("/_dump", method,
                              json.dumps({"probe": 1}) if method == "POST" else None)
        print("=" * 70)
        print("%s /_dump → HTTP %s" % (method, code))
        if code == 200:
            try:
                j = json.loads(body)
                for k in ("keys", "method", "method_type", "raw", "query"):
                    print("   %-12s %s" % (k, j.get(k)))
                h = j.get("headers")
                print("   %-12s %s" % ("headers", str(h)[:200]))
            except Exception as e:
                print("   解析失败 %s：%s" % (e, body[:300]))
        else:
            print("   %s" % body[:300])

    conn.sql('REMOVE API "/_dump";')
    return 0


if __name__ == "__main__":
    sys.exit(main())
