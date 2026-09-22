"""课 3 实操：用字符级 n-gram 复现"猜下一个词"的训练机制。纯标准库，本机实测。

注意：这不是 Transformer，是极简复现。两者机制同源——都靠"从数据里学下一个单元的概率分布"，
但规模差着十几个数量级。用它来观察机制，不用来推断 LLM 的具体表现。
"""
import math
import os
import random
from collections import defaultdict

random.seed(42)

HERE = os.path.dirname(os.path.abspath(__file__))
with open(os.path.join(HERE, "l3-corpus-big.txt"), encoding="utf-8") as f:
    RAW = f.read()

# 去空白，只留字符流——模型看到的就只有这一串字符，没有任何标签
TEXT = "".join(ch for ch in RAW if not ch.isspace())
VOCAB = sorted(set(TEXT))

print("=== 0. 语料：没有任何人工标注 ===")
print(f"  字符数：{len(TEXT)}")
print(f"  不同字符数（词表）：{len(VOCAB)}")
print(f"  开头 40 字：{TEXT[:40]}")


def build(text, order):
    """统计 order 元组 -> 下一个字符 的频次。这就是"学习"，没有别的动作。"""
    m = defaultdict(lambda: defaultdict(int))
    for i in range(len(text) - order + 1):
        m[text[i:i + order - 1]][text[i + order - 1]] += 1
    return m


def make_prob(models, vocab):
    """三阶插值 + 加一平滑：三元组不够用就退到二元组、一元组。"""

    def prob(ch, ctx):
        p, w = 0.0, {3: 0.6, 2: 0.3, 1: 0.1}
        for o in (3, 2, 1):
            c = "" if o == 1 else ctx[-(o - 1):]
            d = models[o].get(c, {})
            total = sum(d.values())
            p += w[o] * (d.get(ch, 0) + 0.1) / (total + 0.1 * len(vocab))
        return p

    return prob


def gen(prob, ctx, length=80):
    out = list(ctx)
    cands = sorted(VOCAB)
    for _ in range(length):
        ps = [prob(ch, "".join(out)) for ch in cands]
        r, acc = random.random() * sum(ps), 0.0
        for ch, p in zip(cands, ps):
            acc += p
            if acc >= r:
                break
        out.append(ch)
    return "".join(out)


def perplexity(prob, text):
    """困惑度：越低说明越"猜得准"。等价于交叉熵损失的指数。"""
    nll, n = 0.0, 0
    for i in range(len(text) - 1):
        nll -= math.log(prob(text[i + 1], text[:i + 1]))
        n += 1
    return math.exp(nll / n)


# 切分：前 90% 训练，后 10% 当验证集（验证集全程不参与训练）
split = int(len(TEXT) * 0.9)
TRAIN, VAL = TEXT[:split], TEXT[split:]

print(f"\n=== 1. 规模直觉：数据量 vs 困惑度（验证集 {len(VAL)} 字，未参与训练）===")
print(f"  {'训练数据量':<12}{'占全文':<10}{'验证集困惑度':<14}")
for frac in (0.1, 0.25, 0.5, 0.75, 1.0):
    sub = TRAIN[:int(len(TRAIN) * frac)]
    models = {o: build(sub, o) for o in (1, 2, 3)}
    p = make_prob(models, VOCAB)
    ppl = perplexity(p, VAL)
    print(f"  {len(sub):<12}{frac:<10.0%}{ppl:<14.2f}")

# 用全量训练的模型做后续演示
MODELS = {o: build(TRAIN, o) for o in (1, 2, 3)}
prob = make_prob(MODELS, VOCAB)

print("\n=== 2. 只学「猜下一个字」，它学到了结构吗？ ===")
for seed in ["云枢科技", "员工手册", "数据质量"]:
    print(f"  [{seed}] → {gen(prob, seed, 60)}")

print("\n=== 3. 它是续写机，不是助手（问它问题会怎样）===")
q = "年假有几天？"
print(f"  输入：{q}")
print(f"  输出：{gen(prob, q, 60)}")
print("  ↑ 语料里没有问号、没有问答对，它只会接着「写下去」，不会「回答」")

print("\n=== 4. 知识截止：语料里没有的事，它会怎么办 ===")
absent = "公司的年度旅游目的地是"
print(f"  输入：{absent}（语料中从未出现）")
print(f"  输出：{gen(prob, absent, 40)}")
print("  ↑ 照样接得通顺、自信——这就是幻觉的雏形：不是查不到就说不知道，而是接着编")

print("\n=== 5. 有损压缩：它存不下原文 ===")
seed = TEXT[100:130]
rebuilt = gen(prob, seed, 30)
print(f"  原文：{TEXT[100:160]}")
print(f"  复现：{rebuilt}")
same = sum(a == b for a, b in zip(TEXT[130:160], rebuilt[30:]))
print(f"  后 30 字与原文字面一致：{same}/30")
print("  ↑ 读起来像，但逐字对不上——存的印象，不是副本")
