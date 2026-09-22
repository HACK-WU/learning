"""课 4 实操：用"后训练数据"改造课 3 的续写机。纯标准库，本机实测。

方法论要点（避免数据泄漏）：
- 预训练语料 PRE 切成 TRAIN(90%) / VAL(10%)，VAL 两个模型都不许看
- 模型 A：只在 PRE_TRAIN 上训
- 模型 B：在 PRE_TRAIN + SFT 上训（模拟"在预训练权重上继续后训练"）
- 评测在 VAL 上做，两边公平
"""
import math
import os
import random
from collections import defaultdict

random.seed(42)
HERE = os.path.dirname(os.path.abspath(__file__))

with open(os.path.join(HERE, "l3-corpus-big.txt"), encoding="utf-8") as f:
    PRE = "".join(ch for ch in f.read() if not ch.isspace())

# --- 后训练数据：人写好的"问答示范"，这就是 SFT 的核心 ---
QA = [
    ("年假有几天？", "员工入职满一年后可享受十天年假。"),
    ("年假需要提前多久申请？", "需提前三个工作日在系统中提交申请，由直属主管审批。"),
    ("年假可以延期吗？", "原则上应在当年使用完毕，最多可延期至次年三月三十一日。"),
    ("出差住宿标准是多少？", "一线城市每晚五百元，其他城市每晚三百五十元。"),
    ("市内交通费怎么报？", "报销标准为每天八十元，需提供有效票据。"),
    ("客服热线是多少？", "四零零八二零一二三四。"),
    ("客服工作时间？", "周一至周五九点至十八点。"),
    ("技术支持多久响应？", "响应时间承诺为两个工作小时以内。"),
    ("公司成立于哪一年？", "云枢科技成立于二零一八年。"),
    ("公司总部在哪里？", "总部位于杭州。"),
    ("数据中台有哪些模块？", "核心模块包括数据接入、元数据管理、任务调度与数据质量监控。"),
    ("绩效考核多久一次？", "每半年进行一次。"),
    ("考核有哪些维度？", "包括交付质量、协作效率与技术成长。"),
    ("新员工培训多久？", "入职培训为期两周。"),
    ("导师制度持续多久？", "导师制度持续六个月。"),
    ("版本多久发布一次？", "每个季度末会进行一次版本发布。"),
    ("研发团队有哪些组？", "下设平台组、算法组和前端组。"),
    ("平台组负责什么？", "负责调度引擎与存储层。"),
    ("算法组负责什么？", "负责数据质量与血缘推断。"),
    ("前端组负责什么？", "负责控制台与可视化。"),
]
REPEAT = 6
SFT = "".join(f"问：{q}答：{a}" for q, a in QA * REPEAT)

# 关键：切分后 VAL 两个模型都不参与训练
split = int(len(PRE) * 0.9)
PRE_TRAIN, VAL = PRE[:split], PRE[split:]

VOCAB = sorted(set(PRE + SFT))


def build(text, order):
    m = defaultdict(lambda: defaultdict(int))
    for i in range(len(text) - order + 1):
        m[text[i:i + order - 1]][text[i + order - 1]] += 1
    return m


def make_prob(models, vocab, w=None):
    w = w or {3: 0.6, 2: 0.3, 1: 0.1}

    def prob(ch, ctx):
        p = 0.0
        for o in models:
            c = "" if o == 1 else ctx[-(o - 1):]
            d = models[o].get(c, {})
            tot = sum(d.values())
            p += w[o] * (d.get(ch, 0) + 0.1) / (tot + 0.1 * len(vocab))
        return p

    return prob


def gen(prob, ctx, stop="。", maxlen=200):
    out = list(ctx)
    cands = sorted(VOCAB)
    for _ in range(maxlen):
        ps = [prob(ch, "".join(out)) for ch in cands]
        r, acc = random.random() * sum(ps), 0.0
        pick = cands[-1]
        for ch, p in zip(cands, ps):
            acc += p
            if acc >= r:
                pick = ch
                break
        out.append(pick)
        if pick == stop and len(out) > len(ctx) + 5:
            break
    return "".join(out)


def perplexity(prob, text):
    nll, n = 0.0, 0
    for i in range(len(text) - 1):
        nll -= math.log(prob(text[i + 1], text[:i + 1]))
        n += 1
    return math.exp(nll / n)


print("=== 0. 数据量对比：后训练远小于预训练 ===")
print(f"  预训练语料：{len(PRE_TRAIN):>7} 字符")
print(f"  后训练语料：{len(SFT):>7} 字符（{len(QA)} 条问答 × {REPEAT} 次重复）")
print(f"  后训练 / 预训练 = {len(SFT) / len(PRE_TRAIN):.1%}")
print(f"  验证集：{len(VAL)} 字符（两个模型均未参与训练）")

pA = make_prob({o: build(PRE_TRAIN, o) for o in (1, 2, 3)}, VOCAB)
pB = make_prob({o: build(PRE_TRAIN + SFT, o) for o in (1, 2, 3)}, VOCAB)

PROMPT = "问：{}答："
print("\n=== 1. 行为对比：同一个问题，两个模型 ===")
for q in ["年假有几天？", "客服热线是多少？", "公司总部在哪里？"]:
    cut = len(PROMPT.format(q))
    print(f"\n  问题：{q}")
    print(f"    仅预训练：{gen(pA, PROMPT.format(q))[cut:][:55]}")
    print(f"    后训练后：{gen(pB, PROMPT.format(q))[cut:][:55]}")

print("\n=== 2. 对齐税：在原始续写任务上，谁更好？ ===")
pa, pb = perplexity(pA, VAL), perplexity(pB, VAL)
print(f"  验证集（纯预训练风格文本）困惑度：")
print(f"    仅预训练：{pa:.2f}")
print(f"    后训练后：{pb:.2f}")
if pb > pa:
    print(f"  → 后训练后变差 {pb - pa:+.2f}（困惑度越低越好）——这就是对齐税")
else:
    print(f"  → 后训练后反而变好 {pb - pa:+.2f}：本实验未复现对齐税")
    print("    原因：后训练语料与预训练语料同域、且体量太小，不足以产生能力挤占")

print("\n=== 3. 后训练数据上的表现（它「学会」的正是这些）===")
qa_text = "".join(f"问：{q}答：{a}" for q, a in QA)
print(f"  问答对困惑度：仅预训练 {perplexity(pA, qa_text):.2f} → 后训练后 {perplexity(pB, qa_text):.2f}")
print("  ↑ 大幅下降 = 确实学会了问答格式。注意这是训练时见过的格式")

print("\n=== 4. 知识量变了吗？问一个两边都没教过的 ===")
unk = "公司明年会上市吗？"
cut = len(PROMPT.format(unk))
print(f"  问题：{unk}（语料中从未出现）")
print(f"    仅预训练：{gen(pA, PROMPT.format(unk))[cut:][:55]}")
print(f"    后训练后：{gen(pB, PROMPT.format(unk))[cut:][:55]}")
print("  ↑ 两个都不知道，但后训练后依然会「编一个像模像样的回答」")
print("     对齐教会了它「怎么答」，没教会它「不知道就别说」")
