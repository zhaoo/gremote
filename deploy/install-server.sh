#!/usr/bin/env bash
# Run as root on the intended Baota host, with a dedicated public key file.
set -euo pipefail
[[ "$(id -u)" == 0 ]] || { echo '需要 root 安装受限发布入口。' >&2; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PUBLIC_KEY_FILE="${1:?用法: bash deploy/install-server.sh /path/to/dedicated-key.pub}"
[[ -f "$PUBLIC_KEY_FILE" ]] || exit 1
[[ -d /www/server/panel/vhost/nginx ]] || { echo '未找到宝塔 Nginx。' >&2; exit 1; }
install -d -m 755 /usr/local/lib/gremote-deploy /www/wwwroot/gremote /www/wwwroot/gremote-acme
install -m 644 "$ROOT_DIR/deploy/publish_site.py" "$ROOT_DIR/deploy/receive_ssh.py" /usr/local/lib/gremote-deploy/
python3 - "$PUBLIC_KEY_FILE" <<'PY'
import fcntl
from pathlib import Path
import sys
key = Path(sys.argv[1]).read_text().strip()
parts = key.split()
if len(parts) not in (2, 3) or parts[0] != 'ssh-ed25519' or '\n' in key or '\r' in key:
    raise ValueError('Expected one dedicated Ed25519 public key')
line = 'restrict,command="/usr/bin/python3 /usr/local/lib/gremote-deploy/receive_ssh.py" ' + key + '\n'
folder = Path('/root/.ssh'); folder.mkdir(mode=0o700, exist_ok=True)
p = folder / 'authorized_keys'
with p.open('a+') as target:
    fcntl.flock(target, fcntl.LOCK_EX)
    target.seek(0)
    old = target.read()
    if parts[1] not in old:
        target.write(('\n' if old and not old.endswith('\n') else '') + line)
p.chmod(0o600)
print('GREMOTE_DEPLOY_ENTRY_READY')
PY
# Nginx is installed separately after certificates and initial content exist.
