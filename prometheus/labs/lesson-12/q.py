import sys, json, urllib.parse, urllib.request

PORT   = sys.argv[1]
EXPR   = sys.argv[2]
url = f"http://localhost:{PORT}/api/v1/query?" + urllib.parse.urlencode({"query": EXPR})
try:
    with urllib.request.urlopen(url, timeout=10) as r:
        d = json.load(r)
    res = d.get("data", {}).get("result", [])
    if not res:
        print("empty")
    else:
        print(res[0]["value"][1])
except Exception as e:
    print("ERR", e)
