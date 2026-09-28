#!/usr/bin/env bash
TS=${1:-}
if [ -z "$TS" ]; then
  TS=$(ls -1 /root/bk72/ | grep -E '^config-backup-[0-9]{8}-[0-9]{6}$' | sort | tail -1 | sed 's/config-backup-//')
fi
echo "USING_TS=$TS"
W=/mnt/d/projects/learning/bk-blueking-72/assets/config-backup
mkdir -p "$W"
rm -rf "$W"/blueking
cp -a "/root/bk72/config-backup-$TS/blueking" "$W"/
cp -a "/root/bk72/config-backup-$TS.tar.gz" "$W"/ 2>/dev/null
echo "WORKSPACE_BACKUP=$W"
echo "FILES=$(find "$W" -type f | wc -l)"
echo ""
echo "=== 关键配置文件校验（必须存在） ==="
for f in blueking/base-blueking.yaml.gotmpl \
         blueking/monitor.yaml.gotmpl \
         blueking/04-bkmonitor.yaml.gotmpl \
         blueking/monitor-storage.yaml.gotmpl \
         blueking/base-storage.yaml.gotmpl \
         blueking/env.yaml \
         blueking/environments/default/version.yaml; do
  if [ -f "$W/$f" ]; then echo "  OK   $f  ($(wc -c < "$W/$f") bytes)"
  else echo "  MISS $f"; fi
done
