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
    'docs/index.md',
    'docs/PLANS.md',
    'docs/SECURITY.md',
    'docs/RELIABILITY.md',
    'docs/REPO_TOOLING.md',
    'docs/agent-harness/index.md',
    'docs/agent-harness/config.json',
    'docs/agent-harness/registry.md',
    'docs/agent-harness/environment-contract.md',
    'docs/agent-harness/verification-matrix.md',
    'docs/agent-harness/coverage-matrix.md',
    'docs/agent-harness/certification.md',
    'docs/agent-harness/certification.json',
    'docs/agent-harness/output-contract.md',
    'docs/agent-harness/entropy-cleanup-checklist.md',
    'docs/harness-plans/index.md',
    'docs/harness-plans/active',
    'docs/harness-plans/completed',
    'docs/harness-plans/plan-template.md',
    'docs/harness-plans/tech-debt-tracker.md',
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

managed_active_dir = ROOT / 'docs/harness-plans/active'
managed_plans = sorted(managed_active_dir.glob('*.md'))
if len(managed_plans) > 1:
    rendered = ', '.join(str(plan.relative_to(ROOT)) for plan in managed_plans)
    errors.append(f'more than one active managed plan: {rendered}')

legacy_active_dir = ROOT / 'docs/exec-plans/active'
legacy_active_plans = sorted(legacy_active_dir.glob('*.md')) if legacy_active_dir.exists() else []
if legacy_active_plans:
    rendered = ', '.join(str(plan.relative_to(ROOT)) for plan in legacy_active_plans)
    errors.append(
        'historical exec-plans/active is no longer an active lifecycle; '
        f'promote intent into docs/harness-plans/active: {rendered}'
    )

for md in ROOT.glob('docs/**/*.md'):
    text = md.read_text(encoding='utf-8')
    if 'TODO TODO' in text:
        errors.append(f'{md.relative_to(ROOT)} contains repeated TODO marker')

if errors:
    for error in errors:
        print(f'REPO_LINT_ERROR: {error}')
    sys.exit(1)

print('repo lint passed')
