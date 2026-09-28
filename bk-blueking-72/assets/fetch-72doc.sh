#!/usr/bin/env bash
echo "=== 7.2 资源及环境要求 (prepare.md) ==="
timeout 30 curl -sS "https://bk.tencent.com/docs/markdown/ZH/DeploymentGuides/7.2/prepare.md" 2>&1 | head -c 6000
