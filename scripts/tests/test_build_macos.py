"""验证发布公共配置与本机连接资料的隔离边界。"""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('build_macos', ROOT / 'scripts/build-macos.py')
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class PublicConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        for name in ['client-config.json', 'cert.der']:
            shutil.copy2(ROOT / 'config/distribution' / name, self.directory / name)

    def rewrite(self, **changes):
        path = self.directory / 'client-config.json'
        value = json.loads(path.read_text())
        value.update(changes)
        path.write_text(json.dumps(value))

    def test_matching_public_certificate_is_accepted(self):
        self.assertEqual(build.validate_client_resources(self.directory), self.directory.resolve())

    def test_changed_certificate_is_rejected(self):
        (self.directory / 'cert.der').write_bytes(b'changed certificate')
        with self.assertRaises(ValueError):
            build.validate_client_resources(self.directory)

    def test_private_configuration_field_is_rejected(self):
        self.rewrite(database_password='test-only')
        with self.assertRaises(ValueError):
            build.validate_client_resources(self.directory)

    def test_unsafe_backend_roots_are_rejected(self):
        for address in ['http://example.com', 'https://user:secret@example.com',
                        'https://example.com/api', 'https://example.com?token=value',
                        'https://example.com#fragment', 'https://example.com:99999']:
            with self.subTest(address=address):
                self.rewrite(base_url=address)
                with self.assertRaises(ValueError):
                    build.validate_client_resources(self.directory)


if __name__ == '__main__':
    unittest.main()
