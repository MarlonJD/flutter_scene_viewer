# Exec plan: renderer-native clearcoat follow-up

> **Status (2026-07-16): completed.** The renderer-native contract is published
> and pinned. iOS Simulator evidence is `verified locally`; release maturity
> remains `release pending`, and no successor plan is active yet.

## Goal

Add a first-class `KHR_materials_clearcoat` contract to `flutter_scene`, then
integrate it through the viewer only after the renderer, importer, and selected
target evidence satisfy the Khronos layering semantics.

## Assumptions

- Khronos defines the glTF factor, texture-channel, normal, and layering
  semantics.
- The pinned `flutter_scene` revision
  `ccf7372428961ebe0abb053727fe443150547a74` defines the current native
  clearcoat importer, material, serialization, texture-slot, and layered PBR
  capability.
- The repository-owned translucent overlay remains target-scoped
  `candidate-only` evidence. Availability, maturity, and target evidence stay
  separate.

## Non-goals

- Do not build a replacement PBR renderer or general shader graph in
  `flutter_scene_viewer`.
- Do not lower base roughness, boost environment intensity, bake textures,
  generate UVs, or add asset-specific material fixes to imitate clearcoat.
- Do not treat simulator-only, skipped, or historical candidate evidence as a
  physical-device or production-ready result.

## Steps

1. Add an upstream `flutter_scene` material/importer contract for clearcoat
   factor, red-channel factor texture, roughness factor, green-channel
   roughness texture, and an independent tangent-space normal texture/scale.
   Verify with upstream unit tests and a concrete upstream commit.
2. Integrate an energy-aware second dielectric lobe inside the renderer-owned
   standard PBR path. Preserve base material, emission, alpha, shadows,
   double-sided state, direct lighting, and IBL without double-counting the
   directional highlight or manipulating base roughness.
3. Update the viewer dependency pin and advertise runtime capability only
   after the pinned material, importer, and shader consume every requested
   field. Keep unsupported combinations atomic and diagnostic until then.
4. Run the fixed-state Khronos clearcoat corpus and focused wrapper tests on
   each selected target. Record runtime capability, release maturity, and
   target evidence independently.

## Acceptance criteria

- [x] A concrete upstream commit and viewer dependency pin expose the complete
  selected clearcoat contract.
- [x] Factor zero/full, red-channel texture multiplication, roughness/green
  trend, independent coat normal, base attenuation, combined base-plus-coat,
  double-sided, shadow, direct-light, and IBL tests pass without an extra
  heuristic highlight.
- [x] Khronos `ClearCoatTest`, `ClearCoatCarPaint`, and combined `ToyCar`
  evidence is captured under the fixed reference state for every claimed
  target.
- [x] No target is labeled `production-ready` without matching local target
  evidence and the Plan 014 release gates.

## Progress log

- 2026-07-16: Promoted to active at the user's direction after reading the
  project charter, architecture, materials/lighting contract, completed Plan
  014, the full Plan 015 objective, and the required PBR references. Work stays
  on the current viewer branch. Upstream implementation will use a separate
  local `flutter_scene` checkout and a local commit; publishing that commit or
  changing any remote remains separately approval-gated.
- 2026-07-16: Implemented the upstream material/parser/runtime-import/offline-
  import/serialized-scene contract and the standard PBR second coat lobe in
  local commit `a5aa66fcbf8838eb9803944a1281fbe4799be84d`. Factor and roughness
  textures consume Khronos red and green channels; coat normal/scale and UV
  metadata stay independent; base direct, IBL, and emission are attenuated by
  coat Fresnel before the direct and environment coat lobes are added. Existing
  shadows, double-sided orientation, fog, tone mapping, and alpha remain in the
  shared renderer path.
- 2026-07-16: The first iOS Simulator run found Metal's complete fragment
  resource count exceeded the 16-sampler floor. Follow-up commit
  `7bc726aefd830bbebbc0ba4f01c63385891319ce` compiles only the backend's
  radiance sampler type, preserves Web's 2D mip radiance path, and adds a
  protected custom-PBR slot hook. Both upstream shader bundles and the viewer's
  two bounded extended-PBR variants then compiled and rendered through
  Impeller Metal without a binding exception.
