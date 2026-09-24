import json, subprocess
out = subprocess.run(["docker", "inspect", "l11", "--format",
                      "{{json .NetworkSettings.Networks}}"],
                     capture_output=True, text=True).stdout
d = json.loads(out)
print("l11 networks:", list(d.keys()))
for n, v in d.items():
    print("   ", n, v.get("IPAddress"))
