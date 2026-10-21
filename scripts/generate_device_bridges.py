#!/usr/bin/env python3
"""Regenerate platform boundaries and normalize generator-only whitespace."""
from pathlib import Path
import subprocess,sys
ROOT=Path(__file__).resolve().parents[1]
subprocess.run(['dart','run','pigeon','--input','pigeons/device_api.dart'],cwd=ROOT,check=True)
subprocess.run([sys.executable,'scripts/generate_ios_bridges.py'],cwd=ROOT,check=True)
for name in ['android/app/src/main/kotlin/com/izhaoo/gremote/device/DeviceApi.g.kt','ios/Runner/DeviceApi.g.swift','ios/Runner/MediaApi.g.swift']:
 path=ROOT/name;path.write_text('\n'.join(line.rstrip()for line in path.read_text().splitlines())+'\n')
subprocess.run(['dart','format','lib/platform/device_api.g.dart'],cwd=ROOT,check=True)
