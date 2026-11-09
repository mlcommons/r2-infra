"""Execute the workflow's metadata sinks with literal shell metacharacters."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

import yaml


class PRMetadataTest(unittest.TestCase):
    def test_title_and_branch_are_literal_data(self):
        path = Path(__file__).resolve().parents[1] / 'workflows/build-stage-web.yml'
        workflow = yaml.safe_load(path.read_text())
        job = workflow['jobs']['deploy-staging']
        self.assertIn('head.repo.full_name == github.repository', job['if'])
        steps = job['steps']
        commit = next(s for s in steps if s.get('name') == 'Commit index.html files')
        deploy = next(s for s in steps if s.get('name') == 'Deploy All Directories to Staging')
        self.assertIn('PR_BRANCH', commit['env'])
        self.assertIn('PR_TITLE', deploy['env'])
        self.assertNotIn('${{ github.head_ref }}', commit['run'])
        self.assertNotIn('${{ github.event.pull_request.title }}', deploy['run'])
        with tempfile.TemporaryDirectory() as directory:
            args = Path(directory) / 'arguments'
            env = dict(os.environ, PR_TITLE='$(touch marker)',
                       PR_BRANCH='audit-$(touch${IFS}marker)', AUDIT_ARGS=str(args))
            line = next(l for l in deploy['run'].splitlines() if 'printf' in l and 'PR_TITLE' in l)
            line = line.replace('${{ github.event.number }}', '1')
            output = subprocess.check_output(['bash', '-c', line], cwd=directory, env=env, text=True)
            self.assertIn(env['PR_TITLE'], output)
            line = next(l for l in commit['run'].splitlines() if 'git push origin' in l)
            script = 'git() { printf "%s\\n" "$@" > "$AUDIT_ARGS"; }; ' + line
            subprocess.run(['bash', '-c', script], cwd=directory, env=env, check=True)
            self.assertEqual(args.read_text().splitlines(), ['push', 'origin', 'HEAD:' + env['PR_BRANCH']])
            self.assertFalse((Path(directory) / 'marker').exists())


if __name__ == '__main__':
    unittest.main()
