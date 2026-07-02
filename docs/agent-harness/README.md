# Agent harness

This directory defines the repository's agent harness contract. It is not a
second planning system and it is not a replacement for `AGENTS.md`.

Use it to answer three recurring questions:

- what executable checks exist;
- which outputs are durable evidence;
- how to keep agent-facing docs from becoming parallel source material.

## Files

- `output-contract.md` defines which outputs are temporary, which belong in
  plan logs, and when an artifact should be committed.
- `entropy-cleanup-checklist.md` lists the smallest recurring cleanup checks
  for plans, generated docs, archived planning packs, and claims.

## Script boundary

Shell and Python files under `tools/` are the executable harness. Markdown files
under this directory are the contract those scripts and plan logs follow.

Prefer this split:

- `.sh` for command orchestration;
- `.py` for repository scanning or structured checks;
- `.md` for policy, evidence rules, and cleanup criteria.

Do not add another script until the rule is repeated often enough that a human
or agent is likely to forget it.
