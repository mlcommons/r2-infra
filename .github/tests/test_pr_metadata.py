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
                       PR_BRANCH='audit-$(touch${IFS}marker)', PR_NUM='1', AUDIT_ARGS=str(args))
            line = next(l for l in deploy['run'].splitlines() if 'printf' in l and 'PR_TITLE' in l)
            line = line.replace('${{ github.event.number }}', '1')
            output = subprocess.check_output(['bash', '-c', line], cwd=directory, env=env, text=True)
            self.assertIn(env['PR_TITLE'], output)
            line = next(l for l in commit['run'].splitlines() if 'git push origin' in l)
            script = 'git() { printf "%s\\n" "$@" > "$AUDIT_ARGS"; }; ' + line
            subprocess.run(['bash', '-c', script], cwd=directory, env=env, check=True)
            self.assertEqual(args.read_text().splitlines(), ['push', 'origin', 'HEAD:' + env['PR_BRANCH']])
            self.assertFalse((Path(directory) / 'marker').exists())

    def test_directory_names_are_data_in_deployment_shell(self):
        path = Path(__file__).resolve().parents[1] / 'workflows/build-stage-web.yml'
        steps = yaml.safe_load(path.read_text())['jobs']['deploy-staging']['steps']
        deploy = next(s for s in steps if s.get('name') == 'Deploy All Directories to Staging')
        self.assertIn('DIRS_TO_PROCESS', deploy['env'])
        self.assertNotIn('${{', deploy['run'])
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / "dataset'$(touch${IFS}marker)"
            folder.mkdir()
            (folder / 'manifest.json').write_text('{}')
            (folder / 'index.html').write_text('<html></html>')
            env = dict(os.environ, PR_TITLE='literal title', PR_NUM='1',
                       DIRS_TO_PROCESS=folder.name)
            # Exercise the actual deployment shell; rclone cannot reach the network.
            script = 'rclone() { :; }; ' + deploy['run']
            subprocess.run(['bash', '-c', script], cwd=directory, env=env,
                           check=True, capture_output=True, text=True)
            self.assertFalse((Path(directory) / 'marker').exists())

    def test_directory_names_are_data_in_comment_javascript(self):
        path = Path(__file__).resolve().parents[1] / 'workflows/build-stage-web.yml'
        steps = yaml.safe_load(path.read_text())['jobs']['deploy-staging']['steps']
        comment = next(s for s in steps if s.get('name') == 'Comment PR with Staging URLs')
        self.assertIn('PROCESSED_DIRS', comment['env'])
        self.assertNotIn('${{', comment['with']['script'])
        # Execute the real async github-script body with filesystem/git/API adapters
        # stubbed out. An interpolated directory name would throw instead of posting.
        harness = r"""
const assert = require('assert');
const AsyncFunction = Object.getPrototypeOf(async function(){}).constructor;
let body = '';
const github = {rest: {issues: {
  listComments: async () => ({data: []}),
  createComment: async args => {body = args.body;}
}}};
const fakeRequire = name => {
  if (name === 'fs') return {existsSync: () => true};
  if (name === 'child_process') return {execSync: () => Buffer.from('')};
  throw new Error('unexpected module');
};
new AsyncFunction('github', 'context', 'require', 'process', process.env.AUDIT_SCRIPT)(
  github, {issue: {number: 1}, repo: {owner: 'test', repo: 'test'}}, fakeRequire, process
).then(() => assert(body.includes('Web files built and staged'))).catch(e => {
  console.error(e); process.exitCode = 1;
});
"""
        env = dict(os.environ, PROCESSED_DIRS="dir';throw(7);const x='",
                   AUDIT_SCRIPT=comment['with']['script'])
        subprocess.run(['node', '-e', harness], env=env, check=True, capture_output=True)


if __name__ == '__main__':
    unittest.main()
