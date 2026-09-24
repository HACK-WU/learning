"""课 3：确认 aiokafka 到底有没有 AdminClient（上一版 dir(aiokafka) 查不到）。

可能原因：
  1. aiokafka.admin 是子模块，顶层没导出 → 需要 from aiokafka.admin import ...
  2. 真的没有
"""
print("=== 1. 直接尝试 from aiokafka.admin import ===")
try:
    from aiokafka.admin import AIOKafkaAdminClient

    print(f"  ✓ AIOKafkaAdminClient 存在: {AIOKafkaAdminClient}")
except ImportError as e:
    print(f"  ✗ ImportError: {e}")

print("\n=== 2. 看 aiokafka.admin 模块有哪些公开类 ===")
try:
    import aiokafka.admin as adm

    names = [n for n in dir(adm) if n[0].isupper()]
    print(f"  {names}")
except ImportError as e:
    print(f"  模块不存在: {e}")

print("\n=== 3. 看 aiokafka.__init__ 显式导出了什么 ===")
import aiokafka

print(f"  __all__ = {getattr(aiokafka, '__all__', '（无 __all__）')}")
print(f"  公开名: {[n for n in dir(aiokafka) if n[0].isupper()]}")

print("\n=== 4. 包目录里有没有 admin 文件 ===")
import os

p = os.path.dirname(aiokafka.__file__)
print(f"  包路径: {p}")
try:
    print(f"  顶层文件: {sorted(os.listdir(p))}")
    if os.path.isdir(os.path.join(p, "admin")):
        print(f"  admin/ 内容: {sorted(os.listdir(os.path.join(p, 'admin')))}")
except Exception as e:
    print(f"  {e}")

print("\n=== 5. 若有 AIOKafkaAdminClient：它的能力和两库比如何 ===")
try:
    from aiokafka.admin import AIOKafkaAdminClient

    APIS = ["create_topics", "delete_topics", "list_topics",
            "describe_topics", "list_consumer_groups",
            "list_consumer_group_offsets", "describe_consumer_groups",
            "create_partitions", "describe_configs", "alter_configs"]
    present = [a for a in APIS if hasattr(AIOKafkaAdminClient, a)]
    absent = [a for a in APIS if a not in present]
    print(f"  存在: {present}")
    print(f"  缺失: {absent}")
    print(f"  （aiokafka 是 async，方法需 await）")
except Exception as e:
    print(f"  无法比对: {type(e).__name__}: {e}")
