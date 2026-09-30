import importlib, subprocess, sys, os

VENV = "/mnt/d/projects/learning/k8s/子教程/Python客户端专项/.venv"

print("=== python ===")
print(sys.version)

print("\n=== 已安装包（含 async / aiohttp / kubernetes） ===")
try:
    out = subprocess.run([os.path.join(VENV, "bin", "pip"), "list"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        if any(k in line.lower() for k in ("async", "aiohttp", "kubernetes", "certifi", "urllib3")):
            print(" ", line)
except Exception as e:
    print("pip list 失败:", e)

print("\n=== 同步库 kubernetes ===")
try:
    import kubernetes
    print("  version =", kubernetes.__version__)
    print("  path    =", kubernetes.__file__)
    print("  有 aio 子模块? ", end="")
    try:
        import kubernetes.aio
        print("是 ->", kubernetes.aio.__file__)
    except Exception as e:
        print("否 (", type(e).__name__, ":", e, ")")
except Exception as e:
    print("  未安装:", e)

print("\n=== 异步包 kubernetes_asyncio ===")
try:
    import kubernetes_asyncio as ka
    print("  version =", getattr(ka, "__version__", "?"))
    print("  path    =", ka.__file__)
except Exception as e:
    print("  未安装:", type(e).__name__, ":", e)
