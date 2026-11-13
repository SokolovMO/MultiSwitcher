"""Fail closed unless the exact release commit has successful main push CI."""
import json
import os
import subprocess
repo = os.environ['GITHUB_REPOSITORY']
if repo not in {'SokolovMO/MultiShift','SokolovMO/MultiSwitcher'}:
    raise SystemExit('unexpected source repository')
workflow='macos.yml' if repo.endswith('/MultiShift') else 'multi-switcher-ci.yml'
result=subprocess.run(['gh','api',f'repos/{repo}/actions/workflows/{workflow}/runs?head_sha={os.environ["GITHUB_SHA"]}&event=push&per_page=100'],capture_output=True,text=True,check=True)
runs=[r for r in json.loads(result.stdout)['workflow_runs'] if r['head_branch']=='main']
if not runs or runs[0]['conclusion']!='success':
    raise SystemExit('latest main CI for the exact commit must be successful')
print('exact main CI verified')
