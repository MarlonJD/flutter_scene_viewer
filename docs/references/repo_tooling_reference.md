# Repository tooling reference

The repository follows these tooling practices:

- start from a short `AGENTS.md` map;
- make durable project knowledge available inside the repo;
- keep executable plans in versioned files;
- expose validation commands that agents can run repeatedly;
- add mechanical checks for architecture and documentation structure;
- treat docs, tests, CI, and tool scripts as first-class code;
- update plans and quality score as work progresses.

This repo intentionally avoids a giant instruction file and instead uses
layered, agent-readable documentation plus small repeatable checks.
