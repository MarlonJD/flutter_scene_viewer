#!/usr/bin/env python3
"""Run and record one bounded Plan 018 iOS Simulator capture model."""

from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import math
import os
import re
import selectors
import signal
import struct
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


REPO_ROOT = Path(__file__).resolve().parent.parent
FLUTTER_BIN = Path("/Users/marlonjd/Developer/flutter/bin/flutter")
HARNESS_ROOT = (
    REPO_ROOT
    / "tools/out/material_extension_acceptance/plan018_controlled_comparison"
    / "flutter_ios_harness"
)
IOS_OUTPUT_ROOT = (
    REPO_ROOT
    / "tools/out/material_extension_acceptance/plan018_controlled_comparison"
    / "ios_simulator"
)
PLAN018_OUTPUT_ROOT = IOS_OUTPUT_ROOT.parent
THREE_CAPTURE_ROOT = (
    REPO_ROOT
    / "tools/out/material_extension_acceptance/plan018_controlled_comparison"
    / "threejs"
)
THREE_EVIDENCE_PATH = THREE_CAPTURE_ROOT / "evidence.json"
THREE_CAPTURE_PATH_PREFIX = (
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/threejs"
)
KHRONOS_CAPTURE_ROOT = PLAN018_OUTPUT_ROOT / "khronos_sample_renderer"
KHRONOS_TOYCAR_EVIDENCE_PATH = KHRONOS_CAPTURE_ROOT / "evidence.json"
KHRONOS_GLAM_EVIDENCE_PATH = (
    KHRONOS_CAPTURE_ROOT / "glam_velvet_sofa_evidence.json"
)
IOS_HEALTH_ANALYZER_PATH = (
    REPO_ROOT
    / "tools/reference_renderers/threejs_material_extension_fixture"
    / "analyze_plan018_ios_capture_health.mjs"
)
RENDERER_NATIVE_HEALTH_ANALYZER_PATH = (
    REPO_ROOT
    / "tools/reference_renderers/threejs_material_extension_fixture"
    / "analyze_plan018_renderer_native_sheen_control.mjs"
)
STATE_PATH = (
    REPO_ROOT
    / "tools/material_extension_acceptance/fixtures"
    / "plan018_controlled_comparison_state.json"
)
NATIVE_CONTROL_STATE_PATH = (
    REPO_ROOT
    / "tools/material_extension_acceptance/fixtures"
    / "plan018_renderer_native_scalar_sheen_control_state.json"
)
ACCEPTANCE_MANIFEST_PATH = (
    REPO_ROOT / "tools/material_extension_acceptance/manifest.json"
)
GENERATOR_PATH = REPO_ROOT / "tools/generate_plan018_ios_harness.py"

EXPECTED_HEAD = "af0568c11126904bbcfae72338ba51fb313cc9e9"
EXPECTED_PIN = "766351c865c621e8720c726f9aa51173ce76e786"
EXPECTED_CACHE_TREE = "1479be24e5472cece6c041151bc48f663146da94"
RETAINED_M3_CANDIDATE_PIN = "8e2e2221405b04c517189428d0faf8474cf7f708"
RETAINED_M3_CANDIDATE_CACHE_TREE = "f4a25955cc7fe886a0addb476387eea40ec86742"
RETAINED_M3_FINAL_EVIDENCE_SHA256 = (
    "87cb87f7ecce3b5916ae72896d1b7980ca6d950ef18a2aed2165734cb8d05cbb"
)
RETAINED_M3_ROOT_PUBSPEC_SHA256 = (
    "f71dfea644bdd430e22b484feb154b4f0f64f86173e69e29ee96af1b219bb6ca"
)
RETAINED_M3_ROOT_LOCK_SHA256 = (
    "31e55352f3fdd09fa874d08b3bb4cd8c0fd87bbca33a5e0566f5d0112d4cdcd9"
)
CACHE_CHECKOUT = Path(
    "/Users/marlonjd/.pub-cache/git"
) / f"flutter_scene-{EXPECTED_PIN}"
EXPECTED_STATE_SHA256 = (
    "385b1a476d74c6ef670f80fdc42066b6191179619006c3094dc5dbaa31eb7843"
)
EXPECTED_NATIVE_CONTROL_STATE_SHA256 = (
    "e55b84b6e3701a10c7cd98817328428e5f07d5adb0708ec55114f0ec2da68a63"
)
EXPECTED_ENVIRONMENT_SHA256 = (
    "ef94e6aa0de3e5703a245f2e18dfd3b7bf8e07a24a794395cd50bd6e746e6a4a"
)
EXPECTED_MODELS = (
    "sheen_chair",
    "sheen_cloth",
    "glam_velvet_sofa",
    "toycar",
)
EXPECTED_NATIVE_CONTROL_MODELS = (
    "renderer_native_scalar_sheen_on",
    "renderer_native_scalar_sheen_off",
)
EXPECTED_PARTIAL_MODELS = (
    "sheen_cloth",
    "glam_velvet_sofa",
    "toycar",
)
EXPECTED_PARTIAL_MISSING_MODELS = ("sheen_chair",)
EXPECTED_KHRONOS_REFERENCE_MODELS = ("toycar", "glam_velvet_sofa")
EXPECTED_PASSES = ("directOnly", "iblOnly", "combined")
HISTORICAL_LOG_SCAN_BYTES = 1024 * 1024
MATERIAL_EXTENSION_KEYS = (
    "KHR_materials_sheen",
    "KHR_materials_clearcoat",
    "KHR_materials_transmission",
    "KHR_materials_volume",
    "KHR_materials_ior",
    "KHR_materials_specular",
)
PART_ADDRESS_KEYS = frozenset(("nodePath", "primitiveIndex"))
INSTALLED_SHEEN_KEYS = frozenset(
    (
        "authoredAddress",
        "concreteAddress",
        "materialType",
        "hasSheenIntent",
        "usesSheenShader",
        "usesClearcoatShader",
        "sheenColorFactor",
        "sheenRoughness",
        "sheenColorTextureExpected",
        "sheenColorTextureGpuBacked",
        "sheenRoughnessTextureExpected",
        "sheenRoughnessTextureGpuBacked",
    )
)
INSTALLED_PROBE_KEYS = frozenset(
    (
        "authoredDefaultSceneSheenCount",
        "installedDefaultSceneSheenCount",
        "installedDefaultSceneSheen",
        "noExtraRuntimeSheen",
        "genericSeparateExtensionRoles",
        "nonDefaultDependencyBoundary",
    )
)
GENERIC_ROLE_KEYS = frozenset(
    (
        "selection",
        "sheenAddresses",
        "clearcoatAddresses",
        "transmissionVolumeAddresses",
        "distinctPrimitiveAddresses",
        "distinctMaterialIdentity",
        "clearcoatFactors",
        "transmissionFactors",
    )
)
FACTOR_RECORD_KEYS = frozenset(("address", "expected", "actual"))
NON_DEFAULT_DEPENDENCY_BOUNDARY = (
    "Authored dependency indices are recorded separately; only "
    "default-scene suffix-resolved primitives are installed and rendered."
)
EXPECTED_RUNTIME_KEY_SUFFIX = "iOS-26-5"
EXPECTED_DEVICE_NAME = "iPhone 17"
IMPELLER_BACKEND = "Impeller Metal"
IMPELLER_LOG_SOURCE = "iOS Simulator unified log"
IMPELLER_LOG_PREDICATE = (
    'process == "Runner" AND '
    '(eventMessage CONTAINS "Using the Impeller rendering backend" OR '
    'eventMessage CONTAINS "PLAN018_COMPLETE")'
)
IMPELLER_EVENT_MESSAGE = (
    "[IMPORTANT:flutter/shell/platform/darwin/graphics/"
    "FlutterDarwinContextMetalImpeller.mm(45)] "
    "Using the Impeller rendering backend (Metal)."
)
IMPELLER_EVIDENCE_KEYS = frozenset(
    (
        "schemaVersion",
        "status",
        "executionEvidence",
        "fixtureValidation",
        "source",
        "modelId",
        "deviceUdid",
        "captureWindow",
        "queryCommand",
        "records",
    )
)
IMPELLER_RECORD_KEYS = frozenset(
    (
        "kind",
        "timestamp",
        "eventMessage",
        "eventType",
        "messageType",
        "processId",
        "processImagePath",
        "processImageUuid",
        "senderImagePath",
        "bootUuid",
    )
)
EXPECTED_PNG_SIGNATURE = bytes((137, 80, 78, 71, 13, 10, 26, 10))
EXPECTED_PHYSICAL_WIDTH = 1206
EXPECTED_PHYSICAL_HEIGHT = 2622
EXPECTED_LOGICAL_WIDTH = 402.0
EXPECTED_LOGICAL_HEIGHT = 874.0
EXPECTED_DPR = 3.0
COMMAND_TIMEOUT_SECONDS = 30.0
DEVICE_DISCOVERY_TIMEOUT_SECONDS = 60.0
HARNESS_VALIDATION_TIMEOUT_SECONDS = 60.0
FLUTTER_DRIVE_TIMEOUT_SECONDS = 1800.0
PROCESS_TERMINATION_GRACE_SECONDS = 10.0
PROCESS_KILL_WAIT_SECONDS = 5.0
STREAM_DRAIN_TIMEOUT_SECONDS = 1.0

FROZEN_HASHES = {
    "pubspec.yaml": "89538562bf96a228fdd13c0d0a6a2ee92df27616615f4c42116b61ca464d5586",
    "pubspec.lock": "7c9415caf27fdca2453234a7ea61e7a54df79eef25947a7767e4486206eeaa95",
    "lib/src/internal/flutter_scene_adapter.dart": "d1d1a3cec68c0b4261507a3a30fcec7c589fb58e7fddd4acbfecf58b9b875de3",
    "lib/src/internal/flutter_scene_extended_pbr_backend.dart": "dc68f414f2e00fd6094f8ae10fef382dec21248047fbcbbb0ef32d3003f45efc",
    "lib/src/internal/flutter_scene_extended_pbr_material.dart": "a67c31f7132d00be0f423c245fd44085d67d855ce5e0032bac4da38caa0ac713",
    "lib/src/internal/flutter_scene_material_extension_backend.dart": "e90d8ff9c3d9138a67af7b0b5ea310f7400194091af1436fa5d15690dbb81085",
    "lib/src/internal/glb_capability_reader.dart": "3b7dca41416fc0f2ad6e83e2ba28d22dd1a69a1c2b0bb86d456fc4bb0701ab27",
    "lib/src/internal/glb_material_extension_reader.dart": "225476d7688e213447dc94d69238e7403e3e44baf3b0962c6cd7116378072c6f",
    "lib/src/internal/glb_texture_binding_reader.dart": "68d47e214bd7cdfd2352557bbbbb055a187b363c9c731e574c912430122c840c",
    "lib/src/internal/material_extension_native_applier.dart": "a398b1f09848be2872ebf510c72a4099f968c870418ca5ec9c876e66c08e239b",
    "lib/src/internal/material_extension_native_capability.dart": "b9a237580a2b18a1171ee8ffb578cddb3f517bd4bc3cd866a7b7682a52383a91",
    "lib/src/internal/material_extension_patch_group.dart": "5d413ed6265b12da82cd129fe9956a1bafd22e35088215fdd12cbd7051a43afd",
    "lib/src/internal/sheen_semantics.dart": "7e318f321eccce10dc8ec73336ef5636ae1f5da489ac785336f57f4a13cd2c95",
    "lib/src/material_extension_policy.dart": "674970e1d24aff6e9f5be66729335402775d5073e0f04fa29e82aad8538afeaa",
    "lib/src/material_patch.dart": "e187fd88b09d1377efaad60dddb8e3c5f25def2616aa386582fd79871023f6ff",
    "lib/src/model_loader.dart": "72493b77d005c637c5ca4b588320f2b3ffb2652b750b24f2399a25c1ff53ed61",
    "lib/src/texture_binding.dart": "3031d4249c5ab27ca428b0078d5e6628f29a7e210235596d0d7582f0eb0bf38d",
    "lib/src/viewer_controller.dart": "4d14b1dd3acdfc1a4612310c5287e9cf5d8918f3fbbcf882a9015fe697a9ea6c",
    "lib/src/viewer_widget.dart": "451151df37c0b72b340b64068eb4d6b54c1c538a614e80a7f01adfd7e3abe04f",
    "shaders/fsviewer_extended_pbr.frag": "91db4f3e08424025ffa82a6d82db4c8f4603215eefc3f04a8fb11f3342bec56d",
    "shaders/fsviewer_extended_pbr_uv1.frag": "abc69bcdaa6cebe40c749447cebcdea1742cc5c2375f6700696239aecbcf254b",
    "shaders/fsviewer_clearcoat_extended_pbr.frag": "b449bf46f7da13ed5ace3ed1804fadadf6388f0ce6ec7c9a7b1b7b4586d1b899",
    "shaders/fsviewer_clearcoat_extended_pbr_uv1.frag": "dd69a5614b3111b6521a97168788214f089e4716f5e3e802be1a654aa6373ee2",
    "shaders/fsviewer_sheen_extended_pbr.frag": "6e32cf046a99495228340030fb2f85720f3dc81cd33f2f0b30f5d265091ea630",
    "shaders/fsviewer_sheen_extended_pbr_uv1.frag": "bca51c16988070fd644dc8596991edac7e97df2b254371834b5726ee8d3873ee",
    "shaders/fsviewer_clearcoat_sheen_extended_pbr.frag": "b0a4416c28399103d64e9e3b9626998eaaf3779e49aaf1ccdd9be925697c066f",
    "shaders/fsviewer_clearcoat_sheen_extended_pbr_uv1.frag": "4051d34a98e3c93ef86345957416a77d425447ad831dfeb8bc551d17399ce8d4",
    "shaders/fsviewer_extended_pbr.shaderbundle.json": "2ecfa2f8f7abc9680965d495762c1f0acfd690883e23a9934ab7fe25cd7a664e",
    "tools/generate_plan018_ios_harness.py": "0707df23db30d097bfc74bf91433fbdb58b80852eeff77f73c246389df815a33",
    "test/plan018_ios_harness_generator_test.dart": "5bf365cc78429796fa054859a39bb2d6b7128b9050201b33912e2633d12de389",
    "tools/material_extension_acceptance/plan018_ios_harness_templates/Info.plist.tmpl": "a79075faf9ed118adb91f9acd8a46180f68795b6526aa31d132b29cae1d22871",
    "tools/material_extension_acceptance/plan018_ios_harness_templates/analysis_options.yaml.tmpl": "b5326ee03221b0411611df13a8464297dc2d9f81bfc042ab025df866254a610b",
    "tools/material_extension_acceptance/plan018_ios_harness_templates/integration_test_driver.dart.tmpl": "6df2f4df7ad32a3864dc35aa8a8b7329a50e5d3fa96f5aecce4c6042d7c254b0",
    "tools/material_extension_acceptance/plan018_ios_harness_templates/main.dart.tmpl": "a98a51212bcc5614b65dd8c46bca98200e0b26c7fb1eeda0e8b1b395ae1ff880",
    "tools/material_extension_acceptance/plan018_ios_harness_templates/plan018_capture_test.dart.tmpl": "1b87f40986da4134f600504da73a11dd61114012e06951ddaf7eb271e84a6999",
    "tools/material_extension_acceptance/plan018_ios_harness_templates/plan018_generated_contract.dart.tmpl": "5b8c448e3498fe8e682c3ef0d8bc203bc37c1682f6cbf3e6baafec5b454d9f81",
    "tools/material_extension_acceptance/plan018_ios_harness_templates/pubspec.yaml.tmpl": "9bd6efbf287e96cca9caeb2b941922c43b3fe8848fd8863481d79100574f2894",
    "tools/generate_plan018_renderer_native_sheen_fixture.py": "7f86260f720fdafa243c93dedbfbf8a35949a823be36a747210a0a124e52365b",
    "test/fixtures/MultiMaterialAssembly.glb": "5f717f321050c3049a29cdf3e3223ad10fd05ce485a088011f77d84357b9ad5f",
    "test/fixtures/Plan018RendererNativeSheenControl.glb": "8c0d893fbf72553b3dbf4d9bf8bfa3a1a24bbbfebd699beee5cf72a8216d967d",
    "test/plan018_renderer_native_sheen_fixture_test.dart": "c8fd3c57cfe7eb7b45de74a7d2cc12203d245cf4b5046a3756caeca54b5a24e4",
    "tools/material_extension_acceptance/fixtures/plan018_controlled_comparison_state.json": EXPECTED_STATE_SHA256,
    "tools/material_extension_acceptance/fixtures/plan018_renderer_native_scalar_sheen_control_state.json": EXPECTED_NATIVE_CONTROL_STATE_SHA256,
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/plan018_controlled_studio.hdr": EXPECTED_ENVIRONMENT_SHA256,
    "tools/out/material_extension_acceptance/plan018_sheen_corpus/sheen_chair/source/SheenChair.glb": "f0af2a2b102d28d540236306ae19f8fb36842df76bd38cf76f063f9bd2853399",
    "tools/out/material_extension_acceptance/plan018_sheen_corpus/sheen_cloth/derived/SheenCloth.glb": "bab89a56fe44396877f35fc794222b54f2107ba273634c6514c2a910cab61588",
    "tools/out/material_extension_acceptance/plan018_sheen_corpus/glam_velvet_sofa/source/GlamVelvetSofa.glb": "67202c74a1a33377771f162dc7fad612a6c9bd51ee15124c488e9851d9ac5266",
    "tools/out/material_extension_acceptance/plan018_sheen_corpus/toycar/source/ToyCar.glb": "01a60862de55cd4b9f3acfab0b0def86451800f9c42467fcd61052c16cb9838c",
    "tools/reference_renderers/threejs_material_extension_fixture/package.json": "43baa2b7276859a9aef8ad327f50dd1f827366652b69cec89dd1b1ca6d1b6d78",
    "tools/reference_renderers/threejs_material_extension_fixture/package-lock.json": "9f8355fc951b35917e7275513a329a5d446611e6655b5ec2933ab766e0c94c2a",
    "tools/reference_renderers/threejs_material_extension_fixture/README.md": "4424a5c00719fab795393c75349b4e912eed4e572194fcc3632243fcb4445bec",
    "tools/reference_renderers/threejs_material_extension_fixture/plan018_controlled_comparison_contract.mjs": "1f953cbb7f2d19c9b3c0eaf0a1ca1569b98b21e0ff23c3884038e2ec81438835",
    "tools/reference_renderers/threejs_material_extension_fixture/plan018_controlled_comparison.test.mjs": "55e29e63f08e8d01d2a206771bbc287fdfad151a4f1ea7bdcbb51d4c7b73eeae",
    "tools/reference_renderers/threejs_material_extension_fixture/inspect_plan018_sheen_loader.mjs": "1fa417b298b0f355d6a2ec6cbb868cd15062afc47b683ccc16c9f3de2e3d0f95",
    "tools/reference_renderers/threejs_material_extension_fixture/render_plan018_controlled_comparison.mjs": "7c51ca1bc995227dd53c99d6305f649ab4d3e37b0831ca9043ca153b567fd957",
    "tools/reference_renderers/threejs_material_extension_fixture/render_plan018_controlled_comparison.test.mjs": "d329a5b9de8f7a32f51ce826c5e28523d60901fbb1a7242fc5bf2d7817ec97e4",
    "tools/reference_renderers/threejs_material_extension_fixture/plan018_controlled_comparison_analysis.mjs": "2c6336ce39cf18d0fa6ae58fd6f372406a411a65533c77cf8ed4acf6ba96def6",
    "tools/reference_renderers/threejs_material_extension_fixture/plan018_controlled_comparison_analysis.test.mjs": "e38cdea1bb8a1e827d3c40efbf8ac97d07c25ac932843d9771e5a89202737812",
    "tools/reference_renderers/threejs_material_extension_fixture/analyze_plan018_controlled_comparison_health.mjs": "25cad6d1d4031c9c3bfebc99466513d32426965c558f5dae448a218a193d6b90",
    "tools/reference_renderers/threejs_material_extension_fixture/analyze_plan018_controlled_comparison_health.test.mjs": "487bda4a03ea45260e9005ba132b06ef8adc39f647d5afce93d7e3b8465eeb48",
    "tools/reference_renderers/threejs_material_extension_fixture/analyze_plan018_renderer_native_sheen_control.mjs": "87dfa3368c9b06836f151031fccebe7e3d09120d107a5c6da843e75ba278da58",
    "tools/reference_renderers/threejs_material_extension_fixture/analyze_plan018_renderer_native_sheen_control.test.mjs": "f2c7b6f2beabe4140fc6cb7e089795faee291d83100507d5c316b874fe102e80",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/threejs/evidence.json": "f86291c540ea7023a26451ad551b4b6d66181ee92f566cd13e5a273b8aa5498b",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/threejs_loader_audit.json": "729c867f36a6079aa8b9069fabd90b600e3000270db5b8038d90b6b889c47bfc",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/threejs/health_baseline.json": "4f4dd8b26cb9677405b15b78e2070936f2a111e45aba43997cac87728d61142d",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/flutter_ios_harness/analysis_options.yaml": "b5326ee03221b0411611df13a8464297dc2d9f81bfc042ab025df866254a610b",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/flutter_ios_harness/pubspec.yaml": "9bd6efbf287e96cca9caeb2b941922c43b3fe8848fd8863481d79100574f2894",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/flutter_ios_harness/pubspec.lock": "a99d1d3c588de5450148a2446da1fa706a0d1d30a20cba15dbb541670cff4818",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/flutter_ios_harness/.dart_tool/package_config.json": "762a209b51530f5ab4e31dc880ffd56940adc0257d74448b1e31d4bdf06d4fe8",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/flutter_ios_harness/lib/main.dart": "a98a51212bcc5614b65dd8c46bca98200e0b26c7fb1eeda0e8b1b395ae1ff880",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/flutter_ios_harness/lib/plan018_generated_contract.dart": "0ff5250af272f68fec228606795a90e90112a71943cde5b07d1b7aae32a2f6f3",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/flutter_ios_harness/integration_test/plan018_capture_test.dart": "1b87f40986da4134f600504da73a11dd61114012e06951ddaf7eb271e84a6999",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/flutter_ios_harness/test_driver/integration_test.dart": "6df2f4df7ad32a3864dc35aa8a8b7329a50e5d3fa96f5aecce4c6042d7c254b0",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/flutter_ios_harness/ios/Runner/Info.plist": "a79075faf9ed118adb91f9acd8a46180f68795b6526aa31d132b29cae1d22871",
    "tools/out/material_extension_acceptance/plan018_controlled_comparison/flutter_ios_harness/ios/Runner.xcodeproj/project.pbxproj": "34945810997239fb579ee38a2ebf01292bcf939da327e9abb446919b57f387ce",
}

DYNAMIC_SOURCE_PATHS = (
    "tools/run_plan018_ios_capture.py",
    "test/plan018_ios_capture_runner_test.dart",
    "test/plan018_renderer_native_ios_capture_runner_test.dart",
    ".superpowers/sdd/plan018-m3-task5-slice5a-brief.md",
    ".superpowers/sdd/plan018-m3-task5-slice5a-report.md",
)
POST_CAPTURE_MUTABLE_SOURCE_PATHS = frozenset(
    (
        "tools/run_plan018_ios_capture.py",
        "test/plan018_ios_capture_runner_test.dart",
        "test/plan018_renderer_native_ios_capture_runner_test.dart",
    )
)


class CaptureError(RuntimeError):
    """A capture contract violation."""


class CaptureTimeoutError(CaptureError):
    """A bounded child process exceeded its wall-clock deadline."""

    def __init__(
        self,
        *,
        operation: str,
        timeout_seconds: float,
        termination: dict[str, Any],
        partial_log: str | None = None,
    ) -> None:
        super().__init__(
            f"{operation} exceeded its {timeout_seconds:g}s wall-clock timeout"
        )
        self.operation = operation
        self.timeout_seconds = timeout_seconds
        self.termination = termination
        self.partial_log = partial_log

    def to_json(self) -> dict[str, Any]:
        result = {
            "type": type(self).__name__,
            "operation": self.operation,
            "timeoutSeconds": self.timeout_seconds,
            **self.termination,
        }
        if self.partial_log is not None:
            result["partialLog"] = self.partial_log
        return result


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        while True:
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()


def json_text(value: Any) -> str:
    return json.dumps(value, indent=2, sort_keys=True) + "\n"


def path_resolves_within(path: Path, root: Path) -> bool:
    try:
        path.resolve(strict=True).relative_to(root.resolve(strict=True))
    except (OSError, ValueError):
        return False
    return True


def read_bounded_text(path: Path, byte_limit: int) -> tuple[str, bool]:
    with path.open("rb") as source:
        data = source.read(byte_limit + 1)
    truncated = len(data) > byte_limit
    return data[:byte_limit].decode("utf-8", errors="replace"), truncated


def timeout_contract() -> dict[str, float]:
    return {
        "deviceDiscoveryTimeoutSeconds": DEVICE_DISCOVERY_TIMEOUT_SECONDS,
        "harnessValidationTimeoutSeconds": HARNESS_VALIDATION_TIMEOUT_SECONDS,
        "captureTimeoutSeconds": FLUTTER_DRIVE_TIMEOUT_SECONDS,
        "terminationGraceSeconds": PROCESS_TERMINATION_GRACE_SECONDS,
        "killWaitSeconds": PROCESS_KILL_WAIT_SECONDS,
        "streamDrainTimeoutSeconds": STREAM_DRAIN_TIMEOUT_SECONDS,
    }


