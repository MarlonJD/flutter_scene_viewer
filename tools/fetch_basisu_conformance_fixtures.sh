#!/usr/bin/env bash

set -euo pipefail

readonly COMMIT='8c6bd82215d2ca4e015dca0b3378c602b9d4e688'
readonly BASE_URL="https://raw.githubusercontent.com/KhronosGroup/KTX-Software-CTS/${COMMIT}"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly DEST_DIR="${ROOT_DIR}/packages/flutter_scene_viewer_basisu/test/fixtures/ktx2-cts"
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
  'LICENSE' \
  'LICENSE' \
  'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4'
fetch_and_verify \
  'clitests/golden/create/encode_blze/output_R8G8B8A8_UNORM.ktx2' \
  'create/encode_blze/output_R8G8B8A8_UNORM.ktx2' \
  '03327b968ed91664759d69cc9c951117f22f97c75bb437507937be122ce565fd'
fetch_and_verify \
  'clitests/golden/create/encode_blze/output_R8G8B8_UNORM.ktx2' \
  'create/encode_blze/output_R8G8B8_UNORM.ktx2' \
  '7e185709429d723bda938c1fe9efc9bee4f529c08ebdf018db059755805a612d'
fetch_and_verify \
  'clitests/golden/create/encode_blze/output_R8G8_UNORM.ktx2' \
  'create/encode_blze/output_R8G8_UNORM.ktx2' \
  '1c4355725730e0f3a0c180e300fadf8bd4b91a0c3903647063b043f627090556'
fetch_and_verify \
  'clitests/golden/create/encode_blze/output_R8_UNORM.ktx2' \
  'create/encode_blze/output_R8_UNORM.ktx2' \
  '44d1eaa7453926293e29e57d583c0289e550d605b53865ad42d64e7699083f3d'
fetch_and_verify \
  'clitests/golden/create/encode_uastc/output_R8G8B8A8_UNORM.ktx2' \
  'create/encode_uastc/output_R8G8B8A8_UNORM.ktx2' \
  '97beaf23d78c3c01289cb994bbd8b051b2a1a6dd12c211b347a24fb76f47324f'
fetch_and_verify \
  'clitests/golden/create/encode_uastc/output_R8G8B8_UNORM.ktx2' \
  'create/encode_uastc/output_R8G8B8_UNORM.ktx2' \
  '6ff5fed15df2eb7d8f4ecc26db162187f638d061593e198c97c77757f07993c0'
fetch_and_verify \
  'clitests/golden/create/encode_uastc/output_R8G8_UNORM.ktx2' \
  'create/encode_uastc/output_R8G8_UNORM.ktx2' \
  '7ba0de14b4df1ca9ea14c8b60c7a7eca715449f668237908b885365210fa8129'
fetch_and_verify \
  'clitests/golden/create/encode_uastc/output_R8_UNORM.ktx2' \
  'create/encode_uastc/output_R8_UNORM.ktx2' \
  '37986f8ce541bfd5e4485dac36b919fb91b006e64bab6716b5c913b1600d9f60'
fetch_and_verify \
  'clitests/input/ktx2/valid_R8G8_UNORM_2D_UASTC.ktx2' \
  'input/ktx2/valid_R8G8_UNORM_2D_UASTC.ktx2' \
  '318f68b48970fcdf76fbc407bfdc83a8afef6f611382f1283ff8106345b4a5d9'
fetch_and_verify \
  'clitests/golden/deflate/metadata/output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2' \
  'deflate/metadata/output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2' \
  '27484bc9b6e062acf0d6478df1b3ad62f6b6f32b923539c93353e535b572b0e4'
fetch_and_verify \
  'clitests/golden/create/compare/output_blze_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2' \
  'create/compare/output_blze_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2' \
  '7f13880e79f166815c9adcf2a1a5d0c38976316cb35a6b35a3a540dbb6a1f012'
