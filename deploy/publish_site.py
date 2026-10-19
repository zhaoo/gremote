#!/usr/bin/env python3
"""Validate and atomically publish a static GRemote site. No shell extraction."""
import argparse
from contextlib import contextmanager
import fcntl
import gzip
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import tarfile
import tempfile

REQUIRED = {'index.html', 'style.css', 'app.js', 'releases.json',
            'assets/street.jpg', 'assets/camera.png', 'assets/editorial.ttf',
            'assets/icon.png', 'assets/OFL.txt'}
MAX_BYTES = 24 * 1024 * 1024

@contextmanager
def locked(root):
    root = Path(root)
    root.mkdir(parents=True, exist_ok=True)
    with open(root / '.deploy.lock', 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        yield root

def switch(root, name, target):
    temporary = root / ('.%s-next' % name)
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    temporary.replace(root / name)

def release_target(root, link):
    path = root / link
    if not path.is_symlink():
        return None
    target = path.resolve(strict=True)
    if target.parent != (root / 'releases').resolve() or not re.fullmatch('[a-f0-9]{40}', target.name):
        raise ValueError('Release link points outside managed releases')
    return target

def publish(root, archive, commit):
    if not re.fullmatch('[a-f0-9]{40}', commit):
        raise ValueError('Expected full lowercase commit SHA')
    if Path(archive).stat().st_size > MAX_BYTES:
        raise ValueError('Archive exceeds size limit')
    with locked(root) as root:
        releases = root / 'releases'
        releases.mkdir(exist_ok=True)
        destination = releases / commit
        if destination.exists():
            raise FileExistsError('Release is immutable: ' + commit)
        current = release_target(root, 'current')
        # Bound decompression before tar parses PAX metadata or skips file bodies.
        # gzip can hide huge padding/headers even when the compressed file is tiny.
        with open(archive, 'rb') as source:
            is_gzip = source.read(2) == b'\x1f\x8b'
        opener = gzip.open if is_gzip else open
        expanded_limit = MAX_BYTES + 100 * 1024
        with opener(archive, 'rb') as source:
            expanded = source.read(expanded_limit + 1)
        if len(expanded) > expanded_limit:
            raise ValueError('Expanded archive exceeds size limit')
        with tarfile.open(fileobj=io.BytesIO(expanded), mode='r:') as tar:
            members = tar.getmembers()
            names = set()
            size = 0
            if len(members) > 100:
                raise ValueError('Too many archive members')
            for member in members:
                path = PurePosixPath(member.name)
                if (path.is_absolute() or '..' in path.parts or str(path) != member.name
                        or not member.isfile() or member.name not in REQUIRED
                        or member.name in names or member.size < 1):
                    raise ValueError('Unsafe or unexpected archive member: ' + member.name)
                names.add(member.name)
                size += member.size
            if names != REQUIRED or size > MAX_BYTES:
                raise ValueError('Incomplete or oversized site archive')
            with tempfile.TemporaryDirectory(prefix='.incoming-', dir=releases) as incoming:
                staging = Path(incoming)
                for member in members:
                    target = staging / member.name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    with tar.extractfile(member) as source, open(target, 'wb') as output:
                        shutil.copyfileobj(source, output)
                    target.chmod(0o644)
                data = json.loads((staging / 'releases.json').read_text())
                if not isinstance(data, list):
                    raise ValueError('Release data must be an array')
                (staging / 'version.json').write_text(json.dumps({'commit': commit}) + '\n')
                (staging / 'version.json').chmod(0o644)
                staging.chmod(0o755)
                for directory in staging.rglob('*'):
                    if directory.is_dir(): directory.chmod(0o755)
                staging.rename(destination)
        if current:
            switch(root, 'previous', 'releases/' + current.name)
        switch(root, 'current', 'releases/' + commit)
    return commit

def rollback(root):
    with locked(root) as root:
        previous = release_target(root, 'previous')
        current = release_target(root, 'current')
        if not previous or not current:
            raise ValueError('Both current and previous releases are required')
        switch(root, 'current', 'releases/' + previous.name)
        switch(root, 'previous', 'releases/' + current.name)
        return previous.name

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--commit')
    parser.add_argument('--rollback', action='store_true')
    args = parser.parse_args()
    root = Path('/www/wwwroot/gremote')
    if args.rollback:
        commit = rollback(root)
    elif args.archive and args.commit:
        commit = publish(root, args.archive, args.commit)
    else:
        parser.error('Specify --archive and --commit, or --rollback')
    print('DEPLOY_OK commit=%s root=%s' % (commit, root))

if __name__ == '__main__': main()
