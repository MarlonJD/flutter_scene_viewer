# Material Extension Platform Evidence

## 011 Target

| Target | Flutter renderer | Glass shader load | Glass visual matrix | Clearcoat shader load | Clearcoat visual matrix | Real-asset status | Status | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| iOS Simulator | Impeller + Flutter GPU | verified locally | verified locally | verified locally | verified locally | verified locally | candidate-only; evidence verified locally | Primary 011 target evidence ran on the `iPhone 17` iOS Simulator through a temporary `integration_test` app that depends on this package by path. Fixture evidence, ToyCar real-asset evidence, and Task 012 acceptance metrics are durable local evidence for the repo-owned custom shader candidate; simulator evidence is not physical-device release readiness. |

## Deferred Targets

| Target | Renderer | Status | Notes |
| --- | --- | --- | --- |
| macOS local | Impeller + Flutter GPU | not run | Deferred from 011; local host visual smokes are development evidence only and are not production target evidence. |
| iOS physical device | Impeller + Flutter GPU | not run | Deferred to a later device evidence plan. |
| Android emulator/device | Impeller + Flutter GPU or platform backend | not run | Deferred to a later platform hardening plan. |
| Web | WebGL2 or future web backend | not run | Deferred to a later platform hardening plan. |

## Commands

The package-level focused test still documents the expected evidence case, but
it runs in the host Flutter tester in this repository and reports
`TargetPlatform.android` even when `-d` points at a simulator:

```sh
flutter test test/flutter_scene_material_extension_backend_test.dart --plain-name "ios simulator production material extension visual matrix" --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Actual iOS Simulator evidence was collected with a temporary Flutter
`integration_test` app under `/private/tmp/fsviewer_ios_evidence_app`:

```sh
flutter drive -d 10C2CF77-CBA8-4948-ADD5-24C49D375059 --driver=test_driver/ios_material_extension_evidence_test.dart --target=integration_test/ios_material_extension_evidence_test.dart --dart-define=FLUTTER_SCENE_GPU_TESTS=true --dart-define=FLUTTER_SCENE_VISUAL_SMOKE=true --enable-impeller --enable-flutter-gpu
```

Result: passed on the `iPhone 17` iOS Simulator for the glass and synthetic
clearcoat visual matrices. Follow-up ToyCar evidence passed on the same
simulator with authored glass and clearcoat in one real GLB. These runs make
the iOS Simulator evidence `verified locally`; the repo-owned custom shader
path remains `candidate-only`. Physical iOS, Android material rendering, and
Web material rendering remain `not run`.

Shader preflight and the evidence record answer different questions. Preflight
proves that required package shader entries are available and routable. It does
not prove Khronos correctness or physical-device release readiness, and it does
not promote maturity or write target evidence into the static policy.

Artifacts:

```text
tools/out/fsviewer_ios_simulator_glass_matrix.png
tools/out/fsviewer_ios_simulator_clearcoat_matrix.png
tools/out/fsviewer_ios_simulator_material_extension_matrix.json
tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_baseline.png
tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_enhanced.png
tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_diff.png
tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat.json
tools/out/fsviewer_ios_simulator_damaged_helmet_manual_clearcoat_side_by_side.png
tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_baseline.png
tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_enhanced.png
tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat_side_by_side.png
tools/out/fsviewer_ios_simulator_toycar_glass_clearcoat.json
```

Recorded metrics:

```json
{
  "target": "iOS Simulator",
  "backendKind": "flutterSceneCustomShader",
  "status": "verified locally",
  "platform": "iOS",
  "glass": {
    "transmission0Spread": 14,
    "transmission1Spread": 239,
    "iorDelta": 5.111805555555556
  },
  "clearcoat": {
    "zeroHighlight": 242,
    "fullHighlight": 254,
    "smoothPeak": 254,
    "roughPeak": 250,
    "baseMaterialPreserved": true
  },
  "realModelClearcoat": {
    "fixture": "DamagedHelmet",
    "status": "historical candidate-only",
    "fullFrameMeanAbsoluteDelta": 6.942640817901235,
    "colorRegionSpread": 220,
    "clearcoatRegionHighlight": 235,
    "note": "Manual-clearcoat iOS Simulator evidence passes the smoke thresholds but still shows overly stylized/striped behavior on a real textured GLB, so it is not production-ready."
  },
  "realModelGlassAndClearcoat": {
    "fixture": "ToyCar",
    "status": "verified locally",
    "sourceAuthoredClearcoatExtension": true,
    "sourceAuthoredTransmissionExtension": true,
    "fullFrameMeanAbsoluteDelta": 0.8378311471193416,
    "colorRegionSpread": 249,
    "highlight": 248,
    "note": "The follow-up iOS Simulator run preserves the ToyCar source PBR body material, adds a clearcoat overlay primitive, and applies the glass shader to the authored Glass node. This is durable verified-locally evidence for a candidate-only repo-owned custom shader path."
  }
}
```
