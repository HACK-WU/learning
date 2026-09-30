"""按行插入进度勾选（避开"整文已存在"的误判）

上一版用整文 `if "课 9 番外" not in text` 判断，被课程表里的同名条目误挡。
改为只在学习进度区块内判断。
"""
import io
import os
import shutil

SUBROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", ".."))
TARGET = os.path.join(SUBROOT, "overview.md")


def main():
    with io.open(TARGET, encoding="utf-8") as f:
        lines = f.readlines()

    # 只在 "- [x] 课 " 开头的进度行里找
    prog_idx = [i for i, l in enumerate(lines) if l.startswith("- [x] 课 ")]
    if not prog_idx:
        print("未找到进度区块")
        return

    already = any("番外：异步三个未实测项" in lines[i] for i in prog_idx)
    if already:
        print("进度已勾选，跳过")
        return

    # 找到 "- [x] 课 9：异步客户端与并发" 这一行
    idx = None
    for i in prog_idx:
        if "课 9：异步客户端与并发" in lines[i]:
            idx = i
            break
    if idx is None:
        print("未找到课 9 进度行")
        return

    print(f"在进度行 {idx+1} 后插入")
    shutil.copyfile(TARGET, TARGET + ".bak4")
    lines.insert(idx + 1,
                 "- [x] 课 9 番外：异步三个未实测项（写共享 · 429 · 重试风暴）\n")
    with io.open(TARGET, "w", encoding="utf-8") as f:
        f.writelines(lines)
    print("完成")
    if os.path.exists(TARGET + ".bak4"):
        os.remove(TARGET + ".bak4")


if __name__ == "__main__":
    main()