- 2026-07-16: Integrated renderer-native clearcoat in the viewer with strict
  validation, texture loading, staged PBR cloning, atomic replacement/reset,
  retained clearcoat state, and typed diagnostics. A transformed-core material
  and native clearcoat compose through one clearcoat-specific extended
  fragment under the sampler floor. Clearcoat-after-transform order is covered;
  a forced second-material construction failure preserves the live transformed
  state unchanged.
- 2026-07-16: Staged hash-pinned ClearCoatTest, ClearCoatCarPaint, and ToyCar
  from Khronos Sample Assets commit
  `2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf`, including license hashes. The
  iPhone 17 iOS 26.5 Simulator run through Impeller Metal is `verified locally`
  for all three assets and four views. ClearCoatTest and ClearCoatCarPaint had
  zero diagnostics. ToyCar rendered its transformed coated paint and reported
  only the expected optional unsupported transmission diagnostic on `Glass#0`.
  Capture hashes and commands are in
  `docs/references/material_extension_platform_evidence.md`.
- 2026-07-16: Historical publication blocker: the stable viewer dependency was
  still at
  `cd6760912fa38beb55f63e388655a1aeabd32fe4`. The final upstream revision is
  local-only at this point, so the first acceptance criterion and plan
  completion remained blocked on minimum publication authorization. Runtime capability was
  `verified locally against a path override`; release maturity is `release
  pending`; production readiness is `false`; physical iOS, Android, and Web are
  `not run`.
- 2026-07-16: Historical temporary evidence: exported the exact upstream series to
  `/private/tmp/flutter_scene_plan015_patches/`. Patch 1 SHA-256 is
  `1eb8d845564b80c2dec788e9117ed701f148411111be5f27feb7792f9b0f5b1d`;
  patch 2 SHA-256 is
  `6308d025c4b8f6dc45cbec53da66fb31c82a0279c524dff0ebd931dd2347a59b`.
  The checkout remote points at the local pub-cache mirror, which must not be
  modified; publishing therefore needed an explicitly approved external remote.
- 2026-07-16: The two temporary implementation commits and their contract were
  reconstructed after the disposable checkout was reclaimed, validated again,
  and published as immutable upstream commit
  `ccf7372428961ebe0abb053727fe443150547a74` on
  `MarlonJD/flutter_scene:plan015-clearcoat`. `git ls-remote` resolved that exact
  branch hash. The viewer dependency now resolves the published commit directly
  without a path override; the earlier unpublished-pin blocker is closed.
- 2026-07-16: A disposable iPhone 17 Simulator harness built the exact Git pin
  through Impeller Metal and loaded ClearCoatTest, ClearCoatCarPaint, and ToyCar.
  The first two reported zero diagnostics; ToyCar reported only its expected
  unsupported transmission diagnostic. This fresh runtime smoke supplements
  the existing controlled three-pass visual evidence; it is not a pixel-parity
  or physical-device claim.
- 2026-07-16: Rebuilt the Three.js comparison at the user's request as a
  controlled three-pass audit. The first draft exposed two invalid controls:
  Three.js used fit padding `1.0` while the viewer uses `1.15`, and only the HDR
  had been mirrored even though flutter_scene's imported-glTF Z mirror requires
  the camera, directional light, and environment to transform together. The
  final tracked state freezes canonical per-model bounds, the exact generated
  HDR hash, direct/IBL/combined passes, PBR Neutral, sRGB, and the complete
  coordinate mapping. ToyCar's independent automatic fit was also rejected
  after its authored root scale produced a distant native frame; both sides
  now receive the same canonical camera frame.
- 2026-07-16: The final 3-assets × 3-passes iOS Simulator and Three.js r167
  evidence sets are `verified locally`. ClearCoatCarPaint's direct-light point
  is colocated and its HDR panels have the same orientation and ordering.
  Small IBL panel-center, blur, and brightness differences remain explicitly
  bounded to the renderers' independent rough-reflection and PMREM/GGX
  prefilter implementations; no pixel-parity claim is made. ClearCoatTest and
  ClearCoatCarPaint report zero diagnostics. ToyCar retains its one honest
  unsupported transmission diagnostic and is not used as transmission-parity
  proof. The zoomed board and hashed evidence records are under
  `tools/out/material_extension_acceptance/plan015_controlled_comparison/`.
