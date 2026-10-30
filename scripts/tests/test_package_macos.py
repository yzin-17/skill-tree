"""验证版本标签与安装包内私有数据的拒绝行为。"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('package_macos', ROOT / 'scripts/package-macos.py')
package = importlib.util.module_from_spec(spec)
spec.loader.exec_module(package)


class PackageBoundaryTests(unittest.TestCase):
    def test_tag_must_match_source_version(self):
        package.validate_tag('v0.1.0', '0.1.0')
        for tag in ['v0.2.0', '0.1.0', 'v0.1.0/other', 'v0.1.0-rc1']:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                package.validate_tag(tag, '0.1.0')

    def test_private_data_is_rejected_before_packaging(self):
        for name, data in [('local.env', b'DATABASE_PASSWORD=fixture'),
                           ('history.sqlite', b'fixture database'),
                           ('unknown.txt', b'-----BEGIN EC PRIVATE KEY-----\nfixture\n')]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temporary:
                path = Path(temporary)
                (path / name).write_bytes(data)
                with self.assertRaises(ValueError):
                    package.check_private_files(path)

    def test_public_certificate_is_allowed(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            (path / 'cert.der').write_bytes((ROOT / 'config/distribution/cert.der').read_bytes())
            package.check_private_files(path)


if __name__ == '__main__':
    unittest.main()
