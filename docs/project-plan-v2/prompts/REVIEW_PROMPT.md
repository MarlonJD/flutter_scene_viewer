# Architecture/Scope Review Promptu

Audit the current implementation against START_HERE.md, AGENTS.md, docs/02, docs/03, docs/04, and prompts/MASTER_PROMPT.txt.

Report, with file/line references:

1. Any accidental engine work, raw flutter_gpu renderer code, custom PBR shader, tessellation, UV/tangent generation, or V1-scope creep.
2. Any leakage of upstream Node/Material/GPU types into the stable public API.
3. Any unsafe async lifecycle, stale load, shared material mutation, or GPU resource ownership issue.
4. Any missing assembly/dummy-node behavior or unstable name-only addressing.
5. Any unsupported performance or compatibility claim.
6. Missing tests and diagnostics.

Then propose the smallest patches, ordered by risk. Do not implement future features during this review.
