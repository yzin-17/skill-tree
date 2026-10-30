"""验证接续发布只能采用原工作流中测试与打包均成功的有效资产。"""
import copy
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('release_source', ROOT / 'scripts/resolve-release-source.py')
source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(source)


class ReleaseSourceTests(unittest.TestCase):
    def setUp(self):
        self.sha = 'a' * 40
        self.repository = 'fixture/skill-tree'
        self.run = {'id': 123, 'repository': {'full_name': self.repository}, 'event': 'push',
                    'path': '.github/workflows/release.yml', 'head_branch': 'v0.1.0', 'head_sha': self.sha}
        self.jobs = [{'name': name, 'conclusion': 'success'} for name in ['源码与后端测试', 'macOS 通用安装包']]
        self.artifacts = [{'name': 'SkillAtlas-macos-universal', 'expired': False,
                           'workflow_run': {'head_sha': self.sha}}]

    def validate(self, **values):
        return source.validate_source(values.get('run', self.run), values.get('jobs', self.jobs),
                                      values.get('artifacts', self.artifacts), values.get('tag_sha', self.sha), self.repository)

    def test_verified_build_can_resume_after_publish_failure(self):
        self.run['conclusion'] = 'failure'
        self.assertEqual(self.validate(), {'sha': self.sha, 'tag': 'v0.1.0', 'run_id': '123'})

    def test_other_repository_workflow_or_moved_tag_is_rejected(self):
        for field, value in [('repository', {'full_name': 'fixture/other'}), ('path', '.github/workflows/other.yml'),
                             ('event', 'pull_request'), ('head_branch', 'main')]:
            with self.subTest(field=field):
                run = copy.deepcopy(self.run)
                run[field] = value
                with self.assertRaises(ValueError): self.validate(run=run)
        with self.assertRaises(ValueError): self.validate(tag_sha='b' * 40)

    def test_incomplete_or_failed_required_job_is_rejected(self):
        for conclusion in ['failure', 'skipped', None]:
            with self.subTest(conclusion=conclusion):
                jobs = copy.deepcopy(self.jobs)
                jobs[1]['conclusion'] = conclusion
                with self.assertRaises(ValueError): self.validate(jobs=jobs)

    def test_expired_or_wrong_commit_artifact_is_rejected(self):
        for change in [{'expired': True}, {'workflow_run': {'head_sha': 'b' * 40}}]:
            artifacts = copy.deepcopy(self.artifacts)
            artifacts[0].update(change)
            with self.assertRaises(ValueError): self.validate(artifacts=artifacts)
        with self.assertRaises(ValueError): self.validate(artifacts=[])


if __name__ == '__main__':
    unittest.main()
