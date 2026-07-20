# Plan 017 decoder and authored-mip evidence

This directory is the tracked evidence contract for Plan 017. It does not
contain runtime evidence yet. Device discovery is recorded separately from
target execution and cannot promote a capability row.

- `schema.json` closes the manifest, discovery, claim, record, and nested
  record vocabularies with `additionalProperties: false`.
- `manifest.json` declares the release claims and their required gates.
- `records/` contains tracked metadata for completed evidence captures.
- generated apps, logs, screenshots, binaries, validator reports, and symbol
  listings belong below ignored
  `tools/out/plan017_decoder_mip_acceptance/`.

Validate tracked metadata with:

```sh
python3 tools/validate_decoder_mip_evidence.py --check
```

On the machine that owns the ignored capture artifacts, additionally run:

```sh
python3 tools/validate_decoder_mip_evidence.py --check --verify-local-artifacts
```

The validator keeps host, build-only, simulator, physical-device, and Web
records independent. A `production-ready` claim requires every gate declared
for that exact feature and target. Those required gate sets are canonical and
cannot be weakened in the manifest. Missing records remain `not run`; known
environment failures are `blocked`; overall maturity remains `release pending`.

The empty tracked manifest is portable. Once a claim cites a record, every
validator, package, runtime, diagnostic, cancellation, and mip-readback
reference must resolve through that record's artifact inventory. Capability
generation verifies that every inventoried local file exists and still matches
its recorded positive byte length and SHA-256 before accepting any newly
`verified locally` or promoted claim.

The runtime gate means a successful target load, render, and readback with
inventoried render/readback artifacts. The native-only Web diagnostic gate
means exactly one `unsupportedModelFeature` diagnostic, zero native plugin
invocations, and an inventoried diagnostic artifact. A gate label without
these facts is not evidence.

Texture evidence records both the decoded content role and native storage role.
`color` uploads are distinct from `nonColor` uploads. Exact glTF material slots
and sampler values remain on each consumer, so normal and scalar/data slots may
share one `nonColor` allocation without becoming interchangeable inputs. The
validator enforces role/slot compatibility, exact glTF sampler enums, canonical
halved mip dimensions, RGBA byte lengths, and declared resource limits.
Authored-mip sampling requires matching expected/observed RGB evidence for
every explicit LOD plus a discriminating base-only negative control; level
metadata or generated mipmaps alone cannot satisfy that gate.