def terminate_then_kill(
    process: subprocess.Popen[Any],
    *,
    grace_seconds: float,
) -> dict[str, Any]:
    process_group = process.pid

    def group_exists() -> bool:
        try:
            os.killpg(process_group, 0)
        except ProcessLookupError:
            return False
        except PermissionError:
            return True
        return True

    def wait_for_group(deadline: float) -> bool:
        while group_exists() and time.monotonic() < deadline:
            process.poll()
            time.sleep(0.02)
        return not group_exists()

    evidence: dict[str, Any] = {
        "timedOut": True,
        "terminateAttempted": False,
        "terminationGraceSeconds": grace_seconds,
        "killRequired": False,
        "exitCode": process.poll(),
    }
    if group_exists():
        evidence["terminateAttempted"] = True
        try:
            os.killpg(process_group, signal.SIGTERM)
        except ProcessLookupError:
            pass
        group_gone = wait_for_group(time.monotonic() + grace_seconds)
        if not group_gone:
            evidence["killRequired"] = True
            try:
                os.killpg(process_group, signal.SIGKILL)
            except ProcessLookupError:
                pass
            if not wait_for_group(
                time.monotonic() + PROCESS_KILL_WAIT_SECONDS
            ):
                evidence["killWaitExpired"] = True
    if process.poll() is None:
        try:
            process.wait(timeout=PROCESS_KILL_WAIT_SECONDS)
        except subprocess.TimeoutExpired:
            evidence["parentReaped"] = False
        else:
            evidence["parentReaped"] = True
    else:
        evidence["parentReaped"] = True
    evidence["exitCode"] = process.returncode
    evidence["processGroupExitConfirmed"] = not group_exists()
    return evidence


