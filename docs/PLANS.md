# Execution Plans

Use a managed ExecPlan for work that is cross-cutting, risky, multi-hour,
uncertainty-heavy, or likely to cross a context or contributor boundary.
Narrow mechanical work may use a lightweight task plan.

## Authorities and history

The configured registry is
[`harness-plans/index.md`](harness-plans/index.md). Its sibling `active/` and
`completed/` directories are the only managed lifecycle. The older
`exec-plans/` tree remains a product roadmap archive and deferred-work source;
it is not the strict managed lifecycle. Before implementing an archived or
deferred idea, create a current managed plan that cites the relevant historical
file and current repository evidence.

## Plan requirements

Every managed plan must:

- start from [`harness-plans/plan-template.md`](harness-plans/plan-template.md);
- be self-contained for a contributor who has the current tree but no chat
  history;
- define observable behavior, exact repository paths, commands, expected
  signals, failure modes, and safe recovery;
- keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and
  `Outcomes & Retrospective` current;
- use independently verifiable milestones and record evidence rather than
  inferred success;
- state dependency and interface decisions when upstream behavior determines
  the result;
- record every material revision in `Revision History`.

The OpenAI Cookbook pattern recommends frequent commits, but this file grants
no Git authority. Current user and repository instructions determine whether
commits, branches, external writes, releases, or deployments are allowed.

## Metadata and formatting

Managed plans use the `harness-plan:v1` metadata block with exactly `id`,
`status`, `created`, `updated`, `completed`, and `owner`. The filename stem
equals the lowercase-hyphenated `id`. Active plans use `status: active` and an
empty `completed` value. Completed plans use `status: completed` and a valid
completion date.

Use the thirteen H2 headings from the template in their exact order. Leave a
blank line after each heading. Keep granular checkboxes only in `Progress`;
write milestone explanations as prose. Use UTC timestamps for completed
progress and revision entries.

## Lifecycle

1. Add one plan beneath `harness-plans/active/` and one matching Active row in
   the registry.
2. Keep metadata, registry state, progress, decisions, discoveries, evidence,
   and recovery instructions synchronized.
3. Leave a blocked plan active with a named blocker and recovery condition.
4. Before completion, run all applicable acceptance checks, resolve every
   placeholder, write the retrospective, and account for remaining work.
5. Perform the semantic review described below, validate the active plan with
   `--completion --semantic-review`, then move the same file to `completed/`
   while replacing its registry row.
6. Validate the completed state with `--semantic-review` and run the
   repository-native harness gate.

## Completion and semantic review

Completion requires no unchecked progress item, no unresolved template marker,
an evidence-backed retrospective, current recovery guidance, and resolving
local links. The final Revision History entry has one indented continuation:

    Semantic-Review: reviewer=<role-or-team>; reviewed-at=<YYYY-MM-DD HH:MMZ>; content-sha256=<64-lowercase-hex>; evidence=<observed review evidence>

The digest is SHA-256 over exact UTF-8 plan bytes after removing that entire
continuation line, including its line ending. It detects later local edits; it
does not authenticate the reviewer or prove human, external, security,
release, or production approval.

Validate with:

    python3 /Users/marlonjd/.codex/skills/harness-engineering/scripts/harness.py validate-plan --root . --slug <slug> --state active

The absolute installed-skill path is an interactive authoring cross-check only.
The durable project gate is `python3 tools/harness_gate.py` and must not depend
on the external skill installation.
