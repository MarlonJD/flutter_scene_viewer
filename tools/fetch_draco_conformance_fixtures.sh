#!/usr/bin/env bash

set -euo pipefail

readonly COMMIT='2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf'
readonly BASE_URL="https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/${COMMIT}"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DEST_DIR="${ROOT_DIR}/packages/flutter_scene_viewer_draco/test/fixtures/draco"
readonly TEMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

fetch_and_verify() {
  local source_path="$1"
  local destination_path="$2"
  local expected_sha256="$3"
  local temporary_path="${TEMP_DIR}/${destination_path}"

  mkdir -p "$(dirname "${temporary_path}")"
  curl --fail --silent --show-error --location \
    "${BASE_URL}/${source_path}" \
    --output "${temporary_path}"
  printf '%s  %s\n' "${expected_sha256}" "${temporary_path}" | \
    shasum -a 256 --check
}

verify_prefix() {
  local source_path="$1"
  local byte_length="$2"
  local expected_sha256="$3"
  local actual_sha256

  actual_sha256="$(
    dd if="${TEMP_DIR}/${source_path}" bs=1 count="${byte_length}" 2>/dev/null | \
      shasum -a 256 | awk '{print $1}'
  )"
  if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
    printf 'SHA-256 mismatch for first %s bytes of %s\n' \
      "${byte_length}" "${source_path}" >&2
    return 1
  fi
  printf '%s (first %s bytes): OK\n' "${source_path}" "${byte_length}"
}

fetch_and_verify \
  'Models/Box/glTF-Draco/Box.gltf' \
  'Box/glTF-Draco/Box.gltf' \
  '3c46acecdfa90b012ec9052d8a1dfa61358e6d56a9e333504189cc78a2de4d1b'
fetch_and_verify \
  'Models/Box/glTF-Draco/Box.bin' \
  'Box/glTF-Draco/Box.bin' \
  '610dc6e08aba7c2720c8e4ec0578efd91cf2d88a5e638dab7811a22f0235bf2e'
fetch_and_verify \
  'Models/Box/LICENSE.md' \
  'Box/LICENSE.txt' \
  '634623c7bef43aa4b16a3556ac55ae71b671daf4509437d403e4f2a0273928dc'
verify_prefix \
  'Box/glTF-Draco/Box.bin' \
  '118' \
  '1d5e57c8179d5768bcfcf3fc53da7c1833386b071146236d59eec568a99a9831'

mkdir -p "${DEST_DIR}"
cp -R "${TEMP_DIR}/." "${DEST_DIR}/"
