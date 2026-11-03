import ast
from fnmatch import fnmatchcase
import importlib.util
import io
import json
from pathlib import Path
import re
import tarfile
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'deploy/publish_site.py'

class SiteDeployTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(SCRIPT.exists(), 'deployment implementation is missing')
        spec = importlib.util.spec_from_file_location('publish_site', SCRIPT)
        self.deploy = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.deploy)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)

    def archive(self, extra=None, missing=None):
        files = {'index.html': b'<html>GRemote</html>', 'style.css': b'body{}',
                 'app.js': b'"use strict";', 'releases.json': b'[]',
                 'assets/street.jpg': b'photo', 'assets/camera.png': b'camera',
                 'assets/editorial.ttf': b'font', 'assets/icon.png': b'icon', 'assets/OFL.txt': b'license'}
        if missing: files.pop(missing)
        if extra: files.update(extra)
        archive = self.root / ('site-%s.tar.gz' % len(list(self.root.glob('*.tar.gz'))))
        with tarfile.open(archive, 'w:gz') as tar:
            for name, data in files.items():
                info = tarfile.TarInfo(name); info.size = len(data)
                tar.addfile(info, io.BytesIO(data))
        return archive

    def test_workflow_trigger_contract(self):
        workflow = SCRIPT.parents[1] / '.github/workflows/deploy-website.yml'
        source = workflow.read_text()
        # Check the small trigger declaration without adding a YAML dependency to CI.
        trigger = re.search(r'^on:\n((?:[ \t]+.*\n|\n)+)', source, re.MULTILINE)
        self.assertIsNotNone(trigger)
        self.assertRegex(trigger.group(1), r'(?m)^  workflow_dispatch:')
        push = re.search(r'^  push:\n((?:    .*\n)+)', trigger.group(1), re.MULTILINE)
        self.assertIsNotNone(push)
        branches = re.search(r'^    branches: (\[[^\n]+\])$', push.group(1), re.MULTILINE)
        tags = re.search(r'^    tags: (\[[^\n]+\])$', push.group(1), re.MULTILINE)
        self.assertIsNotNone(branches, 'develop pushes must trigger deployment')
        self.assertIsNotNone(tags, 'site-* remains an explicit release trigger')
        self.assertEqual(ast.literal_eval(branches.group(1)), ['develop'])
        self.assertEqual(ast.literal_eval(tags.group(1)), ['site-*'])
        self.assertRegex(push.group(1), r'(?m)^    paths:$')
        paths = re.findall(r"^      - ['\"]([^'\"]+)['\"]$", push.group(1), re.MULTILINE)
        self.assertEqual(set(paths), {'website/**', 'deploy/**',
                                     '.github/workflows/deploy-website.yml',
                                     'tests/test_site_deploy.py'})
        for changed in ('website/index.html', 'website/assets/camera.png',
                        'deploy/publish_site.py', '.github/workflows/deploy-website.yml',
                        'tests/test_site_deploy.py'):
            with self.subTest(site_change=changed):
                self.assertTrue(any(fnmatchcase(changed, pattern) for pattern in paths))
        for changed in ('lib/main.dart', 'pubspec.yaml', 'android/app/build.gradle',
                        'docs/releases/v1.2.0.md'):
            with self.subTest(app_change=changed):
                self.assertFalse(any(fnmatchcase(changed, pattern) for pattern in paths))
        self.assertIn("if: github.ref == 'refs/heads/develop' || startsWith(github.ref, 'refs/tags/site-')", source)

    def test_deploy_and_rollback(self):
        site = self.root / 'site'
        self.deploy.publish(site, self.archive(), 'a' * 40)
        self.assertEqual((site/'current').resolve().name, 'a' * 40)
        self.assertEqual(json.loads((site/'current/version.json').read_text())['commit'], 'a' * 40)
        self.deploy.publish(site, self.archive(), 'b' * 40)
        self.assertEqual((site/'previous').resolve().name, 'a' * 40)
        self.deploy.rollback(site)
        self.assertEqual((site/'current').resolve().name, 'a' * 40)

    def test_traversal_rejected_before_writing(self):
        site = self.root/'site'
        for name in ('../escape', '/tmp/escape', 'assets/../../escape'):
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.deploy.publish(site, self.archive({name: b'bad'}), 'a'*40)
        self.assertFalse((site/'current').exists())

    def test_symlink_rejected(self):
        archive = self.archive()
        with tarfile.open(self.root/'link.tar', 'w') as tar:
            info = tarfile.TarInfo('assets/link'); info.type = tarfile.SYMTYPE; info.linkname = '/etc/passwd'; tar.addfile(info)
        with self.assertRaises(ValueError): self.deploy.publish(self.root/'site', self.root/'link.tar', 'a'*40)

    def test_missing_asset_preserves_current(self):
        site = self.root/'site'
        self.deploy.publish(site, self.archive(), 'a'*40)
        with self.assertRaises(ValueError): self.deploy.publish(site, self.archive(missing='style.css'), 'b'*40)
        self.assertEqual((site/'current').resolve().name, 'a'*40)

    def test_compressed_bomb_has_bounded_expansion(self):
        import gzip
        from unittest.mock import patch
        archive = self.archive({'index.html': b'x' * (40 * 1024 * 1024)})
        expanded = 0
        original = gzip._GzipReader.read
        def counted(stream, *args, **kwargs):
            nonlocal expanded
            result = original(stream, *args, **kwargs)
            expanded += len(result)
            return result
        with patch.object(gzip._GzipReader, 'read', counted):
            with self.assertRaises(ValueError):
                self.deploy.publish(self.root/'site', archive, 'a'*40)
        self.assertLessEqual(expanded, self.deploy.MAX_BYTES + 128 * 1024)

    def test_bad_version_rejected(self):
        for version in ('../bad', '', 'main', 'g'*40):
            with self.subTest(version=version), self.assertRaises(ValueError):
                self.deploy.publish(self.root/'site', self.archive(), version)

    def test_duplicate_version_is_immutable(self):
        site = self.root/'site'
        self.deploy.publish(site, self.archive(), 'a'*40)
        with self.assertRaises(FileExistsError): self.deploy.publish(site, self.archive(), 'a'*40)

    def test_lock_rejects_concurrent_publish(self):
        import fcntl
        site = self.root/'site'; site.mkdir()
        with open(site/'.deploy.lock', 'w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError): self.deploy.publish(site, self.archive(), 'a'*40)

if __name__ == '__main__': unittest.main()
