# Harness evidence records

This directory contains only source-commit-bound schema-v2 records referenced
by the coverage matrix and certification manifest. No record is current while
`certification.json` says `candidate-only`.

Evidence HMAC keys remain outside the repository. A local signature establishes
consistency with the caller-supplied key, not human approval, provider identity,
release authority, or production proof.
