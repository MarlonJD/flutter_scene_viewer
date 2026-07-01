#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

print('# Doc garden report')
for md in sorted(ROOT.glob('docs/**/*.md')):
    text = md.read_text(encoding='utf-8')
    stale_markers = [m for m in ['TBD', 'TODO', 'not run yet'] if m in text]
    if stale_markers:
        print(f'- {md.relative_to(ROOT)}: {", ".join(stale_markers)}')
