"""课 7 异步版：动态客户端

课 7（同步）的五个硬结论在异步下的实测裁定（2026-09-29）：

| 项 | 同步版（课 7） | 异步版（本课） | 判定 |
|----|---------------|---------------|------|
| 构造 DynamicClient | 直接用 | **必须 await / async with** | 🚨 新坑 |
| resources.get | 普通方法 | **coroutine，必须 await** | 🚨 新坑 |
| 只给 api_version | ResourceNotUniqueError | 同 | ✓ 一致 |
| kind 写错 | ResourceNotFoundError | 同 | ✓ 一致 |
| patch 不传 content_type | DynamicApiError **415** | **静默返回 415 Status** | 🚨 更危险 |
| watch 参数名 | timeout_seconds → TypeError | **timeout** → TypeError | 🚨 换名 |
| 多协程共用 | N/A | 40 次并发 0 失败 | ✓ 安全 |

本文件给出：
  1. safe_patch —— 把异步版的静默 415 变成显式异常（核心交付）
  2. async_dyn_client —— 正确初始化 DynamicClient 的上下文管理器
  3. dyn_watch_async —— 正确参数名的 watch 封装
  4. 完整 CRUD 异步封装
"""

import asyncio
from contextlib import asynccontextmanager

from kubernetes_asyncio.client import ApiClient
from kubernetes_asyncio.dynamic import DynamicClient
from kubernetes_asyncio.dynamic.exceptions import (
    ResourceNotFoundError, ResourceNotUniqueError)


# ---------------------------------------------------------------- 异常

class DynamicApiErrorAsync(Exception):
    """把异步版"静默返回 415 Status"提升为显式异常

    🚨 这是本课最核心的交付。

    异步版 DynamicClient.patch 在 content_type 不对时：
      - 同步版：抛 DynamicApiError(415)
      - 异步版：**返回** 一个 ResourceInstance[Status]，code=415
        → `.spec` 为 None → 后续 `.spec.n` 报 AttributeError
        → 或更糟：你以为成功，实际**改动静默丢失**

    实测（2026-09-29）：
      返回值 = ResourceInstance[Status]:
        code: 415
        message: 'the body of the request was in an unknown format ...'
        reason: UnsupportedMediaType
        status: Failure
      读回 spec.n = 1   (!! 改动丢失)
    """

    def __init__(self, status_obj):
        self.code = getattr(status_obj, "code", None)
        self.reason = getattr(status_obj, "reason", None)
        self.message = getattr(status_obj, "message", "")
        super().__init__(f"[{self.code}] {self.reason}: {self.message}")


# ---------------------------------------------------------------- 工具

def is_status(obj):
    """判断 ResourceInstance 是否为 Status（而非真实资源）

    判据：kind == 'Status' 且 status in ('Failure','Success')
    不能只看有没有 code —— 有些资源对象也可能带 code 字段。
    """
    if obj is None:
        return False
    try:
        kind = getattr(obj, "kind", None)
    except Exception:
        return False
    if kind != "Status":
        return False
    st = getattr(obj, "status", None)
    return st in ("Failure", "Success")


def raise_if_status(obj):
    """若返回的是 Status 则抛异常，否则原样返回"""
    if is_status(obj):
        raise DynamicApiErrorAsync(obj)
    return obj


# ---------------------------------------------------------------- 初始化

@asynccontextmanager
async def async_dyn_client(api_client=None, **kw):
    """正确初始化的 DynamicClient

    🚨 异步版独有：直接 `DynamicClient(api)` 后访问 `.resources` 会
       RuntimeError: Discoverer is not initialized

    两种正确写法：
        dyn = await DynamicClient(api)
        async with DynamicClient(api) as dyn:   ← 本函数用它
    """
    if api_client is None:
        api_client = ApiClient()
    async with DynamicClient(api_client, **kw) as dyn:
        yield dyn


async def get_resource(dyn, api_version, kind):
    """await 版 resources.get（异步下它是 coroutine）

    🚨 忘了 await 会得到 coroutine 对象，且**不报错**，
       直到你访问 .name 才 AttributeError。
       实测：AttributeError: 'coroutine' object has no attribute 'name'
             + RuntimeWarning: coroutine 'Discoverer.get' was never awaited
    """
    return await dyn.resources.get(api_version=api_version, kind=kind)


