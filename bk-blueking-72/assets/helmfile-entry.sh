#!/usr/bin/env bash
echo "=== HELMFILE ENTRY ==="
ls -la /root/bk72/install/blueking/*.gotmpl 2>&1 | sed 's/^/  /'
echo ""
echo "=== HELM RELEASES (installed) ==="
helm list -n blueking --no-headers 2>/dev/null | awk '{printf "  %-30s %s\n", $1, $8}' | sort
echo ""
echo "=== ENABLED FLAGS in base-blueking ==="
grep -nE 'enabled|when' /root/bk72/install/blueking/base-blueking.yaml.gotmpl 2>/dev/null | head -30 | sed 's/^/  /'
