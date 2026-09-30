# devel（Kubernetes Python Client · 共 9 条）

> 范围：`devel/` 目录（仓库内专题说明）+ 文档构建 · 生成日期：2026-09-21
> 这一分区是**仓库里唯一成篇的专题讲解**，讲义写 patch / 调试日志时应优先参考

| 我要… | 去哪一页 | 锚点 | 关键词 | 相关 |
|-------|----------|------|--------|------|
| 搞清 Kubernetes 四种 patch 的区别与 Python 写法 | [devel/patch_types.md](https://github.com/kubernetes-client/python/blob/master/devel/patch_types.md) | | patch、JSON merge、strategic merge、JSON patch、server-side apply | [patch_namespaced_config_map.py](https://github.com/kubernetes-client/python/blob/master/examples/patch_namespaced_config_map.py) |
| 理解 JSON Merge Patch（合并语义、列表整体替换） | [devel/patch_types.md · 1. JSON Merge Patch](https://github.com/kubernetes-client/python/blob/master/devel/patch_types.md) | #1-json-merge-patch | merge patch、合并、content_type | |
| 理解 Strategic Merge Patch（按 patchStrategy 智能合并列表） | [devel/patch_types.md · 2. Strategic Merge Patch](https://github.com/kubernetes-client/python/blob/master/devel/patch_types.md) | #2-strategic-merge-patch | strategic merge、patchStrategy、列表合并 | |
| 理解 JSON Patch（RFC 6902 操作数组） | [devel/patch_types.md · 3. JSON Patch](https://github.com/kubernetes-client/python/blob/master/devel/patch_types.md) | #3-json-patch | JSON patch、RFC 6902、add/remove/replace | |
| 理解 Apply Patch / Server-Side Apply（field_manager 归属） | [devel/patch_types.md · 4. Apply Patch](https://github.com/kubernetes-client/python/blob/master/devel/patch_types.md) | #4-apply-patch-server-side-apply | server-side apply、SSA、field_manager、apply | [apply_from_dict.py](https://github.com/kubernetes-client/python/blob/master/examples/apply_from_dict.py) |
| 打开调试日志、看客户端实际发出的 HTTP 请求 | [devel/debug_logging.md](https://github.com/kubernetes-client/python/blob/master/devel/debug_logging.md) | | 调试日志、排障、HTTP、urllib3 | [enable_debug_logging.py](https://github.com/kubernetes-client/python/blob/master/examples/enable_debug_logging.py) |
| 了解客户端的发布流程与版本号规则 | [devel/release.md](https://github.com/kubernetes-client/python/blob/master/devel/release.md) | | 发布、版本号、release | |
| 看客户端的统计/指标埋点约定 | [devel/stats.md](https://github.com/kubernetes-client/python/blob/master/devel/stats.md) | | stats、指标、埋点 | |
| 本地构建 Sphinx 文档（离线看完整 API 参考） | [doc/README.md](https://github.com/kubernetes-client/python/blob/master/doc/README.md) | | 文档构建、Sphinx、make html | |
