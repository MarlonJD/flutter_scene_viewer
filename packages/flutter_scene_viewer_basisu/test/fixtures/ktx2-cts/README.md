# BasisU/KTX2 conformance fixtures

This directory contains a minimal official Khronos KTX-Software-CTS corpus
for host comparison of the package bridge with the independently invoked
vendored Basis Universal transcoder. It covers ETC1S with BasisLZ, UASTC with
no supercompression, UASTC with Zstandard supercompression, and official
files produced from RGBA, RGB, RG, and R source layouts. The ETC1S RG fixture
uses the conformant `RRR` plus `GGG` DFD channels. The generic `create/encode`
UASTC RG file uses numeric channel 0 rather than the `UASTC_RG` channel 6 that
`KHR_texture_basisu` requires, so it remains a codec/source-layout oracle only.
A separate pinned official `valid_R8G8_UNORM_2D_UASTC` source contains an 8x8
UASTC payload encoded from R8G8 input with generic `UASTC_RRRG(5)` metadata.
The deterministic repository derivation changes only DFD primaries from BT709
to UNSPECIFIED and the DFD channel to `UASTC_RG(6)`. The compressed payload and
every other byte remain identical to the pinned official source. This derived
fixture is selected-profile conformance evidence, not an unmodified official
CTS fixture. The two mip fixtures are diagnostic
cases: the current bridge rewrites one PNG image and cannot preserve an
authored mip pyramid. Selected official `clitests/input/validate` negatives
cover the KHR codec, DFD, alignment, color-space-pair, swizzle, and orientation
profile boundaries.

This is direct-codec and wrapper host evidence only. It is not an Android or
iOS runtime, device, packaging, release, or `production-ready` claim. DFD
channel shapes and structural transfer/primaries pairs are covered, including
the linear-only rule for R and RG shapes. Dimensions, codec/supercompression
pairing, allowed or omitted orientation/swizzle values, premultiplied-alpha
rejection, strict KVD key ordering/uniqueness, and zero value padding are also
covered by the host bridge tests. KVD keys are validated as UTF-8 before their
unsigned-byte ordering is used as Unicode code-point order, and a leading
UTF-8 BOM is rejected. Host tests derive sampled channel masks and color-space
roles from the selected core and material-extension texture slots, then
aggregate them by BasisU source image. Packed specular color RGB plus linear
specular alpha remains a valid color texture because the sRGB transfer does not
apply to alpha. Ambiguity is limited to images whose RGB channels are sampled
as both color and non-color data. Requested `r`, `rg`, `rgb`, and `rgba` layouts
are matched exactly to the ETC1S/UASTC DFD channel category before codec work.
Clearcoat textures request RGB because `KHR_materials_clearcoat` explicitly
defines all clearcoat textures as RGB in linear space, even though factor and
roughness sample R and G respectively. The pinned R/RG/RGB codec sources use a
BT709-linear DFD pair; direct selected-profile layout tests derive only the
required UNSPECIFIED-linear primaries metadata and retain the pinned payloads.
This does not claim that decoded channels have been bound to renderer material
slots. The selected UASTC RG linear-only and exact-layout paths now use the
derived R8G8 payload and match the independently invoked pinned transcoder. For
UASTC, numeric channel 0 is interpreted as the spec's RGB category: the
official RGB fixture, UASTC color model, requested `rgb` layout, and KHR profile
supply that context. Numeric aliasing with the pinned API's generic `DATA` name
does not promote channel-0 RG source-layout bytes to RG; exact `rg` usage still
requires channel 6. Task 5E.2 host tests route the KTX2 Level Index, DFD,
outer and nested KVD, ETC1S descriptor, and covered Zstd state vectors through
distinct request allocators, and reject valid `KTXanimData` metadata before
codec allocation for both uncompressed and Zstd UASTC. Partial-metadata
cancellation is exercised after the Level Index, DFD, outer KVD, KVD
relocation, and each complete KVD entry. Required malformed Level Index, DFD,
KVD truncation/overflow, missing key terminator, invalid padding/order, and
duplicate-key cases run under the permanent ASan+UBSan host gate. Explicit
caller state is unbound before its request control expires. A deterministic
12-entry KVD fixture proves allocator-aware relocation in both normal and full
`-fno-exceptions` builds, including exact heap/budget/cancellation cleanup and
a source-different relocation mutant. ETC1S codebook/history state, the Zstd
context workspace, platform/result lifetimes, and outer-envelope removal
remain open. This slice does not establish target runtime, release, or complete
codec-resource-control compliance.

Source: `KhronosGroup/KTX-Software-CTS`, commit
`8c6bd82215d2ca4e015dca0b3378c602b9d4e688`, under `clitests/golden`,
`clitests/input/ktx2`, and `clitests/input/validate`. The corpus and its
vendored `LICENSE` are Apache-2.0 licensed.

The decoder under test is the repository-vendored Basis Universal transcoder
at commit `882abb5320400ab650c1be33f9152e4955e83af3`, also Apache-2.0.

