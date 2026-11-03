#!/usr/bin/env python3
"""Offline GLSL semantic check; not a physical GPU/driver test."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
sdk = os.environ.get('ANDROID_SDK_ROOT')
if not sdk:
    sdk = next(line.split('=', 1)[1] for line in (root / 'android/local.properties').read_text().splitlines() if line.startswith('sdk.dir='))
compiler = Path(sdk) / 'ndk/27.0.12077973/shader-tools/darwin-x86_64/glslc'
files = sorted((root / 'native/imaging/src/gpu/shaders').glob('*'))
with tempfile.TemporaryDirectory(prefix='gremote-glsl-') as directory:
    for source in files:
        if source.suffix not in ('.frag', '.comp'):
            continue
        # OpenGL SPIR-V requires ESSL310. Validate the same300-source constructs
        # with310 in a disposable copy; the runtime300 source is not rewritten.
        text = source.read_text().replace('#version 300 es', '#version 310 es', 1)
        check = Path(directory) / source.name
        check.write_text(text)
        subprocess.run([str(compiler), '--target-env=opengl', '-fauto-bind-uniforms',
            '-fauto-map-locations', '-fshader-stage=' + ('comp' if source.suffix == '.comp' else 'frag'),
            '-c', str(check), '-o', str(check) + '.spv'], check=True)
        print('GLSL checked:', source.name)
