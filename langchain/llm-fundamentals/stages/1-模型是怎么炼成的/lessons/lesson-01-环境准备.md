# 课 1：环境准备

> 本课采用**直述模式**：环境准备是参考性内容，学习目标是"装好能跑"，没有认知冲突可设，硬套五幕反而干扰查阅。
> **已有环境可跳过**：若你已跟完 [LangChain 主干课程](../../../../langchain/02-课程目录.md)，只需确认 `tiktoken` 可用（见"一、现状确认"），很可能**一步都不用装**。

## 🎯 本课目标

确认一个能跑通本教程全部实操的最小 Python 环境，并验证分词链路可用。

## 一、现状确认（先跑这个，再决定装不装）

本教程**复用主干课程已验证的 `playground/` 环境**，不新建项目目录。先在 `langchain/playground/` 下执行：

```bash
uv run python -c "import tiktoken; print(tiktoken.__version__)"
```

看到版本号即**已就绪，直接进课 2**。

> 本教程在本机实测的环境（2026-09-21）：
> ```
> uv 0.11.11
> Python 3.12.13（由 uv 托管）
> tiktoken 0.14.0
> openai 3.14.0 / langchain-openai 1.6.2
> ```
> `tiktoken` **无需单独安装**——它是 `langchain-openai` / `openai` 的传递依赖，主干装好时就已在里面。

## 二、最小环境集

| 组件 | 版本 | 用途 | 是否已具备 |
|------|------|------|-----------|
| Python | 3.12+ | 运行全部示例 | ✅ uv 托管 3.12.13 |
| uv | 0.11.11 | 依赖与运行管理（有 `uv.lock`） | ✅ |
| tiktoken | 0.14.0 | **本教程核心**：本地分词与 token 计数 | ✅ 传递依赖已带 |
| openai SDK | 3.14.0 | 调 API 验证采样与长上下文 | ✅ 主干已配 |

> **明确不装**：`torch` / `transformers` / `accelerate`。它们数百 MB 到数 GB，本教程不训练、不加载本地权重，装了没有用处。真要本地跑小模型看 logits 时，会在该课首单独征求你同意。

## 三、装法（仅在第一步确认缺失时）

**主路径：补装进主干环境**

```bash
cd ../langchain/playground
uv add tiktoken
```

**备选 A：本教程独立建环境**（不想动主干时）

```bash
cd llm-fundamentals/playground
uv init
uv add tiktoken openai
```

**备选 B：pip + venv（不用 uv 时）**

```bash
python -m venv .venv
.venv\Scripts\activate
pip install tiktoken openai
```

## 四、验证命令与实测输出

> ✅ 以下命令 2026-09-21 本机实测通过（环境见第一节）。

```bash
uv run python -c "import tiktoken; enc = tiktoken.get_encoding('cl100k_base'); print(len(enc.encode('hello world')), enc.encode('hello world'))"
```

实测输出：

```
2 [15339, 1917]
```

模型调用链路验证沿用主干的 `check_connection.py`：

```bash
uv run python check_connection.py
```

## 五、常见坑（本机实测 + 高发）

| 症状 | 原因 | 处理 |
|------|------|------|
| `Python was not found; run without arguments to install from the Microsoft Store` | Windows 装了微软商店的 Python **别名**，裸 `python` 命中的是它 | **用 `uv run python`，不用裸 `python`**。本教程全部命令都带 `uv run` 前缀 |
| 输出中文报 `UnicodeEncodeError: 'gbk' codec` | Windows 控制台默认 GBK，`print` 中文/特殊符号炸 | 命令前加 `$env:PYTHONIOENCODING='utf-8'`（PowerShell），或代码里避免直接 print 生僻符号 |
| `tiktoken` 首次运行卡住 | 首用需联网下载 BPE 词表 | 保证网络可达；或设 `TIKTOKEN_CACHE_DIR` 指定缓存目录 |
| `No module named tiktoken` | 在错误的解释器里执行 | 确认用 `uv run`，或在 `playground/` 目录内执行 |
| API 调用 401 | `.env` 未配置或 key 失效 | 沿用主干 `playground/.env`（参考 `.env.example`） |

> 前两条是本轮**真实踩到**的坑，不是理论清单——Windows 上跑 Python 教学代码，这两条命中率极高。

## 六、安全约定

- API Key 一律走环境变量，只存在于 `playground/.env`（已在 `.gitignore` 中）
- 所有代码示例中的 key 一律写作 `<YOUR_API_KEY>`
- 临时脚本放 `playground/` 下，不散落在教程目录

## ✅ 完成标准

第一节那条命令能输出 `tiktoken` 版本号，即环境就绪，可进入课 2。

---

## 🧭 本课导航

**↩️ 返回**：[阶段 1 概览](../overview.md) ｜ [课程目录](../../../02-课程目录.md)

**➡️ 下一课**：[课 2：语言模型是什么——一个巨大的"下一个词预测器"](../lessons/lesson-02-语言模型是什么.md)

**🗺️ 全局位置**：阶段 1「模型是怎么炼成的」第 1 课（环境准备，无知识点），是为课 2 起全部实操铺路。
