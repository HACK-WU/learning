"""课 2 实操：token / 自回归 / 中英文成本对比。全部数值为本机实测。"""
import tiktoken

enc = tiktoken.get_encoding("cl100k_base")

print("=== 1. 分词：模型看到的不是字母 ===")
for text in ["strawberry", " berry", "rr", "r"]:
    ids = enc.encode(text)
    pieces = [enc.decode([i]) for i in ids]
    print(f"  {text!r:14} -> {len(ids)} token  {pieces}")

print("\n=== 2. 自回归：一个一个接上去 ===")
prompt = "The capital of France is"
ids = enc.encode(prompt)
print(f"  prompt: {ids}")
for nxt in [5907, 1029, 11]:
    print(f"  + {nxt:5} -> {enc.decode(ids + [nxt])!r}")

print("\n=== 3. 中英文 token 成本对比 ===")
pairs = [
    ("人工智能正在改变世界", "AI is changing the world"),
    ("请总结这份文档的核心观点", "Summarize the key points of this document"),
]
for zh, en in pairs:
    z, e = len(enc.encode(zh)), len(enc.encode(en))
    print(f"  中: {len(zh):2d} 字 -> {z:2d} token ｜ 英: {len(en):2d} 字符 -> {e:2d} token")

print("\n=== 4. 数一数你的 prompt 要花多少 token ===")
my_prompt = "你是一个资深的 Java 工程师，请帮我 review 这段代码，指出潜在的并发问题。"
n = len(enc.encode(my_prompt))
print(f"  {len(my_prompt)} 个字符 -> {n} token")
print(f"  按 $0.15/1M 输入 token 估算：${n / 1_000_000 * 0.15:.8f}")
