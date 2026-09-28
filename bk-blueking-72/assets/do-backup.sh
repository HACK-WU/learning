#!/usr/bin/env bash
set -e
TS=$(date +%Y%m%d-%H%M%S)
SRC=/root/bk72/install/blueking
DST=/root/bk72/config-backup-$TS
mkdir -p "$DST"
cp -a "$SRC" "$DST"/blueking
cd /root/bk72/install
tar czf "$DST".tar.gz -C /root/bk72 "config-backup-$TS"
echo "BACKUP_DIR=$DST"
echo "BACKUP_TAR=$DST.tar.gz"
echo "SIZE=$(du -sh "$DST".tar.gz | cut -f1)"
echo "FILE_COUNT=$(find "$DST" -type f | wc -l)"
ls -1 /root/bk72/ | grep config-backup | sed 's/^/  /'