def run_checked(
    arguments: list[str],
    *,
    cwd: Path | None = None,
    timeout_seconds: float = COMMAND_TIMEOUT_SECONDS,
    termination_grace_seconds: float = PROCESS_TERMINATION_GRACE_SECONDS,
    operation: str | None = None,
) -> str:
    process = subprocess.Popen(
        arguments,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired as error:
        termination = terminate_then_kill(
            process,
            grace_seconds=termination_grace_seconds,
        )
        try:
            process.communicate(timeout=STREAM_DRAIN_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            if process.stdout is not None:
                process.stdout.close()
            if process.stderr is not None:
                process.stderr.close()
        raise CaptureTimeoutError(
            operation=operation or arguments[0],
            timeout_seconds=timeout_seconds,
            termination=termination,
        ) from error
    if process.returncode != 0:
        detail = stderr.strip() or stdout.strip()
        raise CaptureError(f"Command failed ({arguments[0]}): {detail}")
    return stdout.strip()


def git(arguments: list[str], *, checkout: Path = REPO_ROOT) -> str:
    return run_checked(
        ["git", "--no-optional-locks", "-C", str(checkout), *arguments]
    )


def load_state() -> dict[str, Any]:
    if sha256_path(STATE_PATH) != EXPECTED_STATE_SHA256:
        raise CaptureError("Plan 018 controlled-state bytes drifted")
    decoded = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict):
        raise CaptureError("Plan 018 controlled state is not an object")
    if tuple(decoded.get("models", {})) != EXPECTED_MODELS:
        raise CaptureError("Plan 018 model order or inventory drifted")
    if tuple(decoded.get("renderPasses", ())) != EXPECTED_PASSES:
        raise CaptureError("Plan 018 pass inventory drifted")
    return decoded


def load_renderer_native_control_state() -> dict[str, Any]:
    if sha256_path(NATIVE_CONTROL_STATE_PATH) != EXPECTED_NATIVE_CONTROL_STATE_SHA256:
        raise CaptureError("Plan 018 renderer-native control-state bytes drifted")
    decoded = json.loads(NATIVE_CONTROL_STATE_PATH.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict):
        raise CaptureError("Plan 018 renderer-native control state is not an object")
    if decoded.get("name") != "plan018_renderer_native_scalar_sheen_control":
        raise CaptureError("Plan 018 renderer-native control identity drifted")
    if (
        decoded.get("comparisonBoundary")
        != "renderer-local sheen on/off control only"
    ):
        raise CaptureError("Plan 018 renderer-native control boundary drifted")
    if tuple(decoded.get("models", {})) != EXPECTED_NATIVE_CONTROL_MODELS:
        raise CaptureError("Plan 018 renderer-native model inventory drifted")
    if tuple(decoded.get("renderPasses", ())) != EXPECTED_PASSES:
        raise CaptureError("Plan 018 renderer-native pass inventory drifted")
    shared = decoded.get("sharedComparisonState")
    if shared != {
        "path": str(STATE_PATH.relative_to(REPO_ROOT)),
        "sha256": EXPECTED_STATE_SHA256,
    }:
        raise CaptureError("Plan 018 shared candidate-state provenance drifted")
    return decoded


def expected_renderer_native_control_names(
    state: dict[str, Any],
    model_id: str,
) -> list[str]:
    if model_id not in EXPECTED_NATIVE_CONTROL_MODELS:
        raise CaptureError("Unknown Plan 018 renderer-native control model")
    model = state["models"][model_id]
    if tuple(model.get("cameras", {})) != ("grazing",):
        raise CaptureError(f"{model_id} renderer-native camera inventory drifted")
    return [
        f"{model_id}_grazing_{render_pass}"
        for render_pass in EXPECTED_PASSES
    ]


def expected_names(state: dict[str, Any], model_id: str) -> list[str]:
    model = state["models"][model_id]
    views = list(model["cameras"])
    context = model.get("context")
    if isinstance(context, dict) and isinstance(context.get("camera"), dict):
        views.append("context")
    return [
        f"{model_id}_{view}_{render_pass}"
        for view in views
        for render_pass in EXPECTED_PASSES
    ]


def expected_three_inventory(state: dict[str, Any]) -> list[dict[str, str]]:
    result: list[dict[str, str]] = []
    for model_id in EXPECTED_MODELS:
        model = state["models"][model_id]
        views = list(model["cameras"])
        context = model.get("context")
        if isinstance(context, dict) and isinstance(context.get("camera"), dict):
            views.append("context")
        for view in views:
            for render_pass in EXPECTED_PASSES:
                result.append(
                    {
                        "modelId": model_id,
                        "view": view,
                        "pass": render_pass,
                        "fileName": f"{model_id}_{view}_{render_pass}.png",
                    }
                )
    return result


def validate_three_capture_set(
    *,
    evidence_path: Path,
    capture_root: Path,
    path_prefix: str,
    fixture_validation: bool,
) -> dict[str, Any]:
    evidence = read_json_file(evidence_path)
    inventory = expected_three_inventory(load_state())
    if (
        evidence.get("schemaVersion") != 1
        or evidence.get("status") != "verified locally"
        or evidence.get("stateSha256") != EXPECTED_STATE_SHA256
    ):
        raise CaptureError("Three capture evidence identity drifted")
    if evidence.get("captureInventory") != inventory:
        raise CaptureError("Three capture evidence lacks the exact ordered inventory")
    captures = evidence.get("captures")
    if not isinstance(captures, list) or len(captures) != len(inventory):
        raise CaptureError("Three capture evidence must contain exactly 27 captures")
    for index, (capture, expected) in enumerate(
        zip(captures, inventory, strict=True)
    ):
        if not isinstance(capture, dict):
            raise CaptureError(f"Three capture[{index}] is not an object")
        for key in ("modelId", "view", "pass"):
            require_equal(capture, key, expected[key], f"Three capture[{index}]")
        require_equal(
            capture,
            "path",
            f"{path_prefix}/{expected['fileName']}",
            f"Three capture[{index}]",
        )
    expected_files = sorted(item["fileName"] for item in inventory)
    actual_files = sorted(
        str(path.relative_to(capture_root))
        for path in capture_root.rglob("*.png")
        if path.is_file()
    )
    if actual_files != expected_files:
        raise CaptureError("Three capture root lacks the exact 27 PNG inventory")
    artifact_records: list[dict[str, Any]] = []
    for index, (capture, expected) in enumerate(
        zip(captures, inventory, strict=True)
    ):
        path = capture_root / expected["fileName"]
        if path.is_symlink():
            raise CaptureError(f"Three capture[{index}] path is a symlink")
        actual = png_record(path, capture_root)
        if capture.get("sha256") != actual["sha256"]:
            raise CaptureError(f"Three capture[{index}] sha256 drifted")
        if capture.get("byteLength") != actual["byteLength"]:
            raise CaptureError(f"Three capture[{index}] byteLength drifted")
        if capture.get("dimensions") != actual["dimensions"]:
            raise CaptureError(f"Three capture[{index}] dimensions drifted")
        artifact_records.append(actual)
    return {
        "status": "fixture-only" if fixture_validation else "verified locally",
        "executionEvidence": "not run" if fixture_validation else "verified locally",
        "fixtureValidation": fixture_validation,
        "evidencePath": str(evidence_path),
        "evidenceSha256": sha256_path(evidence_path),
        "pngCount": len(captures),
        "orderedCaptureInventory": inventory,
        "artifacts": artifact_records,
    }


def collect_source_hashes() -> dict[str, str]:
    result: dict[str, str] = {}
    for relative_path, expected in FROZEN_HASHES.items():
        path = REPO_ROOT / relative_path
        if not path.is_file():
            raise CaptureError(f"Frozen source is missing: {relative_path}")
        actual = sha256_path(path)
        if actual != expected:
            raise CaptureError(
                f"Frozen source drifted: {relative_path}: {actual} != {expected}"
            )
        result[relative_path] = actual
    for relative_path in DYNAMIC_SOURCE_PATHS:
        path = REPO_ROOT / relative_path
        if path.is_file():
            result[relative_path] = sha256_path(path)
    return result


def expected_flutter_scene_package_uri() -> str:
    return (CACHE_CHECKOUT / "packages/flutter_scene").as_uri()


def assert_dependency_boundary() -> None:
    root_override = REPO_ROOT / "pubspec_overrides.yaml"
    harness_override = HARNESS_ROOT / "pubspec_overrides.yaml"
    if root_override.exists() or harness_override.exists():
        raise CaptureError("A pubspec override exists")

    harness_pubspec = (HARNESS_ROOT / "pubspec.yaml").read_text(encoding="utf-8")
    if re.search(r"(?m)^  flutter_scene:\s*$", harness_pubspec):
        raise CaptureError("Generated harness declares flutter_scene directly")
    if "dependency_overrides:" in harness_pubspec:
        raise CaptureError("Generated harness declares a dependency override")
    for source in HARNESS_ROOT.rglob("*.dart"):
        if "package:flutter_scene/" in source.read_text(encoding="utf-8"):
            raise CaptureError(
                f"Generated harness imports flutter_scene directly: {source}"
            )

    lock = (HARNESS_ROOT / "pubspec.lock").read_text(encoding="utf-8")
    if (
        f'ref: "{EXPECTED_PIN}"' not in lock
        or f'resolved-ref: "{EXPECTED_PIN}"' not in lock
        or 'path: "../../../../.."' not in lock
    ):
        raise CaptureError("Generated lock does not preserve the exact path/pin")

    package_config = json.loads(
        (HARNESS_ROOT / ".dart_tool/package_config.json").read_text(
            encoding="utf-8"
        )
    )
    packages = {
        entry["name"]: entry
        for entry in package_config.get("packages", [])
        if isinstance(entry, dict) and isinstance(entry.get("name"), str)
    }
    expected_scene_uri = expected_flutter_scene_package_uri()
    if packages.get("flutter_scene", {}).get("rootUri") != expected_scene_uri:
        raise CaptureError("Generated package config resolves another flutter_scene")
    if packages.get("flutter_scene_viewer", {}).get("rootUri") != "../../../../../../":
        raise CaptureError("Generated package config does not resolve the root package")


def repository_guard() -> dict[str, Any]:
    if git(["branch", "--show-current"]) != "main":
        raise CaptureError("Capture checkout is not on main")
    head = git(["rev-parse", "HEAD"])
    origin_main = git(["rev-parse", "origin/main"])
    if head != EXPECTED_HEAD or origin_main != EXPECTED_HEAD:
        raise CaptureError("HEAD/origin/main drifted from the Plan 018 base")
    if not FLUTTER_BIN.is_file():
        raise CaptureError(f"Exact Flutter binary is missing: {FLUTTER_BIN}")
    if not HARNESS_ROOT.is_dir():
        raise CaptureError(f"Generated harness is missing: {HARNESS_ROOT}")

    sources = collect_source_hashes()
    reference_capture_set = validate_three_capture_set(
        evidence_path=THREE_EVIDENCE_PATH,
        capture_root=THREE_CAPTURE_ROOT,
        path_prefix=THREE_CAPTURE_PATH_PREFIX,
        fixture_validation=False,
    )
    assert_dependency_boundary()
    cache_head = git(["rev-parse", "HEAD"], checkout=CACHE_CHECKOUT)
    cache_tree = git(["rev-parse", "HEAD^{tree}"], checkout=CACHE_CHECKOUT)
    cache_status = git(
        ["status", "--porcelain=v1", "--untracked-files=all"],
        checkout=CACHE_CHECKOUT,
    )
    if cache_head != EXPECTED_PIN or cache_tree != EXPECTED_CACHE_TREE:
        raise CaptureError("Pub-cache checkout identity drifted")
    if cache_status:
        raise CaptureError("Pub-cache checkout is dirty")

    run_checked(
        [
            sys.executable,
            str(GENERATOR_PATH),
            "--validate-output",
            str(HARNESS_ROOT),
        ],
        cwd=REPO_ROOT,
        timeout_seconds=HARNESS_VALIDATION_TIMEOUT_SECONDS,
        operation="generated harness validation",
    )
    return {
        "branch": "main",
        "head": head,
        "originMain": origin_main,
        "flutterBinary": str(FLUTTER_BIN),
        "harnessRoot": str(HARNESS_ROOT),
        "sourceSha256": sources,
        "referenceCaptureSet": reference_capture_set,
        "flutterScenePin": EXPECTED_PIN,
        "pubCacheCheckout": str(CACHE_CHECKOUT),
        "pubCacheHead": cache_head,
        "pubCacheTree": cache_tree,
        "pubCacheClean": True,
        "generatedHarnessValidator": "passed",
    }


def validate_udid(value: str | None) -> str:
    if value is None or re.fullmatch(
        r"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}",
        value,
    ) is None:
        raise CaptureError("An explicit uppercase Simulator UDID is required")
    return value


def query_devices(fixture_path: Path | None) -> tuple[dict[str, Any], list[Any], str]:
    if fixture_path is not None:
        decoded = json.loads(fixture_path.read_text(encoding="utf-8"))
        if not isinstance(decoded, dict):
            raise CaptureError("Device fixture must be an object")
        simctl = decoded.get("simctl")
        flutter_devices = decoded.get("flutterDevices")
        if not isinstance(simctl, dict) or not isinstance(flutter_devices, list):
            raise CaptureError("Device fixture lacks simctl/flutterDevices")
        return simctl, flutter_devices, "fixture"

    simctl_text = run_checked(
        [
            "/usr/bin/xcrun",
            "simctl",
            "list",
            "devices",
            "booted",
            "--json",
        ],
        timeout_seconds=DEVICE_DISCOVERY_TIMEOUT_SECONDS,
        operation="simctl device discovery",
    )
    flutter_text = run_checked(
        [str(FLUTTER_BIN), "devices", "--machine"],
        timeout_seconds=DEVICE_DISCOVERY_TIMEOUT_SECONDS,
        operation="Flutter device discovery",
    )
    simctl = json.loads(simctl_text)
    flutter_devices = json.loads(flutter_text)
    if not isinstance(simctl, dict) or not isinstance(flutter_devices, list):
        raise CaptureError("Device discovery returned malformed JSON")
    return simctl, flutter_devices, "live"


def validate_device(
    explicit_udid: str,
    simctl: dict[str, Any],
    flutter_devices: list[Any],
    source: str,
) -> dict[str, Any]:
    candidates: list[tuple[str, dict[str, Any]]] = []
    devices_by_runtime = simctl.get("devices")
    if not isinstance(devices_by_runtime, dict):
        raise CaptureError("simctl JSON has no device map")
    for runtime, devices in devices_by_runtime.items():
        if not isinstance(runtime, str) or not runtime.endswith(
            EXPECTED_RUNTIME_KEY_SUFFIX
        ):
            continue
        if not isinstance(devices, list):
            continue
        for device in devices:
            if (
                isinstance(device, dict)
                and device.get("name") == EXPECTED_DEVICE_NAME
                and device.get("state") == "Booted"
                and device.get("isAvailable") is True
            ):
                candidates.append((runtime, device))
    if len(candidates) != 1:
        raise CaptureError(
            "Expected exactly one available booted iPhone 17 on iOS 26.5; "
            f"found {len(candidates)}"
        )
    runtime, simulator = candidates[0]
    if simulator.get("udid") != explicit_udid:
        raise CaptureError("Explicit UDID does not match the sole eligible Simulator")

    flutter_matches = [
        item
        for item in flutter_devices
        if isinstance(item, dict)
        and item.get("id") == explicit_udid
        and item.get("targetPlatform") == "ios"
        and item.get("emulator") is True
        and item.get("isSupported") is not False
    ]
    if len(flutter_matches) != 1:
        raise CaptureError("Flutter does not expose the exact eligible Simulator")
    return {
        "source": source,
        "name": EXPECTED_DEVICE_NAME,
        "runtime": runtime,
        "operatingSystem": "iOS 26.5",
        "udid": explicit_udid,
        "state": "Booted",
        "available": True,
        "flutterDevice": flutter_matches[0],
    }


def resolve_real_run_root(argument: str) -> Path:
    candidate = Path(argument)
    if not candidate.is_absolute():
        candidate = REPO_ROOT / candidate
    resolved = candidate.resolve()
    if resolved.parent != IOS_OUTPUT_ROOT.resolve():
        raise CaptureError(f"Run root must be a direct child of {IOS_OUTPUT_ROOT}")
    if not resolved.name.startswith("candidate-run-"):
        raise CaptureError("Run-root name must begin with candidate-run-")
    return resolved


def resolve_renderer_native_run_root(argument: str) -> Path:
    candidate = Path(argument)
    if not candidate.is_absolute():
        candidate = REPO_ROOT / candidate
    resolved = candidate.resolve()
    if resolved.parent != IOS_OUTPUT_ROOT.resolve():
        raise CaptureError(f"Run root must be a direct child of {IOS_OUTPUT_ROOT}")
    if not resolved.name.startswith("renderer-native-run-"):
        raise CaptureError("Run-root name must begin with renderer-native-run-")
    return resolved


def capture_command(model_id: str, udid: str) -> list[str]:
    return [
        str(FLUTTER_BIN),
        "drive",
        "--no-pub",
        "--debug",
        "--enable-impeller",
        "-d",
        udid,
        "--driver=test_driver/integration_test.dart",
        "--target=integration_test/plan018_capture_test.dart",
        f"--dart-define=PLAN018_MODEL_ID={model_id}",
    ]


def model_paths(run_root: Path, model_id: str, names: Iterable[str]) -> list[Path]:
    return [
        run_root / "logs" / f"{model_id}.log",
        run_root / "logs" / f"{model_id}.impeller.json",
        run_root / f"plan018_integration_response_{model_id}.json",
        run_root / "manifests" / f"{model_id}.json",
        run_root / "manifests" / f"{model_id}.failed.json",
        *(run_root / f"{name}.png" for name in names),
    ]


def existing_model_paths(
    run_root: Path,
    model_id: str,
    names: Iterable[str],
) -> list[Path]:
    paths = {
        path
        for path in model_paths(run_root, model_id, names)
        if path.exists()
    }
    paths.update(run_root.glob(f"{model_id}_*.png"))
    return sorted(paths)


def parse_prefixed_json(log: str, prefix: str) -> list[dict[str, Any]]:
    decoder = json.JSONDecoder()
    result: list[dict[str, Any]] = []
    line_prefix = f"flutter: {prefix}"
    for line in log.splitlines():
        if prefix not in line:
            continue
        if not line.startswith(line_prefix):
            raise CaptureError(f"Malformed {prefix.strip()} line prefix")
        payload = line[len(line_prefix) :].lstrip()
        try:
            value, end = decoder.raw_decode(payload)
        except json.JSONDecodeError as error:
            raise CaptureError(f"Malformed {prefix.strip()} JSON: {error}") from error
        if payload[end:].strip():
            raise CaptureError(f"Malformed {prefix.strip()} trailing JSON data")
        if not isinstance(value, dict):
            raise CaptureError(f"{prefix.strip()} payload is not an object")
        result.append(value)
    return result


def require_equal(record: dict[str, Any], key: str, expected: Any, stage: str) -> None:
    actual = record.get(key)
    if isinstance(expected, bool):
        matches = actual is expected
    elif isinstance(expected, (int, float)):
        matches = (
            not isinstance(actual, bool)
            and isinstance(actual, (int, float))
            and math.isfinite(actual)
            and actual == expected
        )
    else:
        matches = actual == expected
    if not matches:
        raise CaptureError(
            f"{stage} field {key} drifted: {actual!r} != {expected!r}"
        )


def require_numeric_vector(
    actual: Any,
    expected: list[float],
    *,
    field: str,
    stage: str,
) -> None:
    if not isinstance(actual, list) or len(actual) != len(expected):
        raise CaptureError(f"{stage} field {field} drifted")
    for actual_value, expected_value in zip(actual, expected, strict=True):
        if (
            isinstance(actual_value, bool)
            or not isinstance(actual_value, (int, float))
            or not math.isfinite(actual_value)
            or abs(actual_value - expected_value) > 1e-6
        ):
            raise CaptureError(f"{stage} field {field} drifted")


def part_address_key(value: Any, *, field: str, stage: str) -> str:
    if not isinstance(value, dict):
        raise CaptureError(f"{stage} {field} contains a non-object address")
    if set(value) != PART_ADDRESS_KEYS:
        raise CaptureError(f"{stage} {field} contains a non-exact PartAddress")
    node_path = value.get("nodePath")
    primitive_index = value.get("primitiveIndex")
    if (
        not isinstance(node_path, list)
        or not node_path
        or any(not isinstance(segment, str) or not segment for segment in node_path)
        or isinstance(primitive_index, bool)
        or not isinstance(primitive_index, int)
        or primitive_index < 0
    ):
        raise CaptureError(f"{stage} {field} contains an invalid PartAddress")
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def validate_factor_records(
    roles: dict[str, Any],
    *,
    address_field: str,
    factor_field: str,
    stage: str,
) -> set[str]:
    addresses = roles.get(address_field)
    factors = roles.get(factor_field)
    if not isinstance(addresses, list) or not addresses:
        raise CaptureError(f"{stage} lacks non-empty {address_field}")
    if not isinstance(factors, list) or len(factors) != len(addresses):
        raise CaptureError(f"{stage} lacks one {factor_field} proof per address")
    address_keys = {
        part_address_key(value, field=address_field, stage=stage)
        for value in addresses
    }
    if len(address_keys) != len(addresses):
        raise CaptureError(f"{stage} {address_field} contains duplicates")
    factor_address_keys: set[str] = set()
    for index, factor in enumerate(factors):
        if not isinstance(factor, dict):
            raise CaptureError(f"{stage} {factor_field}[{index}] is not an object")
        if set(factor) != FACTOR_RECORD_KEYS:
            raise CaptureError(f"{stage} {factor_field}[{index}] keys drifted")
        factor_address_keys.add(
            part_address_key(
                factor.get("address"),
                field=f"{factor_field}[{index}].address",
                stage=stage,
            )
        )
        expected = factor.get("expected")
        actual = factor.get("actual")
        if (
            isinstance(expected, bool)
            or isinstance(actual, bool)
            or not isinstance(expected, (int, float))
            or not isinstance(actual, (int, float))
            or not math.isfinite(expected)
            or not math.isfinite(actual)
            or abs(expected - actual) > 1e-6
        ):
            raise CaptureError(
                f"{stage} {factor_field}[{index}] does not match authored intent"
            )
    if factor_address_keys != address_keys or len(factor_address_keys) != len(factors):
        raise CaptureError(f"{stage} {factor_field} addresses drifted")
    return address_keys


def finite_glb_number(value: Any, *, field: str, default: float) -> float:
    if value is None:
        return default
    if (
        isinstance(value, bool)
        or not isinstance(value, (int, float))
        or not math.isfinite(value)
    ):
        raise CaptureError(f"Frozen GLB field {field} is not a finite number")
    return float(value)


def finite_glb_vector(
    value: Any,
    *,
    field: str,
    default: list[float],
) -> list[float]:
    if value is None:
        return list(default)
    if not isinstance(value, list) or len(value) != len(default):
        raise CaptureError(f"Frozen GLB field {field} has the wrong vector shape")
    return [
        finite_glb_number(item, field=f"{field}[{index}]", default=0.0)
        for index, item in enumerate(value)
    ]


def read_frozen_glb_json(model_state: dict[str, Any]) -> dict[str, Any]:
    relative_path = model_state.get("path")
    expected_hash = model_state.get("sha256")
    expected_length = model_state.get("byteLength")
    if not isinstance(relative_path, str) or not relative_path:
        raise CaptureError("Controlled state model lacks a GLB path")
    path = (REPO_ROOT / relative_path).resolve()
    try:
        path.relative_to(REPO_ROOT.resolve())
    except ValueError as error:
        raise CaptureError("Controlled state model path leaves the repository") from error
    if not path.is_file():
        raise CaptureError(f"Frozen GLB is missing: {relative_path}")
    data = path.read_bytes()
    if (
        not isinstance(expected_length, int)
        or isinstance(expected_length, bool)
        or len(data) != expected_length
        or not isinstance(expected_hash, str)
        or hashlib.sha256(data).hexdigest() != expected_hash
    ):
        raise CaptureError(f"Frozen GLB identity drifted: {relative_path}")
    if len(data) < 20 or data[:4] != b"glTF":
        raise CaptureError(f"Frozen model is not a GLB 2 container: {relative_path}")
    version, declared_length = struct.unpack_from("<II", data, 4)
    if version != 2 or declared_length != len(data):
        raise CaptureError(f"Frozen GLB header drifted: {relative_path}")
    offset = 12
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk_end = offset + chunk_length
        if chunk_end > len(data):
            raise CaptureError(f"Frozen GLB chunk is truncated: {relative_path}")
        if chunk_type == 0x4E4F534A:
            try:
                decoded = json.loads(
                    data[offset:chunk_end]
                    .decode("utf-8")
                    .rstrip("\x00\t\r\n ")
                )
            except (UnicodeDecodeError, json.JSONDecodeError) as error:
                raise CaptureError(
                    f"Frozen GLB JSON is malformed: {relative_path}"
                ) from error
            if not isinstance(decoded, dict):
                raise CaptureError(f"Frozen GLB JSON is not an object: {relative_path}")
            return decoded
        offset = chunk_end
    raise CaptureError(f"Frozen GLB JSON chunk is missing: {relative_path}")


def glb_list(value: Any, *, field: str) -> list[Any]:
    if value is None:
        return []
    if not isinstance(value, list):
        raise CaptureError(f"Frozen GLB field {field} is not a list")
    return value


def glb_object(value: Any, *, field: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise CaptureError(f"Frozen GLB field {field} is not an object")
    if any(not isinstance(key, str) for key in value):
        raise CaptureError(f"Frozen GLB field {field} has a non-string key")
    return value


def glb_material_extensions(
    materials: list[Any],
    material_index: int,
) -> dict[str, Any]:
    if material_index < 0 or material_index >= len(materials):
        raise CaptureError("Frozen GLB primitive material index is out of range")
    material = glb_object(
        materials[material_index],
        field=f"materials[{material_index}]",
    )
    raw_extensions = material.get("extensions")
    if raw_extensions is None:
        return {}
    return glb_object(
        raw_extensions,
        field=f"materials[{material_index}].extensions",
    )


def glb_part_address(node_path: list[str], primitive_index: int) -> dict[str, Any]:
    return {
        "nodePath": list(node_path),
        "primitiveIndex": primitive_index,
    }


def derive_frozen_glb_contract(model_state: dict[str, Any]) -> dict[str, Any]:
    document = read_frozen_glb_json(model_state)
    materials = glb_list(document.get("materials"), field="materials")
    nodes = glb_list(document.get("nodes"), field="nodes")
    meshes = glb_list(document.get("meshes"), field="meshes")
    scenes = glb_list(document.get("scenes"), field="scenes")

    authored_inventory = {
        extension: [
            index
            for index in range(len(materials))
            if extension in glb_material_extensions(materials, index)
        ]
        for extension in MATERIAL_EXTENSION_KEYS
    }

    if scenes:
        scene_index = document.get("scene", 0)
        if (
            isinstance(scene_index, bool)
            or not isinstance(scene_index, int)
            or scene_index < 0
            or scene_index >= len(scenes)
        ):
            raise CaptureError("Frozen GLB default scene index is invalid")
        scene = glb_object(scenes[scene_index], field=f"scenes[{scene_index}]")
        root_indices = glb_list(
            scene.get("nodes"),
            field=f"scenes[{scene_index}].nodes",
        )
    else:
        child_indices: set[int] = set()
        for node_index, raw_node in enumerate(nodes):
            node = glb_object(raw_node, field=f"nodes[{node_index}]")
            for child in glb_list(
                node.get("children"),
                field=f"nodes[{node_index}].children",
            ):
                if isinstance(child, bool) or not isinstance(child, int):
                    raise CaptureError("Frozen GLB child index is not an integer")
                child_indices.add(child)
        root_indices = [
            index for index in range(len(nodes)) if index not in child_indices
        ]

    primitives: list[dict[str, Any]] = []

    def visit_node(
        raw_node_index: Any,
        parent_path: list[str],
        stack: set[int],
    ) -> None:
        if isinstance(raw_node_index, bool) or not isinstance(raw_node_index, int):
            raise CaptureError("Frozen GLB node index is not an integer")
        node_index = raw_node_index
        if node_index in stack:
            return
        if node_index < 0 or node_index >= len(nodes):
            raise CaptureError("Frozen GLB node index is out of range")
        node = glb_object(nodes[node_index], field=f"nodes[{node_index}]")
        raw_name = node.get("name")
        if raw_name is None:
            name = f"node_{node_index}"
        elif isinstance(raw_name, str) and raw_name:
            name = raw_name
        else:
            raise CaptureError("Frozen GLB node name is invalid")
        node_path = [*parent_path, name]
        mesh_index = node.get("mesh")
        if mesh_index is not None:
            if (
                isinstance(mesh_index, bool)
                or not isinstance(mesh_index, int)
                or mesh_index < 0
                or mesh_index >= len(meshes)
            ):
                raise CaptureError("Frozen GLB mesh index is invalid")
            mesh = glb_object(meshes[mesh_index], field=f"meshes[{mesh_index}]")
            raw_primitives = glb_list(
                mesh.get("primitives"),
                field=f"meshes[{mesh_index}].primitives",
            )
            for primitive_index, raw_primitive in enumerate(raw_primitives):
                primitive = glb_object(
                    raw_primitive,
                    field=f"meshes[{mesh_index}].primitives[{primitive_index}]",
                )
                material_index = primitive.get("material")
                if material_index is None:
                    continue
                if isinstance(material_index, bool) or not isinstance(
                    material_index, int
                ):
                    raise CaptureError("Frozen GLB material index is not an integer")
                extensions = glb_material_extensions(materials, material_index)
                primitives.append(
                    {
                        "address": glb_part_address(node_path, primitive_index),
                        "concreteAddress": glb_part_address(
                            ["root", *node_path], primitive_index
                        ),
                        "materialIndex": material_index,
                        "extensions": extensions,
                    }
                )
        stack.add(node_index)
        for child in glb_list(
            node.get("children"),
            field=f"nodes[{node_index}].children",
        ):
            visit_node(child, node_path, stack)
        stack.remove(node_index)

    for root_index in root_indices:
        visit_node(root_index, [], set())

    default_material_indices = sorted(
        {primitive["materialIndex"] for primitive in primitives}
    )
    default_inventory = {
        extension: [
            index
            for index in default_material_indices
            if extension in glb_material_extensions(materials, index)
        ]
        for extension in MATERIAL_EXTENSION_KEYS
    }

    installed_sheen: list[dict[str, Any]] = []
    sheen_primitives = [
        primitive
        for primitive in primitives
        if "KHR_materials_sheen" in primitive["extensions"]
    ]
    for primitive in sheen_primitives:
        sheen = glb_object(
            primitive["extensions"]["KHR_materials_sheen"],
            field="KHR_materials_sheen",
        )
        installed_sheen.append(
            {
                "authoredAddress": primitive["address"],
                "concreteAddress": primitive["concreteAddress"],
                "materialType": "FlutterSceneExtendedPbrMaterial",
                "hasSheenIntent": True,
                "usesSheenShader": True,
                "usesClearcoatShader": (
                    "KHR_materials_clearcoat" in primitive["extensions"]
                ),
                "sheenColorFactor": finite_glb_vector(
                    sheen.get("sheenColorFactor"),
                    field="KHR_materials_sheen.sheenColorFactor",
                    default=[0.0, 0.0, 0.0],
                ),
                "sheenRoughness": finite_glb_number(
                    sheen.get("sheenRoughnessFactor"),
                    field="KHR_materials_sheen.sheenRoughnessFactor",
                    default=0.0,
                ),
                "sheenColorTextureExpected": "sheenColorTexture" in sheen,
                "sheenColorTextureGpuBacked": "sheenColorTexture" in sheen,
                "sheenRoughnessTextureExpected": (
                    "sheenRoughnessTexture" in sheen
                ),
                "sheenRoughnessTextureGpuBacked": (
                    "sheenRoughnessTexture" in sheen
                ),
            }
        )

    grouped_primitives = {
        "sheen": sheen_primitives,
        "clearcoat": [
            primitive
            for primitive in primitives
            if "KHR_materials_clearcoat" in primitive["extensions"]
        ],
        "transmissionVolume": [
            primitive
            for primitive in primitives
            if "KHR_materials_transmission" in primitive["extensions"]
            or "KHR_materials_volume" in primitive["extensions"]
        ],
    }
    generic_roles: dict[str, Any] | None = None
    if all(grouped_primitives.values()):
        material_groups = [
            {primitive["materialIndex"] for primitive in group}
            for group in grouped_primitives.values()
        ]
        address_groups = [
            {
                json.dumps(
                    primitive["concreteAddress"],
                    sort_keys=True,
                    separators=(",", ":"),
                )
                for primitive in group
            }
            for group in grouped_primitives.values()
        ]
        if any(
            left & right
            for index, left in enumerate(material_groups)
            for right in material_groups[index + 1 :]
        ) or any(
            left & right
            for index, left in enumerate(address_groups)
            for right in address_groups[index + 1 :]
        ):
            raise CaptureError("Frozen GLB generic extension roles are not distinct")
        clearcoat_factors = []
        for primitive in grouped_primitives["clearcoat"]:
            clearcoat = glb_object(
                primitive["extensions"]["KHR_materials_clearcoat"],
                field="KHR_materials_clearcoat",
            )
            factor = finite_glb_number(
                clearcoat.get("clearcoatFactor"),
                field="KHR_materials_clearcoat.clearcoatFactor",
                default=0.0,
            )
            clearcoat_factors.append(
                {
                    "address": primitive["concreteAddress"],
                    "expected": factor,
                    "actual": factor,
                }
            )
        transmission_factors = []
        for primitive in grouped_primitives["transmissionVolume"]:
            raw_transmission = primitive["extensions"].get(
                "KHR_materials_transmission"
            )
            transmission = (
                glb_object(raw_transmission, field="KHR_materials_transmission")
                if raw_transmission is not None
                else {}
            )
            factor = finite_glb_number(
                transmission.get("transmissionFactor"),
                field="KHR_materials_transmission.transmissionFactor",
                default=0.0,
            )
            transmission_factors.append(
                {
                    "address": primitive["concreteAddress"],
                    "expected": factor,
                    "actual": factor,
                }
            )
        generic_roles = {
            "selection": "authored extension-group identity only",
            "sheenAddresses": [
                primitive["concreteAddress"]
                for primitive in grouped_primitives["sheen"]
            ],
            "clearcoatAddresses": [
                primitive["concreteAddress"]
                for primitive in grouped_primitives["clearcoat"]
            ],
            "transmissionVolumeAddresses": [
                primitive["concreteAddress"]
                for primitive in grouped_primitives["transmissionVolume"]
            ],
            "distinctPrimitiveAddresses": True,
            "distinctMaterialIdentity": True,
            "clearcoatFactors": clearcoat_factors,
            "transmissionFactors": transmission_factors,
        }

    return {
        "authoredInventory": authored_inventory,
        "defaultInventory": default_inventory,
        "installedProbe": {
            "authoredDefaultSceneSheenCount": len(sheen_primitives),
            "installedDefaultSceneSheenCount": len(installed_sheen),
            "installedDefaultSceneSheen": installed_sheen,
            "noExtraRuntimeSheen": True,
            "genericSeparateExtensionRoles": generic_roles,
            "nonDefaultDependencyBoundary": NON_DEFAULT_DEPENDENCY_BOUNDARY,
        },
    }


def derive_renderer_native_control_contract(
    model_state: dict[str, Any],
) -> dict[str, Any]:
    contract = derive_frozen_glb_contract(model_state)
    authored_inventory = contract["authoredInventory"]
    if any(
        authored_inventory[extension]
        for extension in MATERIAL_EXTENSION_KEYS
        if extension != "KHR_materials_sheen"
    ):
        raise CaptureError(
            "Renderer-native control contains another material extension"
        )
    historical_probe = contract["installedProbe"]
    historical_installed = historical_probe["installedDefaultSceneSheen"]
    if any(
        material["sheenColorTextureExpected"]
        or material["sheenRoughnessTextureExpected"]
        for material in historical_installed
    ):
        raise CaptureError("Renderer-native scalar control contains a texture")
    installed = [
        {
            "authoredAddress": material["authoredAddress"],
            "concreteAddress": material["concreteAddress"],
            "materialType": "PhysicallyBasedMaterial",
            "application": "rendererNative",
            "runtimeAvailability": "available",
            "maturity": "release pending",
            "targetEvidence": "not run",
            "visualEvidence": "not run",
            "hasSheenIntent": True,
            "usesSheenShader": False,
            "usesClearcoatShader": False,
            "sheenColorFactor": material["sheenColorFactor"],
            "sheenRoughness": material["sheenRoughness"],
            "sheenColorTextureExpected": False,
            "sheenColorTextureGpuBacked": False,
            "sheenColorTextureUvSet": 0,
            "sheenColorTextureTransform": {
                "offsetX": 0.0,
                "offsetY": 0.0,
                "scaleX": 1.0,
                "scaleY": 1.0,
                "rotation": 0.0,
            },
            "sheenRoughnessTextureExpected": False,
            "sheenRoughnessTextureGpuBacked": False,
            "sheenRoughnessTextureUvSet": 0,
            "sheenRoughnessTextureTransform": {
                "offsetX": 0.0,
                "offsetY": 0.0,
                "scaleX": 1.0,
                "scaleY": 1.0,
                "rotation": 0.0,
            },
        }
        for material in historical_installed
    ]
    application = "rendererNative" if installed else "none"
    if model_state.get("expectedApplication") != application:
        raise CaptureError("Renderer-native control application drifted")
    contract["installedProbe"] = {
        "application": application,
        "expectedApplication": application,
        "featureMaturity": "release pending",
        "authoredDefaultSceneSheenCount": len(historical_installed),
        "installedDefaultSceneSheenCount": len(installed),
        "installedDefaultSceneSheen": installed,
        "rendererNativeCount": len(installed),
        "packageLocalCandidateCount": 0,
        "noExtraRuntimeSheen": True,
        "genericSeparateExtensionRoles": None,
        "nonDefaultDependencyBoundary": NON_DEFAULT_DEPENDENCY_BOUNDARY,
    }
    return contract


def validate_inventory(
    actual: Any,
    expected: dict[str, list[int]],
    *,
    field: str,
    stage: str,
) -> None:
    if not isinstance(actual, dict) or set(actual) != set(MATERIAL_EXTENSION_KEYS):
        raise CaptureError(f"{stage} field {field} keys drifted")
    for extension in MATERIAL_EXTENSION_KEYS:
        indices = actual.get(extension)
        if (
            not isinstance(indices, list)
            or any(isinstance(index, bool) or not isinstance(index, int) for index in indices)
            or indices != expected[extension]
        ):
            raise CaptureError(f"{stage} field {field} drifted for {extension}")


def validate_address_list(
    actual: Any,
    expected: list[dict[str, Any]],
    *,
    field: str,
    stage: str,
) -> None:
    if not isinstance(actual, list) or len(actual) != len(expected):
        raise CaptureError(f"{stage} {field} drifted")
    actual_keys = [
        part_address_key(value, field=field, stage=stage) for value in actual
    ]
    expected_keys = [
        part_address_key(value, field=field, stage=stage) for value in expected
    ]
    if actual_keys != expected_keys or len(set(actual_keys)) != len(actual_keys):
        raise CaptureError(f"{stage} {field} drifted")


def validate_expected_factors(
    roles: dict[str, Any],
    expected_roles: dict[str, Any],
    *,
    address_field: str,
    factor_field: str,
    stage: str,
) -> None:
    validate_factor_records(
        roles,
        address_field=address_field,
        factor_field=factor_field,
        stage=stage,
    )
    actual = roles[factor_field]
    expected = expected_roles[factor_field]
    if len(actual) != len(expected):
        raise CaptureError(f"{stage} {factor_field} drifted")
    for index, (actual_factor, expected_factor) in enumerate(
        zip(actual, expected, strict=True)
    ):
        actual_address = part_address_key(
            actual_factor["address"],
            field=f"{factor_field}[{index}].address",
            stage=stage,
        )
        expected_address = part_address_key(
            expected_factor["address"],
            field=f"{factor_field}[{index}].address",
            stage=stage,
        )
        if actual_address != expected_address:
            raise CaptureError(f"{stage} {factor_field} addresses drifted")
        for key in ("expected", "actual"):
            value = actual_factor[key]
            expected_value = expected_factor[key]
            if (
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(value)
                or abs(value - expected_value) > 1e-6
            ):
                raise CaptureError(f"{stage} {factor_field}[{index}] drifted")


def validate_installed_probe(
    actual: Any,
    expected: dict[str, Any],
    *,
    stage: str,
) -> None:
    if not isinstance(actual, dict) or set(actual) != INSTALLED_PROBE_KEYS:
        raise CaptureError(f"{stage} installedMaterialProbe keys drifted")
    for count_field in (
        "authoredDefaultSceneSheenCount",
        "installedDefaultSceneSheenCount",
    ):
        value = actual.get(count_field)
        if (
            isinstance(value, bool)
            or not isinstance(value, int)
            or value != expected[count_field]
        ):
            raise CaptureError(f"{stage} installedMaterialProbe {count_field} drifted")
    if actual.get("noExtraRuntimeSheen") is not True:
        raise CaptureError(f"{stage} installedMaterialProbe reports extra sheen")
    if actual.get("nonDefaultDependencyBoundary") != NON_DEFAULT_DEPENDENCY_BOUNDARY:
        raise CaptureError(
            f"{stage} installedMaterialProbe dependency boundary drifted"
        )
    actual_installed = actual.get("installedDefaultSceneSheen")
    expected_installed = expected["installedDefaultSceneSheen"]
    if not isinstance(actual_installed, list) or len(actual_installed) != len(
        expected_installed
    ):
        raise CaptureError(f"{stage} installedMaterialProbe sheen list drifted")
    for index, (material, expected_material) in enumerate(
        zip(actual_installed, expected_installed, strict=True)
    ):
        material_stage = f"{stage} installedMaterialProbe[{index}]"
        if not isinstance(material, dict):
            raise CaptureError(f"{material_stage} is not an object")
        for address_field in ("authoredAddress", "concreteAddress"):
            actual_address = part_address_key(
                material.get(address_field),
                field=address_field,
                stage=material_stage,
            )
            expected_address = part_address_key(
                expected_material[address_field],
                field=address_field,
                stage=material_stage,
            )
            if actual_address != expected_address:
                raise CaptureError(f"{material_stage} {address_field} drifted")
        if set(material) != INSTALLED_SHEEN_KEYS:
            raise CaptureError(f"{material_stage} keys drifted")
        for string_field in ("materialType",):
            if material.get(string_field) != expected_material[string_field]:
                raise CaptureError(f"{material_stage} {string_field} drifted")
        for boolean_field in (
            "hasSheenIntent",
            "usesSheenShader",
            "usesClearcoatShader",
            "sheenColorTextureExpected",
            "sheenColorTextureGpuBacked",
            "sheenRoughnessTextureExpected",
            "sheenRoughnessTextureGpuBacked",
        ):
            if material.get(boolean_field) is not expected_material[boolean_field]:
                raise CaptureError(f"{material_stage} {boolean_field} drifted")
        require_numeric_vector(
            material.get("sheenColorFactor"),
            expected_material["sheenColorFactor"],
            field="sheenColorFactor",
            stage=material_stage,
        )
        roughness = material.get("sheenRoughness")
        if (
            isinstance(roughness, bool)
            or not isinstance(roughness, (int, float))
            or not math.isfinite(roughness)
            or abs(roughness - expected_material["sheenRoughness"]) > 1e-6
        ):
            raise CaptureError(f"{material_stage} sheenRoughness drifted")

    roles = actual.get("genericSeparateExtensionRoles")
    expected_roles = expected["genericSeparateExtensionRoles"]
    if expected_roles is None:
        if roles is not None:
            raise CaptureError(
                f"{stage} genericSeparateExtensionRoles must be null"
            )
        return
    if not isinstance(roles, dict) or set(roles) != GENERIC_ROLE_KEYS:
        raise CaptureError(f"{stage} genericSeparateExtensionRoles keys drifted")
    if roles.get("selection") != expected_roles["selection"]:
        raise CaptureError(f"{stage} genericSeparateExtensionRoles selection drifted")
    for boolean_field in (
        "distinctPrimitiveAddresses",
        "distinctMaterialIdentity",
    ):
        if roles.get(boolean_field) is not True:
            raise CaptureError(f"{stage} {boolean_field} drifted")
    for address_field in (
        "sheenAddresses",
        "clearcoatAddresses",
        "transmissionVolumeAddresses",
    ):
        validate_address_list(
            roles.get(address_field),
            expected_roles[address_field],
            field=address_field,
            stage=stage,
        )
    validate_expected_factors(
        roles,
        expected_roles,
        address_field="clearcoatAddresses",
        factor_field="clearcoatFactors",
        stage=stage,
    )
    validate_expected_factors(
        roles,
        expected_roles,
        address_field="transmissionVolumeAddresses",
        factor_field="transmissionFactors",
        stage=stage,
    )


def png_record(path: Path, run_root: Path) -> dict[str, Any]:
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != EXPECTED_PNG_SIGNATURE:
        raise CaptureError(f"Capture is not a PNG: {path.name}")
    width = int.from_bytes(data[16:20], "big")
    height = int.from_bytes(data[20:24], "big")
    if width != EXPECTED_PHYSICAL_WIDTH or height != EXPECTED_PHYSICAL_HEIGHT:
        raise CaptureError(
            f"Capture dimensions drifted for {path.name}: {width}x{height}"
        )
    return {
        "name": path.stem,
        "path": str(path.relative_to(run_root)),
        "sha256": hashlib.sha256(data).hexdigest(),
        "byteLength": len(data),
        "dimensions": {"width": width, "height": height},
    }


def parse_aware_timestamp(value: Any, *, field: str) -> datetime:
    if not isinstance(value, str):
        raise CaptureError(f"{field} is not a timestamp string")
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as error:
        raise CaptureError(f"{field} is not an ISO-8601 timestamp") from error
    if parsed.tzinfo is None:
        raise CaptureError(f"{field} lacks a timezone offset")
    return parsed


def impeller_query_command(
    udid: str,
    started: datetime,
    finished: datetime,
) -> list[str]:
    query_start = datetime.fromtimestamp(
        math.floor(started.timestamp()),
        timezone.utc,
    ).strftime("%Y-%m-%d %H:%M:%S%z")
    query_end = datetime.fromtimestamp(
        math.ceil(finished.timestamp()),
        timezone.utc,
    ).strftime("%Y-%m-%d %H:%M:%S%z")
    return [
        "/usr/bin/xcrun",
        "simctl",
        "spawn",
        udid,
        "log",
        "show",
        "--start",
        query_start,
        "--end",
        query_end,
        "--style",
        "json",
        "--predicate",
        IMPELLER_LOG_PREDICATE,
    ]


def validate_impeller_evidence(
    run_root: Path,
    model_id: str,
    complete_record: dict[str, Any],
    *,
    fixture_validation: bool,
    expected_device_udid: str | None = None,
    expected_started_at: str | None = None,
    expected_finished_at: str | None = None,
    expected_status: str = "candidate-only",
) -> dict[str, Any]:
    path = run_root / "logs" / f"{model_id}.impeller.json"
    if path.is_symlink() or not path.is_file():
        raise CaptureError(f"{model_id} process-correlated Impeller proof is missing")
    encoded = path.read_bytes()
    decoded = json.loads(encoded)
    if not isinstance(decoded, dict) or set(decoded) != IMPELLER_EVIDENCE_KEYS:
        raise CaptureError(f"{model_id} Impeller evidence schema drifted")
    expected_execution = "not run" if fixture_validation else "verified locally"
    for key, expected in (
        ("schemaVersion", 1),
        ("status", expected_status),
        ("executionEvidence", expected_execution),
        ("fixtureValidation", fixture_validation),
        ("source", IMPELLER_LOG_SOURCE),
        ("modelId", model_id),
    ):
        if decoded.get(key) != expected:
            raise CaptureError(f"{model_id} Impeller evidence {key} drifted")

    device_udid = validate_udid(decoded.get("deviceUdid"))
    expected_boundary = (
        expected_device_udid,
        expected_started_at,
        expected_finished_at,
    )
    if any(value is not None for value in expected_boundary):
        if any(value is None for value in expected_boundary):
            raise CaptureError(f"{model_id} expected Impeller boundary is incomplete")
        if device_udid != expected_device_udid:
            raise CaptureError(f"{model_id} Impeller evidence deviceUdid drifted")
    device_path = run_root / "device.json"
    if device_path.is_file():
        device = read_json_file(device_path)
        if device.get("udid") != device_udid:
            raise CaptureError(f"{model_id} Impeller evidence deviceUdid drifted")

    window = decoded.get("captureWindow")
    if not isinstance(window, dict) or set(window) != {"startedAt", "finishedAt"}:
        raise CaptureError(f"{model_id} Impeller evidence captureWindow drifted")
    started = parse_aware_timestamp(
        window.get("startedAt"),
        field=f"{model_id} Impeller captureWindow.startedAt",
    )
    finished = parse_aware_timestamp(
        window.get("finishedAt"),
        field=f"{model_id} Impeller captureWindow.finishedAt",
    )
    if expected_started_at is not None and window != {
        "startedAt": expected_started_at,
        "finishedAt": expected_finished_at,
    }:
        raise CaptureError(
            f"{model_id} Impeller evidence captureWindow differs from manifest"
        )
    if finished < started or (
        finished - started
    ).total_seconds() > FLUTTER_DRIVE_TIMEOUT_SECONDS:
        raise CaptureError(f"{model_id} Impeller evidence captureWindow is invalid")
    query_command = decoded.get("queryCommand")
    if query_command != impeller_query_command(device_udid, started, finished):
        raise CaptureError(f"{model_id} Impeller evidence queryCommand drifted")

    records = decoded.get("records")
    if not isinstance(records, list) or len(records) != 2:
        raise CaptureError(f"{model_id} Impeller evidence requires two records")
    normalized_records: list[dict[str, Any]] = []
    record_times: list[datetime] = []
    for index, expected_kind in enumerate(("impeller", "complete")):
        record = records[index]
        if not isinstance(record, dict) or set(record) != IMPELLER_RECORD_KEYS:
            raise CaptureError(f"{model_id} Impeller record[{index}] schema drifted")
        if record.get("kind") != expected_kind:
            raise CaptureError(f"{model_id} Impeller record[{index}] kind drifted")
        process_id = record.get("processId")
        if isinstance(process_id, bool) or not isinstance(process_id, int) or process_id <= 0:
            raise CaptureError(f"{model_id} Impeller record[{index}] processId is invalid")
        timestamp = parse_aware_timestamp(
            record.get("timestamp"),
            field=f"{model_id} Impeller record[{index}].timestamp",
        )
        if timestamp < started or timestamp > finished:
            raise CaptureError(
                f"{model_id} Impeller record[{index}] is outside captureWindow"
            )
        record_times.append(timestamp)
        for field in (
            "eventMessage",
            "eventType",
            "messageType",
            "processImagePath",
            "processImageUuid",
            "senderImagePath",
            "bootUuid",
        ):
            if not isinstance(record.get(field), str) or not record[field]:
                raise CaptureError(
                    f"{model_id} Impeller record[{index}] {field} is invalid"
                )
        if record["eventType"] != "logEvent" or record["messageType"] != "Default":
            raise CaptureError(
                f"{model_id} Impeller record[{index}] log type drifted"
            )
        process_image_path = record["processImagePath"]
        if (
            f"/Devices/{device_udid}/" not in process_image_path
            or not process_image_path.endswith("/Runner.app/Runner")
        ):
            raise CaptureError(
                f"{model_id} Impeller record[{index}] processImagePath drifted"
            )
        if not record["senderImagePath"].endswith(
            "/Runner.app/Frameworks/Flutter.framework/Flutter"
        ):
            raise CaptureError(
                f"{model_id} Impeller record[{index}] senderImagePath drifted"
            )
        normalized_records.append(record)

    correlation_fields = (
        "processId",
        "processImagePath",
        "processImageUuid",
        "senderImagePath",
        "bootUuid",
    )
    for field in correlation_fields:
        if normalized_records[0][field] != normalized_records[1][field]:
            raise CaptureError(f"{model_id} Impeller records have different {field}")
    if record_times[0] > record_times[1]:
        raise CaptureError(f"{model_id} Impeller record order drifted")
    if normalized_records[0]["eventMessage"] != IMPELLER_EVENT_MESSAGE:
        raise CaptureError(f"{model_id} Impeller backend message drifted")
    complete_values = parse_prefixed_json(
        normalized_records[1]["eventMessage"],
        "PLAN018_COMPLETE ",
    )
    if complete_values != [complete_record]:
        raise CaptureError(
            f"{model_id} Impeller proof is not correlated to COMPLETE"
        )

    return {
        "source": IMPELLER_LOG_SOURCE,
        "path": str(path.relative_to(run_root)),
        "sha256": hashlib.sha256(encoded).hexdigest(),
        "byteLength": len(encoded),
        "deviceUdid": device_udid,
        "captureWindow": dict(window),
        "processId": normalized_records[0]["processId"],
        "backend": IMPELLER_BACKEND,
        "impellerTimestamp": normalized_records[0]["timestamp"],
        "completeTimestamp": normalized_records[1]["timestamp"],
    }


def validate_model_artifacts(
    run_root: Path,
    model_id: str,
    *,
    fixture_validation: bool = False,
    expected_device_udid: str | None = None,
    expected_started_at: str | None = None,
    expected_finished_at: str | None = None,
    expected_root_pubspec_sha256: str | None = None,
    expected_root_lock_sha256: str | None = None,
    expected_flutter_scene_ref: str | None = None,
) -> dict[str, Any]:
    expected_root_pubspec_sha256 = (
        expected_root_pubspec_sha256 or FROZEN_HASHES["pubspec.yaml"]
    )
    expected_root_lock_sha256 = (
        expected_root_lock_sha256 or FROZEN_HASHES["pubspec.lock"]
    )
    expected_flutter_scene_ref = expected_flutter_scene_ref or EXPECTED_PIN
    state = load_state()
    names = expected_names(state, model_id)
    log_path = run_root / "logs" / f"{model_id}.log"
    response_path = run_root / f"plan018_integration_response_{model_id}.json"
    if not log_path.is_file() or not response_path.is_file():
        raise CaptureError(f"{model_id} log or response is missing")
    log_bytes = log_path.read_bytes()
    log = log_bytes.decode("utf-8", errors="replace")
    nonempty_lines = [line.strip() for line in log.splitlines() if line.strip()]
    if not nonempty_lines or nonempty_lines[-1] != "All tests passed.":
        raise CaptureError(f"{model_id} log lacks terminal success")

    marker_order: list[str] = []
    for line in log.splitlines():
        has_ready = "PLAN018_READY " in line
        has_complete = "PLAN018_COMPLETE " in line
        if has_ready and has_complete:
            raise CaptureError(
                f"{model_id} log has ambiguous READY/COMPLETE markers"
            )
        if has_ready:
            marker_order.append("READY")
        if has_complete:
            marker_order.append("COMPLETE")
    expected_marker_order = ["READY"] * len(names) + ["COMPLETE"]
    if marker_order != expected_marker_order:
        raise CaptureError(
            f"{model_id} log lacks ordered READY/COMPLETE evidence"
        )

    ready_markers = parse_prefixed_json(log, "PLAN018_READY ")
    complete = parse_prefixed_json(log, "PLAN018_COMPLETE ")
    if len(ready_markers) != len(names):
        raise CaptureError(
            f"{model_id} READY count is {len(ready_markers)}; expected {len(names)}"
        )
    if len(complete) != 1:
        raise CaptureError(f"{model_id} must have exactly one COMPLETE record")

    response_bytes = response_path.read_bytes()
    response = json.loads(response_bytes)
    if not isinstance(response, dict):
        raise CaptureError(f"{model_id} response is not an object")
    if response.get("expectedScreenshotNames") != names:
        raise CaptureError(f"{model_id} response has the wrong ordered screenshot inventory")
    for key, expected in (
        ("modelId", model_id),
        ("status", "candidate-only"),
        ("integrationPath", "executed by flutter drive"),
    ):
        require_equal(response, key, expected, f"{model_id} response")
    ready_payloads = response.get("readyPayloads")
    if not isinstance(ready_payloads, list) or len(ready_payloads) != len(names):
        raise CaptureError(f"{model_id} response READY payload inventory drifted")
    ready: list[dict[str, Any]] = []
    for index, (marker, payload, name) in enumerate(
        zip(ready_markers, ready_payloads, names, strict=True)
    ):
        stage = f"{model_id} READY[{index}]"
        if not isinstance(marker, dict) or set(marker) != {
            "stage",
            "sha256",
            "byteLength",
        }:
            raise CaptureError(f"{stage} marker schema drifted")
        if marker.get("stage") != name:
            raise CaptureError(f"{stage} marker stage drifted")
        if not isinstance(payload, str):
            raise CaptureError(f"{stage} response payload is not a string")
        payload_bytes = payload.encode("utf-8")
        actual_sha256 = hashlib.sha256(payload_bytes).hexdigest()
        if marker.get("sha256") != actual_sha256:
            raise CaptureError(f"{stage} READY sha256 drifted")
        byte_length = marker.get("byteLength")
        if (
            isinstance(byte_length, bool)
            or not isinstance(byte_length, int)
            or byte_length != len(payload_bytes)
        ):
            raise CaptureError(f"{stage} READY byteLength drifted")
        try:
            record = json.loads(payload)
        except json.JSONDecodeError as error:
            raise CaptureError(f"{stage} response payload is malformed JSON") from error
        if not isinstance(record, dict):
            raise CaptureError(f"{stage} response payload is not an object")
        ready.append(record)

    model_state = state["models"][model_id]
    glb_contract = derive_frozen_glb_contract(model_state)
    state_lighting = state["lighting"]
    for index, (record, name) in enumerate(zip(ready, names, strict=True)):
        remainder = name[len(model_id) + 1 :]
        view, render_pass = remainder.rsplit("_", 1)
        stage = f"{model_id} READY[{index}]"
        for key, expected in (
            ("status", "candidate-only"),
            ("modelId", model_id),
            ("stateSha256", EXPECTED_STATE_SHA256),
            ("rootPubspecSha256", expected_root_pubspec_sha256),
            ("rootLockSha256", expected_root_lock_sha256),
            ("flutterSceneRef", expected_flutter_scene_ref),
            ("flutterSceneResolvedRef", expected_flutter_scene_ref),
            ("modelSha256", model_state["sha256"]),
            ("environmentSha256", EXPECTED_ENVIRONMENT_SHA256),
            ("blockingDiagnostics", 0),
            ("stage", name),
            ("view", view),
            ("pass", render_pass),
            ("logicalWidth", EXPECTED_LOGICAL_WIDTH),
            ("logicalHeight", EXPECTED_LOGICAL_HEIGHT),
            ("devicePixelRatio", EXPECTED_DPR),
            ("physicalWidth", EXPECTED_PHYSICAL_WIDTH),
            ("physicalHeight", EXPECTED_PHYSICAL_HEIGHT),
            ("showSkybox", False),
            ("toneMapping", "pbrNeutral"),
            ("outputColorSpace", "sRGB"),
        ):
            require_equal(record, key, expected, stage)
        expected_environment = 0.0 if render_pass == "directOnly" else 1.0
        expected_key = 0.0 if render_pass == "iblOnly" else 3.0
        require_equal(
            record,
            "appliedEnvironmentIntensity",
            expected_environment,
            stage,
        )
        require_equal(record, "appliedKeyLightIntensity", expected_key, stage)
        camera_state = (
            model_state["context"]["camera"]
            if view == "context"
            else model_state["cameras"][view]
        )
        require_numeric_vector(
            record.get("cameraPosition"),
            [float(value) for value in camera_state["position"]],
            field="cameraPosition",
            stage=stage,
        )
        if int(record.get("postCameraFrameTail", 0)) < 12:
            raise CaptureError(f"{stage} lacks the fixed post-camera frame tail")
        if int(record.get("freshCompatibleStatsSamples", 0)) < 2:
            raise CaptureError(f"{stage} lacks two compatible stats samples")
        frames_per_second = record.get("framesPerSecond")
        if (
            isinstance(frames_per_second, bool)
            or not isinstance(frames_per_second, (int, float))
            or not math.isfinite(frames_per_second)
            or frames_per_second <= 0
        ):
            raise CaptureError(f"{stage} has invalid framesPerSecond evidence")
        if record.get("renderPolicyActive") is not True:
            raise CaptureError(f"{stage} lacks renderPolicyActive evidence")
        if record.get("renderPolicyAlways") is not True:
            raise CaptureError(f"{stage} lacks renderPolicyAlways evidence")
        lighting = record.get("appliedStageLighting")
        expected_lighting = {
            "environmentPresent": True,
            "environmentIntensity": expected_environment,
            "keyLightPresent": True,
            "keyLightIntensity": expected_key,
            "keyLightDirection": state_lighting[
                "keyLightDirectionFlutterSceneWorld"
            ],
            "keyLightColor": state_lighting["keyLightColorLinear"],
            "keyLightCastsShadow": state_lighting["keyLightCastsShadow"],
            "ambientOcclusion": state_lighting["ambientOcclusion"],
            "exposure": state_lighting["exposure"],
        }
        if not isinstance(lighting, dict) or set(lighting) != set(
            expected_lighting
        ):
            raise CaptureError(f"{stage} appliedStageLighting keys drifted")
        for boolean_field in (
            "environmentPresent",
            "keyLightPresent",
            "keyLightCastsShadow",
            "ambientOcclusion",
        ):
            if lighting.get(boolean_field) is not expected_lighting[boolean_field]:
                raise CaptureError(
                    f"{stage} appliedStageLighting {boolean_field} drifted"
                )
        for numeric_field in (
            "environmentIntensity",
            "keyLightIntensity",
            "exposure",
        ):
            value = lighting.get(numeric_field)
            expected_value = expected_lighting[numeric_field]
            if (
                isinstance(value, bool)
                or not isinstance(value, (int, float))
                or not math.isfinite(value)
                or abs(value - expected_value) > 1e-6
            ):
                raise CaptureError(
                    f"{stage} appliedStageLighting {numeric_field} drifted"
                )
        require_numeric_vector(
            lighting.get("keyLightDirection"),
            [float(value) for value in expected_lighting["keyLightDirection"]],
            field="appliedStageLighting.keyLightDirection",
            stage=stage,
        )
        require_numeric_vector(
            lighting.get("keyLightColor"),
            [float(value) for value in expected_lighting["keyLightColor"]],
            field="appliedStageLighting.keyLightColor",
            stage=stage,
        )
        validate_inventory(
            record.get("authoredDependencyInventory"),
            glb_contract["authoredInventory"],
            field="authoredDependencyInventory",
            stage=stage,
        )
        validate_inventory(
            record.get("defaultSceneInventory"),
            glb_contract["defaultInventory"],
            field="defaultSceneInventory",
            stage=stage,
        )
        validate_installed_probe(
            record.get("installedMaterialProbe"),
            glb_contract["installedProbe"],
            stage=stage,
        )

    complete_record = complete[0]
    for key, expected in (
        ("status", "candidate-only"),
        ("integrationPath", "executed by flutter drive"),
        ("modelId", model_id),
        ("screenshots", names),
        ("count", len(names)),
        ("comparisonBoundary", "direction/conformance-only"),
    ):
        require_equal(complete_record, key, expected, f"{model_id} COMPLETE")
    if (
        not fixture_validation
        and expected_device_udid is None
        and expected_started_at is None
        and expected_finished_at is None
    ):
        manifest_path = run_root / "manifests" / f"{model_id}.json"
        if not manifest_path.is_file():
            raise CaptureError(
                f"{model_id} capture boundary lacks an in-memory or manifest source"
            )
        boundary_manifest = read_json_file(manifest_path)
        boundary_device = boundary_manifest.get("device")
        if not isinstance(boundary_device, dict):
            raise CaptureError(f"{model_id} success manifest device drifted")
        expected_device_udid = boundary_device.get("udid")
        expected_started_at = boundary_manifest.get("startedAt")
        expected_finished_at = boundary_manifest.get("captureFinishedAt")
    backend_evidence = validate_impeller_evidence(
        run_root,
        model_id,
        complete_record,
        fixture_validation=fixture_validation,
        expected_device_udid=expected_device_udid,
        expected_started_at=expected_started_at,
        expected_finished_at=expected_finished_at,
    )

    actual_model_pngs = sorted(path.name for path in run_root.glob(f"{model_id}_*.png"))
    expected_model_pngs = sorted(f"{name}.png" for name in names)
    if actual_model_pngs != expected_model_pngs:
        raise CaptureError(f"{model_id} PNG inventory is incomplete or has extras")
    artifacts = [png_record(run_root / f"{name}.png", run_root) for name in names]
    return {
        "status": "candidate-only",
        "executionEvidence": (
            "not run" if fixture_validation else "verified locally"
        ),
        "fixtureValidation": fixture_validation,
        "modelId": model_id,
        "readyCount": len(ready),
        "orderedScreenshotNames": names,
        "log": {
            "path": str(log_path.relative_to(run_root)),
            "sha256": hashlib.sha256(log_bytes).hexdigest(),
            "byteLength": len(log_bytes),
        },
        "response": {
            "path": str(response_path.relative_to(run_root)),
            "sha256": hashlib.sha256(response_bytes).hexdigest(),
            "byteLength": len(response_bytes),
        },
        "readyRecords": ready,
        "readyMarkers": ready_markers,
        "completeRecord": complete_record,
        "backendEvidence": backend_evidence,
        "artifacts": artifacts,
        "pixelHealthStatus": "not run",
        "pixelHealthBoundary": (
            "Recorded PNG bytes only; blank, flat, render-delta, and visual "
            "direction checks belong to the separately frozen renderer-local analyzer."
        ),
    }


def validate_renderer_native_control_artifacts(
    run_root: Path,
    model_id: str,
    *,
    fixture_validation: bool = False,
    expected_device_udid: str | None = None,
    expected_started_at: str | None = None,
    expected_finished_at: str | None = None,
) -> dict[str, Any]:
    state = load_renderer_native_control_state()
    if model_id not in EXPECTED_NATIVE_CONTROL_MODELS:
        raise CaptureError("Unknown Plan 018 renderer-native control model")
    names = expected_renderer_native_control_names(state, model_id)
    model_state = state["models"][model_id]
    contract = derive_renderer_native_control_contract(model_state)
    expected_probe = contract["installedProbe"]
    application = expected_probe["application"]
    log_path = run_root / "logs" / f"{model_id}.log"
    response_path = run_root / f"plan018_integration_response_{model_id}.json"
    if not log_path.is_file() or not response_path.is_file():
        raise CaptureError(f"{model_id} log or response is missing")
    log_bytes = log_path.read_bytes()
    log = log_bytes.decode("utf-8", errors="replace")
    nonempty_lines = [line.strip() for line in log.splitlines() if line.strip()]
    if not nonempty_lines or nonempty_lines[-1] != "All tests passed.":
        raise CaptureError(f"{model_id} log lacks terminal success")

    marker_order = [
        marker
        for line in log.splitlines()
        for marker in (
            (["READY"] if "PLAN018_READY " in line else [])
            + (["COMPLETE"] if "PLAN018_COMPLETE " in line else [])
        )
    ]
    if marker_order != ["READY"] * len(names) + ["COMPLETE"]:
        raise CaptureError(f"{model_id} log marker order drifted")
    ready_markers = parse_prefixed_json(log, "PLAN018_READY ")
    complete_records = parse_prefixed_json(log, "PLAN018_COMPLETE ")
    if len(ready_markers) != len(names) or len(complete_records) != 1:
        raise CaptureError(f"{model_id} READY/COMPLETE inventory drifted")

    response_bytes = response_path.read_bytes()
    response = json.loads(response_bytes)
    if not isinstance(response, dict):
        raise CaptureError(f"{model_id} response is not an object")
    for key, expected in (
        ("modelId", model_id),
        ("expectedScreenshotNames", names),
        ("status", "release pending"),
        ("application", application),
        ("comparisonBoundary", "renderer-local sheen on/off control only"),
        ("integrationPath", "executed by flutter drive"),
    ):
        require_equal(response, key, expected, f"{model_id} response")
    payloads = response.get("readyPayloads")
    if not isinstance(payloads, list) or len(payloads) != len(names):
        raise CaptureError(f"{model_id} response READY payload inventory drifted")

    ready: list[dict[str, Any]] = []
    for index, (marker, payload, name) in enumerate(
        zip(ready_markers, payloads, names, strict=True)
    ):
        stage = f"{model_id} READY[{index}]"
        if not isinstance(marker, dict) or set(marker) != {
            "stage",
            "sha256",
            "byteLength",
        }:
            raise CaptureError(f"{stage} marker schema drifted")
        if marker.get("stage") != name or not isinstance(payload, str):
            raise CaptureError(f"{stage} marker/payload drifted")
        payload_bytes = payload.encode("utf-8")
        if (
            marker.get("sha256") != hashlib.sha256(payload_bytes).hexdigest()
            or marker.get("byteLength") != len(payload_bytes)
        ):
            raise CaptureError(f"{stage} marker identity drifted")
        decoded = json.loads(payload)
        if not isinstance(decoded, dict):
            raise CaptureError(f"{stage} payload is not an object")
        ready.append(decoded)

    lighting_state = state["lighting"]
    camera_state = model_state["cameras"]["grazing"]
    for index, (record, name) in enumerate(zip(ready, names, strict=True)):
        render_pass = name.rsplit("_", 1)[1]
        stage = f"{model_id} READY[{index}]"
        for key, expected in (
            ("status", "release pending"),
            ("application", application),
            ("runtimeAvailability", "available"),
            ("featureMaturity", "release pending"),
            ("targetEvidence", "not run"),
            ("visualEvidence", "not run"),
            ("comparisonBoundary", "renderer-local sheen on/off control only"),
            ("modelId", model_id),
            ("stateSha256", EXPECTED_NATIVE_CONTROL_STATE_SHA256),
            ("rootPubspecSha256", FROZEN_HASHES["pubspec.yaml"]),
            ("rootLockSha256", FROZEN_HASHES["pubspec.lock"]),
            ("flutterSceneRef", EXPECTED_PIN),
            ("flutterSceneResolvedRef", EXPECTED_PIN),
            ("modelSha256", model_state["sha256"]),
            ("environmentSha256", EXPECTED_ENVIRONMENT_SHA256),
            ("blockingDiagnostics", 0),
            ("showSkybox", False),
            ("toneMapping", "pbrNeutral"),
            ("outputColorSpace", "sRGB"),
            ("stage", name),
            ("view", "grazing"),
            ("pass", render_pass),
            ("logicalWidth", EXPECTED_LOGICAL_WIDTH),
            ("logicalHeight", EXPECTED_LOGICAL_HEIGHT),
            ("devicePixelRatio", EXPECTED_DPR),
            ("physicalWidth", EXPECTED_PHYSICAL_WIDTH),
            ("physicalHeight", EXPECTED_PHYSICAL_HEIGHT),
            ("renderPolicyAlways", True),
            ("renderPolicyActive", True),
        ):
            require_equal(record, key, expected, stage)
        if record.get("installedMaterialProbe") != expected_probe:
            raise CaptureError(f"{stage} installed renderer-native probe drifted")
        validate_inventory(
            record.get("authoredDependencyInventory"),
            contract["authoredInventory"],
            field="authoredDependencyInventory",
            stage=stage,
        )
        validate_inventory(
            record.get("defaultSceneInventory"),
            contract["defaultInventory"],
            field="defaultSceneInventory",
            stage=stage,
        )
        require_numeric_vector(
            record.get("cameraPosition"),
            [float(value) for value in camera_state["position"]],
            field="cameraPosition",
            stage=stage,
        )
        if int(record.get("postCameraFrameTail", 0)) < 12:
            raise CaptureError(f"{stage} lacks the fixed post-camera frame tail")
        if int(record.get("freshCompatibleStatsSamples", 0)) < 2:
            raise CaptureError(f"{stage} lacks two compatible stats samples")
        fps = record.get("framesPerSecond")
        if (
            isinstance(fps, bool)
            or not isinstance(fps, (int, float))
            or not math.isfinite(fps)
            or fps <= 0
        ):
            raise CaptureError(f"{stage} has invalid framesPerSecond evidence")
        expected_environment = 0.0 if render_pass == "directOnly" else 1.0
        expected_key = 0.0 if render_pass == "iblOnly" else 3.0
        require_equal(
            record,
            "appliedEnvironmentIntensity",
            expected_environment,
            stage,
        )
        require_equal(record, "appliedKeyLightIntensity", expected_key, stage)
        expected_lighting = {
            "environmentPresent": True,
            "environmentIntensity": expected_environment,
            "keyLightPresent": True,
            "keyLightIntensity": expected_key,
            "keyLightDirection": lighting_state[
                "keyLightDirectionFlutterSceneWorld"
            ],
            "keyLightColor": lighting_state["keyLightColorLinear"],
            "keyLightCastsShadow": lighting_state["keyLightCastsShadow"],
            "ambientOcclusion": lighting_state["ambientOcclusion"],
            "exposure": lighting_state["exposure"],
        }
        actual_lighting = record.get("appliedStageLighting")
        if (
            not isinstance(actual_lighting, dict)
            or set(actual_lighting) != set(expected_lighting)
        ):
            raise CaptureError(f"{stage} appliedStageLighting drifted")
        for field in (
            "environmentPresent",
            "environmentIntensity",
            "keyLightPresent",
            "keyLightIntensity",
            "keyLightCastsShadow",
            "ambientOcclusion",
            "exposure",
        ):
            require_equal(
                actual_lighting,
                field,
                expected_lighting[field],
                f"{stage} appliedStageLighting",
            )
        require_numeric_vector(
            actual_lighting.get("keyLightDirection"),
            [float(value) for value in expected_lighting["keyLightDirection"]],
            field="keyLightDirection",
            stage=f"{stage} appliedStageLighting",
        )
        require_numeric_vector(
            actual_lighting.get("keyLightColor"),
            [float(value) for value in expected_lighting["keyLightColor"]],
            field="keyLightColor",
            stage=f"{stage} appliedStageLighting",
        )

    complete = complete_records[0]
    expected_complete = {
        "status": "release pending",
        "application": application,
        "integrationPath": "executed by flutter drive",
        "modelId": model_id,
        "screenshots": names,
        "count": len(names),
        "comparisonBoundary": "renderer-local sheen on/off control only",
    }
    if complete != expected_complete:
        raise CaptureError(f"{model_id} COMPLETE record drifted")
    backend_evidence = validate_impeller_evidence(
        run_root,
        model_id,
        complete,
        fixture_validation=fixture_validation,
        expected_device_udid=expected_device_udid,
        expected_started_at=expected_started_at,
        expected_finished_at=expected_finished_at,
        expected_status="release pending",
    )
    actual_pngs = sorted(path.name for path in run_root.glob(f"{model_id}_*.png"))
    expected_pngs = sorted(f"{name}.png" for name in names)
    if actual_pngs != expected_pngs:
        raise CaptureError(f"{model_id} PNG inventory is incomplete or has extras")
    artifacts = [png_record(run_root / f"{name}.png", run_root) for name in names]
    return {
        "status": "release pending",
        "executionEvidence": (
            "not run" if fixture_validation else "verified locally"
        ),
        "fixtureValidation": fixture_validation,
        "application": application,
        "runtimeAvailability": "available",
        "featureMaturity": "release pending",
        "targetEvidence": (
            "not run" if fixture_validation else "verified locally"
        ),
        "visualEvidence": "not run",
        "modelId": model_id,
        "readyCount": len(ready),
        "orderedScreenshotNames": names,
        "log": {
            "path": str(log_path.relative_to(run_root)),
            "sha256": hashlib.sha256(log_bytes).hexdigest(),
            "byteLength": len(log_bytes),
        },
        "response": {
            "path": str(response_path.relative_to(run_root)),
            "sha256": hashlib.sha256(response_bytes).hexdigest(),
            "byteLength": len(response_bytes),
        },
        "readyRecords": ready,
        "readyMarkers": ready_markers,
        "completeRecord": complete,
        "backendEvidence": backend_evidence,
        "artifacts": artifacts,
        "artifactCount": len(artifacts),
        "comparisonBoundary": "renderer-local sheen on/off control only",
    }


def assert_no_selected_artifacts(run_root: Path, model_id: str) -> None:
    state = load_state()
    present = existing_model_paths(
        run_root,
        model_id,
        expected_names(state, model_id),
    )
    if present:
        raise CaptureError(
            f"Selected model already has artifacts in this run root: {present[0]}"
        )


def read_json_file(path: Path) -> dict[str, Any]:
    decoded = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict):
        raise CaptureError(f"JSON file is not an object: {path}")
    return decoded


def validate_success_manifest(
    run_root: Path,
    model_id: str,
    validation: dict[str, Any],
    *,
    expected_guard: dict[str, Any] | None,
    expected_device: dict[str, Any],
) -> dict[str, Any]:
    manifest_path = run_root / "manifests" / f"{model_id}.json"
    if not manifest_path.is_file():
        raise CaptureError(f"Existing {model_id} artifacts lack a success manifest")
    manifest = read_json_file(manifest_path)
    preflight = manifest.get("preflight")
    postflight = manifest.get("postflight")
    if not isinstance(preflight, dict) or preflight != postflight:
        raise CaptureError(
            f"Existing {model_id} source/dependency state drifted during capture"
        )
    if expected_guard is not None and preflight != expected_guard:
        raise CaptureError(
            f"Existing {model_id} source/dependency state differs from this run"
        )
    if manifest.get("device") != expected_device:
        raise CaptureError(f"Existing {model_id} Simulator identity drifted")
    backend_evidence = validation.get("backendEvidence")
    capture_window = (
        backend_evidence.get("captureWindow")
        if isinstance(backend_evidence, dict)
        else None
    )
    if not isinstance(capture_window, dict):
        raise CaptureError(f"Existing {model_id} backend captureWindow drifted")
    if (
        manifest.get("status") != "candidate-only"
        or manifest.get("executionEvidence") != "verified locally"
        or manifest.get("modelId") != model_id
        or manifest.get("captureExitCode") != 0
        or manifest.get("startedAt") != capture_window.get("startedAt")
        or manifest.get("captureFinishedAt") != capture_window.get("finishedAt")
        or manifest.get("workingDirectory") != str(HARNESS_ROOT)
        or manifest.get("command")
        != capture_command(model_id, str(expected_device["udid"]))
        or manifest.get("environment")
        != {"PLAN018_SCREENSHOT_OUTPUT": str(run_root)}
        or manifest.get("shell") is not False
        or manifest.get("captureTimeoutSeconds")
        != FLUTTER_DRIVE_TIMEOUT_SECONDS
        or manifest.get("terminationGraceSeconds")
        != PROCESS_TERMINATION_GRACE_SECONDS
        or manifest.get("timeoutContract") != timeout_contract()
        or manifest.get("artifactRecordSha256")
        != hashlib.sha256(json_text(validation).encode()).hexdigest()
        or manifest.get("result") != validation
        or manifest.get("featureMaturity") != "candidate-only"
        or manifest.get("physicalTargets") != "not run"
        or manifest.get("comparisonBoundary") != "direction/conformance-only"
    ):
        raise CaptureError(f"Existing {model_id} success manifest drifted")
    return manifest


def validate_renderer_native_success_manifest_record(
    manifest: dict[str, Any],
    *,
    model_id: str,
    validation: dict[str, Any],
    expected_guard: dict[str, Any],
    expected_device: dict[str, Any],
    run_root: str | Path,
) -> dict[str, Any]:
    backend = validation.get("backendEvidence")
    capture_window = backend.get("captureWindow") if isinstance(backend, dict) else None
    if not isinstance(capture_window, dict):
        raise CaptureError("renderer-native success manifest lacks capture window")
    expected_application = validation.get("application")
    if expected_application not in {"rendererNative", "none"}:
        raise CaptureError("renderer-native success manifest application drifted")
    if (
        manifest.get("schemaVersion") != 1
        or manifest.get("status") != "release pending"
        or manifest.get("executionEvidence") != "verified locally"
        or manifest.get("application") != expected_application
        or manifest.get("runtimeAvailability") != "available"
        or manifest.get("featureMaturity") != "release pending"
        or manifest.get("targetEvidence") != "verified locally"
        or manifest.get("visualEvidence") != "not run"
        or manifest.get("modelId") != model_id
        or manifest.get("captureExitCode") != 0
        or manifest.get("startedAt") != capture_window.get("startedAt")
        or manifest.get("captureFinishedAt") != capture_window.get("finishedAt")
        or manifest.get("workingDirectory") != str(HARNESS_ROOT)
        or manifest.get("command")
        != capture_command(model_id, str(expected_device["udid"]))
        or manifest.get("environment")
        != {"PLAN018_SCREENSHOT_OUTPUT": str(run_root)}
        or manifest.get("shell") is not False
        or manifest.get("captureTimeoutSeconds") != FLUTTER_DRIVE_TIMEOUT_SECONDS
        or manifest.get("terminationGraceSeconds")
        != PROCESS_TERMINATION_GRACE_SECONDS
        or manifest.get("timeoutContract") != timeout_contract()
        or manifest.get("device") != expected_device
        or manifest.get("preflight") != expected_guard
        or manifest.get("postflight") != expected_guard
        or manifest.get("artifactRecordSha256")
        != hashlib.sha256(json_text(validation).encode()).hexdigest()
        or manifest.get("result") != validation
        or manifest.get("physicalTargets") != "not run"
        or manifest.get("comparisonBoundary")
        != "renderer-local sheen on/off control only"
    ):
        raise CaptureError(f"{model_id} renderer-native success manifest drifted")
    return manifest


def validate_renderer_native_success_manifest(
    run_root: Path,
    model_id: str,
    validation: dict[str, Any],
    *,
    expected_guard: dict[str, Any],
    expected_device: dict[str, Any],
) -> dict[str, Any]:
    path = run_root / "manifests" / f"{model_id}.json"
    if not path.is_file():
        raise CaptureError(f"{model_id} renderer-native success manifest is missing")
    return validate_renderer_native_success_manifest_record(
        read_json_file(path),
        model_id=model_id,
        validation=validation,
        expected_guard=expected_guard,
        expected_device=expected_device,
        run_root=run_root,
    )


def guard_without_source_hashes(guard: dict[str, Any], *, label: str) -> dict[str, Any]:
    source_hashes = guard.get("sourceSha256")
    if not isinstance(source_hashes, dict):
        raise CaptureError(f"{label} guard lacks sourceSha256")
    comparable = dict(guard)
    comparable["sourceSha256"] = {
        path: (
            "post-capture mutable"
            if path in POST_CAPTURE_MUTABLE_SOURCE_PATHS
            else value
        )
        for path, value in source_hashes.items()
    }
    return comparable


def dependency_evidence_status(
    evidence_path: Path,
    capture_guard: dict[str, Any],
    current_guard: dict[str, Any],
) -> str:
    if guard_without_source_hashes(
        capture_guard,
        label="captured evidence",
    ) == guard_without_source_hashes(
        current_guard,
        label="current evidence validation",
    ):
        return "verified locally"

    if sha256_path(evidence_path) != RETAINED_M3_FINAL_EVIDENCE_SHA256:
        raise CaptureError(
            "Captured final evidence dependency state differs from the "
            "current audit outside sourceSha256"
        )
    expected_retained_fields = {
        "flutterScenePin": RETAINED_M3_CANDIDATE_PIN,
        "pubCacheCheckout": str(
            Path("/Users/marlonjd/.pub-cache/git")
            / f"flutter_scene-{RETAINED_M3_CANDIDATE_PIN}"
        ),
        "pubCacheHead": RETAINED_M3_CANDIDATE_PIN,
        "pubCacheTree": RETAINED_M3_CANDIDATE_CACHE_TREE,
        "pubCacheClean": True,
    }
    for key, expected in expected_retained_fields.items():
        if capture_guard.get(key) != expected:
            raise CaptureError(
                f"Retained candidate dependency field {key} drifted"
            )

    normalized_capture = dict(capture_guard)
    normalized_capture.pop("sourceSha256", None)
    current_without_sources = dict(current_guard)
    current_without_sources.pop("sourceSha256", None)
    for key in expected_retained_fields:
        normalized_capture[key] = current_without_sources.get(key)
    if normalized_capture != current_without_sources:
        raise CaptureError(
            "Retained candidate dependency state changed outside its exact "
            "renderer revision"
        )
    return "candidate-only"


def assert_known_run_root_entries(
    run_root: Path,
    state: dict[str, Any],
    selected_model: str | None,
) -> None:
    expected_root_files = {"device.json"}
    expected_log_files: set[str] = set()
    expected_manifest_files: set[str] = set()
    for model_id in EXPECTED_MODELS:
        expected_root_files.add(f"plan018_integration_response_{model_id}.json")
        expected_root_files.update(
            f"{name}.png" for name in expected_names(state, model_id)
        )
        expected_log_files.add(f"{model_id}.log")
        expected_log_files.add(f"{model_id}.impeller.json")
        expected_manifest_files.add(f"{model_id}.json")
        expected_manifest_files.add(f"{model_id}.failed.json")

    for entry in run_root.iterdir():
        if entry.is_symlink():
            raise CaptureError(f"Run root contains an unexpected symlink: {entry.name}")
        if (
            selected_model is not None
            and entry.name.startswith(f"{selected_model}_")
            and entry.name.endswith(".png")
        ):
            raise CaptureError(
                f"Selected model {selected_model} would overwrite existing evidence"
            )
        if entry.name in ("logs", "manifests"):
            if not entry.is_dir():
                raise CaptureError(f"Run root has an unexpected {entry.name} entry")
            allowed = (
                expected_log_files if entry.name == "logs" else expected_manifest_files
            )
            for child in entry.iterdir():
                if child.is_symlink() or not child.is_file() or child.name not in allowed:
                    raise CaptureError(
                        f"Run root contains an unexpected {entry.name} artifact: "
                        f"{child.name}"
                    )
            continue
        if not entry.is_file() or entry.name not in expected_root_files:
            raise CaptureError(f"Run root contains an unexpected artifact: {entry.name}")


def inspect_existing_run_root(
    run_root: Path,
    selected_model: str | None,
    expected_device: dict[str, Any],
    expected_guard: dict[str, Any],
) -> None:
    if not run_root.exists():
        return
    if not run_root.is_dir():
        raise CaptureError("Run root exists but is not a directory")
    state = load_state()
    assert_known_run_root_entries(run_root, state, selected_model)
    device_path = run_root / "device.json"
    if device_path.exists() and read_json_file(device_path) != expected_device:
        raise CaptureError("Run root belongs to another Simulator identity")
    if any((run_root / "manifests").glob("*.failed.json")):
        raise CaptureError("Run root contains a failed/partial model; use a fresh root")
    for model_id in EXPECTED_MODELS:
        names = expected_names(state, model_id)
        paths = existing_model_paths(run_root, model_id, names)
        has_any = bool(paths)
        if model_id == selected_model:
            if has_any:
                raise CaptureError(
                    f"Selected model {model_id} would overwrite existing evidence"
                )
            continue
        if has_any:
            validation = validate_model_artifacts(run_root, model_id)
            validate_success_manifest(
                run_root,
                model_id,
                validation,
                expected_guard=expected_guard,
                expected_device=expected_device,
            )


def write_exclusive_json(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("x", encoding="utf-8") as destination:
        destination.write(json_text(value))
        destination.flush()
        os.fsync(destination.fileno())


class _NonBlockingOutputMirror:
    def __init__(self, output: Any | None) -> None:
        self._descriptor: int | None = None
        self.dropped = False
        if output is not None:
            try:
                self._descriptor = output.fileno()
            except (AttributeError, OSError):
                self.dropped = True

    def submit(self, chunk: bytes) -> None:
        if self._descriptor is None:
            return
        descriptor = self._descriptor
        flags = fcntl.fcntl(descriptor, fcntl.F_GETFL)
        try:
            fcntl.fcntl(descriptor, fcntl.F_SETFL, flags | os.O_NONBLOCK)
            written = os.write(descriptor, chunk)
            if written != len(chunk):
                self.dropped = True
        except (BlockingIOError, BrokenPipeError, OSError):
            self.dropped = True
        finally:
            fcntl.fcntl(descriptor, fcntl.F_SETFL, flags)


def stream_process(
    command: list[str],
    *,
    log_path: Path,
    cwd: Path,
    environment: dict[str, str],
    timeout_seconds: float,
    termination_grace_seconds: float,
    operation: str,
    output: Any | None,
) -> int:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("xb") as log_file:
        process = subprocess.Popen(
            command,
            cwd=cwd,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=0,
            start_new_session=True,
        )
        assert process.stdout is not None
        descriptor = process.stdout.fileno()
        os.set_blocking(descriptor, False)
        selector = selectors.DefaultSelector()
        selector.register(descriptor, selectors.EVENT_READ)
        deadline = time.monotonic() + timeout_seconds
        output_mirror = _NonBlockingOutputMirror(output)

        def persist(chunk: bytes) -> None:
            log_file.write(chunk)
            log_file.flush()
            output_mirror.submit(chunk)

        def drain_after_exit() -> bool:
            drain_deadline = time.monotonic() + STREAM_DRAIN_TIMEOUT_SECONDS
            while True:
                try:
                    chunk = os.read(descriptor, 8192)
                except BlockingIOError:
                    remaining = drain_deadline - time.monotonic()
                    if remaining <= 0:
                        return False
                    selector.select(min(0.05, remaining))
                    continue
                if not chunk:
                    return True
                persist(chunk)
                if time.monotonic() >= drain_deadline:
                    return False

        try:
            stream_eof = False
            while True:
                if stream_eof and process.poll() is not None:
                    return process.returncode
                if time.monotonic() >= deadline:
                    termination = terminate_then_kill(
                        process,
                        grace_seconds=termination_grace_seconds,
                    )
                    termination["streamEof"] = drain_after_exit()
                    raise CaptureTimeoutError(
                        operation=operation,
                        timeout_seconds=timeout_seconds,
                        termination=termination,
                        partial_log=str(log_path),
                    )
                remaining = max(0.0, deadline - time.monotonic())
                if stream_eof:
                    time.sleep(min(0.05, remaining))
                    events = []
                else:
                    events = selector.select(min(0.25, remaining))
                if events:
                    try:
                        chunk = os.read(descriptor, 8192)
                    except BlockingIOError:
                        chunk = None
                    if chunk == b"":
                        selector.unregister(descriptor)
                        stream_eof = True
                    if chunk:
                        persist(chunk)
        except BaseException:
            if process.poll() is None:
                terminate_then_kill(
                    process,
                    grace_seconds=termination_grace_seconds,
                )
            raise
        finally:
            selector.close()
            log_file.flush()
            os.fsync(log_file.fileno())


def stream_capture(command: list[str], run_root: Path, model_id: str) -> int:
    environment = os.environ.copy()
    environment["PLAN018_SCREENSHOT_OUTPUT"] = str(run_root)
    return stream_process(
        command,
        log_path=run_root / "logs" / f"{model_id}.log",
        cwd=HARNESS_ROOT,
        environment=environment,
        timeout_seconds=FLUTTER_DRIVE_TIMEOUT_SECONDS,
        termination_grace_seconds=PROCESS_TERMINATION_GRACE_SECONDS,
        operation=f"flutter drive ({model_id})",
        output=sys.stdout.buffer,
    )


def normalize_unified_log_record(
    record: dict[str, Any],
    *,
    kind: str,
) -> dict[str, Any]:
    return {
        "kind": kind,
        "timestamp": record.get("timestamp"),
        "eventMessage": record.get("eventMessage"),
        "eventType": record.get("eventType"),
        "messageType": record.get("messageType"),
        "processId": record.get("processID"),
        "processImagePath": record.get("processImagePath"),
        "processImageUuid": record.get("processImageUUID"),
        "senderImagePath": record.get("senderImagePath"),
        "bootUuid": record.get("bootUUID"),
    }


def collect_impeller_evidence(
    run_root: Path,
    model_id: str,
    udid: str,
    *,
    started_at: str,
    finished_at: str,
    status: str = "candidate-only",
) -> None:
    started = parse_aware_timestamp(
        started_at,
        field=f"{model_id} capture startedAt",
    )
    finished = parse_aware_timestamp(
        finished_at,
        field=f"{model_id} capture finishedAt",
    )
    if finished < started or (
        finished - started
    ).total_seconds() > FLUTTER_DRIVE_TIMEOUT_SECONDS:
        raise CaptureError(f"{model_id} capture window is invalid")

    log_path = run_root / "logs" / f"{model_id}.log"
    log = log_path.read_text(encoding="utf-8", errors="replace")
    complete_records = parse_prefixed_json(log, "PLAN018_COMPLETE ")
    if len(complete_records) != 1:
        raise CaptureError(
            f"{model_id} log must contain one COMPLETE before backend collection"
        )
    expected_complete = complete_records[0]

    query_command = impeller_query_command(udid, started, finished)
    raw_text = run_checked(
        query_command,
        timeout_seconds=DEVICE_DISCOVERY_TIMEOUT_SECONDS,
        operation=f"Simulator unified-log backend evidence ({model_id})",
    )
    raw_records = json.loads(raw_text)
    if not isinstance(raw_records, list):
        raise CaptureError(f"{model_id} Simulator unified log is not an array")

    complete_candidates: list[dict[str, Any]] = []
    impeller_candidates: list[dict[str, Any]] = []
    for index, raw_record in enumerate(raw_records):
        if not isinstance(raw_record, dict):
            raise CaptureError(
                f"{model_id} Simulator unified log record[{index}] is malformed"
            )
        timestamp = parse_aware_timestamp(
            raw_record.get("timestamp"),
            field=f"{model_id} Simulator unified log record[{index}].timestamp",
        )
        if timestamp < started or timestamp > finished:
            continue
        event_message = raw_record.get("eventMessage")
        if not isinstance(event_message, str):
            raise CaptureError(
                f"{model_id} Simulator unified log record[{index}] lacks a message"
            )
        if event_message == IMPELLER_EVENT_MESSAGE:
            impeller_candidates.append(raw_record)
            continue
        values = parse_prefixed_json(event_message, "PLAN018_COMPLETE ")
        if values == [expected_complete]:
            complete_candidates.append(raw_record)

    if len(complete_candidates) != 1:
        raise CaptureError(
            f"{model_id} unified log lacks one capture-window COMPLETE record"
        )
    complete_raw = complete_candidates[0]
    process_id = complete_raw.get("processID")
    matching_impeller = [
        record
        for record in impeller_candidates
        if record.get("processID") == process_id
    ]
    if len(matching_impeller) != 1:
        raise CaptureError(
            f"{model_id} unified log lacks one same-process Impeller record"
        )

    evidence = {
        "schemaVersion": 1,
        "status": status,
        "executionEvidence": "verified locally",
        "fixtureValidation": False,
        "source": IMPELLER_LOG_SOURCE,
        "modelId": model_id,
        "deviceUdid": udid,
        "captureWindow": {
            "startedAt": started_at,
            "finishedAt": finished_at,
        },
        "queryCommand": query_command,
        "records": [
            normalize_unified_log_record(
                matching_impeller[0],
                kind="impeller",
            ),
            normalize_unified_log_record(
                complete_raw,
                kind="complete",
            ),
        ],
    }
    write_exclusive_json(
        run_root / "logs" / f"{model_id}.impeller.json",
        evidence,
    )


def timeout_fixture_command(label: str) -> list[str]:
    descendant = (
        "import signal,time;"
        "signal.signal(signal.SIGTERM, lambda *_: None);"
        "time.sleep(60)"
    )
    source = (
        "import signal,subprocess,sys,time;"
        f"subprocess.Popen([sys.executable, '-c', {descendant!r}]);"
        f"sys.stdout.write({label!r} + '\\n');"
        "sys.stdout.flush();"
        "time.sleep(60)"
    )
    return [sys.executable, "-c", source]


def exercise_timeout_fixture(run_root: Path) -> dict[str, Any]:
    if not run_root.is_dir() or any(run_root.iterdir()):
        raise CaptureError("Timeout fixture requires an existing empty directory")
    logs = run_root / "logs"
    manifests = run_root / "manifests"
    logs.mkdir()
    manifests.mkdir()

    command_timeout: CaptureTimeoutError | None = None
    try:
        run_checked(
            timeout_fixture_command("partial command timeout fixture"),
            cwd=REPO_ROOT,
            timeout_seconds=0.5,
            termination_grace_seconds=0.1,
            operation="bounded command timeout fixture",
        )
    except CaptureTimeoutError as error:
        command_timeout = error
    if command_timeout is None:
        raise CaptureError("Bounded command timeout fixture did not time out")

    stream_timeout: CaptureTimeoutError | None = None
    try:
        stream_process(
            timeout_fixture_command("partial timeout fixture"),
            log_path=logs / "timeout_fixture.log",
            cwd=REPO_ROOT,
            environment=os.environ.copy(),
            timeout_seconds=0.5,
            termination_grace_seconds=0.1,
            operation="stream timeout fixture",
            output=None,
        )
    except CaptureTimeoutError as error:
        stream_timeout = error
    if stream_timeout is None:
        raise CaptureError("Stream timeout fixture did not time out")

    timeout_record = stream_timeout.to_json()
    failure_manifest = {
        "schemaVersion": 1,
        "status": "failed",
        "executionEvidence": "not run",
        "fixtureValidation": True,
        "failureType": type(stream_timeout).__name__,
        "failure": str(stream_timeout),
        "timeout": timeout_record,
        "retentionBoundary": (
            "Partial streamed bytes are retained; no artifact was overwritten."
        ),
    }
    write_exclusive_json(
        manifests / "timeout_fixture.failed.json",
        failure_manifest,
    )
    return {
        "status": "failed-as-expected",
        "executionEvidence": "not run",
        "fixtureValidation": True,
        "commandTimeoutType": type(command_timeout).__name__,
        "commandTermination": command_timeout.to_json(),
        "streamTimeoutType": type(stream_timeout).__name__,
        "streamTermination": timeout_record,
        "partialLog": str(logs / "timeout_fixture.log"),
        "failedManifest": str(manifests / "timeout_fixture.failed.json"),
    }


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def require_renderer_native_model(value: str | None) -> str:
    if value not in EXPECTED_NATIVE_CONTROL_MODELS:
        raise CaptureError(
            "Renderer-native model must be one of: "
            + ", ".join(EXPECTED_NATIVE_CONTROL_MODELS)
        )
    return value


def assert_known_renderer_native_run_root_entries(
    run_root: Path,
    state: dict[str, Any],
) -> None:
    expected_root_files = {"device.json"}
    expected_log_files: set[str] = set()
    expected_manifest_files: set[str] = set()
    for control_model in EXPECTED_NATIVE_CONTROL_MODELS:
        names = expected_renderer_native_control_names(state, control_model)
        expected_root_files.add(
            f"plan018_integration_response_{control_model}.json"
        )
        expected_root_files.update(f"{name}.png" for name in names)
        expected_log_files.update(
            (f"{control_model}.log", f"{control_model}.impeller.json")
        )
        expected_manifest_files.update(
            (f"{control_model}.json", f"{control_model}.failed.json")
        )
    for entry in run_root.iterdir():
        if entry.is_symlink():
            raise CaptureError(
                f"Renderer-native run root has unexpected entry: {entry.name}"
            )
        if entry.name in ("logs", "manifests"):
            if not entry.is_dir():
                raise CaptureError(
                    f"Renderer-native run root has unexpected entry: {entry.name}"
                )
            allowed = (
                expected_log_files
                if entry.name == "logs"
                else expected_manifest_files
            )
            for child in entry.iterdir():
                if (
                    child.is_symlink()
                    or not child.is_file()
                    or child.name not in allowed
                ):
                    raise CaptureError(
                        "Renderer-native run root has unexpected nested entry: "
                        f"{entry.name}/{child.name}"
                    )
            continue
        if not entry.is_file() or entry.name not in expected_root_files:
            raise CaptureError(
                f"Renderer-native run root has unexpected entry: {entry.name}"
            )


def inspect_renderer_native_run_root(
    run_root: Path,
    model_id: str,
    device: dict[str, Any],
    preflight: dict[str, Any],
) -> None:
    if not run_root.exists():
        return
    if not run_root.is_dir():
        raise CaptureError("Renderer-native run root is not a directory")
    if (run_root / "evidence.json").exists():
        raise CaptureError("Renderer-native run root is already finalized")
    state = load_renderer_native_control_state()
    assert_known_renderer_native_run_root_entries(run_root, state)
    device_path = run_root / "device.json"
    if device_path.exists() and read_json_file(device_path) != device:
        raise CaptureError("Renderer-native run root belongs to another Simulator")
    if any((run_root / "manifests").glob("*.failed.json")):
        raise CaptureError(
            "Renderer-native run root contains a failed/partial model; use a fresh root"
        )
    selected_paths = existing_model_paths(
        run_root,
        model_id,
        expected_renderer_native_control_names(state, model_id),
    )
    if selected_paths:
        raise CaptureError(
            "Selected renderer-native model already has artifacts in this run root"
        )
    for control_model in EXPECTED_NATIVE_CONTROL_MODELS:
        if control_model == model_id:
            continue
        names = expected_renderer_native_control_names(state, control_model)
        paths = existing_model_paths(run_root, control_model, names)
        if not paths:
            continue
        validation = validate_renderer_native_control_artifacts(
            run_root,
            control_model,
        )
        validate_renderer_native_success_manifest(
            run_root,
            control_model,
            validation,
            expected_guard=preflight,
            expected_device=device,
        )


def plan_renderer_native_capture(arguments: argparse.Namespace) -> dict[str, Any]:
    model_id = require_renderer_native_model(arguments.model)
    udid = validate_udid(arguments.udid)
    run_root = resolve_renderer_native_run_root(arguments.run_root)
    preflight = repository_guard()
    fixture_path = Path(arguments.device_fixture) if arguments.device_fixture else None
    simctl, flutter_devices, source = query_devices(fixture_path)
    device = validate_device(udid, simctl, flutter_devices, source)
    inspect_renderer_native_run_root(run_root, model_id, device, preflight)
    state = load_renderer_native_control_state()
    application = derive_renderer_native_control_contract(
        state["models"][model_id]
    )["installedProbe"]["application"]
    return {
        "mode": "plan",
        "status": "release pending",
        "application": application,
        "runtimeAvailability": "available",
        "featureMaturity": "release pending",
        "targetEvidence": "not run",
        "visualEvidence": "not run",
        "externalExecution": "not run",
        "modelId": model_id,
        "udid": udid,
        "runRoot": str(run_root),
        "workingDirectory": str(HARNESS_ROOT),
        "command": capture_command(model_id, udid),
        "environment": {"PLAN018_SCREENSHOT_OUTPUT": str(run_root)},
        "shell": False,
        "captureTimeoutSeconds": FLUTTER_DRIVE_TIMEOUT_SECONDS,
        "terminationGraceSeconds": PROCESS_TERMINATION_GRACE_SECONDS,
        "timeoutContract": timeout_contract(),
        "device": device,
        "preflight": preflight,
        "overwrite": False,
        "simulatorLifecycleActions": [],
        "comparisonBoundary": "renderer-local sheen on/off control only",
    }


def capture_renderer_native_control(
    arguments: argparse.Namespace,
) -> dict[str, Any]:
    model_id = require_renderer_native_model(arguments.model)
    udid = validate_udid(arguments.udid)
    run_root = resolve_renderer_native_run_root(arguments.run_root)
    preflight = repository_guard()
    simctl, flutter_devices, source = query_devices(None)
    device = validate_device(udid, simctl, flutter_devices, source)
    inspect_renderer_native_run_root(run_root, model_id, device, preflight)
    if not run_root.exists():
        run_root.mkdir(parents=True, exist_ok=False)
    (run_root / "logs").mkdir(exist_ok=True)
    (run_root / "manifests").mkdir(exist_ok=True)

    state = load_renderer_native_control_state()
    for other_model in EXPECTED_NATIVE_CONTROL_MODELS:
        if other_model == model_id:
            continue
        other_names = expected_renderer_native_control_names(state, other_model)
        other_paths = existing_model_paths(run_root, other_model, other_names)
        if not other_paths:
            continue
        validation = validate_renderer_native_control_artifacts(
            run_root,
            other_model,
        )
        validate_renderer_native_success_manifest(
            run_root,
            other_model,
            validation,
            expected_guard=preflight,
            expected_device=device,
        )

    device_path = run_root / "device.json"
    if device_path.exists():
        if read_json_file(device_path) != device:
            raise CaptureError("Renderer-native run root device drifted")
    else:
        write_exclusive_json(device_path, device)

    command = capture_command(model_id, udid)
    started = utc_now()
    exit_code: int | None = None
    try:
        exit_code = stream_capture(command, run_root, model_id)
        if exit_code != 0:
            raise CaptureError(f"flutter drive exited {exit_code}")
        capture_finished = utc_now()
        collect_impeller_evidence(
            run_root,
            model_id,
            udid,
            started_at=started,
            finished_at=capture_finished,
            status="release pending",
        )
        validation = validate_renderer_native_control_artifacts(
            run_root,
            model_id,
            expected_device_udid=udid,
            expected_started_at=started,
            expected_finished_at=capture_finished,
        )
        postflight = repository_guard()
        if preflight != postflight:
            raise CaptureError(
                "Protected source/dependency state changed during native capture"
            )
        manifest = {
            "schemaVersion": 1,
            "status": "release pending",
            "executionEvidence": "verified locally",
            "application": validation["application"],
            "runtimeAvailability": "available",
            "featureMaturity": "release pending",
            "targetEvidence": "verified locally",
            "visualEvidence": "not run",
            "modelId": model_id,
            "captureExitCode": exit_code,
            "startedAt": started,
            "captureFinishedAt": capture_finished,
            "finishedAt": utc_now(),
            "workingDirectory": str(HARNESS_ROOT),
            "command": command,
            "environment": {"PLAN018_SCREENSHOT_OUTPUT": str(run_root)},
            "shell": False,
            "captureTimeoutSeconds": FLUTTER_DRIVE_TIMEOUT_SECONDS,
            "terminationGraceSeconds": PROCESS_TERMINATION_GRACE_SECONDS,
            "timeoutContract": timeout_contract(),
            "device": device,
            "preflight": preflight,
            "postflight": postflight,
            "artifactRecordSha256": hashlib.sha256(
                json_text(validation).encode()
            ).hexdigest(),
            "result": validation,
            "physicalTargets": "not run",
            "comparisonBoundary": "renderer-local sheen on/off control only",
        }
        validate_renderer_native_success_manifest_record(
            manifest,
            model_id=model_id,
            validation=validation,
            expected_guard=preflight,
            expected_device=device,
            run_root=run_root,
        )
        write_exclusive_json(
            run_root / "manifests" / f"{model_id}.json",
            manifest,
        )
        return manifest
    except Exception as error:
        if isinstance(error, CaptureTimeoutError):
            timed_out_exit_code = error.termination.get("exitCode")
            if isinstance(timed_out_exit_code, int):
                exit_code = timed_out_exit_code
        failed_manifest = {
            "schemaVersion": 1,
            "status": "failed",
            "executionEvidence": "not run",
            "modelId": model_id,
            "captureExitCode": exit_code,
            "startedAt": started,
            "finishedAt": utc_now(),
            "workingDirectory": str(HARNESS_ROOT),
            "command": command,
            "environment": {"PLAN018_SCREENSHOT_OUTPUT": str(run_root)},
            "shell": False,
            "device": device,
            "preflight": preflight,
            "failure": str(error),
            "failureType": type(error).__name__,
            "timeout": (
                error.to_json() if isinstance(error, CaptureTimeoutError) else None
            ),
            "retentionBoundary": (
                "Partial artifacts are retained. Retry in a fresh "
                "renderer-native run root; nothing was deleted or overwritten."
            ),
        }
        failed_path = run_root / "manifests" / f"{model_id}.failed.json"
        if not failed_path.exists():
            write_exclusive_json(failed_path, failed_manifest)
        raise


def plan_capture(arguments: argparse.Namespace) -> dict[str, Any]:
    model_id = require_model(arguments.model)
    udid = validate_udid(arguments.udid)
    run_root = resolve_real_run_root(arguments.run_root)
    preflight = repository_guard()
    fixture_path = Path(arguments.device_fixture) if arguments.device_fixture else None
    simctl, flutter_devices, source = query_devices(fixture_path)
    device = validate_device(udid, simctl, flutter_devices, source)
    inspect_existing_run_root(run_root, model_id, device, preflight)
    return {
        "mode": "plan",
        "externalExecution": "not run",
        "modelId": model_id,
        "udid": udid,
        "runRoot": str(run_root),
        "workingDirectory": str(HARNESS_ROOT),
        "command": capture_command(model_id, udid),
        "environment": {"PLAN018_SCREENSHOT_OUTPUT": str(run_root)},
        "shell": False,
        "captureTimeoutSeconds": FLUTTER_DRIVE_TIMEOUT_SECONDS,
        "terminationGraceSeconds": PROCESS_TERMINATION_GRACE_SECONDS,
        "timeoutContract": timeout_contract(),
        "device": device,
        "preflight": preflight,
        "overwrite": False,
        "simulatorLifecycleActions": [],
    }


def capture_one(arguments: argparse.Namespace) -> dict[str, Any]:
    if arguments.device_fixture is not None:
        raise CaptureError("A device fixture cannot authorize a real capture")
    model_id = require_model(arguments.model)
    udid = validate_udid(arguments.udid)
    run_root = resolve_real_run_root(arguments.run_root)
    preflight = repository_guard()
    simctl, flutter_devices, source = query_devices(None)
    device = validate_device(udid, simctl, flutter_devices, source)
    inspect_existing_run_root(run_root, model_id, device, preflight)
    if not run_root.exists():
        run_root.mkdir(parents=True, exist_ok=False)
    (run_root / "logs").mkdir(exist_ok=True)
    (run_root / "manifests").mkdir(exist_ok=True)
    assert_no_selected_artifacts(run_root, model_id)

    device_path = run_root / "device.json"
    if device_path.exists():
        if read_json_file(device_path) != device:
            raise CaptureError("Run root belongs to another Simulator identity")
    else:
        write_exclusive_json(device_path, device)

    command = capture_command(model_id, udid)
    started = utc_now()
    exit_code: int | None = None
    failure: str | None = None
    try:
        exit_code = stream_capture(command, run_root, model_id)
        if exit_code != 0:
            raise CaptureError(f"flutter drive exited {exit_code}")
        capture_finished = utc_now()
        collect_impeller_evidence(
            run_root,
            model_id,
            udid,
            started_at=started,
            finished_at=capture_finished,
        )
        validation = validate_model_artifacts(
            run_root,
            model_id,
            expected_device_udid=udid,
            expected_started_at=started,
            expected_finished_at=capture_finished,
        )
        postflight = repository_guard()
        if preflight != postflight:
            raise CaptureError("Protected source/dependency state changed during capture")
        manifest = {
            "schemaVersion": 1,
            "status": "candidate-only",
            "executionEvidence": "verified locally",
            "modelId": model_id,
            "captureExitCode": exit_code,
            "startedAt": started,
            "captureFinishedAt": capture_finished,
            "finishedAt": utc_now(),
            "workingDirectory": str(HARNESS_ROOT),
            "command": command,
            "environment": {"PLAN018_SCREENSHOT_OUTPUT": str(run_root)},
            "shell": False,
            "captureTimeoutSeconds": FLUTTER_DRIVE_TIMEOUT_SECONDS,
            "terminationGraceSeconds": PROCESS_TERMINATION_GRACE_SECONDS,
            "timeoutContract": timeout_contract(),
            "device": device,
            "preflight": preflight,
            "postflight": postflight,
            "artifactRecordSha256": hashlib.sha256(
                json_text(validation).encode()
            ).hexdigest(),
            "result": validation,
            "featureMaturity": "candidate-only",
            "physicalTargets": "not run",
            "comparisonBoundary": "direction/conformance-only",
        }
        write_exclusive_json(
            run_root / "manifests" / f"{model_id}.json", manifest
        )
        return manifest
    except Exception as error:
        failure = str(error)
        if isinstance(error, CaptureTimeoutError):
            timed_out_exit_code = error.termination.get("exitCode")
            if isinstance(timed_out_exit_code, int):
                exit_code = timed_out_exit_code
        failed_postflight: dict[str, Any] | None = None
        failed_postflight_error: str | None = None
        try:
            failed_postflight = repository_guard()
        except Exception as postflight_error:
            failed_postflight_error = str(postflight_error)
        failed_manifest = {
            "schemaVersion": 1,
            "status": "failed",
            "executionEvidence": "not verified",
            "modelId": model_id,
            "captureExitCode": exit_code,
            "startedAt": started,
            "finishedAt": utc_now(),
            "workingDirectory": str(HARNESS_ROOT),
            "command": command,
            "environment": {"PLAN018_SCREENSHOT_OUTPUT": str(run_root)},
            "shell": False,
            "captureTimeoutSeconds": FLUTTER_DRIVE_TIMEOUT_SECONDS,
            "terminationGraceSeconds": PROCESS_TERMINATION_GRACE_SECONDS,
            "timeoutContract": timeout_contract(),
            "device": device,
            "preflight": preflight,
            "postflight": failed_postflight,
            "postflightError": failed_postflight_error,
            "failure": failure,
            "failureType": type(error).__name__,
            "timeout": (
                error.to_json() if isinstance(error, CaptureTimeoutError) else None
            ),
            "retentionBoundary": (
                "Partial artifacts are retained. Retry in a fresh run root; "
                "nothing was deleted or overwritten."
            ),
        }
        failed_path = run_root / "manifests" / f"{model_id}.failed.json"
        if not failed_path.exists():
            write_exclusive_json(failed_path, failed_manifest)
        raise


def evidence_from_models(
    run_root: Path,
    models: list[dict[str, Any]],
    *,
    source_hashes: dict[str, str],
    device: dict[str, Any] | None,
    fixture_validation: bool,
    flutter_scene_pin: str = EXPECTED_PIN,
) -> dict[str, Any]:
    all_pngs = sorted(run_root.glob("*.png"))
    all_logs = sorted((run_root / "logs").glob("*.log"))
    all_backend_evidence = sorted((run_root / "logs").glob("*.impeller.json"))
    all_responses = sorted(run_root.glob("plan018_integration_response_*.json"))
    if len(all_pngs) != 27:
        raise CaptureError(f"Final evidence requires exactly 27 PNG files; found {len(all_pngs)}")
    if len(all_logs) != 4:
        raise CaptureError(f"Final evidence requires exactly 4 logs; found {len(all_logs)}")
    if len(all_backend_evidence) != 4:
        raise CaptureError(
            "Final evidence requires exactly 4 Impeller proofs; "
            f"found {len(all_backend_evidence)}"
        )
    if len(all_responses) != 4:
        raise CaptureError(
            f"Final evidence requires exactly 4 responses; found {len(all_responses)}"
        )
    ordered_names = [
        name
        for model in models
        for name in model["orderedScreenshotNames"]
    ]
    if [path.stem for path in all_pngs] != sorted(ordered_names):
        raise CaptureError("Final PNG names differ from the exact 27-stage inventory")
    return {
        "schemaVersion": 1,
        "status": "candidate-only",
        "executionEvidence": (
            "not run" if fixture_validation else "verified locally"
        ),
        "featureMaturity": "candidate-only",
        "timeoutContract": timeout_contract(),
        "scope": (
            "synthetic capture-recorder fixture validation"
            if fixture_validation
            else "flutter_scene_viewer iOS Simulator controlled sheen captures"
        ),
        "comparisonBoundary": "direction/conformance-only",
        "stateSha256": EXPECTED_STATE_SHA256,
        "environmentSha256": EXPECTED_ENVIRONMENT_SHA256,
        "flutterScenePin": flutter_scene_pin,
        "device": device,
        "sourceSha256": source_hashes,
        "models": models,
        "orderedScreenshotNames": ordered_names,
        "pngCount": len(all_pngs),
        "logCount": len(all_logs),
        "backendEvidenceCount": len(all_backend_evidence),
        "responseCount": len(all_responses),
        "fixtureValidation": fixture_validation,
        "pixelHealthStatus": "not run",
        "pixelHealthBoundary": (
            "Pixel health is validated separately by frozen renderer-local "
            "blank, flat, and render-delta gates. This recorder defines no "
            "cross-renderer pixel threshold and makes no pixel-parity claim."
        ),
        "referenceComparison": "not run",
        "physicalIos": "not run",
        "android": "not run",
        "web": "not run",
        "rendererNativeSheen": "not established",
        "release": "not established",
        "productionReadiness": "not established",
    }


def renderer_native_evidence_from_models(
    run_root: Path,
    models: list[dict[str, Any]],
    *,
    source_hashes: dict[str, str],
    device: dict[str, Any] | None,
    fixture_validation: bool,
    visual_evidence: str = "not run",
    visual_analysis: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if [model.get("modelId") for model in models] != list(
        EXPECTED_NATIVE_CONTROL_MODELS
    ):
        raise CaptureError("Renderer-native evidence model order drifted")
    if [model.get("application") for model in models] != [
        "rendererNative",
        "none",
    ]:
        raise CaptureError("Renderer-native evidence application pair drifted")
    state = load_renderer_native_control_state()
    expected_execution = "not run" if fixture_validation else "verified locally"
    expected_target = "not run" if fixture_validation else "verified locally"
    for model_id, model in zip(
        EXPECTED_NATIVE_CONTROL_MODELS,
        models,
        strict=True,
    ):
        expected_names = expected_renderer_native_control_names(state, model_id)
        if (
            model.get("status") != "release pending"
            or model.get("executionEvidence") != expected_execution
            or model.get("fixtureValidation") is not fixture_validation
            or model.get("runtimeAvailability") != "available"
            or model.get("featureMaturity") != "release pending"
            or model.get("targetEvidence") != expected_target
            or model.get("visualEvidence") != "not run"
            or model.get("readyCount") != 3
            or model.get("artifactCount") != 3
            or model.get("orderedScreenshotNames") != expected_names
            or model.get("comparisonBoundary")
            != "renderer-local sheen on/off control only"
            or not isinstance(model.get("artifacts"), list)
            or len(model["artifacts"]) != 3
        ):
            label = "fixture" if fixture_validation else "real"
            raise CaptureError(
                f"Renderer-native {label} model evidence drifted: {model_id}"
            )
    if fixture_validation:
        if (
            source_hashes
            or device is not None
            or visual_evidence != "not run"
            or visual_analysis is not None
        ):
            raise CaptureError("Renderer-native fixture evidence boundary drifted")
    else:
        if (
            not source_hashes
            or any(
                not isinstance(value, str)
                or re.fullmatch(r"[0-9a-f]{64}", value) is None
                for value in source_hashes.values()
            )
            or not isinstance(device, dict)
            or visual_evidence != "verified locally"
            or not isinstance(visual_analysis, dict)
        ):
            raise CaptureError("Renderer-native real evidence boundary drifted")
        artifact_by_name = {
            Path(artifact["path"]).name: artifact
            for model in models
            for artifact in model["artifacts"]
        }
        visual_frames = visual_analysis.get("frames")
        expected_visual_names = [
            f"{name}.png"
            for model in models
            for name in model["orderedScreenshotNames"]
        ]
        if (
            not isinstance(visual_frames, list)
            or len(visual_frames) != 6
            or [
                frame.get("fileName") if isinstance(frame, dict) else None
                for frame in visual_frames
            ]
            != expected_visual_names
            or set(artifact_by_name) != set(expected_visual_names)
        ):
            raise CaptureError("Renderer-native visual frame binding drifted")
        for frame in visual_frames:
            if not isinstance(frame, dict):
                raise CaptureError("Renderer-native visual frame binding drifted")
            artifact = artifact_by_name.get(frame.get("fileName"))
            if artifact is None or any(
                frame.get(field) != artifact.get(field)
                for field in ("path", "sha256", "byteLength", "dimensions")
            ):
                raise CaptureError("Renderer-native visual frame binding drifted")
    all_pngs = sorted(run_root.glob("*.png"))
    all_logs = sorted((run_root / "logs").glob("*.log"))
    all_backend = sorted((run_root / "logs").glob("*.impeller.json"))
    all_responses = sorted(run_root.glob("plan018_integration_response_*.json"))
    if (
        len(all_pngs) != 6
        or len(all_logs) != 2
        or len(all_backend) != 2
        or len(all_responses) != 2
    ):
        raise CaptureError("Renderer-native evidence artifact inventory drifted")
    ordered_names = [
        name
        for model in models
        for name in model["orderedScreenshotNames"]
    ]
    if [path.stem for path in all_pngs] != sorted(ordered_names):
        raise CaptureError("Renderer-native PNG inventory drifted")
    target_evidence = "not run" if fixture_validation else "verified locally"
    return {
        "schemaVersion": 1,
        "status": "release pending",
        "executionEvidence": target_evidence,
        "application": {
            "sheenOn": "rendererNative",
            "sheenOff": "none",
        },
        "runtimeAvailability": "available",
        "featureMaturity": "release pending",
        "targetEvidence": target_evidence,
        "visualEvidence": visual_evidence,
        "scope": (
            "synthetic renderer-native capture-recorder fixture validation"
            if fixture_validation
            else "flutter_scene_viewer iOS Simulator renderer-native sheen control"
        ),
        "comparisonBoundary": "renderer-local sheen on/off control only",
        "stateSha256": EXPECTED_NATIVE_CONTROL_STATE_SHA256,
        "historicalCandidateStateSha256": EXPECTED_STATE_SHA256,
        "environmentSha256": EXPECTED_ENVIRONMENT_SHA256,
        "flutterScenePin": EXPECTED_PIN,
        "device": device,
        "sourceSha256": source_hashes,
        "models": models,
        "orderedScreenshotNames": ordered_names,
        "pngCount": len(all_pngs),
        "modelCount": len(models),
        "logCount": len(all_logs),
        "backendEvidenceCount": len(all_backend),
        "responseCount": len(all_responses),
        "fixtureValidation": fixture_validation,
        "visualAnalysis": visual_analysis,
        "referenceComparison": "not run",
        "physicalIos": "not run",
        "android": "not run",
        "web": "not run",
        "release": "release pending",
        "productionReadiness": "not run",
        "physicalCorrectness": "not run",
        "generalPixelParity": "not run",
        "claimBoundary": (
            "Renderer-local scalar sheen on/off evidence only; no external "
            "reference, physical correctness, general pixel parity, physical "
            "target, release, or production-ready claim."
        ),
    }


def analyze_renderer_native_control_images(run_root: Path) -> dict[str, Any]:
    output = run_checked(
        [
            "node",
            str(RENDERER_NATIVE_HEALTH_ANALYZER_PATH),
            str(run_root),
        ],
        cwd=REPO_ROOT,
        timeout_seconds=HARNESS_VALIDATION_TIMEOUT_SECONDS,
        operation="renderer-native sheen visual analysis",
    )
    try:
        analysis = json.loads(output)
    except json.JSONDecodeError as error:
        raise CaptureError(
            "Renderer-native sheen analyzer returned malformed JSON"
        ) from error
    if not isinstance(analysis, dict):
        raise CaptureError("Renderer-native sheen analysis is not an object")
    expected = {
        "status": "verified locally",
        "executionEvidence": "verified locally",
        "visualEvidence": "verified locally",
        "featureMaturity": "release pending",
        "application": {
            "sheenOn": "rendererNative",
            "sheenOff": "none",
        },
        "comparisonBoundary": "renderer-local sheen on/off control only",
        "stateSha256": EXPECTED_NATIVE_CONTROL_STATE_SHA256,
        "frameCount": 6,
        "onOffComparisonCount": 3,
        "externalReference": "not run",
        "physicalIos": "not run",
        "android": "not run",
        "web": "not run",
        "physicalCorrectness": "not run",
        "generalPixelParity": "not run",
        "productionReadiness": "not run",
    }
    for key, value in expected.items():
        if analysis.get(key) != value:
            raise CaptureError(
                f"Renderer-native sheen visual analysis drifted: {key}"
            )
    frames = analysis.get("frames")
    comparisons = analysis.get("onOffComparisons")
    if (
        not isinstance(frames, list)
        or len(frames) != 6
        or any(
            not isinstance(frame, dict)
            or any(not check.get("passed") for check in frame.get("checks", []))
            for frame in frames
        )
        or not isinstance(comparisons, list)
        or len(comparisons) != 3
        or any(
            not isinstance(comparison, dict)
            or comparison.get("check", {}).get("passed") is not True
            for comparison in comparisons
        )
    ):
        raise CaptureError("Renderer-native sheen visual checks are incomplete")
    return analysis


def finalize_renderer_native_fixture(run_root: Path) -> dict[str, Any]:
    models = [
        validate_renderer_native_control_artifacts(
            run_root,
            model_id,
            fixture_validation=True,
        )
        for model_id in EXPECTED_NATIVE_CONTROL_MODELS
    ]
    return renderer_native_evidence_from_models(
        run_root,
        models,
        source_hashes={},
        device=None,
        fixture_validation=True,
    )


def finalize_renderer_native_capture(
    arguments: argparse.Namespace,
) -> dict[str, Any]:
    run_root = resolve_renderer_native_run_root(arguments.run_root)
    if not run_root.is_dir():
        raise CaptureError("Renderer-native finalization run root does not exist")
    evidence_path = run_root / "evidence.json"
    if evidence_path.exists():
        raise CaptureError(
            "evidence.json already exists; renderer-native finalization never overwrites"
        )
    assert_known_renderer_native_run_root_entries(
        run_root,
        load_renderer_native_control_state(),
    )
    guard = repository_guard()
    device = read_json_file(run_root / "device.json")
    models: list[dict[str, Any]] = []
    for model_id in EXPECTED_NATIVE_CONTROL_MODELS:
        validation = validate_renderer_native_control_artifacts(
            run_root,
            model_id,
        )
        validate_renderer_native_success_manifest(
            run_root,
            model_id,
            validation,
            expected_guard=guard,
            expected_device=device,
        )
        models.append(validation)
    manifests = sorted((run_root / "manifests").glob("*.json"))
    if (
        len(manifests) != len(EXPECTED_NATIVE_CONTROL_MODELS)
        or any(path.name.endswith(".failed.json") for path in manifests)
    ):
        raise CaptureError(
            "Renderer-native final evidence requires exactly 2 successful manifests"
        )
    visual_analysis = analyze_renderer_native_control_images(run_root)
    evidence = renderer_native_evidence_from_models(
        run_root,
        models,
        source_hashes=guard["sourceSha256"],
        device=device,
        fixture_validation=False,
        visual_evidence="verified locally",
        visual_analysis=visual_analysis,
    )
    evidence["manifests"] = [
        {
            "path": str(path.relative_to(run_root)),
            "sha256": sha256_path(path),
            "byteLength": path.stat().st_size,
        }
        for path in manifests
    ]
    postflight = repository_guard()
    if postflight != guard:
        raise CaptureError(
            "Protected source/dependency state changed during renderer-native finalization"
        )
    evidence["preflight"] = guard
    evidence["postflight"] = postflight
    write_exclusive_json(evidence_path, evidence)
    return evidence


def missing_partial_model_record(model_id: str) -> dict[str, Any]:
    if model_id == "sheen_chair":
        reason = (
            "genuine authored TEXCOORD_1 ambient-occlusion / "
            "unsupportedMaterialFeature boundary; no UVs were invented or "
            "reinterpreted"
        )
    else:
        reason = "not run"
    return {
        "modelId": model_id,
        "status": "absent",
        "executionEvidence": "not run",
        "reason": reason,
    }


def partial_evidence_from_models(
    run_root: Path,
    models: list[dict[str, Any]],
    missing_models: list[dict[str, Any]],
    *,
    source_hashes: dict[str, str],
    summary_source_hashes: dict[str, str] | None = None,
    device: dict[str, Any] | None,
    fixture_validation: bool,
    manifests: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    completed_model_ids = [model["modelId"] for model in models]
    missing_model_ids = [model["modelId"] for model in missing_models]
    if tuple(completed_model_ids) != EXPECTED_PARTIAL_MODELS:
        raise CaptureError(
            "Partial evidence requires exactly the accepted "
            "SheenCloth/GlamVelvetSofa/ToyCar model set"
        )
    if tuple(missing_model_ids) != EXPECTED_PARTIAL_MISSING_MODELS:
        raise CaptureError("Partial evidence requires only SheenChair to be absent")
    ordered_names = [
        name
        for model in models
        for name in model["orderedScreenshotNames"]
    ]
    return {
        "schemaVersion": 1,
        "status": "candidate-only",
        "executionEvidence": (
            "not run" if fixture_validation else "verified locally"
        ),
        "featureMaturity": "candidate-only",
        "evidenceCompleteness": "partial",
        "scope": (
            "synthetic partial capture-recorder fixture validation"
            if fixture_validation
            else "partial flutter_scene_viewer iOS Simulator controlled sheen captures"
        ),
        "comparisonBoundary": "direction/conformance-only",
        "claimBoundary": (
            "Partial summary only; this is not final four-model M3 evidence, "
            "does not establish pixel parity, and does not establish physical, "
            "rendererNative, release, or production-ready sheen support."
        ),
        "stateSha256": EXPECTED_STATE_SHA256,
        "environmentSha256": EXPECTED_ENVIRONMENT_SHA256,
        "flutterScenePin": EXPECTED_PIN,
        "device": device,
        "sourceSha256": source_hashes,
        "summarySourceSha256": summary_source_hashes or source_hashes,
        "sourceHashBoundary": (
            "sourceSha256 records the captured model manifests; "
            "summarySourceSha256 records the partial-summary tool run."
        ),
        "completedModelIds": completed_model_ids,
        "missingModels": missing_models,
        "models": models,
        "orderedScreenshotNames": ordered_names,
        "pngCount": sum(len(model["artifacts"]) for model in models),
        "logCount": len(models),
        "backendEvidenceCount": len(models),
        "responseCount": len(models),
        "finalEvidencePath": "evidence.json",
        "finalEvidenceStatus": "absent",
        "finalEvidenceRequiredModels": list(EXPECTED_MODELS),
        "physicalTargets": "not run",
        "iosSimulator": "verified locally" if not fixture_validation else "not run",
        "android": "not run",
        "web": "not run",
        "release": "release pending",
        "productionReadiness": "not run",
        "pixelHealthStatus": "not run",
        "referenceComparison": "not run",
        "fixtureValidation": fixture_validation,
        "manifests": manifests or [],
    }


def finalize_fixture(run_root: Path) -> dict[str, Any]:
    models = [
        validate_model_artifacts(
            run_root,
            model_id,
            fixture_validation=True,
        )
        for model_id in EXPECTED_MODELS
    ]
    return evidence_from_models(
        run_root,
        models,
        source_hashes=collect_source_hashes(),
        device=None,
        fixture_validation=True,
    )


def summarize_partial_fixture(run_root: Path) -> dict[str, Any]:
    models = [
        validate_model_artifacts(
            run_root,
            model_id,
            fixture_validation=True,
        )
        for model_id in EXPECTED_PARTIAL_MODELS
    ]
    missing_models = [
        missing_partial_model_record(model_id)
        for model_id in EXPECTED_PARTIAL_MISSING_MODELS
    ]
    return partial_evidence_from_models(
        run_root,
        models,
        missing_models,
        source_hashes=collect_source_hashes(),
        device=None,
        fixture_validation=True,
    )


def finalize_real(arguments: argparse.Namespace) -> dict[str, Any]:
    run_root = resolve_real_run_root(arguments.run_root)
    if not run_root.is_dir():
        raise CaptureError("Finalization run root does not exist")
    if (run_root / "evidence.json").exists():
        raise CaptureError("evidence.json already exists; finalization never overwrites")
    guard = repository_guard()
    device = read_json_file(run_root / "device.json")
    models: list[dict[str, Any]] = []
    for model_id in EXPECTED_MODELS:
        validation = validate_model_artifacts(run_root, model_id)
        validate_success_manifest(
            run_root,
            model_id,
            validation,
            expected_guard=guard,
            expected_device=device,
        )
        models.append(validation)
    manifests = sorted((run_root / "manifests").glob("*.json"))
    if len(manifests) != 4 or any(path.name.endswith(".failed.json") for path in manifests):
        raise CaptureError("Final evidence requires exactly 4 successful manifests")
    evidence = evidence_from_models(
        run_root,
        models,
        source_hashes=guard["sourceSha256"],
        device=device,
        fixture_validation=False,
    )
    evidence["manifests"] = [
        {
            "path": str(path.relative_to(run_root)),
            "sha256": sha256_path(path),
            "byteLength": path.stat().st_size,
        }
        for path in manifests
    ]
    postflight = repository_guard()
    if postflight != guard:
        raise CaptureError("Protected source/dependency state changed during finalization")
    evidence["preflight"] = guard
    evidence["postflight"] = postflight
    write_exclusive_json(run_root / "evidence.json", evidence)
    return evidence


def validate_final_evidence_real(arguments: argparse.Namespace) -> dict[str, Any]:
    run_root = resolve_real_run_root(arguments.run_root)
    if not run_root.is_dir():
        raise CaptureError("Final evidence run root does not exist")
    evidence_path = run_root / "evidence.json"
    if not evidence_path.is_file():
        raise CaptureError("evidence.json is missing")
    if (run_root / "partial_evidence.json").exists():
        raise CaptureError("Final evidence cannot coexist with partial evidence")
    if any((run_root / "manifests").glob("*.failed.json")):
        raise CaptureError("Final evidence cannot include failed model manifests")

    evidence = read_json_file(evidence_path)
    current_guard = repository_guard()
    capture_preflight = evidence.get("preflight")
    capture_postflight = evidence.get("postflight")
    if (
        not isinstance(capture_preflight, dict)
        or capture_preflight != capture_postflight
    ):
        raise CaptureError("Final evidence stored guard drifted")
    dependency_status = dependency_evidence_status(
        evidence_path,
        capture_preflight,
        current_guard,
    )
    retained_dependency = dependency_status == "candidate-only"

    device = read_json_file(run_root / "device.json")
    models: list[dict[str, Any]] = []
    capture_guard: dict[str, Any] | None = None
    for model_id in EXPECTED_MODELS:
        validation = validate_model_artifacts(
            run_root,
            model_id,
            expected_root_pubspec_sha256=(
                RETAINED_M3_ROOT_PUBSPEC_SHA256
                if retained_dependency
                else None
            ),
            expected_root_lock_sha256=(
                RETAINED_M3_ROOT_LOCK_SHA256
                if retained_dependency
                else None
            ),
            expected_flutter_scene_ref=(
                RETAINED_M3_CANDIDATE_PIN if retained_dependency else None
            ),
        )
        manifest = validate_success_manifest(
            run_root,
            model_id,
            validation,
            expected_guard=None,
            expected_device=device,
        )
        manifest_guard = manifest["preflight"]
        if capture_guard is None:
            capture_guard = manifest_guard
        elif manifest_guard != capture_guard:
            raise CaptureError("Final model manifests use different guards")
        models.append(validation)
    if capture_guard != capture_preflight:
        raise CaptureError("Final evidence capture guard drifted")

    manifests = sorted((run_root / "manifests").glob("*.json"))
    if len(manifests) != len(EXPECTED_MODELS):
        raise CaptureError("Final evidence requires exactly 4 manifests")
    expected = evidence_from_models(
        run_root,
        models,
        source_hashes=capture_preflight["sourceSha256"],
        device=device,
        fixture_validation=False,
        flutter_scene_pin=capture_preflight["flutterScenePin"],
    )
    expected["manifests"] = [
        {
            "path": str(path.relative_to(run_root)),
            "sha256": sha256_path(path),
            "byteLength": path.stat().st_size,
        }
        for path in manifests
    ]
    expected["preflight"] = capture_preflight
    expected["postflight"] = capture_postflight
    if expected != evidence:
        raise CaptureError("evidence.json no longer matches final artifacts")

    ios_renderer_local_health = validate_ios_renderer_local_health(run_root)

    return {
        "mode": "validate-final-evidence",
        "status": "verified locally",
        "executionEvidence": evidence["executionEvidence"],
        "evidencePath": str(evidence_path),
        "evidenceSha256": sha256_path(evidence_path),
        "evidenceStatus": evidence["status"],
        "dependencyEvidenceStatus": dependency_status,
        "capturedRendererRevision": capture_preflight["flutterScenePin"],
        "currentRendererRevision": current_guard["flutterScenePin"],
        "evidenceCompleteness": "complete",
        "comparisonBoundary": evidence["comparisonBoundary"],
        "completedModelIds": [model["modelId"] for model in models],
        "missingModels": [],
        "pngCount": evidence["pngCount"],
        "logCount": evidence["logCount"],
        "backendEvidenceCount": evidence["backendEvidenceCount"],
        "responseCount": evidence["responseCount"],
        "finalEvidenceStatus": "verified locally",
        "pixelHealthStatus": "verified locally",
        "iosRendererLocalHealth": ios_renderer_local_health,
        "physicalTargets": "not run",
        "android": "not run",
        "web": "not run",
        "rendererNativeSheen": "not run",
        "release": "release pending",
        "productionReadiness": "not run",
    }


def validate_ios_renderer_local_health(run_root: Path) -> dict[str, Any]:
    evidence_path = run_root / "ios_renderer_local_health.json"
    if not evidence_path.is_file():
        raise CaptureError("iOS renderer-local health evidence is missing")
    output = run_checked(
        [
            "node",
            str(IOS_HEALTH_ANALYZER_PATH),
            "--validate",
            str(run_root),
        ],
        cwd=REPO_ROOT,
        timeout_seconds=HARNESS_VALIDATION_TIMEOUT_SECONDS,
        operation="iOS renderer-local health validation",
    )
    try:
        validation = json.loads(output)
    except json.JSONDecodeError as error:
        raise CaptureError(
            "iOS renderer-local health validator returned malformed JSON"
        ) from error
    if validation != {
        "status": "verified locally",
        "frameCount": 27,
        "passTripletCount": 9,
    }:
        raise CaptureError("iOS renderer-local health validation drifted")
    return {
        "status": "verified locally",
        "evidencePath": str(evidence_path),
        "evidenceSha256": sha256_path(evidence_path),
        "frameCount": 27,
        "passTripletCount": 9,
        "comparisonBoundary": "renderer-local structural health only",
        "crossRendererPixelThresholds": [],
        "physicalIos": "not run",
        "android": "not run",
        "web": "not run",
        "productionReadiness": "not run",
    }


def summarize_partial_real(arguments: argparse.Namespace) -> dict[str, Any]:
    run_root = resolve_real_run_root(arguments.run_root)
    if not run_root.is_dir():
        raise CaptureError("Partial summary run root does not exist")
    if (run_root / "evidence.json").exists():
        raise CaptureError("Final evidence already exists; partial summary is obsolete")
    if (run_root / "partial_evidence.json").exists():
        raise CaptureError(
            "partial_evidence.json already exists; partial summary never overwrites"
        )
    if any((run_root / "manifests").glob("*.failed.json")):
        raise CaptureError("Partial summary cannot include failed model roots")
    summary_preflight = repository_guard()
    device = read_json_file(run_root / "device.json")
    models: list[dict[str, Any]] = []
    manifests: list[dict[str, Any]] = []
    capture_guard: dict[str, Any] | None = None
    for model_id in EXPECTED_PARTIAL_MODELS:
        validation = validate_model_artifacts(run_root, model_id)
        manifest = validate_success_manifest(
            run_root,
            model_id,
            validation,
            expected_guard=None,
            expected_device=device,
        )
        manifest_guard = manifest["preflight"]
        if capture_guard is None:
            capture_guard = manifest_guard
        elif manifest_guard != capture_guard:
            raise CaptureError("Partial summary model manifests use different guards")
        models.append(validation)
        manifest_path = run_root / "manifests" / f"{model_id}.json"
        manifests.append(
            {
                "modelId": model_id,
                "path": str(manifest_path.relative_to(run_root)),
                "sha256": sha256_path(manifest_path),
                "byteLength": manifest_path.stat().st_size,
            }
        )
    if capture_guard is None:
        raise CaptureError("Partial summary has no captured model manifests")
    if guard_without_source_hashes(
        capture_guard,
        label="captured partial-summary",
    ) != guard_without_source_hashes(
        summary_preflight,
        label="current partial-summary",
    ):
        raise CaptureError(
            "Captured partial summary dependency state differs from the "
            "current summary run outside sourceSha256"
        )
    for model_id in EXPECTED_PARTIAL_MISSING_MODELS:
        if existing_model_paths(run_root, model_id, expected_names(load_state(), model_id)):
            raise CaptureError("SheenChair artifacts cannot be summarized as absent")
    evidence = partial_evidence_from_models(
        run_root,
        models,
        [
            missing_partial_model_record(model_id)
            for model_id in EXPECTED_PARTIAL_MISSING_MODELS
        ],
        source_hashes=capture_guard["sourceSha256"],
        summary_source_hashes=summary_preflight["sourceSha256"],
        device=device,
        fixture_validation=False,
        manifests=manifests,
    )
    postflight = repository_guard()
    if postflight != summary_preflight:
        raise CaptureError("Protected source/dependency state changed during summary")
    evidence["capturePreflight"] = capture_guard
    evidence["capturePostflight"] = capture_guard
    evidence["preflight"] = summary_preflight
    evidence["postflight"] = postflight
    write_exclusive_json(run_root / "partial_evidence.json", evidence)
    return evidence


def validate_partial_summary_real(arguments: argparse.Namespace) -> dict[str, Any]:
    run_root = resolve_real_run_root(arguments.run_root)
    if not run_root.is_dir():
        raise CaptureError("Partial summary run root does not exist")
    if (run_root / "evidence.json").exists():
        raise CaptureError("Final evidence already exists; partial summary is obsolete")
    evidence_path = run_root / "partial_evidence.json"
    if not evidence_path.is_file():
        raise CaptureError("partial_evidence.json is missing")
    if any((run_root / "manifests").glob("*.failed.json")):
        raise CaptureError("Partial summary cannot include failed model roots")
    evidence = read_json_file(evidence_path)
    current_guard = repository_guard()
    device = read_json_file(run_root / "device.json")

    capture_preflight = evidence.get("capturePreflight")
    capture_postflight = evidence.get("capturePostflight")
    summary_preflight = evidence.get("preflight")
    summary_postflight = evidence.get("postflight")
    if (
        not isinstance(capture_preflight, dict)
        or capture_preflight != capture_postflight
        or not isinstance(summary_preflight, dict)
        or summary_preflight != summary_postflight
    ):
        raise CaptureError("Partial evidence stored guards drifted")
    if guard_without_source_hashes(
        capture_preflight,
        label="captured partial-summary",
    ) != guard_without_source_hashes(
        current_guard,
        label="current partial-summary validation",
    ):
        raise CaptureError(
            "Captured partial summary dependency state differs from the "
            "current validation run outside sourceSha256"
        )
    if guard_without_source_hashes(
        summary_preflight,
        label="stored partial-summary",
    ) != guard_without_source_hashes(
        current_guard,
        label="current partial-summary validation",
    ):
        raise CaptureError(
            "Stored partial summary dependency state differs from the "
            "current validation run outside sourceSha256"
        )

    models: list[dict[str, Any]] = []
    manifests: list[dict[str, Any]] = []
    capture_guard: dict[str, Any] | None = None
    for model_id in EXPECTED_PARTIAL_MODELS:
        validation = validate_model_artifacts(run_root, model_id)
        manifest = validate_success_manifest(
            run_root,
            model_id,
            validation,
            expected_guard=None,
            expected_device=device,
        )
        manifest_guard = manifest["preflight"]
        if capture_guard is None:
            capture_guard = manifest_guard
        elif manifest_guard != capture_guard:
            raise CaptureError("Partial summary model manifests use different guards")
        models.append(validation)
        manifest_path = run_root / "manifests" / f"{model_id}.json"
        manifests.append(
            {
                "modelId": model_id,
                "path": str(manifest_path.relative_to(run_root)),
                "sha256": sha256_path(manifest_path),
                "byteLength": manifest_path.stat().st_size,
            }
        )
    if capture_guard != capture_preflight:
        raise CaptureError("Partial evidence capture guard drifted")
    for model_id in EXPECTED_PARTIAL_MISSING_MODELS:
        if existing_model_paths(run_root, model_id, expected_names(load_state(), model_id)):
            raise CaptureError("SheenChair artifacts cannot be summarized as absent")

    expected = partial_evidence_from_models(
        run_root,
        models,
        [
            missing_partial_model_record(model_id)
            for model_id in EXPECTED_PARTIAL_MISSING_MODELS
        ],
        source_hashes=capture_preflight["sourceSha256"],
        summary_source_hashes=summary_preflight["sourceSha256"],
        device=device,
        fixture_validation=False,
        manifests=manifests,
    )
    expected["capturePreflight"] = capture_preflight
    expected["capturePostflight"] = capture_postflight
    expected["preflight"] = summary_preflight
    expected["postflight"] = summary_postflight
    if expected != evidence:
        raise CaptureError("partial_evidence.json no longer matches artifacts")
    return {
        "mode": "validate-partial-summary",
        "status": "verified locally",
        "executionEvidence": "verified locally",
        "evidencePath": str(evidence_path),
        "evidenceSha256": sha256_path(evidence_path),
        "evidenceStatus": evidence["status"],
        "evidenceCompleteness": evidence["evidenceCompleteness"],
        "comparisonBoundary": evidence["comparisonBoundary"],
        "completedModelIds": evidence["completedModelIds"],
        "missingModels": evidence["missingModels"],
        "pngCount": evidence["pngCount"],
        "logCount": evidence["logCount"],
        "backendEvidenceCount": evidence["backendEvidenceCount"],
        "responseCount": evidence["responseCount"],
        "finalEvidenceStatus": evidence["finalEvidenceStatus"],
        "physicalTargets": evidence["physicalTargets"],
        "android": evidence["android"],
        "web": evidence["web"],
        "productionReadiness": evidence["productionReadiness"],
    }


def invalid_historical_sheen_chair_attempt(
    candidate: Path,
    *,
    invalid_reason: str,
    manifest_path: Path | None = None,
) -> dict[str, Any]:
    manifest_sha256: str | None = None
    manifest_byte_length: int | None = None
    manifest_relative_path: str | None = None
    if manifest_path is not None:
        manifest_relative_path = str(manifest_path.relative_to(candidate))
        if (
            not manifest_path.is_symlink()
            and manifest_path.is_file()
            and path_resolves_within(manifest_path, candidate)
        ):
            manifest_sha256 = sha256_path(manifest_path)
            manifest_byte_length = manifest_path.stat().st_size
    return {
        "attemptRoot": candidate.name,
        "modelId": "sheen_chair",
        "status": "invalid",
        "executionEvidence": "not verified",
        "invalidReason": invalid_reason,
        "unsupportedMaterialFeatureDetected": False,
        "acceptedEvidence": False,
        "finalEvidence": False,
        "manifestPath": manifest_relative_path,
        "manifestSha256": manifest_sha256,
        "manifestByteLength": manifest_byte_length,
        "logPath": None,
        "logSha256": None,
        "logByteLength": None,
        "evidenceBoundary": (
            "Historical failed attempt diagnostic only; invalid records are "
            "not accepted M3 evidence, not final four-model M3 evidence, "
            "and not newly verified."
        ),
    }


def collect_historical_sheen_chair_attempts(run_root: Path) -> list[dict[str, Any]]:
    attempts: list[dict[str, Any]] = []
    for candidate in sorted(run_root.parent.glob("candidate-run-*")):
        if candidate.resolve() == run_root.resolve():
            continue
        if candidate.is_symlink() or not candidate.is_dir():
            continue
        manifest_path = candidate / "manifests" / "sheen_chair.failed.json"
        if manifest_path.is_symlink() or not manifest_path.is_file():
            continue
        if not path_resolves_within(manifest_path, candidate):
            attempts.append(
                invalid_historical_sheen_chair_attempt(
                    candidate,
                    invalid_reason=(
                        "historical manifest path resolves outside the "
                        "attempt root"
                    ),
                    manifest_path=manifest_path,
                )
            )
            continue
        try:
            manifest = read_json_file(manifest_path)
        except (CaptureError, OSError, ValueError) as error:
            attempts.append(
                invalid_historical_sheen_chair_attempt(
                    candidate,
                    invalid_reason=f"malformed historical manifest: {error}",
                    manifest_path=manifest_path,
                )
            )
            continue
        if manifest.get("modelId") != "sheen_chair" or manifest.get("status") != "failed":
            continue

        log_path = candidate / "logs" / "sheen_chair.log"
        log_text = ""
        log_sha256: str | None = None
        log_byte_length: int | None = None
        log_truncated = False
        log_rejected_reason: str | None = None
        if log_path.is_symlink():
            log_rejected_reason = "historical log path is a symlink"
        elif log_path.is_file():
            if path_resolves_within(log_path, candidate):
                log_text, log_truncated = read_bounded_text(
                    log_path,
                    HISTORICAL_LOG_SCAN_BYTES,
                )
                log_sha256 = sha256_path(log_path)
                log_byte_length = log_path.stat().st_size
            else:
                log_rejected_reason = (
                    "historical log path resolves outside the attempt root"
                )

        searchable_text = json.dumps(manifest, sort_keys=True) + "\n" + log_text
        attempts.append(
            {
                "attemptRoot": candidate.name,
                "modelId": "sheen_chair",
                "status": "failed",
                "executionEvidence": "not verified",
                "manifestExecutionEvidence": manifest.get("executionEvidence"),
                "failureType": manifest.get("failureType"),
                "failure": manifest.get("failure"),
                "captureExitCode": manifest.get("captureExitCode"),
                "unsupportedMaterialFeatureDetected": (
                    "unsupportedMaterialFeature" in searchable_text
                ),
                "acceptedEvidence": False,
                "finalEvidence": False,
                "manifestPath": str(manifest_path.relative_to(candidate)),
                "manifestSha256": sha256_path(manifest_path),
                "manifestByteLength": manifest_path.stat().st_size,
                "logPath": str(log_path.relative_to(candidate))
                if log_sha256 is not None
                else None,
                "logSha256": log_sha256,
                "logByteLength": log_byte_length,
                "logScanByteLimit": HISTORICAL_LOG_SCAN_BYTES,
                "logScanTruncated": log_truncated,
                "logRejectedReason": log_rejected_reason,
                "evidenceBoundary": (
                    "Historical failed attempt only; not accepted M3 evidence, "
                    "not final four-model M3 evidence, and not newly verified."
                ),
            }
        )
    return attempts


def glb_int(value: Any, *, field: str, default: int) -> int:
    if value is None:
        return default
    if isinstance(value, bool) or not isinstance(value, int):
        raise CaptureError(f"Frozen GLB field {field} is not an integer")
    return value


def default_scene_primitives(document: dict[str, Any]) -> list[dict[str, Any]]:
    materials = glb_list(document.get("materials"), field="materials")
    nodes = glb_list(document.get("nodes"), field="nodes")
    meshes = glb_list(document.get("meshes"), field="meshes")
    scenes = glb_list(document.get("scenes"), field="scenes")
    if not scenes:
        raise CaptureError("Frozen SheenChair GLB lacks an explicit default scene")
    scene_index = glb_int(document.get("scene"), field="scene", default=0)
    if scene_index < 0 or scene_index >= len(scenes):
        raise CaptureError("Frozen SheenChair GLB default scene index is invalid")
    scene = glb_object(scenes[scene_index], field=f"scenes[{scene_index}]")
    root_indices = glb_list(scene.get("nodes"), field=f"scenes[{scene_index}].nodes")
    primitives: list[dict[str, Any]] = []

    def visit_node(raw_node_index: Any, parent_path: list[str], stack: set[int]) -> None:
        node_index = glb_int(raw_node_index, field="node index", default=-1)
        if node_index in stack:
            return
        if node_index < 0 or node_index >= len(nodes):
            raise CaptureError("Frozen SheenChair GLB node index is out of range")
        node = glb_object(nodes[node_index], field=f"nodes[{node_index}]")
        raw_name = node.get("name")
        if raw_name is None:
            name = f"node_{node_index}"
        elif isinstance(raw_name, str) and raw_name:
            name = raw_name
        else:
            raise CaptureError("Frozen SheenChair GLB node name is invalid")
        node_path = [*parent_path, name]
        mesh_index = node.get("mesh")
        if mesh_index is not None:
            mesh_index = glb_int(mesh_index, field=f"nodes[{node_index}].mesh", default=-1)
            if mesh_index < 0 or mesh_index >= len(meshes):
                raise CaptureError("Frozen SheenChair GLB mesh index is invalid")
            mesh = glb_object(meshes[mesh_index], field=f"meshes[{mesh_index}]")
            raw_primitives = glb_list(
                mesh.get("primitives"),
                field=f"meshes[{mesh_index}].primitives",
            )
            for primitive_index, raw_primitive in enumerate(raw_primitives):
                primitive = glb_object(
                    raw_primitive,
                    field=f"meshes[{mesh_index}].primitives[{primitive_index}]",
                )
                material_index = primitive.get("material")
                if material_index is None:
                    continue
                material_index = glb_int(
                    material_index,
                    field=f"meshes[{mesh_index}].primitives[{primitive_index}].material",
                    default=-1,
                )
                if material_index < 0 or material_index >= len(materials):
                    raise CaptureError(
                        "Frozen SheenChair GLB material index is out of range"
                    )
                attributes = glb_object(
                    primitive.get("attributes"),
                    field=(
                        f"meshes[{mesh_index}].primitives"
                        f"[{primitive_index}].attributes"
                    ),
                )
                material = glb_object(
                    materials[material_index],
                    field=f"materials[{material_index}]",
                )
                primitives.append(
                    {
                        "address": glb_part_address(node_path, primitive_index),
                        "concreteAddress": glb_part_address(
                            ["root", *node_path],
                            primitive_index,
                        ),
                        "materialIndex": material_index,
                        "material": material,
                        "primitiveAttributes": sorted(attributes.keys()),
                    }
                )
        stack.add(node_index)
        for child in glb_list(
            node.get("children"),
            field=f"nodes[{node_index}].children",
        ):
            visit_node(child, node_path, stack)
        stack.remove(node_index)

    for root_index in root_indices:
        visit_node(root_index, [], set())
    return primitives


def sheen_chair_static_blocker_audit() -> dict[str, Any]:
    state = load_state()
    model_state = state["models"]["sheen_chair"]
    document = read_frozen_glb_json(model_state)
    contract = derive_frozen_glb_contract(model_state)
    blocked_primitives: list[dict[str, Any]] = []
    for primitive in default_scene_primitives(document):
        material = primitive["material"]
        raw_extensions = material.get("extensions")
        if raw_extensions is None:
            continue
        extensions = glb_object(
            raw_extensions,
            field=f"materials[{primitive['materialIndex']}].extensions",
        )
        if "KHR_materials_sheen" not in extensions:
            continue
        occlusion = glb_object(
            material.get("occlusionTexture"),
            field=f"materials[{primitive['materialIndex']}].occlusionTexture",
        )
        tex_coord = glb_int(
            occlusion.get("texCoord"),
            field=f"materials[{primitive['materialIndex']}].occlusionTexture.texCoord",
            default=0,
        )
        if tex_coord == 0:
            continue
        transform_tex_coord: int | None = None
        raw_extensions = occlusion.get("extensions")
        if raw_extensions is not None:
            texture_extensions = glb_object(
                raw_extensions,
                field=(
                    f"materials[{primitive['materialIndex']}]."
                    "occlusionTexture.extensions"
                ),
            )
            raw_transform = texture_extensions.get("KHR_texture_transform")
            if raw_transform is not None:
                transform = glb_object(
                    raw_transform,
                    field=(
                        f"materials[{primitive['materialIndex']}]."
                        "occlusionTexture.extensions.KHR_texture_transform"
                    ),
                )
                transform_tex_coord = glb_int(
                    transform.get("texCoord"),
                    field=(
                        f"materials[{primitive['materialIndex']}]."
                        "occlusionTexture.extensions."
                        "KHR_texture_transform.texCoord"
                    ),
                    default=tex_coord,
                )
        material_name = material.get("name")
        if not isinstance(material_name, str) or not material_name:
            raise CaptureError("Frozen SheenChair GLB material name is invalid")
        occlusion_index = glb_int(
            occlusion.get("index"),
            field=f"materials[{primitive['materialIndex']}].occlusionTexture.index",
            default=-1,
        )
        if occlusion_index < 0:
            raise CaptureError("Frozen SheenChair GLB occlusion texture index is invalid")
        blocked_primitives.append(
            {
                "address": primitive["address"],
                "concreteAddress": primitive["concreteAddress"],
                "materialIndex": primitive["materialIndex"],
                "materialName": material_name,
                "primitiveAttributes": primitive["primitiveAttributes"],
                "occlusionTexture": {
                    "index": occlusion_index,
                    "texCoord": tex_coord,
                    "textureTransformTexCoord": transform_tex_coord,
                },
            }
        )
    if not blocked_primitives:
        raise CaptureError("Frozen SheenChair GLB no longer proves the UV1 AO boundary")
    return {
        "modelId": "sheen_chair",
        "status": "not run",
        "executionEvidence": "not run",
        "blockerEvidence": "verified locally",
        "blockerType": "unsupportedMaterialFeature",
        "unsupportedFeature": "occlusionTexture.texCoord_1",
        "source": "authored frozen GLB static inspection",
        "sourceBoundary": "Parsed GLB JSON chunk only; no renderer capture was run.",
        "modelPath": model_state["path"],
        "modelSha256": model_state["sha256"],
        "modelByteLength": model_state["byteLength"],
        "stateSha256": EXPECTED_STATE_SHA256,
        "authoredSheenMaterialIndices": contract["authoredInventory"][
            "KHR_materials_sheen"
        ],
        "defaultSceneSheenMaterialIndices": contract["defaultInventory"][
            "KHR_materials_sheen"
        ],
        "blockedPrimitives": blocked_primitives,
        "noUvInvented": True,
        "noChannelReinterpretation": True,
        "acceptedEvidence": False,
        "finalEvidence": False,
        "claimBoundary": (
            "Static SheenChair blocker proof only; this does not satisfy "
            "SheenChair iOS capture, final four-model M3 evidence, pixel parity, "
            "physical target coverage, renderer-native sheen, release, or "
            "production-ready support."
        ),
        "m4Boundary": "not started",
    }


def audit_artifact_record(path: Path, expected_root: Path) -> dict[str, Any]:
    record: dict[str, Any] = {
        "path": str(path.relative_to(REPO_ROOT)),
    }
    if path.is_symlink():
        return {
            **record,
            "status": "not run",
            "reason": "artifact path is a symlink",
        }
    if not path.is_file():
        return {
            **record,
            "status": "not run",
            "reason": "artifact is absent",
        }
    if not path_resolves_within(path, expected_root):
        return {
            **record,
            "status": "not run",
            "reason": "artifact path resolves outside the expected root",
        }
    return {
        **record,
        "status": "verified locally",
        "sha256": sha256_path(path),
        "byteLength": path.stat().st_size,
    }


def all_artifacts_verified(records: list[dict[str, Any]]) -> bool:
    return all(record["status"] == "verified locally" for record in records)


def expected_reference_capture_keys(
    model_ids: tuple[str, ...],
) -> list[tuple[str, str, str]]:
    keys: list[tuple[str, str, str]] = []
    for model_id in model_ids:
        views = ["close", "grazing"]
        if model_id == "toycar":
            views.append("context")
        for view in views:
            for pass_name in EXPECTED_PASSES:
                keys.append((model_id, view, pass_name))
    return keys


def audit_reference_evidence(
    path: Path,
    expected_root: Path,
    expected_model_ids: tuple[str, ...],
) -> dict[str, Any]:
    record = audit_artifact_record(path, expected_root)
    if record["status"] != "verified locally":
        return record
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        return {
            **record,
            "status": "not run",
            "reason": f"reference evidence JSON is unreadable: {error}",
        }
    if not isinstance(payload, dict):
        return {
            **record,
            "status": "not run",
            "reason": "reference evidence root is not a JSON object",
        }
    if payload.get("schemaVersion") != 1:
        return {
            **record,
            "status": "not run",
            "reason": "reference evidence schemaVersion is not 1",
        }
    if payload.get("status") != "verified locally":
        return {
            **record,
            "status": "not run",
            "reason": "reference evidence status is not verified locally",
        }
    if payload.get("stateSha256") != EXPECTED_STATE_SHA256:
        return {
            **record,
            "status": "not run",
            "reason": "reference evidence state hash changed",
        }
    if "direction/conformance" not in str(payload.get("comparisonBoundary")):
        return {
            **record,
            "status": "not run",
            "reason": "reference evidence comparison boundary changed",
        }
    captures = payload.get("captures")
    if not isinstance(captures, list):
        return {
            **record,
            "status": "not run",
            "reason": "reference evidence captures are not a JSON array",
        }
    expected_keys = expected_reference_capture_keys(expected_model_ids)
    actual_keys: list[tuple[str, str, str]] = []
    for capture in captures:
        if not isinstance(capture, dict):
            return {
                **record,
                "status": "not run",
                "reason": "reference evidence capture is not a JSON object",
            }
        key = (
            capture.get("modelId"),
            capture.get("view"),
            capture.get("pass"),
        )
        if not all(isinstance(value, str) for value in key):
            return {
                **record,
                "status": "not run",
                "reason": "reference evidence capture identity is malformed",
            }
        actual_keys.append(key)  # type: ignore[arg-type]
        capture_path_raw = capture.get("path")
        if not isinstance(capture_path_raw, str):
            return {
                **record,
                "status": "not run",
                "reason": "reference evidence capture path is malformed",
            }
        capture_path = REPO_ROOT / capture_path_raw
        capture_record = audit_artifact_record(capture_path, expected_root)
        dimensions = capture.get("dimensions")
        if (
            capture_record["status"] != "verified locally"
            or capture.get("sha256") != capture_record.get("sha256")
            or capture.get("byteLength") != capture_record.get("byteLength")
            or not isinstance(dimensions, dict)
            or dimensions.get("width") != EXPECTED_PHYSICAL_WIDTH
            or dimensions.get("height") != EXPECTED_PHYSICAL_HEIGHT
        ):
            return {
                **record,
                "status": "not run",
                "reason": (
                    "reference capture bytes, dimensions, or containment "
                    f"changed: {capture_path_raw}"
                ),
            }
    if actual_keys != expected_keys:
        return {
            **record,
            "status": "not run",
            "reason": "reference capture inventory changed",
        }
    return {
        **record,
        "modelIds": list(expected_model_ids),
        "captureCount": len(captures),
        "comparisonBoundary": "direction/conformance-only",
    }


def task5_checklist_audit(validation: dict[str, Any]) -> list[dict[str, Any]]:
    provenance_artifacts = [
        audit_artifact_record(
            ACCEPTANCE_MANIFEST_PATH,
            ACCEPTANCE_MANIFEST_PATH.parent,
        ),
        audit_artifact_record(STATE_PATH, STATE_PATH.parent),
    ]
    state_artifacts = [audit_artifact_record(STATE_PATH, STATE_PATH.parent)]
    three_reference = audit_reference_evidence(
        THREE_EVIDENCE_PATH,
        THREE_CAPTURE_ROOT,
        EXPECTED_MODELS,
    )
    khronos_toycar_reference = audit_reference_evidence(
        KHRONOS_TOYCAR_EVIDENCE_PATH,
        KHRONOS_CAPTURE_ROOT,
        ("toycar",),
    )
    khronos_glam_reference = audit_reference_evidence(
        KHRONOS_GLAM_EVIDENCE_PATH,
        KHRONOS_CAPTURE_ROOT,
        ("glam_velvet_sofa",),
    )
    reference_artifacts = [
        three_reference,
        khronos_toycar_reference,
        khronos_glam_reference,
    ]
    references_verified = all_artifacts_verified(reference_artifacts)
    loader_artifacts = [
        audit_artifact_record(THREE_EVIDENCE_PATH, THREE_CAPTURE_ROOT)
    ]
    viewer_artifacts = [
        audit_artifact_record(
            Path(validation["evidencePath"]),
            Path(validation["evidencePath"]).parent,
        ),
    ]
    ios_health = validation.get("iosRendererLocalHealth")
    if isinstance(ios_health, dict) and isinstance(
        ios_health.get("evidencePath"), str
    ):
        viewer_artifacts.append(
            audit_artifact_record(
                Path(ios_health["evidencePath"]),
                Path(validation["evidencePath"]).parent,
            )
        )
    completed_model_ids = validation["completedModelIds"]
    missing_model_ids = [
        model["modelId"]
        for model in validation["missingModels"]
        if model["status"] != "verified locally"
    ]
    final_evidence_verified = (
        validation["finalEvidenceStatus"] == "verified locally"
        and validation.get("pixelHealthStatus") == "verified locally"
        and completed_model_ids == list(EXPECTED_MODELS)
        and not missing_model_ids
    )
    return [
        {
            "item": "fixtureProvenance",
            "status": "verified locally"
            if all_artifacts_verified(provenance_artifacts)
            else "not run",
            "completion": "complete"
            if all_artifacts_verified(provenance_artifacts)
            else "open",
            "artifacts": provenance_artifacts,
            "m4Boundary": "not started",
            "claimBoundary": (
                "Fixture provenance support only; not final M3 evidence."
            ),
        },
        {
            "item": "comparisonState",
            "status": "verified locally"
            if all_artifacts_verified(state_artifacts)
            else "not run",
            "completion": "complete"
            if all_artifacts_verified(state_artifacts)
            else "open",
            "stateSha256": EXPECTED_STATE_SHA256,
            "artifacts": state_artifacts,
            "m4Boundary": "not started",
            "claimBoundary": (
                "Frozen comparison-state support only; not final M3 evidence."
            ),
        },
        {
            "item": "threeAndKhronosReferences",
            "status": "verified locally"
            if references_verified
            else "candidate-only",
            "completion": "complete" if references_verified else "partial",
            "maturity": "candidate-only",
            "artifacts": reference_artifacts,
            "referenceCoverage": {
                "threejs": {
                    "status": three_reference["status"],
                    "modelIds": three_reference.get("modelIds", []),
                    "captureCount": three_reference.get("captureCount", 0),
                },
                "khronosSampleRenderer": {
                    "status": "verified locally"
                    if khronos_toycar_reference["status"] == "verified locally"
                    and khronos_glam_reference["status"] == "verified locally"
                    else "not run",
                    "modelIds": list(EXPECTED_KHRONOS_REFERENCE_MODELS),
                    "captureCount": khronos_toycar_reference.get(
                        "captureCount", 0
                    )
                    + khronos_glam_reference.get("captureCount", 0),
                },
            },
            "referenceBoundary": "direction/conformance-only",
            "practicalBoundary": (
                "Three.js covers all four frozen models; pinned Khronos Sample "
                "Renderer coverage is limited to the two practical audited "
                "models, ToyCar and GlamVelvetSofa."
            ),
            "m4Boundary": "not started",
            "claimBoundary": (
                "Reference renderer captures are direction/conformance-only; "
                "they are not pixel parity, physical correctness, or "
                "renderer-native sheen evidence."
            ),
        },
        {
            "item": "threeLoaderContract",
            "status": "verified locally"
            if all_artifacts_verified(loader_artifacts)
            else "not run",
            "completion": "complete"
            if all_artifacts_verified(loader_artifacts)
            else "open",
            "artifacts": loader_artifacts,
            "m4Boundary": "not started",
            "claimBoundary": (
                "Pinned Three.js loader contract only; not viewer renderer-native "
                "evidence."
            ),
        },
        {
            "item": "closeGrazingViews",
            "status": (
                "verified locally" if final_evidence_verified else "candidate-only"
            ),
            "completion": "complete" if final_evidence_verified else "partial",
            "completedModelIds": completed_model_ids,
            "missingModelIds": missing_model_ids,
            "evidence": viewer_artifacts,
            "m4Boundary": "not started",
            "claimBoundary": (
                "Final four-model close/grazing iOS Simulator captures are "
                "candidate-only direction/conformance evidence; they do not "
                "establish physical target coverage or pixel parity."
                if final_evidence_verified
                else "Close/grazing viewer captures are partial and not final "
                "four-model M3 evidence."
            ),
        },
        {
            "item": "captureHashesDiagnostics",
            "status": (
                "verified locally" if final_evidence_verified else "candidate-only"
            ),
            "completion": "complete" if final_evidence_verified else "partial",
            "evidence": viewer_artifacts,
            "finalEvidenceStatus": validation["finalEvidenceStatus"],
            "m4Boundary": "not started",
            "claimBoundary": (
                "Final hashes, commands, diagnostics, Simulator identity, and "
                "Impeller Metal records are verified locally; maturity remains "
                "candidate-only."
                if final_evidence_verified
                else "Retained hashes and diagnostics are partial until final "
                "four-model M3 evidence exists."
            ),
        },
    ]


def final_m3_status_audit(validation: dict[str, Any]) -> dict[str, Any]:
    return {
        "mode": "audit-m3-status",
        "status": "candidate-only",
        "dependencyEvidenceStatus": validation["dependencyEvidenceStatus"],
        "capturedRendererRevision": validation["capturedRendererRevision"],
        "currentRendererRevision": validation["currentRendererRevision"],
        "m3Status": "complete",
        "m4Status": "not started",
        "executionEvidence": validation["executionEvidence"],
        "finalEvidenceValidation": validation,
        "completedModelIds": validation["completedModelIds"],
        "missingModels": validation["missingModels"],
        "finalEvidenceStatus": validation["finalEvidenceStatus"],
        "pixelHealthStatus": validation["pixelHealthStatus"],
        "iosRendererLocalHealth": validation["iosRendererLocalHealth"],
        "canStartM4": True,
        "m3ClosureDisposition": {
            "status": "verified locally",
            "milestone": "M3",
            "task": 5,
            "finalEvidenceStatus": validation["finalEvidenceStatus"],
            "task5OverallCompletion": "complete",
            "canCloseM3": True,
            "canStartM4": True,
            "m4Status": "not started",
            "resolutionBoundary": (
                "The frozen four-model iOS Simulator inventory is retained "
                "with exact hashes, zero blocking diagnostics, per-model "
                "Impeller Metal evidence, and 27-frame / 9-triplet "
                "renderer-local structural health evidence."
            ),
            "claimBoundary": (
                "M3 candidate evidence only; this does not establish physical "
                "target coverage, pixel parity, renderer-native sheen, release, "
                "or production-ready support."
            ),
        },
        "task5OverallCompletion": "complete",
        "task5Checklist": task5_checklist_audit(validation),
        "remainingBoundaries": [
            {
                "gate": "physicalTargets",
                "status": validation["physicalTargets"],
            },
            {"gate": "android", "status": validation["android"]},
            {"gate": "web", "status": validation["web"]},
            {
                "gate": "rendererNativeSheen",
                "status": validation["rendererNativeSheen"],
            },
            {"gate": "release", "status": validation["release"]},
            {
                "gate": "productionReadiness",
                "status": validation["productionReadiness"],
            },
        ],
        "claimBoundary": (
            "M3 is complete with candidate-only iOS Simulator evidence. This "
            "does not establish renderer-native sheen, physical correctness, "
            "pixel parity, physical target coverage, release, or "
            "production-ready support."
        ),
    }


def audit_m3_status_real(arguments: argparse.Namespace) -> dict[str, Any]:
    run_root = resolve_real_run_root(arguments.run_root)
    if (run_root / "evidence.json").is_file():
        return final_m3_status_audit(validate_final_evidence_real(arguments))
    validation = validate_partial_summary_real(arguments)
    sheen_chair_static_blocker = sheen_chair_static_blocker_audit()
    historical_sheen_chair_attempts = collect_historical_sheen_chair_attempts(
        run_root,
    )
    historical_unsupported_count = sum(
        1
        for attempt in historical_sheen_chair_attempts
        if attempt["unsupportedMaterialFeatureDetected"]
    )
    return {
        "mode": "audit-m3-status",
        "status": "candidate-only",
        "m3Status": "blocked",
        "m4Status": "not started",
        "executionEvidence": validation["executionEvidence"],
        "partialEvidenceValidation": validation,
        "completedModelIds": validation["completedModelIds"],
        "missingModels": validation["missingModels"],
        "finalEvidenceStatus": validation["finalEvidenceStatus"],
        "canStartM4": False,
        "m3ClosureDisposition": {
            "status": "blocked",
            "milestone": "M3",
            "task": 5,
            "blockingGate": "sheenChairIOSCapture",
            "requiredModelId": validation["missingModels"][0]["modelId"],
            "blockerEvidence": sheen_chair_static_blocker["blockerEvidence"],
            "executionEvidence": sheen_chair_static_blocker[
                "executionEvidence"
            ],
            "finalEvidenceStatus": validation["finalEvidenceStatus"],
            "task5OverallCompletion": "partial",
            "canCloseM3": False,
            "canStartM4": False,
            "m4Status": "not started",
            "resolutionBoundary": (
                "Capture the frozen SheenChair without inventing UVs or "
                "reinterpreting channels, or explicitly amend Task 5 acceptance; "
                "this audit does neither."
            ),
            "claimBoundary": (
                "Blocked closure disposition only; this does not close M3, "
                "satisfy final four-model evidence, or permit M4."
            ),
        },
        "sheenChairStaticBlocker": sheen_chair_static_blocker,
        "task5OverallCompletion": "partial",
        "task5Checklist": task5_checklist_audit(validation),
        "openGates": [
            {
                "gate": "finalFourModelM3Evidence",
                "status": validation["finalEvidenceStatus"],
                "requiredModelIds": list(EXPECTED_MODELS),
            },
            {
                "gate": "sheenChairIOSCapture",
                "status": "not run",
                "reason": validation["missingModels"][0]["reason"],
                "historicalAttemptCount": len(historical_sheen_chair_attempts),
                "historicalUnsupportedMaterialFeatureAttempts": (
                    historical_unsupported_count
                ),
                "historicalAttemptBoundary": (
                    "Historical failed attempts are diagnostic only; they are "
                    "not accepted M3 evidence and do not satisfy this gate."
                ),
            },
            {
                "gate": "physicalTargets",
                "status": validation["physicalTargets"],
            },
            {
                "gate": "android",
                "status": validation["android"],
            },
            {
                "gate": "web",
                "status": validation["web"],
            },
            {
                "gate": "productionReadiness",
                "status": validation["productionReadiness"],
            },
        ],
        "historicalSheenChairAttempts": historical_sheen_chair_attempts,
        "claimBoundary": (
            "M3 audit only; retained evidence is partial and candidate-only. "
            "It does not establish final four-model M3 evidence, pixel parity, "
            "physical target coverage, renderer-native sheen, release, or "
            "production-ready support."
        ),
    }


def require_model(value: str | None) -> str:
    if value not in EXPECTED_MODELS:
        raise CaptureError(
            "Model must be one of: " + ", ".join(EXPECTED_MODELS)
        )
    return value


def parse_arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Run one bounded Plan 018 iOS Simulator capture model."
    )
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--renderer-native-control", action="store_true")
    parser.add_argument("--validate-fixture", action="store_true")
    parser.add_argument(
        "--validate-renderer-native-fixture",
        action="store_true",
    )
    parser.add_argument("--validate-three-fixture", action="store_true")
    parser.add_argument("--exercise-timeout-fixture", action="store_true")
    parser.add_argument("--finalize", action="store_true")
    parser.add_argument("--summarize-partial", action="store_true")
    parser.add_argument("--validate-partial-summary", action="store_true")
    parser.add_argument("--audit-m3-status", action="store_true")
    parser.add_argument(
        "--model",
        choices=EXPECTED_MODELS + EXPECTED_NATIVE_CONTROL_MODELS,
    )
    parser.add_argument("--udid")
    parser.add_argument("--run-root", required=True)
    parser.add_argument(
        "--device-fixture",
        help="Plan-only device JSON; forbidden for capture and ignored by no other mode.",
    )
    return parser.parse_args()


def main() -> int:
    arguments = parse_arguments()
    try:
        if arguments.renderer_native_control:
            if (
                arguments.validate_renderer_native_fixture
                or arguments.validate_fixture
                or arguments.validate_three_fixture
                or arguments.exercise_timeout_fixture
                or arguments.summarize_partial
                or arguments.validate_partial_summary
                or arguments.audit_m3_status
            ):
                raise CaptureError(
                    "Renderer-native control mode cannot use historical audit modes"
                )
            if arguments.finalize:
                if (
                    arguments.plan
                    or arguments.model is not None
                    or arguments.udid is not None
                    or arguments.device_fixture is not None
                ):
                    raise CaptureError(
                        "Renderer-native finalization takes only its mode/run-root"
                    )
                result = finalize_renderer_native_capture(arguments)
            elif arguments.plan:
                result = plan_renderer_native_capture(arguments)
            else:
                if arguments.device_fixture is not None:
                    raise CaptureError(
                        "A device fixture cannot authorize a renderer-native capture"
                    )
                result = capture_renderer_native_control(arguments)
        elif arguments.validate_renderer_native_fixture:
            if (
                arguments.validate_fixture
                or arguments.validate_three_fixture
                or arguments.exercise_timeout_fixture
                or arguments.device_fixture is not None
                or arguments.plan
                or arguments.summarize_partial
                or arguments.validate_partial_summary
                or arguments.audit_m3_status
                or arguments.udid is not None
            ):
                raise CaptureError(
                    "Renderer-native fixture validation received another mode"
                )
            fixture_root = Path(arguments.run_root).resolve()
            if arguments.finalize:
                if arguments.model is not None:
                    raise CaptureError(
                        "Renderer-native fixture finalization does not select a model"
                    )
                result = finalize_renderer_native_fixture(fixture_root)
            else:
                result = validate_renderer_native_control_artifacts(
                    fixture_root,
                    require_renderer_native_model(arguments.model),
                    fixture_validation=True,
                )
        elif arguments.exercise_timeout_fixture:
            if (
                arguments.validate_fixture
                or arguments.validate_three_fixture
                or arguments.device_fixture is not None
                or arguments.plan
                or arguments.finalize
                or arguments.summarize_partial
                or arguments.validate_partial_summary
                or arguments.audit_m3_status
                or arguments.model is not None
                or arguments.udid is not None
            ):
                raise CaptureError(
                    "Timeout fixture takes only its mode and empty run-root"
                )
            result = exercise_timeout_fixture(Path(arguments.run_root).resolve())
        elif arguments.validate_three_fixture:
            if (
                arguments.validate_fixture
                or arguments.device_fixture is not None
                or arguments.plan
                or arguments.finalize
                or arguments.summarize_partial
                or arguments.validate_partial_summary
                or arguments.audit_m3_status
                or arguments.model is not None
                or arguments.udid is not None
            ):
                raise CaptureError(
                    "Three fixture validation takes only its mode and run-root"
                )
            fixture_root = Path(arguments.run_root).resolve()
            result = validate_three_capture_set(
                evidence_path=fixture_root / "evidence.json",
                capture_root=fixture_root / "threejs",
                path_prefix="fixture/threejs",
                fixture_validation=True,
            )
        elif arguments.validate_fixture:
            if arguments.device_fixture is not None or arguments.plan:
                raise CaptureError("Fixture validation cannot use plan/device options")
            run_root = Path(arguments.run_root).resolve()
            if arguments.finalize:
                if (
                    arguments.model is not None
                    or arguments.udid is not None
                    or arguments.summarize_partial
                    or arguments.validate_partial_summary
                    or arguments.audit_m3_status
                ):
                    raise CaptureError("Fixture finalization does not select a model/device")
                result = finalize_fixture(run_root)
            elif arguments.summarize_partial:
                if (
                    arguments.model is not None
                    or arguments.udid is not None
                    or arguments.validate_partial_summary
                    or arguments.audit_m3_status
                ):
                    raise CaptureError(
                        "Fixture partial summary does not select a model/device"
                    )
                result = summarize_partial_fixture(run_root)
            else:
                if (
                    arguments.finalize
                    or arguments.summarize_partial
                    or arguments.validate_partial_summary
                    or arguments.audit_m3_status
                    or arguments.udid is not None
                ):
                    raise CaptureError("Model fixture validation takes only model/run-root")
                result = validate_model_artifacts(
                    run_root,
                    require_model(arguments.model),
                    fixture_validation=True,
                )
        elif arguments.finalize:
            if (
                arguments.plan
                or arguments.model is not None
                or arguments.udid is not None
                or arguments.device_fixture is not None
                or arguments.summarize_partial
                or arguments.validate_partial_summary
                or arguments.audit_m3_status
            ):
                raise CaptureError("Real finalization takes only --finalize/--run-root")
            result = finalize_real(arguments)
        elif arguments.summarize_partial:
            if (
                arguments.plan
                or arguments.model is not None
                or arguments.udid is not None
                or arguments.device_fixture is not None
                or arguments.validate_partial_summary
                or arguments.audit_m3_status
            ):
                raise CaptureError(
                    "Real partial summary takes only --summarize-partial/--run-root"
                )
            result = summarize_partial_real(arguments)
        elif arguments.validate_partial_summary:
            if (
                arguments.plan
                or arguments.model is not None
                or arguments.udid is not None
                or arguments.device_fixture is not None
                or arguments.audit_m3_status
            ):
                raise CaptureError(
                    "Real partial summary validation takes only "
                    "--validate-partial-summary/--run-root"
                )
            result = validate_partial_summary_real(arguments)
        elif arguments.audit_m3_status:
            if (
                arguments.plan
                or arguments.model is not None
                or arguments.udid is not None
                or arguments.device_fixture is not None
            ):
                raise CaptureError(
                    "Real M3 status audit takes only --audit-m3-status/--run-root"
                )
            result = audit_m3_status_real(arguments)
        elif arguments.plan:
            result = plan_capture(arguments)
        else:
            result = capture_one(arguments)
        sys.stdout.write(json_text(result))
        return 0
    except (CaptureError, OSError, ValueError, json.JSONDecodeError) as error:
        sys.stderr.write(f"Plan018CaptureError: {error}\n")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
