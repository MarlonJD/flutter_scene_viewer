#!/usr/bin/env python3
"""Repository-native structural and bounded harness certification gate."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "docs/agent-harness/config.json"
DOMAIN = b"harness-engineering-evidence-v2\x00"
EVIDENCE_FIELDS = {
    "schema_version",
    "repository_commit",
    "repository_identity",
    "deployment_target_id",
    "capabilities",
    "environment",
    "command",
    "exit_code",
    "observed_at",
    "result",
    "artifacts",
    "issuer",
    "key_id",
    "signature",
}
PLAN_HEADINGS = [
    "Purpose / Big Picture",
    "Progress",
    "Surprises & Discoveries",
    "Decision Log",
    "Outcomes & Retrospective",
    "Context and Orientation",
    "Plan of Work",
    "Concrete Steps",
    "Validation and Acceptance",
    "Idempotence and Recovery",
    "Artifacts and Notes",
    "Interfaces and Dependencies",
    "Revision History",
]
CAPABILITIES = [
    "Humans set intent; agents execute within authority",
    "Break large goals into reusable design, code, review, test, and verification steps",
    "Agents can self-review and respond to feedback",
    "Application behavior is directly readable",
    "Logs, metrics, and traces are queryable when relevant",
    "Repository knowledge is the durable record",
    "Repository tools and authorized work context are directly invocable",
    "Dependencies and abstractions remain agent-legible",
    "`AGENTS.md` is a concise map, not an encyclopedia",
    "Plans are versioned living artifacts",
    "Architecture and critical taste boundaries are mechanical",
    "Local autonomy exists inside enforced central boundaries",
    "Verification proves working behavior, not only code changes",
    "Failures and review judgment feed back into the harness",
    "Entropy and technical debt are continuously controlled",
    "Autonomy increases only after test, review, recovery, and escalation loops exist",
    "Merge throughput policy matches project risk",
    "Release, deployment, and production actions require repository-local authority",
    "Repository-specific OpenAI examples are treated as options, not universal mandates",
    "Zero human-authored code as an operating constraint",
    "Reported repository size, pull-request throughput, elapsed-time speedup, and long agent-run duration as targets",
    "Local and cloud agent review loops continue until reviewers are satisfied while human review is optional",
    "Per-worktree application isolation",
    "Per-worktree observability stack",
    "Chrome DevTools Protocol for UI control",
    "Victoria Logs, Metrics, and Traces with LogQL/PromQL/TraceQL",
    "OpenAI's fixed layered domain architecture",
    "Reimplementing upstream dependency behavior locally",
    "Minimally blocking merge gates and short-lived pull requests",
    "Scheduled Codex documentation gardening and quality-scoring agents open targeted repair pull requests",
    "Automated merge and agent-authored release tooling",
]
errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def rel(path: Path) -> str:
    try:
        return path.resolve(strict=False).relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def read_text(path: Path) -> str:
    try:
        if path.is_symlink() or not path.is_file():
            raise OSError("not a regular file")
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as exc:
        fail(f"{rel(path)}: cannot read UTF-8 regular file: {exc}")
        return ""


def load_json(path: Path) -> dict[str, Any]:
    text = read_text(path)
    if not text:
        return {}
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        fail(f"{rel(path)}: invalid JSON: {exc}")
        return {}
    if not isinstance(value, dict):
        fail(f"{rel(path)}: JSON root must be an object")
        return {}
    return value


def safe_repo_path(value: str, source: Path | None = None) -> Path | None:
    base = ROOT if source is None else source.parent
    candidate = (ROOT / value.lstrip("/")) if value.startswith("/") else (base / value)
    resolved = candidate.resolve(strict=False)
    try:
        resolved.relative_to(ROOT)
    except ValueError:
        fail(f"{value}: path escapes the repository")
        return None
    return resolved


def visible_markdown(value: str) -> str:
    value = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", value)
    value = value.replace("`", "")
    return re.sub(r"\s+", " ", value).strip()


def split_row(line: str) -> list[str] | None:
    if not line.startswith("|") or not line.rstrip().endswith("|"):
        return None
    return [cell.strip() for cell in line.strip()[1:-1].split("|")]


def parse_status(value: str) -> tuple[str | None, str]:
    visible = visible_markdown(value)
    match = re.fullmatch(
        r"(?is)(verified|candidate|blocked|n\s*/\s*a)(?:\s*(?:—|–|-|:)\s*|\s+)(.+)",
        visible,
    )
    if match is None:
        return None, ""
    status_value = match.group(1).replace(" ", "").lower()
    return ("n/a" if status_value == "n/a" else status_value), match.group(2).strip()


def validate_config() -> tuple[dict[str, str], dict[str, Any]]:
    payload = load_json(CONFIG)
    if payload.get("schema_version") != 1:
        fail("docs/agent-harness/config.json: schema_version must be 1")
    authorities = payload.get("authorities")
    if not isinstance(authorities, dict):
        fail("docs/agent-harness/config.json: authorities must be an object")
        return {}, payload
    expected_keys = {
        "instructions",
        "architecture",
        "planning",
        "exec_plan_index",
        "registry",
        "environment",
        "verification",
        "coverage",
        "certification",
    }
    if set(authorities) != expected_keys:
        fail("docs/agent-harness/config.json: authority keys do not match the adopted contract")
    normalized: dict[str, str] = {}
    for key in expected_keys:
        value = authorities.get(key)
        if not isinstance(value, str) or not value:
            fail(f"docs/agent-harness/config.json: authority {key!r} must be a path")
            continue
        path = safe_repo_path(value)
        if path is None or not path.is_file() or path.is_symlink():
            fail(f"{value}: configured authority {key!r} is missing or unsafe")
            continue
        normalized[key] = value
    return normalized, payload


def validate_instruction_map(authorities: dict[str, str]) -> None:
    agents_path = ROOT / "AGENTS.md"
    text = read_text(agents_path)
    size = len(text.encode("utf-8"))
    if size > 32 * 1024:
        fail(f"AGENTS.md: {size} bytes exceeds the conservative 32 KiB instruction budget")
    for key, value in authorities.items():
        if key == "instructions":
            continue
        if value not in text and "docs/agent-harness/index.md" not in text:
            fail(f"AGENTS.md: no route to configured {key!r} authority {value}")


def index_block(text: str, start: str, end: str) -> list[str]:
    if text.count(start) != 1 or text.count(end) != 1:
        fail(f"managed plan index: lifecycle markers {start!r}/{end!r} must appear once")
        return []
    body = text.split(start, 1)[1].split(end, 1)[0]
    return [line for line in body.splitlines() if line.strip() and line.strip() != "_None._"]


def plan_metadata(text: str) -> dict[str, str]:
    match = re.match(r"\A<!-- harness-plan:v1\n(.*?)\n-->\s*", text, re.DOTALL)
    if not match:
        return {}
    result: dict[str, str] = {}
    for line in match.group(1).splitlines():
        if ":" not in line:
            return {}
        key, value = line.split(":", 1)
        if key.strip() in result:
            return {}
        result[key.strip()] = value.strip()
    return result


def validate_plan(path: Path, state: str, planning_path: Path) -> dict[str, str]:
    text = read_text(path)
    metadata = plan_metadata(text)
    fields = {"id", "status", "created", "updated", "completed", "owner"}
    if set(metadata) != fields:
        fail(f"{rel(path)}: invalid harness-plan:v1 metadata fields")
        return metadata
    if metadata["id"] != path.stem or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", path.stem):
        fail(f"{rel(path)}: id must equal the lowercase-hyphenated filename stem")
    if metadata["status"] != state:
        fail(f"{rel(path)}: metadata status must be {state!r}")
    for field in ("created", "updated"):
        try:
            datetime.strptime(metadata[field], "%Y-%m-%d")
        except ValueError:
            fail(f"{rel(path)}: {field} must be YYYY-MM-DD")
    if not metadata["owner"] or metadata["owner"].lower() in {"none", "n/a", "unknown"}:
        fail(f"{rel(path)}: owner must name a durable role or team")
    if state == "active" and metadata["completed"]:
        fail(f"{rel(path)}: active plan completed field must be empty")
    if state == "completed":
        try:
            datetime.strptime(metadata["completed"], "%Y-%m-%d")
        except ValueError:
            fail(f"{rel(path)}: completed plan must have a YYYY-MM-DD completion date")
        if re.search(r"(?m)^\s*[-*+]\s+\[ \]", text):
            fail(f"{rel(path)}: completed plan contains unchecked progress")
        if "Semantic-Review:" not in text:
            fail(f"{rel(path)}: completed plan lacks the semantic-review continuation")
    headings = re.findall(r"(?m)^##\s+(.+?)\s*$", text)
    if headings != PLAN_HEADINGS:
        fail(f"{rel(path)}: managed H2 headings do not match the required ordered schema")
    planning_rel = Path(os.path.relpath(planning_path, path.parent)).as_posix()
    if planning_rel not in text:
        fail(f"{rel(path)}: plan does not link the configured planning authority")
    if re.search(r"TODO\(harness\)|<replace|<YYYY|<role-or-team>", text, re.IGNORECASE):
        fail(f"{rel(path)}: active/completed plan contains an unresolved template marker")
    return metadata


def validate_plans(authorities: dict[str, str]) -> None:
    index_path = ROOT / authorities["exec_plan_index"]
    planning_path = ROOT / authorities["planning"]
    text = read_text(index_path)
    rows_by_state: dict[str, dict[str, list[str]]] = {"active": {}, "completed": {}}
    markers = {
        "active": ("<!-- harness:plans:active:start -->", "<!-- harness:plans:active:end -->"),
        "completed": (
            "<!-- harness:plans:completed:start -->",
            "<!-- harness:plans:completed:end -->",
        ),
    }
    for state, (start, end) in markers.items():
        for line in index_block(text, start, end):
            cells = split_row(line)
            expected = 5 if state == "active" else 4
            if cells is None or len(cells) != expected:
                fail(f"{rel(index_path)}: malformed {state} lifecycle row: {line}")
                continue
            link = re.fullmatch(r"\[([^\]]+)\]\(([^)]+)\)", cells[0])
            if link is None:
                fail(f"{rel(index_path)}: {state} row must start with one plan link")
                continue
            target = safe_repo_path(link.group(2), index_path)
            if target is None:
                continue
            rows_by_state[state][target.as_posix()] = cells
    for state in ("active", "completed"):
        directory = index_path.parent / state
        if not directory.is_dir() or directory.is_symlink():
            fail(f"{rel(directory)}: managed lifecycle directory is missing or unsafe")
            continue
        plans = sorted(directory.glob("*.md"))
        if state == "active" and len(plans) > 1:
            fail(f"{rel(directory)}: more than one active managed plan")
        file_set = {plan.resolve().as_posix() for plan in plans}
        row_set = set(rows_by_state[state])
        for missing in sorted(file_set - row_set):
            fail(f"{rel(Path(missing))}: managed plan is missing from the registry")
        for stale in sorted(row_set - file_set):
            fail(f"{rel(Path(stale))}: registry points to a missing managed plan")
        for plan in plans:
            metadata = validate_plan(plan, state, planning_path)
            cells = rows_by_state[state].get(plan.resolve().as_posix())
            if not cells or not metadata:
                continue
            title = re.search(r"(?m)^#\s+(.+?)\s*$", read_text(plan))
            link_title = re.match(r"\[([^\]]+)\]", cells[0])
            if title is None or link_title is None or title.group(1) != link_title.group(1):
                fail(f"{rel(plan)}: registry title disagrees with the plan H1")
            if state == "active":
                if cells[1] != metadata["owner"] or cells[3] != metadata["updated"]:
                    fail(f"{rel(plan)}: active registry owner/date disagrees with metadata")
                if cells[2] not in {"planning", "implementing", "blocked"}:
                    fail(f"{rel(plan)}: active registry state is invalid")
            elif cells[1] != metadata["completed"]:
                fail(f"{rel(plan)}: completed registry date disagrees with metadata")


def coverage_rows(path: Path) -> dict[str, str]:
    rows: dict[str, str] = {}
    for line in read_text(path).splitlines():
        cells = split_row(line)
        if cells is None or len(cells) != 4:
            continue
        identity = cells[0]
        if identity in CAPABILITIES:
            if identity in rows:
                fail(f"{rel(path)}: duplicate capability row {identity!r}")
            rows[identity] = cells[3]
    missing = set(CAPABILITIES) - set(rows)
    extra_count = len(rows) - len(CAPABILITIES)
    for identity in sorted(missing):
        fail(f"{rel(path)}: missing canonical capability {identity!r}")
    if extra_count:
        fail(f"{rel(path)}: canonical capability inventory has unexpected duplicates or rows")
    for identity, status_cell in rows.items():
        status_value, reason = parse_status(status_cell)
        if status_value is None or len(reason) < 8:
            fail(f"{rel(path)}: unexplained status for capability {identity!r}")
        elif status_value in {"candidate", "blocked"}:
            fail(f"{rel(path)}: capability {identity!r} remains {status_value}")
    return rows


def project_markdown_files(authorities: dict[str, str]) -> list[Path]:
    paths = {
        ROOT / "AGENTS.md",
        ROOT / "docs/index.md",
        ROOT / "docs/PLANS.md",
        ROOT / "docs/SECURITY.md",
        ROOT / "docs/RELIABILITY.md",
    }
    for pattern in (
        "docs/agent-harness/**/*.md",
        "docs/harness-plans/**/*.md",
        "docs/design-docs/*.md",
        "docs/product-specs/*.md",
        "docs/generated/index.md",
        "docs/references/index.md",
    ):
        paths.update(ROOT.glob(pattern))
    for value in authorities.values():
        path = ROOT / value
        if path.suffix == ".md":
            paths.add(path)
    return sorted(paths)


def validate_links(authorities: dict[str, str]) -> None:
    link_re = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
    for path in project_markdown_files(authorities):
        text = read_text(path)
        if path.name != "plan-template.md" and re.search(
            r"TODO\(harness\)|<replace-with|<!--\s*(?:Describe|Explain|Name|Define|State)",
            text,
            re.IGNORECASE,
        ):
            fail(f"{rel(path)}: unresolved scaffold placeholder")
        for raw in link_re.findall(text):
            target_value = raw.strip().split("#", 1)[0]
            if not target_value or re.match(r"^(?:https?|mailto):", target_value):
                continue
            target = safe_repo_path(target_value, path)
            if target is not None and not target.exists():
                fail(f"{rel(path)}: local Markdown link does not resolve: {raw}")


def parse_instant(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value.endswith("Z"):
        return None
    try:
        return datetime.fromisoformat(value[:-1] + "+00:00").astimezone(timezone.utc)
    except ValueError:
        return None


def validate_manifest(authorities: dict[str, str], strict: bool) -> tuple[dict[str, Any], dict[str, str]]:
    path = ROOT / authorities["certification"]
    payload = load_json(path)
    required = {
        "schema_version",
        "claim",
        "profile",
        "repository_commit",
        "repository_identity",
        "deployment_target_id",
        "environment",
        "issued_at",
        "expires_at",
        "coverage_sha256",
        "evidence_root",
        "project_native_gate",
        "maintenance",
        "production_authority",
    }
    if set(payload) != required:
        fail(f"{rel(path)}: manifest fields do not match schema v2")
    if payload.get("schema_version") != 2 or payload.get("profile") != "adaptive":
        fail(f"{rel(path)}: schema_version/profile must be 2/adaptive")
    if payload.get("claim") not in {"candidate-only", "harness-ready"}:
        fail(f"{rel(path)}: claim must be candidate-only or harness-ready")
    if strict and payload.get("claim") != "harness-ready":
        fail(f"{rel(path)}: strict gate requires claim harness-ready")
    if not strict and payload.get("claim") == "harness-ready":
        fail(
            f"{rel(path)}: harness-ready claims require the strict gate and "
            "external attestation key"
        )
    coverage_path = ROOT / authorities["coverage"]
    digest = hashlib.sha256(read_text(coverage_path).encode("utf-8")).hexdigest()
    if payload.get("coverage_sha256") != digest:
        fail(f"{rel(path)}: coverage_sha256 does not match {rel(coverage_path)}")
    if payload.get("repository_identity") != "scm://github.com/MarlonJD/flutter_scene_viewer":
        fail(f"{rel(path)}: repository identity is not the adopted immutable identity")
    if payload.get("deployment_target_id") != (
        "harness://github.com/MarlonJD/flutter_scene_viewer/flutter-package-local-validation"
    ):
        fail(f"{rel(path)}: harness evaluation target is not the adopted target")
    maintenance = payload.get("maintenance")
    if not isinstance(maintenance, dict) or maintenance.get("triggers") != ["manual"]:
        fail(f"{rel(path)}: maintenance must use the manual trigger")
    if not isinstance(maintenance, dict) or maintenance.get("max_age_hours") != 168:
        fail(f"{rel(path)}: maintenance max_age_hours must be 168")
    if strict:
        issued = parse_instant(payload.get("issued_at"))
        expires = parse_instant(payload.get("expires_at"))
        now = datetime.now(timezone.utc)
        if issued is None or expires is None or not (issued <= now <= expires):
            fail(f"{rel(path)}: strict manifest is not inside its freshness window")
        elif (expires - issued).total_seconds() > 168 * 3600:
            fail(f"{rel(path)}: strict manifest freshness window exceeds seven days")
    rows = coverage_rows(coverage_path)
    return payload, rows


def load_key(cli_path: str | None) -> bytes:
    value = cli_path or os.environ.get("FSV_HARNESS_ATTESTATION_KEY_FILE")
    if not value:
        fail("strict gate requires FSV_HARNESS_ATTESTATION_KEY_FILE or --attestation-key-file")
        return b""
    path = Path(value)
    try:
        if path.is_symlink():
            raise OSError("key must not be a symlink")
        metadata = path.stat()
        if not stat.S_ISREG(metadata.st_mode) or metadata.st_nlink != 1:
            raise OSError("key must be a single-linked regular file")
        if metadata.st_mode & 0o077:
            raise OSError("key must not be accessible to group or world")
        path.resolve().relative_to(ROOT)
        raise OSError("key must be outside the repository")
    except ValueError:
        pass
    except OSError as exc:
        fail(f"attestation key: {exc}")
        return b""
    try:
        data = path.read_bytes()
    except OSError as exc:
        fail(f"attestation key: cannot read key: {exc}")
        return b""
    if not 32 <= len(data) <= 4096:
        fail("attestation key: raw key length must be 32–4096 bytes")
        return b""
    return data


def validate_record(
    path: Path,
    capability: str,
    result: str,
    payload: dict[str, Any],
    key: bytes,
) -> None:
    record = load_json(path)
    if set(record) != EVIDENCE_FIELDS:
        fail(f"{rel(path)}: evidence fields do not match schema v2")
        return
    if record.get("schema_version") != 2 or record.get("capabilities") != [capability]:
        fail(f"{rel(path)}: schema or capability identity mismatch")
    for field in ("repository_commit", "repository_identity", "deployment_target_id"):
        if record.get(field) != payload.get(field):
            fail(f"{rel(path)}: {field} does not match the manifest")
    if record.get("environment") != payload.get("environment"):
        fail(f"{rel(path)}: environment does not match the manifest")
    expected_exit = 0 if result == "passed" else None
    if record.get("result") != result or record.get("exit_code") != expected_exit:
        fail(f"{rel(path)}: result/exit_code mismatch for {result}")
    observed = parse_instant(record.get("observed_at"))
    expires = parse_instant(payload.get("expires_at"))
    if observed is None or expires is None or observed > expires:
        fail(f"{rel(path)}: observed_at is invalid or outside the manifest window")
    if not isinstance(record.get("artifacts"), list) or not record["artifacts"]:
        fail(f"{rel(path)}: artifacts must contain durable evidence identifiers")
    key_id = hashlib.sha256(key).hexdigest()
    if record.get("key_id") != key_id:
        fail(f"{rel(path)}: key_id does not match the supplied key")
    unsigned = {name: value for name, value in record.items() if name != "signature"}
    encoded = json.dumps(
        unsigned, sort_keys=True, separators=(",", ":"), ensure_ascii=True, allow_nan=False
    ).encode("utf-8")
    signature = hmac.new(key, DOMAIN + encoded, hashlib.sha256).hexdigest()
    if not hmac.compare_digest(str(record.get("signature")), signature):
        fail(f"{rel(path)}: HMAC signature mismatch")


def run_git(*args: str) -> str:
    try:
        completed = subprocess.run(
            ["git", *args],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        fail(f"git {' '.join(args)}: {exc}")
        return ""
    if completed.returncode != 0:
        fail(f"git {' '.join(args)}: {completed.stderr.strip()}")
        return ""
    return completed.stdout.strip()


def strict_certification(
    payload: dict[str, Any], rows: dict[str, str], key_path: str | None
) -> None:
    key = load_key(key_path)
    if not key:
        return
    evidence_paths: set[Path] = set()
    production_status = ""
    for capability, status_cell in rows.items():
        status_value, _ = parse_status(status_cell)
        links = re.findall(r"\[[^\]]+\]\(([^)]+\.json)\)", status_cell)
        if status_value not in {"verified", "n/a"} or len(links) != 1:
            fail(f"coverage: {capability!r} must link exactly one JSON record")
            continue
        path = safe_repo_path(links[0], ROOT / "docs/agent-harness/coverage-matrix.md")
        if path is None:
            continue
        evidence_paths.add(path)
        validate_record(
            path,
            capability,
            "passed" if status_value == "verified" else "not-applicable",
            payload,
            key,
        )
        if capability.startswith("Release, deployment"):
            production_status = status_value
    for field, capability in (
        ("project_native_gate", "project-native-harness-gate"),
        ("maintenance", "continuous-harness-maintenance"),
    ):
        section = payload.get(field)
        if not isinstance(section, dict) or not isinstance(section.get("evidence"), str):
            fail(f"manifest: {field} evidence path is missing")
            continue
        path = safe_repo_path(section["evidence"])
        if path is None:
            continue
        evidence_paths.add(path)
        validate_record(path, capability, "passed", payload, key)
    production = payload.get("production_authority")
    if production_status == "n/a":
        if production != {"owner": None, "approval_evidence": None, "rollback_evidence": None}:
            fail("manifest: N/A production authority must keep owner/evidence null")
    source = payload.get("repository_commit")
    head = run_git("rev-parse", "HEAD")
    parent_line = run_git("rev-list", "--parents", "-n", "1", head)
    parents = parent_line.split()
    if not isinstance(source, str) or not re.fullmatch(r"[0-9a-f]{40}", source):
        fail("manifest: repository_commit must be the 40-hex source commit")
    if len(parents) != 2 or parents[1] != source:
        fail("git: current HEAD must be the direct single-parent child of repository_commit")
    nonignored = run_git("ls-files", "--others", "--exclude-standard")
    ignored = run_git("ls-files", "--others", "--ignored", "--exclude-standard")
    modified = run_git("status", "--porcelain", "--untracked-files=no")
    if nonignored or ignored or modified:
        fail("git: strict certification requires a clean tree with no ignored or untracked files")
    changed = set(run_git("diff", "--name-only", source, head).splitlines())
    allowed = {
        "docs/agent-harness/certification.json",
        "docs/agent-harness/coverage-matrix.md",
        *(rel(path) for path in evidence_paths),
    }
    if changed != allowed:
        fail(
            "git: attestation overlay changed-path set does not exactly match manifest, "
            "coverage, and referenced evidence"
        )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--require-harness-ready", action="store_true")
    parser.add_argument("--maintain", action="store_true")
    parser.add_argument("--attestation-key-file")
    args = parser.parse_args()
    strict = args.require_harness_ready or args.maintain

    authorities, _ = validate_config()
    if authorities:
        validate_instruction_map(authorities)
        validate_plans(authorities)
        validate_links(authorities)
        payload, rows = validate_manifest(authorities, strict)
        if strict and payload and rows:
            strict_certification(payload, rows, args.attestation_key_file)

    if errors:
        for message in errors:
            print(f"HARNESS_ERROR: {message}")
        return 1
    state = "harness-ready" if strict else "candidate-only"
    print(f"harness gate passed (certification state: {state})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