# ---------------------------------------------------------------- CRUD

async def dyn_create(dyn, resource, body, namespace=None):
    r = await dyn.create(resource, body=body, namespace=namespace)
    return raise_if_status(r)


async def dyn_get(dyn, resource, name, namespace=None):
    r = await dyn.get(resource, name=name, namespace=namespace)
    return raise_if_status(r)


async def safe_patch(dyn, resource, name, body, namespace=None,
                     content_type="application/merge-patch+json", **kw):
    """带 415 防护的 patch（本课核心）

    与裸 `dyn.patch` 的差别：
      裸调用：415 时**静默返回 Status** → 改动丢失，无异常，无日志
      safe_patch：415 时**抛 DynamicApiErrorAsync** → 立刻暴露

    默认 content_type 用 merge-patch 而不是库的默认 strategic-merge-patch，
    因为 **CRD 不支持 strategic-merge-patch**（实测 415）。
    """
    r = await dyn.patch(resource, name=name, namespace=namespace,
                        body=body, content_type=content_type, **kw)
    return raise_if_status(r)


async def dyn_replace(dyn, resource, name, body, namespace=None):
    r = await dyn.replace(resource, name=name, namespace=namespace, body=body)
    return raise_if_status(r)


async def safe_apply(dyn, resource, body, name=None, namespace=None,
                     field_manager="pyclient", force_conflicts=False,
                     **kw):
    """带 Status 防护的 Server-Side Apply（课 7 §4.5 的异步等价）

    异步版**有** `server_side_apply`，签名与同步版一致：
        (resource, body=None, name=None, namespace=None,
         force_conflicts=None, **kwargs)

    实测（2026-09-29）：
      - 基本可用：managedFields 出现 operation=Apply ✓
      - **同样静默返回 Status**（缺 apiVersion/kind → 400；
        非法字段 → 500；缺 field_manager → 422）
        → 所以也需要 raise_if_status 防护
      - 幂等：同 body 重复 apply，resourceVersion 不变 ✓
      - 冲突：跨 manager 改同一字段 → 409 Conflict（Status 形式返回）
        force_conflicts=True 可强制抢占

    ⚠️ SSA 的字段归属语义（实测确认，与标准一致）：
      - 别的管理器持有的字段 → 你只提交自己的，他的**保留**
      - **你自己**持有的字段 → 你这次不提交，就被**删除**
      （"声明式"意味着你的 body 就是你对这份资源的完整声明）
    """
    r = await dyn.server_side_apply(
        resource, body=body, name=name, namespace=namespace,
        field_manager=field_manager, force_conflicts=force_conflicts, **kw)
    return raise_if_status(r)


async def dyn_delete(dyn, resource, name, namespace=None, **kw):
    r = await dyn.delete(resource, name=name, namespace=namespace, **kw)
    # delete 正常返回 Status(Success)，这里不当错误处理
    return r


async def dyn_list(dyn, resource, namespace=None, **kw):
    r = await dyn.get(resource, namespace=namespace, **kw)
    return raise_if_status(r)


# ---------------------------------------------------------------- watch

async def dyn_watch(dyn, resource, namespace=None, timeout=60, **kw):
    """异步 watch 的生成器封装

    🚨 参数名是 `timeout` 不是 `timeout_seconds`。
       传错会 TypeError（实测已复现），这个错是**显式**的，好排查。
    """
    async for event in dyn.watch(resource, namespace=namespace,
                                 timeout=timeout, **kw):
        yield event


# ---------------------------------------------------------------- 并发

async def concurrent_get(dyn, resource, names, namespace=None,
                         max_concurrency=8):
    """并发批量读取（异步版相对同步版的核心优势）

    实测：8 协程 × 5 次 = 40 次并发 get，0 失败，耗时 0.030s
    → 单个 DynamicClient 可被多协程安全共用（底層 aiohttp 连接池）
    """
    sem = asyncio.Semaphore(max_concurrency)

    async def one(n):
        async with sem:
            try:
                r = await dyn_get(dyn, resource, n, namespace)
                return n, r, None
            except Exception as e:
                return n, None, e

    return await asyncio.gather(*[one(n) for n in names])