Fetch and verify with:

```sh
bash tools/fetch_basisu_conformance_fixtures.sh
```

Tracked files and SHA-256 digests:

| File | SHA-256 |
| --- | --- |
| `LICENSE` | `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4` |
| `create/encode_blze/output_R8G8B8A8_UNORM.ktx2` | `03327b968ed91664759d69cc9c951117f22f97c75bb437507937be122ce565fd` |
| `create/encode_blze/output_R8G8B8_UNORM.ktx2` | `7e185709429d723bda938c1fe9efc9bee4f529c08ebdf018db059755805a612d` |
| `create/encode_blze/output_R8G8_UNORM.ktx2` | `1c4355725730e0f3a0c180e300fadf8bd4b91a0c3903647063b043f627090556` |
| `create/encode_blze/output_R8_UNORM.ktx2` | `44d1eaa7453926293e29e57d583c0289e550d605b53865ad42d64e7699083f3d` |
| `create/encode_uastc/output_R8G8B8A8_UNORM.ktx2` | `97beaf23d78c3c01289cb994bbd8b051b2a1a6dd12c211b347a24fb76f47324f` |
| `create/encode_uastc/output_R8G8B8_UNORM.ktx2` | `6ff5fed15df2eb7d8f4ecc26db162187f638d061593e198c97c77757f07993c0` |
| `create/encode_uastc/output_R8G8_UNORM.ktx2` | `7ba0de14b4df1ca9ea14c8b60c7a7eca715449f668237908b885365210fa8129` |
| `create/encode_uastc/output_R8_UNORM.ktx2` | `37986f8ce541bfd5e4485dac36b919fb91b006e64bab6716b5c913b1600d9f60` |
| `input/ktx2/valid_R8G8_UNORM_2D_UASTC.ktx2` | `318f68b48970fcdf76fbc407bfdc83a8afef6f611382f1283ff8106345b4a5d9` |
| `derived/khr_texture_basisu_uastc_rg.ktx2` | `602fcde544d7bb6c9272bea35f420c9fc9e76e2f7b182d7849dfa5d5bdde8bbd` |
| `deflate/metadata/output_create_R8G8B8A8_SRGB_2D_UASTC_2_RDO_zstd_5.ktx2` | `27484bc9b6e062acf0d6478df1b3ad62f6b6f32b923539c93353e535b572b0e4` |
| `create/compare/output_blze_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2` | `7f13880e79f166815c9adcf2a1a5d0c38976316cb35a6b35a3a540dbb6a1f012` |
| `create/compare/output_uastc_0_psnr_2d_mip_r8g8b8a8_unorm.ktx2` | `4190e313b63aa9f1e6202f81b74db5e59dd2422390b8f6613eb1c1aec1f669e1` |
| `validate/3101/error_InvalidSupercompressionGLTFBU_UASTC_ZLIB.ktx2` | `a6bd1196e6bef3a04376b5bbd1fa58d7e5261777bb11f848d40210f4d0e38eaa` |
| `validate/3103/error_InvalidPixelWidthHeightGLTFBU_bothUnaligned.ktx2` | `143bf285a0c05da1c84fb4214a9a2648367c512bf494926ff6caa0ab4499f99e` |
| `validate/6301/error_IncorrectModelGLTFBU_ASTC.ktx2` | `533b6432785b74041574e347331319fa31d2f06518fd542cf9ce95f1ab155820` |
| `validate/6303/error_InvalidChannelGLTFBU_ETC1S_GGG.ktx2` | `b104eb266c54a68f3662aa64ff4aff9937b1ed39221e55dfd5f0253af6dd6b4c` |
| `validate/6303/error_InvalidChannelGLTFBU_UASTC_RRRG.ktx2` | `6d1a2793dc9c9449ee70f1ec8d497f981a1bd1826adaec871fcbadeaf995cef5` |
| `validate/6304/error_InvalidColorSpaceGLTFBU_ETC1S_ADOBERGB.ktx2` | `3fbe6a10172a8c46c361543e1aa9e50647e7626186823102bc40a8b47a39e5bb` |
| `validate/6304/error_InvalidColorSpaceGLTFBU_ETC1S_BT709_LINEAR.ktx2` | `8431d2170653b6deebe5e859711311ba2ea0ba48d9b804a8fab8767dd0c18412` |
| `validate/7201/error_KTXswizzleInvalidGLTFBU_ETC1S_bgra.ktx2` | `f2daa2bd66b03694f021ff0222e58722ff58b1e245d6a664cbaceafde012e986` |
| `validate/7202/error_KTXorientationInvalidGLTFBU_ETC1S_lu.ktx2` | `56e3bf9dc4e8da3c4774b3930bae9130375ab8dcd93b79c8fc3adc6bd4b60f39` |

`tools/derive_basisu_uastc_rg_fixture.py` verifies the exact official source,
the two source DFD fields, the exact changed-byte offsets, and the derived
SHA-256 before writing or checking the derived fixture. The fetch script runs
that derivation after verifying the official source hash.
