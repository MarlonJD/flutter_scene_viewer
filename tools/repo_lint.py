#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

errors: list[str] = []


def require(path: str) -> Path:
    p = ROOT / path
    if not p.exists():
        errors.append(f"missing required path: {path}")
    return p


for path in [
    'AGENTS.md',
    'docs/PROJECT_CHARTER.md',
    'docs/ARCHITECTURE.md',
    'docs/REPO_TOOLING.md',
    'docs/agent-harness/README.md',
    'docs/agent-harness/output-contract.md',
    'docs/agent-harness/entropy-cleanup-checklist.md',
    'docs/exec-plans/active',
    'docs/exec-plans/completed',
    'docs/exec-plans/templates/EXEC_PLAN_TEMPLATE.md',
    'lib/flutter_scene_viewer.dart',
    'test',
]:
    require(path)

agents = require('AGENTS.md')
if agents.exists():
    line_count = len(agents.read_text(encoding='utf-8').splitlines())
    if line_count > 140:
        errors.append(f'AGENTS.md is too long ({line_count} lines); keep it a map')

active_dir = ROOT / 'docs/exec-plans/active'
if active_dir.exists():
    plans = sorted(active_dir.glob('*.md'))
    if not plans:
        errors.append('no active exec plans found')
    for plan in plans:
        text = plan.read_text(encoding='utf-8')
        for heading in ['## Goal', '## Steps', '## Acceptance criteria', '## Progress log']:
            if heading not in text:
                errors.append(f'{plan.relative_to(ROOT)} missing {heading}')

for md in ROOT.glob('docs/**/*.md'):
    text = md.read_text(encoding='utf-8')
    if 'TODO TODO' in text:
        errors.append(f'{md.relative_to(ROOT)} contains repeated TODO marker')

if errors:
    for error in errors:
        print(f'REPO_LINT_ERROR: {error}')
    sys.exit(1)

print('repo lint passed')
