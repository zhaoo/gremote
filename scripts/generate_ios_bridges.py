#!/usr/bin/env python3
"""Generate iOS bridges without touching the existing Android/Dart outputs."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
for name in ('device', 'media'):
    source = (root / 'pigeons' / (name + '_api.dart')).read_text()
    start = source.index('@ConfigurePigeon(')
    end = source.index('@HostApi()', start)
    source = source[:start] + source[end:]
    config = '@ConfigurePigeon(PigeonOptions(swiftOptions: SwiftOptions(includeErrorClass: %s)))\n' % ('true' if name == 'device' else 'false')
    source = source.replace('class Native', config + 'class Native', 1)
    with tempfile.TemporaryDirectory(prefix='gremote-ios-pigeon-', dir=root / 'pigeons') as directory:
        directory = Path(directory)
        input_file = directory / (name + '.dart')
        input_file.write_text(source)
        subprocess.run(['dart', 'run', 'pigeon', '--input', str(input_file), '--swift_out', str(root / 'ios/Runner' / (name.title() + 'Api.g.swift')), '--dart_out', str(directory / 'unused.dart'), '--package_name', 'gremote'], cwd=root, check=True)
