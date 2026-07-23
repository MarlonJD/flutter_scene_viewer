# Documentation map

Use this map to locate one authoritative source for each kind of repository
knowledge.

| Topic | Canonical source | Update trigger |
| --- | --- | --- |
| Agent instructions | [`../AGENTS.md`](../AGENTS.md) | Commands, durable constraints, or definition of done changes |
| Product intent | [`PROJECT_CHARTER.md`](PROJECT_CHARTER.md) and [`ROADMAP.md`](ROADMAP.md) | Product scope, sequencing, or evidence boundary changes |
| Architecture | [`ARCHITECTURE.md`](ARCHITECTURE.md) | Components, boundaries, or data flow changes |
| Public API | [`PUBLIC_API.md`](PUBLIC_API.md) | Exported behavior or diagnostics change |
| Runtime GLB pipeline | [`RUNTIME_GLB_PIPELINE.md`](RUNTIME_GLB_PIPELINE.md) | Import, decoder, budget, or cancellation behavior changes |
| Materials and lighting | [`MATERIALS_AND_LIGHTING.md`](MATERIALS_AND_LIGHTING.md) | Material semantics, renderer boundary, or evidence changes |
| Repository tooling | [`REPO_TOOLING.md`](REPO_TOOLING.md) | Setup, test, lint, or generation commands change |
| Managed plan policy | [`PLANS.md`](PLANS.md) | Plan schema or lifecycle changes |
| Managed work registry | [`harness-plans/index.md`](harness-plans/index.md) | A managed plan starts, blocks, completes, or is superseded |
| Historical/deferred product plans | [`exec-plans/`](exec-plans/) | Roadmap work is preserved or promoted into the managed lifecycle |
| Security | [`SECURITY.md`](SECURITY.md) | Trust boundary, dependency, or reporting policy changes |
| Reliability | [`RELIABILITY.md`](RELIABILITY.md) | Failure mode, recovery, budget, or operational evidence changes |
| Agent harness | [`agent-harness/index.md`](agent-harness/index.md) | Capabilities, evidence, authority, or maintenance paths change |
| Harness debt | [`harness-plans/tech-debt-tracker.md`](harness-plans/tech-debt-tracker.md) | Harness debt is found, mitigated, or resolved |

## Collections

- [`design-docs/`](design-docs/) records durable cross-cutting rationale.
- [`product-specs/`](product-specs/) indexes existing user-behavior authorities.
- [`generated/`](generated/) records generated artifact provenance.
- [`references/`](references/) indexes stable checked-in dependency and
  material references.
