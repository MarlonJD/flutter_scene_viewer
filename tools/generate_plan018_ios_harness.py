#!/usr/bin/env python3
"""Generate and validate the disposable Plan 018 iOS capture harness."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path, PurePosixPath


REPO_ROOT = Path(__file__).resolve().parent.parent
STATE_PATH = (
    REPO_ROOT
    / "tools/material_extension_acceptance/fixtures/plan018_controlled_comparison_state.json"
)
NATIVE_CONTROL_STATE_PATH = (
    REPO_ROOT
    / "tools/material_extension_acceptance/fixtures/"
    "plan018_renderer_native_scalar_sheen_control_state.json"
)
TEMPLATE_ROOT = (
    REPO_ROOT
    / "tools/material_extension_acceptance/plan018_ios_harness_templates"
)
OUTPUT_ROOT = (
    REPO_ROOT
    / "tools/out/material_extension_acceptance/plan018_controlled_comparison"
    / "flutter_ios_harness"
)
HDR_PATH = (
    REPO_ROOT
    / "tools/out/material_extension_acceptance/plan018_controlled_comparison"
    / "plan018_controlled_studio.hdr"
)
FIXED_BUNDLE_ID = "dev.flutter_scene_viewer.plan018"
MODEL_DEFINE_KEY = "PLAN018_MODEL_ID"
FLUTTER_SCENE_REF = "766351c865c621e8720c726f9aa51173ce76e786"
PLAN018_STATE_SHA256 = "385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843"
PLAN018_NATIVE_CONTROL_STATE_SHA256 = "e55b84b6e3701a10c7cd98817328428e5f07d5adb0708ec55114f0ec2da68a63"
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
EXPECTED_MODEL_IDS = (
    "sheen_chair",
    "sheen_cloth",
    "glam_velvet_sofa",
    "toycar",
)
EXPECTED_NATIVE_CONTROL_MODEL_IDS = (
    "renderer_native_scalar_sheen_on",
    "renderer_native_scalar_sheen_off",
)
EXPECTED_PASSES = ("directOnly", "iblOnly", "combined")
CANDIDATE_STATE_ASSET_PATH = "assets/plan018_controlled_comparison_state.json"
NATIVE_CONTROL_STATE_ASSET_PATH = (
    "assets/plan018_renderer_native_scalar_sheen_control_state.json"
)


class HarnessError(RuntimeError):
    pass


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_path(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _safe_repo_path(value: object, label: str) -> Path:
    if not isinstance(value, str) or not value or "\\" in value:
        raise HarnessError(f"{label} must be a safe relative POSIX path")
    pure = PurePosixPath(value)
    if pure.is_absolute() or any(part in {"", ".", ".."} for part in pure.parts):
        raise HarnessError(f"{label} must be a safe relative POSIX path")
    path = (REPO_ROOT / pure).resolve()
    try:
        path.relative_to(REPO_ROOT.resolve())
    except ValueError as error:
        raise HarnessError(f"{label} escapes the repository") from error
    return path


def _require_hash(path: Path, expected: object, label: str) -> None:
    if not isinstance(expected, str) or SHA256_RE.fullmatch(expected) is None:
        raise HarnessError(f"{label} expected SHA-256 is invalid")
    if not path.is_file():
        raise HarnessError(f"{label} source is missing: {path}")
    actual = _sha256_path(path)
    if actual != expected:
        raise HarnessError(f"{label} SHA-256 mismatch: {actual} != {expected}")


def _load_state() -> dict[str, object]:
    _require_hash(STATE_PATH, PLAN018_STATE_SHA256, "controlled state")
    decoded = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict):
        raise HarnessError("Plan 018 controlled state must be an object")
    if decoded.get("name") != "plan018_khr_materials_sheen_controlled_comparison":
        raise HarnessError("Plan 018 controlled state identity drifted")
    if decoded.get("comparisonBoundary") != "direction/conformance-only":
        raise HarnessError("Plan 018 comparison boundary drifted")
    if decoded.get("renderPasses") != list(EXPECTED_PASSES):
        raise HarnessError("Plan 018 render pass inventory drifted")
    models = decoded.get("models")
    if not isinstance(models, dict) or tuple(models) != EXPECTED_MODEL_IDS:
        raise HarnessError("Plan 018 model order or inventory drifted")
    viewport = decoded.get("viewport")
    if viewport != {
        "logicalWidth": 402,
        "logicalHeight": 874,
        "devicePixelRatio": 3,
    }:
        raise HarnessError("Plan 018 viewport drifted")
    if decoded.get("toneMapping") != "pbrNeutral":
        raise HarnessError("Plan 018 tone mapping drifted")
    if decoded.get("outputColorSpace") != "sRGB":
        raise HarnessError("Plan 018 output color space drifted")
    return decoded


def _load_renderer_native_control_state() -> dict[str, object]:
    _require_hash(
        NATIVE_CONTROL_STATE_PATH,
        PLAN018_NATIVE_CONTROL_STATE_SHA256,
        "renderer-native control state",
    )
    decoded = json.loads(NATIVE_CONTROL_STATE_PATH.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict):
        raise HarnessError("Plan 018 renderer-native control state must be an object")
    if decoded.get("name") != "plan018_renderer_native_scalar_sheen_control":
        raise HarnessError("Plan 018 renderer-native control identity drifted")
    if (
        decoded.get("comparisonBoundary")
        != "renderer-local sheen on/off control only"
    ):
        raise HarnessError("Plan 018 renderer-native control boundary drifted")
    if decoded.get("renderPasses") != list(EXPECTED_PASSES):
        raise HarnessError("Plan 018 renderer-native render passes drifted")
    models = decoded.get("models")
    if not isinstance(models, dict) or tuple(models) != EXPECTED_NATIVE_CONTROL_MODEL_IDS:
        raise HarnessError("Plan 018 renderer-native model inventory drifted")
    base_state = _load_state()
    shared = decoded.get("sharedComparisonState")
    if shared != {
        "path": STATE_PATH.relative_to(REPO_ROOT).as_posix(),
        "sha256": PLAN018_STATE_SHA256,
    }:
        raise HarnessError("Plan 018 shared comparison-state identity drifted")
    for key in (
        "viewport",
        "background",
        "camera",
        "environment",
        "lighting",
        "renderPasses",
        "toneMapping",
        "outputColorSpace",
    ):
        if decoded.get(key) != base_state.get(key):
            raise HarnessError(f"Plan 018 renderer-native {key} drifted")
    expected_models = {
        "renderer_native_scalar_sheen_on": ("sheenOn", "rendererNative", [0]),
        "renderer_native_scalar_sheen_off": ("sheenOff", "none", []),
    }
    for model_id, (role, application, sheen_indices) in expected_models.items():
        model = models[model_id]
        if not isinstance(model, dict):
            raise HarnessError(f"{model_id} control record is malformed")
        if (
            model.get("controlRole") != role
            or model.get("expectedApplication") != application
            or model.get("sheenMaterialIndices") != sheen_indices
        ):
            raise HarnessError(f"{model_id} control semantics drifted")
        cameras = model.get("cameras")
        if not isinstance(cameras, dict) or tuple(cameras) != ("grazing",):
            raise HarnessError(f"{model_id} fixed grazing camera drifted")
    return decoded


def _capture_inventory(state: dict[str, object]) -> list[str]:
    models = state["models"]
    assert isinstance(models, dict)
    passes = state["renderPasses"]
    assert isinstance(passes, list)
    result: list[str] = []
    for model_id, raw_model in models.items():
        if not isinstance(model_id, str) or not isinstance(raw_model, dict):
            raise HarnessError("Plan 018 model catalog is malformed")
        cameras = raw_model.get("cameras")
        if not isinstance(cameras, dict) or tuple(cameras) != ("close", "grazing"):
            raise HarnessError(f"{model_id} close/grazing cameras drifted")
        for view in cameras:
            for render_pass in passes:
                result.append(f"{model_id}_{view}_{render_pass}")
        context = raw_model.get("context")
        if isinstance(context, dict) and isinstance(context.get("camera"), dict):
            for render_pass in passes:
                result.append(f"{model_id}_context_{render_pass}")
    if len(result) != 27 or len(set(result)) != 27:
        raise HarnessError(f"Plan 018 capture inventory has {len(result)} stages")
    return result


def _renderer_native_control_capture_inventory(
    state: dict[str, object],
) -> list[str]:
    models = state["models"]
    passes = state["renderPasses"]
    assert isinstance(models, dict) and isinstance(passes, list)
    result = [
        f"{model_id}_grazing_{render_pass}"
        for model_id in models
        for render_pass in passes
    ]
    if len(result) != 6 or len(set(result)) != 6:
        raise HarnessError(
            f"Plan 018 renderer-native control inventory has {len(result)} stages"
        )
    return result


def _combined_models(
    state: dict[str, object],
    native_control_state: dict[str, object],
) -> dict[str, object]:
    candidate_models = state["models"]
    native_models = native_control_state["models"]
    assert isinstance(candidate_models, dict) and isinstance(native_models, dict)
    if set(candidate_models).intersection(native_models):
        raise HarnessError("Plan 018 candidate/native model ids overlap")
    return {**candidate_models, **native_models}


def _root_dependency_contract() -> dict[str, str]:
    pubspec_path = REPO_ROOT / "pubspec.yaml"
    lock_path = REPO_ROOT / "pubspec.lock"
    pubspec = pubspec_path.read_text(encoding="utf-8")
    lock = lock_path.read_text(encoding="utf-8")
    pubspec_match = re.search(
        r"(?ms)^  flutter_scene:\n    git:\n"
        r"      url: https://github\.com/MarlonJD/flutter_scene\.git\n"
        r"      ref: ([0-9a-f]{40})\n"
        r"      path: packages/flutter_scene$",
        pubspec,
    )
    lock_match = re.search(
        r'(?ms)^  flutter_scene:\n.*?^      ref: "([0-9a-f]{40})"\n'
        r'^      resolved-ref: "([0-9a-f]{40})"\n'
        r'^      url: "https://github\.com/MarlonJD/flutter_scene\.git"\n'
        r'^    source: git$',
        lock,
    )
    if pubspec_match is None or lock_match is None:
        raise HarnessError("Exact flutter_scene root pin could not be parsed")
    ref = pubspec_match.group(1)
    lock_ref, resolved_ref = lock_match.groups()
    if ref != FLUTTER_SCENE_REF:
        raise HarnessError("flutter_scene root pin drifted from the frozen revision")
    if lock_ref != FLUTTER_SCENE_REF or resolved_ref != FLUTTER_SCENE_REF:
        raise HarnessError("flutter_scene root lock drifted from the frozen revision")
    return {
        "rootPubspecSha256": _sha256_path(pubspec_path),
        "rootLockSha256": _sha256_path(lock_path),
        "flutterSceneRef": ref,
        "flutterSceneResolvedRef": resolved_ref,
    }


def _verify_frozen_sources(state: dict[str, object]) -> None:
    _require_hash(STATE_PATH, PLAN018_STATE_SHA256, "controlled state")
    environment = state.get("environment")
    if not isinstance(environment, dict):
        raise HarnessError("Plan 018 environment is missing")
    _require_hash(HDR_PATH, environment.get("sha256"), "controlled HDR")
    models = state["models"]
    assert isinstance(models, dict)
    for model_id, raw_model in models.items():
        assert isinstance(raw_model, dict)
        model_path = _safe_repo_path(raw_model.get("path"), f"{model_id}.path")
        _require_hash(model_path, raw_model.get("sha256"), f"{model_id} GLB")
        expected_length = raw_model.get("byteLength")
        if not isinstance(expected_length, int) or model_path.stat().st_size != expected_length:
            raise HarnessError(f"{model_id} GLB byte length mismatch")
    # The hash-pinned state owns immutable candidate-era source provenance.
    # Current viewer source identity is frozen independently by the runner.


def _verify_renderer_native_control_sources(
    state: dict[str, object],
) -> None:
    _require_hash(
        NATIVE_CONTROL_STATE_PATH,
        PLAN018_NATIVE_CONTROL_STATE_SHA256,
        "renderer-native control state",
    )
    environment = state.get("environment")
    if not isinstance(environment, dict):
        raise HarnessError("Plan 018 renderer-native environment is missing")
    _require_hash(HDR_PATH, environment.get("sha256"), "controlled HDR")
    models = state["models"]
    assert isinstance(models, dict)
    for model_id, raw_model in models.items():
        assert isinstance(raw_model, dict)
        model_path = _safe_repo_path(raw_model.get("path"), f"{model_id}.path")
        _require_hash(model_path, raw_model.get("sha256"), f"{model_id} GLB")
        expected_length = raw_model.get("byteLength")
        if (
            not isinstance(expected_length, int)
            or model_path.stat().st_size != expected_length
        ):
            raise HarnessError(f"{model_id} GLB byte length mismatch")


def _read_template(name: str) -> str:
    path = TEMPLATE_ROOT / name
    if not path.is_file():
        raise HarnessError(f"tracked template is missing: {path}")
    return path.read_text(encoding="utf-8")


def _render_generated_contract(
    state: dict[str, object],
    native_control_state: dict[str, object],
    candidate_inventory: list[str],
    native_control_inventory: list[str],
    dependency: dict[str, str],
) -> str:
    all_model_ids = EXPECTED_MODEL_IDS + EXPECTED_NATIVE_CONTROL_MODEL_IDS
    model_entries = "\n".join(
        f"  {json.dumps(model_id)}: {json.dumps(f'assets/models/{model_id}.glb')},"
        for model_id in all_model_ids
    ).replace('"', "'")
    model_state_entries = "\n".join(
        f"  {json.dumps(model_id)}: {json.dumps(asset_path)},"
        for model_id, asset_path in (
            *(
                (model_id, CANDIDATE_STATE_ASSET_PATH)
                for model_id in EXPECTED_MODEL_IDS
            ),
            *(
                (model_id, NATIVE_CONTROL_STATE_ASSET_PATH)
                for model_id in EXPECTED_NATIVE_CONTROL_MODEL_IDS
            ),
        )
    ).replace('"', "'")
    candidate_screenshot_entries = "\n".join(
        f"  {json.dumps(name)}," for name in candidate_inventory
    ).replace('"', "'")
    native_control_screenshot_entries = "\n".join(
        f"  {json.dumps(name)}," for name in native_control_inventory
    ).replace('"', "'")
    inventory = candidate_inventory + native_control_inventory
    screenshot_names_by_model_entries = "\n".join(
        "  "
        + json.dumps(model_id).replace('"', "'")
        + ": <String>["
        + "".join(
            f"{json.dumps(name).replace(chr(34), chr(39))},"
            for name in inventory
            if name.startswith(f"{model_id}_")
        )
        + "],"
        for model_id in all_model_ids
    )
    rendered = _read_template("plan018_generated_contract.dart.tmpl")
    replacements = {
        "@@STATE_SHA256@@": PLAN018_STATE_SHA256,
        "@@NATIVE_CONTROL_STATE_SHA256@@": PLAN018_NATIVE_CONTROL_STATE_SHA256,
        "@@ROOT_PUBSPEC_SHA256@@": dependency["rootPubspecSha256"],
        "@@ROOT_LOCK_SHA256@@": dependency["rootLockSha256"],
        "@@FLUTTER_SCENE_REF@@": dependency["flutterSceneRef"],
        "@@FLUTTER_SCENE_RESOLVED_REF@@": dependency[
            "flutterSceneResolvedRef"
        ],
        "@@MODEL_ASSET_ENTRIES@@": model_entries,
        "@@MODEL_STATE_ASSET_ENTRIES@@": model_state_entries,
        "@@CANDIDATE_SCREENSHOT_NAME_ENTRIES@@": candidate_screenshot_entries,
        "@@NATIVE_CONTROL_SCREENSHOT_NAME_ENTRIES@@": (
            native_control_screenshot_entries
        ),
        "@@SCREENSHOT_NAMES_BY_MODEL_ENTRIES@@": (
            screenshot_names_by_model_entries
        ),
    }
    for placeholder, value in replacements.items():
        rendered = rendered.replace(placeholder, value)
    if "@@" in rendered:
        raise HarnessError("generated contract contains an unresolved placeholder")
    return rendered


def _expected_rendered_files(
    state: dict[str, object],
    native_control_state: dict[str, object],
    candidate_inventory: list[str],
    native_control_inventory: list[str],
    dependency: dict[str, str],
) -> dict[str, bytes]:
    texts = {
        "pubspec.yaml": _read_template("pubspec.yaml.tmpl"),
        "analysis_options.yaml": _read_template("analysis_options.yaml.tmpl"),
        "lib/main.dart": _read_template("main.dart.tmpl"),
        "lib/plan018_generated_contract.dart": _render_generated_contract(
            state,
            native_control_state,
            candidate_inventory,
            native_control_inventory,
            dependency,
        ),
        "integration_test/plan018_capture_test.dart": _read_template(
            "plan018_capture_test.dart.tmpl"
        ),
        "test_driver/integration_test.dart": _read_template(
            "integration_test_driver.dart.tmpl"
        ),
        "ios/Runner/Info.plist": _read_template("Info.plist.tmpl"),
        "assets/plan018_capture_inventory.json": json.dumps(
            candidate_inventory, indent=2
        )
        + "\n",
        "assets/plan018_renderer_native_control_capture_inventory.json": json.dumps(
            native_control_inventory, indent=2
        )
        + "\n",
    }
    return {name: text.encode("utf-8") for name, text in texts.items()}


def _ensure_ios_scaffold(output: Path) -> None:
    project = output / "ios/Runner.xcodeproj/project.pbxproj"
    if project.is_file():
        return
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        "flutter",
        "create",
        "--empty",
        "--no-pub",
        "--platforms=ios",
        "--org",
        "dev.flutter_scene_viewer",
        "--project-name",
        "plan018_flutter_ios_harness",
        str(output),
    ]
    completed = subprocess.run(
        command,
        cwd=REPO_ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if completed.returncode != 0:
        raise HarnessError(
            "flutter create --empty --no-pub failed:\n"
            f"{completed.stdout}\n{completed.stderr}"
        )


def _write_bytes(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file() and path.read_bytes() == data:
        return
    path.write_bytes(data)


def _patch_bundle_identifiers(project_path: Path) -> None:
    source = project_path.read_text(encoding="utf-8")

    def replace(match: re.Match[str]) -> str:
        old = match.group(1)
        suffix = ".RunnerTests" if old.endswith(".RunnerTests") else ""
        return f"PRODUCT_BUNDLE_IDENTIFIER = {FIXED_BUNDLE_ID}{suffix};"

    patched, count = re.subn(
        r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);",
        replace,
        source,
    )
    if count == 0:
        raise HarnessError("iOS project has no bundle identifier setting")
    project_path.write_text(patched, encoding="utf-8")


def generate() -> None:
    state = _load_state()
    native_control_state = _load_renderer_native_control_state()
    candidate_inventory = _capture_inventory(state)
    native_control_inventory = _renderer_native_control_capture_inventory(
        native_control_state
    )
    dependency = _root_dependency_contract()
    _verify_frozen_sources(state)
    _verify_renderer_native_control_sources(native_control_state)
    _ensure_ios_scaffold(OUTPUT_ROOT)
    rendered = _expected_rendered_files(
        state,
        native_control_state,
        candidate_inventory,
        native_control_inventory,
        dependency,
    )
    for relative_path, data in rendered.items():
        _write_bytes(OUTPUT_ROOT / relative_path, data)

    _write_bytes(
        OUTPUT_ROOT / "assets/plan018_controlled_comparison_state.json",
        STATE_PATH.read_bytes(),
    )
    _write_bytes(
        OUTPUT_ROOT
        / "assets/plan018_renderer_native_scalar_sheen_control_state.json",
        NATIVE_CONTROL_STATE_PATH.read_bytes(),
    )
    _write_bytes(
        OUTPUT_ROOT / "assets/plan018_controlled_studio.hdr",
        HDR_PATH.read_bytes(),
    )
    models = _combined_models(state, native_control_state)
    for model_id, raw_model in models.items():
        assert isinstance(model_id, str) and isinstance(raw_model, dict)
        source = _safe_repo_path(raw_model["path"], f"{model_id}.path")
        _write_bytes(
            OUTPUT_ROOT / f"assets/models/{model_id}.glb",
            source.read_bytes(),
        )

    widget_test = OUTPUT_ROOT / "test/widget_test.dart"
    if widget_test.is_file():
        _write_bytes(
            widget_test,
            b"// The generated integration target owns harness validation.\n"
            b"void main() {}\n",
        )
    _patch_bundle_identifiers(
        OUTPUT_ROOT / "ios/Runner.xcodeproj/project.pbxproj"
    )
    validate_output(OUTPUT_ROOT)
    print(
        "Plan 018 iOS harness: 27 candidate capture stages + "
        "6 renderer-native control stages OK "
        f"({MODEL_DEFINE_KEY}, release pending, integration path not run)"
    )


def _all_dart_sources(output: Path) -> list[Path]:
    roots = (output / "lib", output / "integration_test", output / "test_driver")
    result: list[Path] = []
    for root in roots:
        if root.is_dir():
            result.extend(sorted(root.rglob("*.dart")))
    return result


def _validate_resolved_output(output: Path, *, required: bool) -> None:
    lock_path = output / "pubspec.lock"
    config_path = output / ".dart_tool/package_config.json"
    if not lock_path.exists() and not config_path.exists() and not required:
        return
    if not lock_path.is_file() or not config_path.is_file():
        raise HarnessError(
            "resolved output requires paired pubspec.lock and package_config.json"
        )

    lock = lock_path.read_text(encoding="utf-8")
    lock_match = re.search(
        r'(?ms)^  flutter_scene:\n'
        r'^    dependency: transitive\n'
        r'^    description:\n'
        r'^      path: "packages/flutter_scene"\n'
        r'^      ref: "([0-9a-f]{40})"\n'
        r'^      resolved-ref: "([0-9a-f]{40})"\n'
        r'^      url: "https://github\.com/MarlonJD/flutter_scene\.git"\n'
        r'^    source: git\n'
        r'^    version: "0\.18\.1"$',
        lock,
    )
    if lock_match is None or any(
        value != FLUTTER_SCENE_REF for value in lock_match.groups()
    ):
        raise HarnessError("generated flutter_scene lock resolution drifted")

    config = json.loads(config_path.read_text(encoding="utf-8"))
    packages = config.get("packages") if isinstance(config, dict) else None
    if not isinstance(packages, list):
        raise HarnessError("generated package_config packages are missing")
    flutter_scene_entries = [
        entry
        for entry in packages
        if isinstance(entry, dict) and entry.get("name") == "flutter_scene"
    ]
    if len(flutter_scene_entries) != 1:
        raise HarnessError("generated package_config flutter_scene entry drifted")
    root_uri = flutter_scene_entries[0].get("rootUri")
    expected_suffix = (
        f"/flutter_scene-{FLUTTER_SCENE_REF}/packages/flutter_scene"
    )
    if not isinstance(root_uri, str) or not root_uri.rstrip("/").endswith(
        expected_suffix
    ):
        raise HarnessError("generated package_config flutter_scene root drifted")


def validate_output(output: Path, *, require_resolved: bool = False) -> None:
    state = _load_state()
    native_control_state = _load_renderer_native_control_state()
    candidate_inventory = _capture_inventory(state)
    native_control_inventory = _renderer_native_control_capture_inventory(
        native_control_state
    )
    dependency = _root_dependency_contract()
    _verify_frozen_sources(state)
    _verify_renderer_native_control_sources(native_control_state)
    output = output.resolve()
    if not output.is_dir():
        raise HarnessError(f"generated output is missing: {output}")
    expected = _expected_rendered_files(
        state,
        native_control_state,
        candidate_inventory,
        native_control_inventory,
        dependency,
    )
    for relative_path, data in expected.items():
        path = output / relative_path
        if not path.is_file():
            raise HarnessError(f"generated source is missing: {relative_path}")
        if path.read_bytes() != data:
            raise HarnessError(f"generated source drifted: {relative_path}")

    if (output / "pubspec_overrides.yaml").exists():
        raise HarnessError("generated harness must not contain pubspec_overrides.yaml")
    pubspec = (output / "pubspec.yaml").read_text(encoding="utf-8")
    if re.search(r"(?m)^\s*flutter_scene:\s*", pubspec):
        raise HarnessError("generated harness must not depend on flutter_scene directly")
    if "dependency_overrides:" in pubspec:
        raise HarnessError("generated harness must not declare dependency overrides")
    if "path: ../../../../.." not in pubspec:
        raise HarnessError("generated harness root path dependency drifted")
    _validate_resolved_output(output, required=require_resolved)

    dart_sources = _all_dart_sources(output)
    combined = "\n".join(path.read_text(encoding="utf-8") for path in dart_sources)
    forbidden = {
        "direct flutter_scene import": "package:flutter_scene/",
        "network model source": "ModelSource.network",
        "network environment source": "ViewerPolyHavenEnvironment",
        "mutable camera fitting": "fitCamera(",
        "HTTP URL": "http://",
        "HTTPS URL": "https://",
    }
    for label, token in forbidden.items():
        if token in combined:
            raise HarnessError(f"generated harness contains forbidden {label}")
    main_source = (output / "lib/main.dart").read_text(encoding="utf-8")
    required_main = (
        "FlutterSceneViewer.test(",
        "FlutterSceneRuntimeAdapter(",
        "RenderPolicy.always",
        "MaterialShadingPolicy.authored",
        "ViewerMaterialExtensionPolicy.productionShaders(",
        "enableTransmission: true",
        "enableClearcoat: true",
        "enableSheen: true",
        f"String.fromEnvironment('{MODEL_DEFINE_KEY}')",
        "readGlbMaterialExtensionIntent(",
        "adapter.rootNode",
        "adapter.debugScene",
        "sampledTexture",
        "PLAN018_READY",
        "PLAN018_DIAGNOSTIC",
        "PLAN018_COMPLETE",
    )
    for token in required_main:
        if token not in main_source:
            raise HarnessError(f"generated main is missing contract token: {token}")
    for asset_name in ("ToyCar", "Fabric", "Glass"):
        if f"'{asset_name}'" in main_source or f'"{asset_name}"' in main_source:
            raise HarnessError("harness behavior must not branch on asset/material names")

    integration_source = (
        output / "integration_test/plan018_capture_test.dart"
    ).read_text(encoding="utf-8")
    if "takeScreenshot(name)" not in integration_source:
        raise HarnessError("integration target must call takeScreenshot(name) without args")
    if "pumpAndSettle" in integration_source:
        raise HarnessError("RenderPolicy.always harness must not use pumpAndSettle")
    driver_source = (output / "test_driver/integration_test.dart").read_text(
        encoding="utf-8"
    )
    for token in (
        "integrationDriver(",
        "pngSignature",
        "1206",
        "2622",
        "plan018ExpectedScreenshotNamesByModel",
        "plan018_integration_response_$modelId",
    ):
        if token not in driver_source:
            raise HarnessError(f"screenshot driver is missing contract token: {token}")

    inventory_path = output / "assets/plan018_capture_inventory.json"
    if (
        json.loads(inventory_path.read_text(encoding="utf-8"))
        != candidate_inventory
    ):
        raise HarnessError("generated screenshot inventory drifted")
    native_inventory_path = (
        output / "assets/plan018_renderer_native_control_capture_inventory.json"
    )
    if (
        json.loads(native_inventory_path.read_text(encoding="utf-8"))
        != native_control_inventory
    ):
        raise HarnessError("generated renderer-native inventory drifted")
    state_output = output / "assets/plan018_controlled_comparison_state.json"
    if state_output.read_bytes() != STATE_PATH.read_bytes():
        raise HarnessError("generated app did not copy the current state exactly")
    native_state_output = (
        output
        / "assets/plan018_renderer_native_scalar_sheen_control_state.json"
    )
    if native_state_output.read_bytes() != NATIVE_CONTROL_STATE_PATH.read_bytes():
        raise HarnessError(
            "generated app did not copy the renderer-native state exactly"
        )
    environment = state["environment"]
    assert isinstance(environment, dict)
    _require_hash(
        output / "assets/plan018_controlled_studio.hdr",
        environment["sha256"],
        "generated controlled HDR",
    )
    models = _combined_models(state, native_control_state)
    for model_id, raw_model in models.items():
        assert isinstance(model_id, str) and isinstance(raw_model, dict)
        model_path = output / f"assets/models/{model_id}.glb"
        _require_hash(model_path, raw_model["sha256"], f"generated {model_id}")
        if model_path.stat().st_size != raw_model["byteLength"]:
            raise HarnessError(f"generated {model_id} byte length drifted")

    info = (output / "ios/Runner/Info.plist").read_text(encoding="utf-8")
    if "<key>FLTEnableFlutterGPU</key>" not in info:
        raise HarnessError("iOS scaffold does not enable Flutter GPU")
    if "<key>CADisableMinimumFrameDurationOnPhone</key>" not in info:
        raise HarnessError("iOS scaffold lost minimum-frame-duration support")
    if "UIInterfaceOrientationLandscape" in info:
        raise HarnessError("iOS scaffold is not portrait-only")
    project = (output / "ios/Runner.xcodeproj/project.pbxproj").read_text(
        encoding="utf-8"
    )
    identifiers = re.findall(r"PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);", project)
    if not identifiers or any(
        value not in {FIXED_BUNDLE_ID, f"{FIXED_BUNDLE_ID}.RunnerTests"}
        for value in identifiers
    ):
        raise HarnessError("iOS bundle identifier is not fixed")


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--validate-output",
        type=Path,
        help="validate an existing generated harness without changing it",
    )
    parser.add_argument(
        "--require-resolved-output",
        action="store_true",
        help="require and validate pubspec.lock plus package_config.json",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    try:
        if args.validate_output is not None:
            validate_output(
                args.validate_output,
                require_resolved=args.require_resolved_output,
            )
            print(
                "Plan 018 iOS harness validation: 27 candidate capture "
                "stages + 6 renderer-native control stages OK"
            )
        elif args.require_resolved_output:
            raise HarnessError(
                "--require-resolved-output requires --validate-output"
            )
        else:
            generate()
    except (HarnessError, OSError, ValueError, json.JSONDecodeError) as error:
        print(f"Plan 018 iOS harness error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
