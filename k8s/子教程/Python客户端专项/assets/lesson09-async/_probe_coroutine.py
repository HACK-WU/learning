"""探针：为什么 iscoroutinefunction 对 CoreV1Api 方法返回 0？

课 9 结论「412 个方法完全同名」用 dir() 得出。
本课用 inspect.iscoroutinefunction 复查得「协程方法数 = 0」，明显反常
（异步 API 明明可 await）。先核验测法，再解释现象。
"""
import inspect

from kubernetes_asyncio import client as aclient

TARGET = "list_namespaced_pod"


def main():
    cls = aclient.CoreV1Api

    print("=== 1. 类上能不能拿到这个方法？ ===")
    attr = getattr(cls, TARGET, None)
    print(f"getattr(cls, '{TARGET}') =", attr)
    print("type              =", type(attr))
    print("iscoroutinefn     =", inspect.iscoroutinefunction(attr))
    print("iscoroutine       =", inspect.iscoroutine(attr))
    print("isfunction        =", inspect.isfunction(attr))
    print("ismethod          =", inspect.ismethod(attr))

    print()
    print("=== 2. 类 __dict__ 里有没有它？ ===")
    print(f"'{TARGET}' in cls.__dict__ :", TARGET in cls.__dict__)
    print("cls.__dict__ 键数        :", len(cls.__dict__))
    sample = [k for k in cls.__dict__ if not k.startswith("__")][:12]
    print("__dict__ 非 dunder 样本  :", sample)

    print()
    print("=== 3. 是不是 __getattr__ 动态造的？ ===")
    has_getattr = any("__getattr__" in c.__dict__ for c in cls.__mro__)
    print("MRO 中定义 __getattr__ 的类:",
          [c.__name__ for c in cls.__mro__ if "__getattr__" in c.__dict__])
    print("MRO                        :", [c.__name__ for c in cls.__mro__])

    print()
    print("=== 4. 那 dir() 的 412 个名字从哪来？ ===")
    names = dir(cls)
    in_dict = [n for n in names if n in cls.__dict__]
    print("dir 总数            :", len(names))
    print("其中在本类 __dict__ :", len(in_dict))
    not_in_dict = [n for n in names if n not in cls.__dict__][:15]
    print("不在 __dict__ 的样本:", not_in_dict)

    print()
    print("=== 5. 实例化后再看（关键）===")
    inst = cls(api_client=None)
    a2 = getattr(inst, TARGET, None)
    print("实例上 type      =", type(a2))
    print("实例上 iscoro fn =", inspect.iscoroutinefunction(a2))
    print("实例上 ismethod  =", inspect.ismethod(a2))

    # 统计实例上的协程方法数
    coros = []
    for n in dir(inst):
        if n.startswith("_"):
            continue
        v = getattr(inst, n, None)
        if inspect.iscoroutinefunction(v):
            coros.append(n)
    print("实例上协程方法数 :", len(coros))
    print("样本             :", coros[:8])

    print()
    print("=== 6. 源码位置 ===")
    try:
        f = getattr(inst, TARGET)
        print("__func__.__qualname__:", getattr(f, "__qualname__", None))
        print("__func__ module      :", getattr(f, "__module__", None))
        src_file = inspect.getsourcefile(getattr(f, "__func__", f))
        print("source file          :", src_file)
    except Exception as e:
        print("取源码失败:", type(e).__name__, e)


if __name__ == "__main__":
    main()
