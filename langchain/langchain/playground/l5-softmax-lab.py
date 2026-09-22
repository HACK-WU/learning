"""课 5 实操（补充）：在本地构造一个真实的概率分布，演示 logits -> softmax -> 抽样。

说明：百炼端点不支持 logprobs（2026-09-21 实测，返回 400 invalid_parameter_error），
所以无法拿到真实 LLM 的 token 概率。这里用一组"假想的 logits"来演示数学过程，
数学是真实的，数值是构造的——讲义中会明确标注。
"""
import math
import random

random.seed(42)

# 场景 A：模型很有把握（如"中国的首都是"）
LOGITS_A = {"北京": 6.2, "上海": 2.1, "南京": 1.4, "东京": -1.0, "苹果": -3.5}
# 场景 B：模型不太有把握（如开放式续写的下一个词）——分布平坦
LOGITS_B = {"因此": 2.0, "同时": 1.9, "另外": 1.7, "不过": 1.5, "所以": 1.3}


def softmax(d, temp=1.0):
    exps = {k: math.exp(v / temp) for k, v in d.items()}
    s = sum(exps.values())
    return {k: v / s for k, v in exps.items()}


def top_p_filter(p, threshold=0.9):
    items = sorted(p.items(), key=lambda kv: -kv[1])
    out, acc = [], 0.0
    for k, v in items:
        out.append(k)
        acc += v
        if acc >= threshold:
            break
    return out


def sample(p, n=20000):
    ks, ws = list(p.keys()), [p[k] for k in p]
    picked = random.choices(ks, weights=ws, k=n)
    return {k: picked.count(k) / n for k in ks}


print("=== 1. logits → softmax：原始分数变成概率 ===")
base = softmax(LOGITS_A)
print(f"  {'token':<8}{'logit':>8}{'概率':>10}")
for k, v in sorted(LOGITS_A.items(), key=lambda kv: -kv[1]):
    print(f"  {k:<8}{v:>8.1f}{base[k]:>10.4f}")

print("\n=== 2. temperature 在改什么 ===")
print(f"  {'token':<8}" + "".join(f"{'T=' + str(t):>10}" for t in (0.5, 1.0, 2.0)))
for k in sorted(LOGITS_A, key=lambda k: -LOGITS_A[k]):
    row = "".join(f"{softmax(LOGITS_A, t)[k]:>10.4f}" for t in (0.5, 1.0, 2.0))
    print(f"  {k:<8}{row}")
print("  ↑ T 越小：分布越尖锐（有把握的 token 概率更高）")
print("    T 越大：分布越平坦（冷门 token 也有机会）")

print("\n=== 3. T→0 会变成 argmax 吗？（数学上会，工程上不一定）===")
for t in (0.5, 0.1, 0.01):
    p = softmax(LOGITS_A, t)
    top = max(p, key=p.get)
    print(f"  T={t:<5} 最高概率 token={top:<6} p={p[top]:.6f}")
print("  ↑ 数学上 T→0 收敛到 argmax；但真实服务还有浮点非确定性、批处理、")
print("    推测解码等工程因素——这正是实测中 T=0 也不保证复现的原因")

print("\n=== 4. top_p 核采样：砍掉长尾 ===")
print("  场景 A（分布尖锐）：")
for tp in (0.9, 0.95):
    keep = top_p_filter(base, tp)
    print(f"    top_p={tp}: 保留 {keep}（{len(keep)}/{len(base)} 个候选）")
print("  场景 B（分布平坦）：")
pb = softmax(LOGITS_B)
for tp in (0.5, 0.9):
    keep = top_p_filter(pb, tp)
    print(f"    top_p={tp}: 保留 {keep}（{len(keep)}/{len(pb)} 个候选）")
print("  ↑ 分布越平，top_p 砍掉的越多；分布越尖，top_p 几乎不生效")

print("\n=== 5. 抽样：最有把握的答案不一定被选中 ===")
print("  场景 A（有把握，T=1.0）：")
pa = softmax(LOGITS_A, 1.0)
fa = sample(pa)
ta = max(pa, key=pa.get)
print(f"    「{ta}」理论 {pa[ta]:.4f}，实测抽中 {fa[ta]:.4f}，跑偏 {1 - fa[ta]:.4f}")

print("  场景 B（没把握，T=1.0）：")
fb = sample(pb)
tb = max(pb, key=pb.get)
print(f"    「{tb}」理论 {pb[tb]:.4f}，实测抽中 {fb[tb]:.4f}，跑偏 {1 - fb[tb]:.4f}")
print(f"    各 token 实测频率：{[f'{k}={fb[k]:.3f}' for k in fb]}")
print("  ↑ 场景 B 里「最有把握」的只占约 1/4——多数时候选的是别的")
print("    这就是同一个问题每次答案不同的根源")

print("\n=== 6. 一步偏差如何滚成完全不同的答案 ===")
print("  自回归：第 1 个 token 选岔 → 后续每个 token 的分布都跟着变")
print("  实测：temperature=0.9 问 3 次「什么是采样」，得到 3 种不同表述（见 l5-sampling-lab.py）")
print("  到第 20 个 token 时，三者已经完全没有共同前缀之外的关系了")
