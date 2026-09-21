#!/usr/bin/env bash
R=/mnt/d/projects/learning/consul
P="$R/01-学习路径总览.md"
python3 - <<PYEOF
p = "$P"
s = open(p, encoding='utf-8').read()
old = "｜**进度：课 4 / 8 已交付（课 1、2、3、6）**"
new = "｜**进度：课 6 / 8 已交付（课 1、2、3、4、5、6）**"
if old in s:
    s = s.replace(old, new)
    # 在课3后插入课4、课5链接
    anchor = "[课 3 性能、容量与调优](子教程/运维专项/lessons/lesson-03-性能、容量与调优.md)"
    add = anchor + "、[课 4 证书与密钥生命周期](子教程/运维专项/lessons/lesson-04-证书与密钥生命周期.md)、[课 5 备份、恢复与灾备演练](子教程/运维专项/lessons/lesson-05-备份、恢复与灾备演练.md)"
    s = s.replace(anchor, add)
    open(p, 'w', encoding='utf-8').write(s)
    print("  ✅ 已更新路径总览")
else:
    print("  ❌ 未匹配到进度锚点")
PYEOF
echo
echo "===== 确认 ====="
grep -o '进度：课 [0-9] / 8 已交付（[^）]*）' "$P" | sed 's/^/  /'
