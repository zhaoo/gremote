#!/usr/bin/env python3
"""Check local iOS release metadata, app icons, signatures and imaging symbols."""
import json
from pathlib import Path
import plistlib
import re
import struct
import subprocess
import sys


def verify(archive):
    apps = list((archive / 'Products/Applications').glob('*.app'))
    assert len(apps) == 1, 'Archive must contain one app'
    app = apps[0]
    bundles = [app, *app.glob('Frameworks/*.framework')]
    for bundle in bundles:
        with (bundle / 'Info.plist').open('rb') as stream:
            info = plistlib.load(stream)
        for key in ('CFBundleIdentifier', 'CFBundleExecutable', 'CFBundleVersion', 'CFBundleShortVersionString'):
            assert info.get(key), f'{bundle.name}: missing {key}'
        assert re.fullmatch(r'\d+(?:\.\d+){0,2}', info['CFBundleShortVersionString']), f'{bundle.name}: invalid version'
        assert (bundle / info['CFBundleExecutable']).is_file(), f'{bundle.name}: missing executable'

    root = Path(__file__).resolve().parent.parent
    icons = root / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    manifest = json.loads((icons / 'Contents.json').read_text())
    for entry in manifest['images']:
        path = icons / entry['filename']
        data = path.read_bytes()
        assert data[:8] == b'\x89PNG\r\n\x1a\n', f'{path.name}: not PNG'
        width, height, _, color_type = struct.unpack('>IIBB', data[16:26])
        size = float(entry['size'].split('x')[0]) * float(entry['scale'][:-1])
        assert width == height == size, f'{path.name}: wrong dimensions'
        assert color_type == 2, f'{path.name}: must be opaque RGB PNG'
        offset = 8
        while offset < len(data):
            length = struct.unpack('>I', data[offset:offset + 4])[0]
            assert data[offset + 4:offset + 8] != b'tRNS', f'{path.name}: PNG transparency'
            offset += length + 12

    framework = app / 'Frameworks/gremote_imaging.framework/gremote_imaging'
    symbols = archive / 'dSYMs/gremote_imaging.framework.dSYM'
    assets = json.loads(subprocess.check_output(['/usr/bin/assetutil', '--info', str(app / 'Assets.car')], text=True))
    compiled_icons = [asset for asset in assets if asset.get('Name') == 'AppIcon' and asset.get('AssetType') == 'Icon Image']
    # AssetType differs across SDKs; opaque icon renditions always carry pixel dimensions.
    if not compiled_icons:
        compiled_icons = [asset for asset in assets if asset.get('Name') == 'AppIcon' and 'PixelWidth' in asset]
    assert compiled_icons, 'Archive has no compiled app icon renditions'
    assert all(asset.get('Opaque') is True for asset in compiled_icons), 'Compiled app icon is not opaque'
    assert any(asset.get('PixelWidth') == 1024 for asset in compiled_icons), 'Missing marketing icon'
    def uuids(path):
        output = subprocess.check_output(['xcrun', 'dwarfdump', '--uuid', str(path)], text=True)
        return set(re.findall(r'UUID: ([A-F0-9-]+) \(([^)]+)\)', output))
    binary_ids = uuids(framework)
    assert binary_ids and binary_ids == uuids(symbols), 'Imaging framework/dSYM UUID mismatch'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
    print(f'PASS: {len(bundles)} app/framework bundles, {len(manifest["images"])} icon entries, {len(compiled_icons)} opaque compiled icons, imaging dSYM UUIDs, code signature')


if __name__ == '__main__':
    verify(Path(sys.argv[1]).resolve())