- 2026-07-13: Created from Plan 014 Task 8 because the pinned renderer lacks a
  native clearcoat contract and the package-local alpha overlay remains
  `candidate-only`.

## Verification log

- 2026-07-13: Upstream implementation and selected-target evidence are
  `not run`; this deferred plan records the blocker and required closure gates
  only.
- 2026-07-16: RED upstream parser/material/shader contract tests failed before
  the native fields, channel mappings, importer routes, and layered lighting
  existed. The first simulator run then failed shader compilation above the
  Metal sampler limit, and the first combined ToyCar run exposed a missing
  custom-fragment clearcoat binding boundary. Each failure was retained as a
  focused regression before the implementation advanced.
- 2026-07-16: `flutter test test/clearcoat_shader_contract_test.dart
  test/clearcoat_material_test.dart`, full upstream `flutter test`, upstream
  `flutter analyze`, and upstream `git diff --check` pass at
  `7bc726aefd830bbebbc0ba4f01c63385891319ce`; host-only GPU tests remain
  skipped where no Impeller context exists.
- 2026-07-16: Viewer RED
  `flutter test test/flutter_scene_adapter_material_test.dart --plain-name
  'native clearcoat delta keeps the active transformed PBR state'` failed with
  one material construction instead of the required two. The same test and the
  complete adapter material test file now pass, including the atomic-failure
  case.
- 2026-07-16: `bash tools/run_checks.sh` passes against the local renderer
  override: repo lint and format are clean, Flutter analysis reports no issues,
  and the full viewer suite passes 517 tests with 16 explicitly GPU-gated
  skips. `python3 tools/repo_lint.py` also passes independently. The temporary
  Plan 015 harness then completed `flutter build ios --simulator --debug`,
  compiling the final upstream base bundle and both viewer extended-PBR shader
  variants into `Runner.app`.
- 2026-07-16: Removed `pubspec_overrides.yaml`, restored dependency resolution
  to the checked-in `cd6760912fa38beb55f63e388655a1aeabd32fe4` Git pin, and
  ran `flutter analyze` deliberately. It reports 81 expected missing-contract
  issues for the clearcoat material/parser fields, backend radiance-stage flag,
  and protected texture-slot hook. This is the concrete stable-pin blocker;
  it is not blended with the green path-override verification above.
- 2026-07-16: A final completion audit rechecked the Khronos view-angle coat
  Fresnel and emission-layering semantics, viewer atomicity/reset/persistence,
  and every manifest, GLB, license, capture, and exported-patch hash. Against
  the temporary local renderer override, the 18 focused upstream clearcoat
  tests passed, 149 focused viewer tests passed with 3 explicitly GPU-gated
  host skips, and viewer analysis reported no issues. The override was then
  removed and `flutter pub get` restored the checked-in stable Git pin. No
  additional implementation or evidence gap was found; publication and pinning
  remain the sole unfinished gate.
- 2026-07-16: `npm run test:plan015-controlled`,
  `npm run capture:plan015-controlled`,
  `npm run record:plan015-controlled-ios`, and
  `npm run capture:plan015-controlled-board` pass. The temporary native harness
  passes `flutter analyze`; all nine 1206×2622 native PNGs and all nine Three.js
  PNGs are hash-recorded against the same schema-1 state. Direct-only isolates
  camera/light alignment, IBL-only isolates the generated environment, and
  combined verifies their composition.
- 2026-07-16: At published revision
  `ccf7372428961ebe0abb053727fe443150547a74`, all 18 focused upstream clearcoat
  tests pass, the full upstream suite passes 650 tests with 12 host-only GPU
  skips, upstream analysis reports no issues, and both shader bundles compile.
  The viewer's immutable Git dependency resolves the same hash; `flutter pub
  get`, viewer analysis, the iOS Simulator debug build, and `git diff --check`
  pass. `bash tools/run_checks.sh` passes repository lint, formatting, analysis,
  and 519 tests with 16 explicitly GPU-gated skips. Runtime smoke records `0`,
  `0`, and `1` diagnostics for ClearCoatTest, ClearCoatCarPaint, and ToyCar
  respectively, with ToyCar's single diagnostic bounded to unsupported
  transmission.
