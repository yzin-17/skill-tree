"""验证局域网配置输入、兼容性与公开证书导出边界。"""
import importlib.util
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('lan', SCRIPTS / 'lan.py')
lan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lan)


class LANTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.env_file = self.root / 'local.env'
        self.env_file.write_text('API_PORT=8447\nDATABASE_PORT=55437\nPOSTGRES_ADMIN_PASSWORD=keep-me\n')
        self.patch_env = patch.object(lan.local, 'ENV_FILE', self.env_file)
        self.patch_env.start()
        self.addCleanup(self.patch_env.stop)

    def test_existing_credentials_are_preserved_and_settings_are_idempotent(self):
        lan.settings('SkillAtlas.local.', '8448', save=True)
        first = self.env_file.read_text()
        lan.settings(save=True)
        self.assertEqual(self.env_file.read_text(), first)
        self.assertIn('POSTGRES_ADMIN_PASSWORD=keep-me\n', first)
        self.assertIn('LAN_HOST=skillatlas.local\n', first)
        self.assertEqual(self.env_file.stat().st_mode & 0o777, 0o600)

    def test_invalid_host_or_port_does_not_modify_existing_configuration(self):
        initial = self.env_file.read_text()
        for host in ['example.local\nLAN_PORT=1', '{$HOST}.local', 'https://host.local',
                     '192.168.5.22', 'host..local', '-host.local', 'a' * 64 + '.local']:
            with self.subTest(host=host), self.assertRaises(ValueError):
                lan.settings(host, save=True)
        for port in ['443', '65536', '8447', '55437', 'abc']:
            with self.subTest(port=port), self.assertRaises(ValueError):
                lan.settings('skillatlas.local', port, save=True)
        self.assertEqual(initial, self.env_file.read_text())

    def test_failed_atomic_update_keeps_credentials_and_removes_temporary_file(self):
        initial = self.env_file.read_text()
        with patch.object(lan.os, 'replace', side_effect=OSError('模拟替换失败')):
            with self.assertRaises(OSError): lan.settings('skillatlas.local', save=True)
        self.assertEqual(initial, self.env_file.read_text())
        self.assertEqual([file.name for file in self.root.iterdir()], ['local.env'])

    def test_lan_switch_and_download_port_are_persisted_without_changing_local_port(self):
        env = lan.settings('skillatlas.local', save=True, enabled=True, ca_port='8082')
        self.assertEqual(lan.ca_address(env), 'http://skillatlas.local:8082/root.crt')
        self.assertEqual(env['LAN_SITE_FILE'], 'Caddyfile.lan')
        env = lan.settings(save=True, enabled=False)
        self.assertEqual(env['LAN_SITE_FILE'], 'Caddyfile.lan-disabled')
        self.assertEqual(env['API_PORT'], '8447')
        for port in ['8447', '8448', '55437', '0']:
            with self.subTest(port=port), self.assertRaises(ValueError):
                lan.settings(ca_port=port, save=True)

    def test_old_environment_uses_macos_hostname_without_writing_during_read(self):
        initial = self.env_file.read_text()
        with patch.object(lan.sys, 'platform', 'darwin'), \
             patch.object(lan.subprocess, 'check_output', return_value='Example-Mac\n'):
            env = lan.settings()
        self.assertEqual(env['LAN_HOST'], 'example-mac.local')
        self.assertEqual(env['LAN_PORT'], '8448')
        self.assertEqual(initial, self.env_file.read_text())

    def test_export_reads_only_public_root_and_produces_shareable_materials(self):
        ca = self.root / 'root.crt'
        share = self.root / 'share'
        env = lan.settings('skillatlas.local')
        result = subprocess.CompletedProcess([], 0, b'PUBLIC ROOT', b'')
        with patch.object(lan, 'CA_FILE', ca), patch.object(lan, 'SHARE', share), \
             patch.object(lan.subprocess, 'run', return_value=result) as run, \
             patch.object(lan.ssl, 'PEM_cert_to_DER_cert', return_value=b'public der'), \
             patch.object(lan.local, 'publish_root') as publish, \
             patch('builtins.print'):
            lan.export_ca(env)
            lan.export_ca(env)
        for call in run.call_args_list:
            self.assertEqual(call.args[0][-2:], ['cat', lan.CA_SOURCE])
            self.assertNotIn('key', ' '.join(call.args[0]))
        self.assertEqual((share / 'root.crt').read_text(), 'PUBLIC ROOT')
        self.assertEqual((ca.parent / 'public/root.crt').read_text(), 'PUBLIC ROOT')
        self.assertEqual(publish.call_count, 2)
        self.assertEqual({file.name for file in share.iterdir()},
                         {'root.crt', '安装信任.command', '接入说明.txt'})
        self.assertIn('https://skillatlas.local:8448', (share / '接入说明.txt').read_text())

    def test_health_checks_real_api_envelope_and_rejects_other_services(self):
        ca = self.root / 'root.crt'
        ca.write_text('PUBLIC ROOT')
        env = lan.settings('skillatlas.local')
        for service in ['Skill Atlas', 'Other Service']:
            payload = ('{"data":{"service":"' + service + '","status":"ok","database":"ready"}}').encode()
            with patch.object(lan, 'CA_FILE', ca), \
                 patch.object(lan.ssl, 'create_default_context') as context, \
                 patch.object(lan.urllib.request, 'build_opener') as opener, \
                 patch('builtins.print'):
                opener.return_value.open.return_value = io.BytesIO(payload)
                if service == 'Skill Atlas': lan.health(env)
                else:
                    with self.assertRaises(ValueError): lan.health(env)
                context.assert_called_once_with(cafile=str(ca))


if __name__ == '__main__': unittest.main()
