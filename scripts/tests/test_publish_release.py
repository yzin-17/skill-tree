"""验证跨提交产物、篡改资产和已有发布的边界。"""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('publish_release', ROOT / 'scripts/publish-release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
REVISION = 'a' * 40
REPOSITORY = 'fixture/skill-tree'
RUN_ID = '123'


class ReleaseBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        version = json.loads((ROOT / 'macos/version.json').read_text())
        stem = f"Skill-Atlas-{version['version']}-{version['build']}-macos-universal"
        self.packages = [stem + '.zip', stem + '.dmg']
        for name in self.packages:
            (self.directory / name).write_bytes(b'fixture artifact')
        self.metadata = {**version, 'tag': 'v' + version['version'], 'source_revision': REVISION,
                         'ci_run_url': f'https://github.com/{REPOSITORY}/actions/runs/{RUN_ID}',
                         'packages': self.packages, 'architectures': ['arm64', 'x86_64'],
                         'bundle_id': 'local.skillatlas.app', 'signature': 'ad-hoc', 'notarized': False,
                         'minimum_macos': '14.0'}
        self.write_metadata()

    def write_metadata(self):
        (self.directory / 'build-info.json').write_text(json.dumps(self.metadata))
        (self.directory / 'SHA256SUMS').write_text(''.join(
            hashlib.sha256((self.directory / name).read_bytes()).hexdigest() + '  ' + name + '\n'
            for name in self.packages + ['build-info.json']))

    def validate(self):
        return release.validate_assets(self.directory, self.metadata['tag'], REVISION, REPOSITORY, RUN_ID)

    def test_complete_matching_ci_assets_are_accepted(self):
        metadata, assets = self.validate()
        self.assertEqual(metadata['source_revision'], REVISION)
        self.assertEqual(set(assets), set(self.packages + ['build-info.json', 'SHA256SUMS']))

    def test_cross_commit_or_cross_run_assets_are_rejected(self):
        for field, value in [('source_revision', 'b' * 40), ('ci_run_url', 'https://github.com/fixture/other/actions/runs/123')]:
            with self.subTest(field=field):
                original = self.metadata[field]
                self.metadata[field] = value
                self.write_metadata()
                with self.assertRaises(ValueError): self.validate()
                self.metadata[field] = original

    def test_tampered_or_missing_package_is_rejected(self):
        (self.directory / self.packages[0]).write_bytes(b'tampered')
        with self.assertRaises(ValueError): self.validate()
        (self.directory / self.packages[0]).unlink()
        with self.assertRaises(ValueError): self.validate()

    def test_unexpected_asset_is_rejected(self):
        (self.directory / 'private.env').write_text('fixture')
        with self.assertRaises(ValueError): self.validate()

    def test_published_release_is_never_overwritten(self):
        with patch.object(release, 'get_release', return_value={'draft': False}), patch.object(release, 'gh') as gh:
            with self.assertRaises(ValueError):
                release.publish(self.directory, self.metadata['tag'], REVISION, REPOSITORY, RUN_ID)
            gh.assert_not_called()

    def test_unrelated_draft_is_not_taken_over(self):
        with patch.object(release, 'get_release', return_value={'draft': True, 'body': 'unrelated', 'target_commitish': REVISION}), patch.object(release, 'gh') as gh:
            with self.assertRaises(ValueError):
                release.publish(self.directory, self.metadata['tag'], REVISION, REPOSITORY, RUN_ID)
            gh.assert_not_called()

    def test_tag_404_still_discovers_a_draft(self):
        response = subprocess.CompletedProcess([], 1, '', 'HTTP 404: Not Found')
        draft = {'id': 1, 'tag_name': self.metadata['tag'], 'draft': True}
        with patch.object(release.subprocess, 'run', return_value=response), patch.object(release, 'gh', return_value=json.dumps([draft])):
            self.assertEqual(release.get_release(REPOSITORY, self.metadata['tag']), draft)

    def test_tag_and_list_absence_means_no_release(self):
        response = subprocess.CompletedProcess([], 1, '', 'HTTP 404: Not Found')
        with patch.object(release.subprocess, 'run', return_value=response), patch.object(release, 'gh', return_value='[]'):
            self.assertIsNone(release.get_release(REPOSITORY, self.metadata['tag']))

    def test_permission_failure_does_not_look_like_absence(self):
        response = subprocess.CompletedProcess([], 1, '', 'HTTP 403: Forbidden')
        with patch.object(release.subprocess, 'run', return_value=response), patch.object(release, 'gh') as gh:
            with self.assertRaises(RuntimeError):
                release.get_release(REPOSITORY, self.metadata['tag'])
            gh.assert_not_called()

    def draft(self):
        return {'draft': True, 'body': f'<!-- skillatlas-ci:{REVISION}:{RUN_ID} -->',
                'target_commitish': REVISION,
                'assets': [{'name': p.name, 'size': p.stat().st_size,
                            'digest': 'sha256:' + hashlib.sha256(p.read_bytes()).hexdigest()}
                           for p in self.directory.iterdir()]}

    def test_partial_upload_stays_draft(self):
        partial = self.draft()
        partial['assets'].pop()
        with patch.object(release, 'get_release', side_effect=[self.draft(), partial]), patch.object(release, 'gh') as gh:
            with self.assertRaises(ValueError):
                release.publish(self.directory, self.metadata['tag'], REVISION, REPOSITORY, RUN_ID)
            self.assertEqual(len(gh.call_args_list), 1)
            self.assertEqual(gh.call_args.args[:2], ('release', 'upload'))

    def test_remote_digest_mismatch_stays_draft(self):
        invalid = self.draft()
        invalid['assets'][0]['digest'] = 'sha256:' + '0' * 64
        with patch.object(release, 'get_release', side_effect=[self.draft(), invalid]), patch.object(release, 'gh') as gh:
            with self.assertRaises(ValueError):
                release.publish(self.directory, self.metadata['tag'], REVISION, REPOSITORY, RUN_ID)
            self.assertEqual(len(gh.call_args_list), 1)

    def test_complete_verified_upload_is_published(self):
        final = {'draft': False, 'html_url': 'https://github.com/fixture/skill-tree/releases/tag/v0.1.0'}
        with patch.object(release, 'get_release', side_effect=[self.draft(), self.draft(), final]), patch.object(release, 'gh') as gh, patch('builtins.print'):
            result = release.publish(self.directory, self.metadata['tag'], REVISION, REPOSITORY, RUN_ID)
            self.assertFalse(result['draft'])
            self.assertEqual(gh.call_args_list[0].args[:2], ('release', 'upload'))
            self.assertEqual(gh.call_args_list[1].args[:2], ('release', 'edit'))
            self.assertIn('--draft=false', gh.call_args_list[1].args)


if __name__ == '__main__':
    unittest.main()
