#!/usr/bin/env bash

set -euo pipefail

readonly COMMIT='2bac6f8c57bf471df0d2a1e8a8ec023c7801dddf'
readonly BASE_URL="https://raw.githubusercontent.com/KhronosGroup/glTF-Sample-Assets/${COMMIT}"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DEST_DIR="${ROOT_DIR}/test/fixtures/meshopt"
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

fetch_and_verify \
  'Models/MeshoptCubeTest/glTF/MeshoptCubeTest.gltf' \
  'MeshoptCubeTest/glTF/MeshoptCubeTest.gltf' \
  '8721150e3409425acf83aa21986e55880360ab084c17e96409c25fac53477f72'
fetch_and_verify \
  'Models/MeshoptCubeTest/glTF/MeshoptCubeTest.bin' \
  'MeshoptCubeTest/glTF/MeshoptCubeTest.bin' \
  '6578c1d82c5cc2b228e9513e37f348ca89cdb24b5985aa0567efef8d3c014360'
fetch_and_verify \
  'Models/MeshoptCubeTest/glTF/MeshoptCubeTestFallback.bin' \
  'MeshoptCubeTest/glTF/MeshoptCubeTestFallback.bin' \
  '8d3d779653780e85a75eda988110ab235ea85cd3d174361ffb318c6b657dee07'
fetch_and_verify \
  'Models/MeshoptCubeTest/glTF-Meshopt/MeshoptCubeTest.gltf' \
  'MeshoptCubeTest/glTF-Meshopt/MeshoptCubeTest.gltf' \
  'b5947609f3d8aba58de3d43101df3b635ffaaab5849431f8518af6a98a040433'
fetch_and_verify \
  'Models/MeshoptCubeTest/LICENSE.md' \
  'LICENSE.md' \
  '63fc4b5080289c3640c904dcf5adb3a6122a707928164d7520f46b3051da8ac3'

mkdir -p "${DEST_DIR}"
cp -R "${TEMP_DIR}/." "${DEST_DIR}/"