fetch_and_verify \
  'clitests/golden/create/compare/output_uastc_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2' \
  'create/compare/output_uastc_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2' \
  '4190e313b63aa9f1e6202f81b74db5e59dd2422390b8f6613eb1c1aec1f669e1'
fetch_and_verify \
  'clitests/input/validate/3101/error_InvalidSupercompressionGLTFBU_UASTC_ZLIB.ktx2' \
  'validate/3101/error_InvalidSupercompressionGLTFBU_UASTC_ZLIB.ktx2' \
  'a6bd1196e6bef3a04376b5bbd1fa58d7e5261777bb11f848d40210f4d0e38eaa'
fetch_and_verify \
  'clitests/input/validate/3103/error_InvalidPixelWidthHeightGLTFBU_bothUnaligned.ktx2' \
  'validate/3103/error_InvalidPixelWidthHeightGLTFBU_bothUnaligned.ktx2' \
  '143bf285a0c05da1c84fb4214a9a2648367c512bf494926ff6caa0ab4499f99e'
fetch_and_verify \
  'clitests/input/validate/6301/error_IncorrectModelGLTFBU_ASTC.ktx2' \
  'validate/6301/error_IncorrectModelGLTFBU_ASTC.ktx2' \
  '533b6432785b74041574e347331319fa31d2f06518fd542cf9ce95f1ab155820'
fetch_and_verify \
  'clitests/input/validate/6303/error_InvalidChannelGLTFBU_ETC1S_GGG.ktx2' \
  'validate/6303/error_InvalidChannelGLTFBU_ETC1S_GGG.ktx2' \
  'b104eb266c54a68f3662aa64ff4aff9937b1ed39221e55dfd5f0253af6dd6b4c'
fetch_and_verify \
  'clitests/input/validate/6303/error_InvalidChannelGLTFBU_UASTC_RRRG.ktx2' \
  'validate/6303/error_InvalidChannelGLTFBU_UASTC_RRRG.ktx2' \
  '6d1a2793dc9c9449ee70f1ec8d497f981a1bd1826adaec871fcbadeaf995cef5'
fetch_and_verify \
  'clitests/input/validate/6304/error_InvalidColorSpaceGLTFBU_ETC1S_ADOBERGB.ktx2' \
  'validate/6304/error_InvalidColorSpaceGLTFBU_ETC1S_ADOBERGB.ktx2' \
  '3fbe6a10172a8c46c361543e1aa9e50647e7626186823102bc40a8b47a39e5bb'
fetch_and_verify \
  'clitests/input/validate/6304/error_InvalidColorSpaceGLTFBU_ETC1S_BT709_LINEAR.ktx2' \
  'validate/6304/error_InvalidColorSpaceGLTFBU_ETC1S_BT709_LINEAR.ktx2' \
  '8431d2170653b6deebe5e859711311ba2ea0ba48d9b804a8fab8767dd0c18412'
fetch_and_verify \
  'clitests/input/validate/7201/error_KTXswizzleInvalidGLTFBU_ETC1S_bgra.ktx2' \
  'validate/7201/error_KTXswizzleInvalidGLTFBU_ETC1S_bgra.ktx2' \
  'f2daa2bd66b03694f021ff0222e58722ff58b1e245d6a664cbaceafde012e986'
fetch_and_verify \
  'clitests/input/validate/7202/error_KTXorientationInvalidGLTFBU_ETC1S_lu.ktx2' \
  'validate/7202/error_KTXorientationInvalidGLTFBU_ETC1S_lu.ktx2' \
  '56e3bf9dc4e8da3c4774b3930bae9130375ab8dcd93b79c8fc3adc6bd4b60f39'

python3 "${ROOT_DIR}/tools/derive_basisu_uastc_rg_fixture.py" \
  --write \
  --source "${TEMP_DIR}/input/ktx2/valid_R8G8_UNORM_2D_UASTC.ktx2" \
  --output "${TEMP_DIR}/derived/khr_texture_basisu_uastc_rg.ktx2"

mkdir -p "${DEST_DIR}"
cp -R "${TEMP_DIR}/." "${DEST_DIR}/"
