#!/bin/bash
# 课 9 实验⑧（修正版）：兼容性策略矩阵 —— backward / forward / full / none
#
# ⚠⚠ 重要修正记录（两轮纠错，这是本课最有价值的排障案例）⚠⚠
#
# 第 1 轮：set_config 传 dict -> 报 'dict' object has no attribute 'to_dict'
#          整张表 8 个格子全是 set_config 失败信息，表格完全无效
# 第 2 轮：改传 ServerConfig 对象 -> 不报错了，但 8 个格子【全部"放行"】
#          我怀疑结果可疑（full 下删字段本该被拒），诊断发现：
#          set_config 返回 {} 且【策略根本没设上去】——查出来仍是 BACKWARD
#          也就是说第 2 轮那张"全部放行"的表，测的其实是默认的 backward，
#          等于什么都没测。如果直接写进讲义就是一张假表。
# 第 3 轮：改用 REST API 直接设（PUT /config/{subject}），
#          设完立刻 GET 回读确认生效，再跑注册 —— 这才拿到真实结果
#
# 根因：confluent-kafka 2.15 的 ServerConfig 有 compatibility 和
#       compatibility_level 两个字段，to_dict() 分别产出
#       {"compatibility":...} 和 {"compatibilityLevel":...} 两种 JSON，
#       而 SR 7.6.1 REST 端认的是 compatibility。
#       客户端传 compatibility_level 不报错但静默不生效 —— 最危险的失败模式。
set -u
cat > /tmp/policy2.py <<'PYEOF'
import json, urllib.request, urllib.error

SR = "http://l9-sr:8081"

def rest(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(SR+path, data=data, method=method,
                              headers={"Content-Type":"application/json"})
    try:
        with urllib.request.urlopen(r) as resp:
            return resp.status, json.loads(resp.read() or b'{}')
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read())

def set_level(subj, level):
    c, r = rest("PUT", f"/config/{subj}", {"compatibility": level})
    # 关键：设完立刻回读确认，不确认就等于没设
    c2, r2 = rest("GET", f"/config/{subj}")
    got = r2.get("compatibilityLevel")
    if got != level:
        raise RuntimeError(f"策略未生效: 期望 {level} 实际 {got}")
    return got

def reg(subj, schema_str):
    c, r = rest("POST", f"/subjects/{subj}/versions", {"schema": schema_str})
    return c, r

# 场景 A：删字段
A_V1 = {"type":"record","name":"PA","fields":[
    {"name":"a","type":"string"},{"name":"b","type":"int"}]}
A_V2 = {"type":"record","name":"PA","fields":[{"name":"b","type":"int"}]}
# 场景 B：加字段带默认值
B_V1 = {"type":"record","name":"PB","fields":[{"name":"b","type":"int"}]}
B_V2 = {"type":"record","name":"PB","fields":[
    {"name":"b","type":"int"},{"name":"a","type":"string","default":"x"}]}

def run(tag, v1, v2, levels):
    print(f"\n【{tag}】")
    print(f"{'策略':<12}{'生效确认':<10}{'注册结果':<10}服务端错误类型")
    print("-" * 76)
    out = {}
    for lv in levels:
        subj = f"{tag}-{lv}"
        try:
            set_level(subj, lv)
            confirmed = "✓"
        except Exception as e:
            print(f"{lv:<12}{'✗':<10}{'-':<10}{str(e)[:50]}")
            out[lv] = "N/A"; continue
        c1, _ = reg(subj, json.dumps(v1))
        c2, r2 = reg(subj, json.dumps(v2))
        if c2 == 200:
            res, err = "放行", "-"
        else:
            res = "拒绝"
            msg = r2.get("message","")
            err = msg.split("errorType:'")[1].split("'")[0] if "errorType:'" in msg else "?"
        out[lv] = res
        print(f"{lv:<12}{confirmed:<10}{res:<10}{err}")
    return out

print("=" * 76)
print("兼容性策略矩阵（真 SR 7.6.1，REST 直连 + 设完回读确认）")
print("=" * 76)

a = run("A-dropfield", A_V1, A_V2, ["BACKWARD","FORWARD","FULL","NONE"])
b = run("B-addfield", B_V1, B_V2, ["BACKWARD","FORWARD","FULL","NONE"])

print("\n" + "=" * 76)
print("矩阵汇总")
print("=" * 76)
print(f"{'演进':<22}{'BACKWARD':<12}{'FORWARD':<12}{'FULL':<12}{'NONE'}")
print("-" * 76)
print(f"{'删字段':<22}{a['BACKWARD']:<12}{a['FORWARD']:<12}{a['FULL']:<12}{a['NONE']}")
print(f"{'加字段(带默认值)':<22}{b['BACKWARD']:<12}{b['FORWARD']:<12}{b['FULL']:<12}{b['NONE']}")
print("=" * 76)
# 结论由实测结果反推，不写死预设
diff = [lv for lv in ("BACKWARD","FORWARD","FULL") if a.get(lv) != b.get(lv)]
print("实测解读（由上表反推，非预设）：")
print(f"  · 两种演进结果有差异的策略: {diff if diff else '无（本次两种演进判定一致）'}")
safe = [lv for lv in ("BACKWARD","FORWARD","FULL") if b.get(lv)=="放行"]
print(f"  · 加字段带默认值放行的策略: {safe} —— 这是最安全的演进方式")
print(f"  · NONE 结果: {a.get('NONE')}/{b.get('NONE')} = 不校验，等于没上 SR")
print("=" * 76)
PYEOF
docker run --rm --network bench_kafka-net -v /tmp/policy2.py:/p.py \
  kafka-pybench:3.12 /app/.venv/bin/python /p.py 2>&1 | head -45
