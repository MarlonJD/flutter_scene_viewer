# Reliability

This is a library reliability contract. Deployed availability, service SLOs,
incident paging, database recovery, and production rollback are N/A because
the repository does not operate a service. Observable reliability is expressed
through deterministic loading behavior, budgets, cancellation, diagnostics,
render scheduling, and fixture-driven tests.

## Reliability contract

| Risk or invariant | Detection | Recovery | Verification |
| --- | --- | --- | --- |
| Oversized or adversarial model input exhausts memory or decode time | Byte/decode budgets and typed load diagnostics | Cancel the load, reduce the asset, or raise an explicit caller-owned budget after review | `flutter test test/glb_decode_budget_test.dart test/model_loader_test.dart` |
| A stale load completes after a newer request | Cancellation tokens and adapter cancellation checks | Cancel and dispose the superseded request; retry the latest source | `flutter test test/model_load_cancellation_test.dart test/viewer_controller_load_test.dart` |
| Optional decoder is absent or rejects content | Capability probes and typed diagnostics | Install/enable the matching plugin or supply an uncompressed supported asset | `flutter test test/glb_native_decoder_probe_test.dart test/meshopt_decoder_test.dart` |
| Material authoring data or renderer capability is unavailable | Validation and material-extension diagnostics | Correct the asset or select a supported policy; never synthesize UVs or fake a lobe | Material tests selected by [`verification-matrix.md`](agent-harness/verification-matrix.md) |
| Rendering continues while the scene is idle or misses an invalidation | Render scheduler state and widget tests | Request a frame after state changes; stop continuous rendering when static | `flutter test test/render_scheduler_test.dart test/viewer_widget_test.dart` |
| Generated capability documentation drifts from its source | Repository generation test | Regenerate with `python3 tools/generate_capability_matrix.py` and review the diff | `flutter test test/capability_matrix_generation_test.dart` |
| Harness routes or plan evidence drift | Repository-native harness gate | Repair only repository-local authorized drift, update the active plan, and rerun the gate | `python3 tools/harness_gate.py` |

## Operational evidence boundary

Simulator captures and unit/widget tests can be `verified locally`. Physical
device, browser renderer, release artifact, and production claims remain
`not run` or `release pending` until a plan records exact target evidence.
Raw local logs under `tools/out/` are temporary and do not by themselves prove
release or production readiness.
