import importlib.util
import io
import json
from pathlib import Path
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
