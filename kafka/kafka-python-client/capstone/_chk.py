import json
import urllib.request
import urllib.error

try:
    r = urllib.request.urlopen("http://localhost:8000/ready", timeout=25)
    print("ready:", json.loads(r.read().decode()))
except urllib.error.HTTPError as e:
    print("503:", e.read().decode()[:150])
s = json.loads(urllib.request.urlopen("http://localhost:8000/stats", timeout=20).read())
print("parts:", len(s.get("lag_by_partition", {})), "lag:", s.get("lag_total"))
