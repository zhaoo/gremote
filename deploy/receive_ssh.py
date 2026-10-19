#!/usr/bin/env python3
"""Root-owned forced-command entrypoint for a restricted deploy key."""
import os
from pathlib import Path
import re
import sys
import tempfile
from publish_site import MAX_BYTES, publish, rollback

def main():
    command = os.environ.get('SSH_ORIGINAL_COMMAND', '')
    root = Path('/www/wwwroot/gremote')
    if command == 'rollback':
        commit = rollback(root)
    else:
        match = re.fullmatch(r'deploy ([a-f0-9]{40})', command)
        if not match:
            raise ValueError('Only deploy <full SHA> or rollback is allowed')
        with tempfile.TemporaryDirectory(prefix='gremote-deploy-') as incoming:
            archive = Path(incoming) / 'site.tar.gz'
            size = 0
            with archive.open('wb') as output:
                while True:
                    chunk = sys.stdin.buffer.read(65536)
                    if not chunk: break
                    size += len(chunk)
                    if size > MAX_BYTES: raise ValueError('Archive exceeds size limit')
                    output.write(chunk)
            commit = publish(root, archive, match.group(1))
    print('DEPLOY_OK commit=%s root=%s' % (commit, root))

if __name__ == '__main__': main()
