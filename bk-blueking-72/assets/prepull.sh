#!/usr/bin/env bash
LOG=/tmp/prepull2.log
: > "$LOG"

while read -r img; do
  [ -z "$img" ] && continue
  for attempt in 1 2 3; do
    if timeout 300 docker pull "$img" >> "$LOG" 2>&1; then
      echo "OK   $img (第${attempt}次)"
      break
    else
      if [ $attempt -eq 3 ]; then
        echo "FAIL $img (3次均失败)"
      fi
    fi
  done
done < /tmp/imglist.txt

echo "=== 完成 $(date '+%H:%M:%S') ==="
echo "本地 bk-lite 镜像数: $(docker images --format '{{.Repository}}' | grep -c bk-lite)"
