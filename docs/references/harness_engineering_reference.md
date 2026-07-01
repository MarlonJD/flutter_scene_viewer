# Harness engineering reference

The repository follows these harness engineering practices:

- start from a short `AGENTS.md` map;
- make durable project knowledge available inside the repo;
- keep executable plans in versioned files;
- expose validation commands that agents can run repeatedly;
- add mechanical checks for architecture and documentation structure;
- treat docs, tests, CI, and harness scripts as first-class code;
- update plans and quality score as work progresses.

This is a repo-local adaptation of OpenAI's harness engineering approach. The
project intentionally avoids a giant instruction file and instead uses layered,
agent-readable documentation.
