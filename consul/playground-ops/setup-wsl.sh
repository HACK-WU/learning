#!/usr/bin/env bash
set -euo pipefail
cd /tmp/consul-ops
python3 - <<'PYEOF'
import zipfile
zipfile.ZipFile("consul.zip").extractall(".")
PYEOF
chmod +x consul
mv consul /usr/local/bin/consul
consul version
