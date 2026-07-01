# 15 — Önerilen Repository Layout

```text
flutter_scene_viewer/
├── lib/
│   ├── flutter_scene_viewer.dart
│   └── src/
│       ├── widget/
│       │   ├── flutter_scene_viewer_widget.dart
│       │   └── viewer_scope.dart
│       ├── controller/
│       │   └── flutter_scene_viewer_controller.dart
│       ├── session/
│       │   ├── viewer_session.dart
│       │   ├── load_generation.dart
│       │   └── viewer_load_state.dart
│       ├── source/
│       │   ├── model_source.dart
│       │   ├── texture_source.dart
│       │   └── source_fingerprint.dart
│       ├── network/
│       │   ├── model_fetcher.dart
│       │   └── fetch_progress.dart
│       ├── validation/
│       │   ├── glb_header_validator.dart
│       │   └── viewer_limits.dart
│       ├── upstream/
│       │   └── flutter_scene_adapter.dart
│       ├── model/
│       │   ├── node_address.dart
│       │   ├── part_address.dart
│       │   ├── assembly_info.dart
│       │   ├── part_info.dart
│       │   └── part_registry.dart
│       ├── material/
│       │   ├── material_patch.dart
│       │   ├── material_snapshot.dart
│       │   ├── material_override_service.dart
│       │   └── material_capabilities.dart
│       ├── texture/
│       │   ├── runtime_texture_service.dart
│       │   ├── texture_cache.dart
│       │   └── texture_semantics.dart
│       ├── lighting/
│       │   └── viewer_lighting.dart
│       ├── camera/
│       │   ├── orbit_camera_controller.dart
│       │   ├── camera_fit.dart
│       │   └── viewer_camera_state.dart
│       ├── interaction/
│       │   ├── part_picker.dart
│       │   └── part_hit.dart
│       ├── render/
│       │   ├── render_policy.dart
│       │   ├── render_reason.dart
│       │   └── adaptive_render_scheduler.dart
│       ├── cache/
│       │   ├── model_disk_cache.dart
│       │   └── cache_metadata.dart
│       ├── state/
│       │   ├── viewer_state.dart
│       │   └── state_apply_report.dart
│       ├── diagnostics/
│       │   ├── model_diagnostics.dart
│       │   └── viewer_exception.dart
│       └── lifecycle/
│           └── resource_ownership.dart
├── test/
│   ├── unit/
│   ├── widget/
│   ├── integration/
│   └── fixtures/
├── benchmark/
├── example/
├── docs/
└── tool/
```

## Dependency direction

```text
widget/controller
      ↓
session/services/domain
      ↓
flutter_scene_adapter
      ↓
flutter_scene
```

Domain classes upstream import etmemelidir. Böylece API stabil kalır ve testler GPU olmadan çalışabilir.
