# Exec plan: top-down skylight smoke evidence

## Goal

Correct the skylight/shadow-readability smoke setup so it proves the intended
claim: with the directional key light directly overhead, the object below the
table should be slightly darker than the object above the table while still
remaining readable from the environment/IBL contribution.

## Assumptions

- This is smoke/debug evidence, not benchmark or photometric validation.
- The SDK already exposes key-light direction and shadow controls; the defect is
  the smoke setup using an angled key light for a top-down claim.
- A top-down key light should use `keyLightDirection: [0, -1, 0]` with tight
  shadow distance/cascade settings for the compact `SkylightTable.glb` fixture.

## Non-goals

- Do not add a custom renderer, shader, fake shadow, or baked lightmap.
- Do not change default studio lighting for product use.
- Do not include CPU/RAM/GPU/power sampling or benchmark claims.

## Steps

1. Change: document the top-down skylight smoke setup and distinguish it from
   the default studio key-light angle.
   Verify: docs identify `[0, -1, 0]`, key-light shadows, and environment/IBL
   readability as smoke evidence only.
2. Change: run a manual iPhone 17 smoke with `SkylightTable.glb`,
   `keyLightDirection: [0, -1, 0]`, and key-light shadows enabled.
   Verify: screenshot path recorded; lower object is slightly darker than the
   upper object while still visible.
3. Change: keep unrelated dirty worktree changes out of this slice.
   Verify: git status reviewed before final response.

## Acceptance criteria

- [x] docs no longer imply the angled smoke light proves the top-down skylight
      claim;
- [x] iPhone 17 smoke evidence uses top-down directional light
      `[0, -1, 0]`;
- [x] lower object reads slightly darker than the upper object and remains
      visible;
- [x] focused checks and `bash tools/run_checks.sh` are recorded, with any
      unrelated dirty-worktree assumptions called out.

## Progress log

- 2026-07-03: Created after visual review feedback showed the previous
  skylight smoke was not convincing. Root cause: the manual smoke used an
  angled key light (`[-0.2, -0.9, -0.35]`) while the claim requires a directly
  overhead directional light.
- 2026-07-03: Updated the lighting docs and `SkylightTable.glb` fixture notes
  to require `keyLightDirection: [0, -1, 0]` for the skylight/shadow-readability
  smoke. The default studio key-light angle remains unchanged for product use.
- 2026-07-03: Working tree note: unrelated glass/transmission material work was
  present or appeared during this slice, including
  `docs/exec-plans/active/009_transmission_glass_materials.md` and related
  material/docs edits. This plan did not modify or stage those unrelated files
  except where this slice explicitly updated shared lighting fixture docs.
- 2026-07-03: Acceptance criteria and verification are complete; moved this
  plan to `docs/exec-plans/completed/`.

## Verification log

- 2026-07-03: Manual iPhone 17 top-down skylight smoke launched
  `/private/tmp/fsv_ios_smoke.CgURf8` with `SkylightTable.glb`,
  `ViewerEnvironment.studio(intensity: 1.0, showSkybox: true,
  skyboxBlur: 0.2)`, `ambientOcclusion: false`,
  `environmentIntensity: 1.35`, `keyLightIntensity: 6.0`,
  `keyLightDirection: [0, -1, 0]`, `keyLightCastsShadow: true`,
  `keyLightShadowMapResolution: 4096`, `keyLightShadowMaxDistance: 6`,
  `keyLightShadowSoftness: 0.02`, `keyLightShadowFadeRange: 0.5`,
  `keyLightShadowDepthBias: 0.01`, `keyLightShadowNormalBias: 0.015`,
  `keyLightShadowCascadeCount: 2`, and
  `keyLightShadowCascadeSplitLambda: 0.75`. Screenshot:
  `/var/folders/hb/d_4bmzm911143_n2rw1zj4nr0000gn/T/screenshot_optimized_8a46bbf5-5b8e-4252-987e-825da7c0b440.jpg`.
  Visual check: the upper object is brighter, and the lower object is slightly
  darker while still visible.
- 2026-07-03: Cleaned up the `flutter run` process started for the iPhone smoke.
  A follow-up `ps -axo pid,ppid,stat,command | rg 'flutter run|fsv_ios_smoke|flutter_tools|dart .*frontend_server'`
  showed no remaining `flutter run` / `fsv_ios_smoke` process.
- 2026-07-03: Focused checks:
  `flutter test test/fixture_metadata_test.dart test/viewer_lighting_test.dart`
  passed, 3 tests.
- 2026-07-03: Full harness: `bash tools/run_checks.sh` passed. Output stages:
  repo lint passed; Dart format check formatted 41 files with 0 changed;
  `flutter pub get` succeeded; `flutter analyze` reported no issues;
  `flutter test` passed 110 tests with 3 existing GPU-gated skips. The 110-test
  count includes unrelated glass/transmission material tests in the dirty
  worktree.
- 2026-07-03: Post-move checks: `git diff --check` passed;
  `python3 tools/repo_lint.py` passed; `docs/exec-plans/active/` contained the
  unrelated `009_transmission_glass_materials.md` plan and not this completed
  top-down smoke plan.
