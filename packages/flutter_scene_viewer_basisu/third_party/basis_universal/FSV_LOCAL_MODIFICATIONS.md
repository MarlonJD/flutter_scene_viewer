# Basis Universal local modifications

The vendored Basis Universal decoder is based on the official
`BinomialLLC/basis_universal` commit
`882abb5320400ab650c1be33f9152e4955e83af3` under Apache-2.0.

Upstream source identity:

- path: `transcoder/basisu_transcoder.cpp`;
- official URL: `https://raw.githubusercontent.com/BinomialLLC/basis_universal/882abb5320400ab650c1be33f9152e4955e83af3/transcoder/basisu_transcoder.cpp`;
- SHA-256: `27fda5a2330831704a7adcf254b852c6df5081258dcc1e42283a936030b6f01f`.

Vendored source identity:

- path: `transcoder/basisu_transcoder.cpp`;
- SHA-256: `e7af01b01b33dbcfbbda9b9365be308347ee45e87b7fbd7bf65cd215b1e07ba5`.

## Modified hunk

`ktx2_transcoder::init()` has one local functional change immediately after
the existing 2D-texture dimension check. It rejects a KTX2 whose width or
height exceeds `BASISU_MAX_SUPPORTED_TEXTURE_DIMENSION` before later size and
layout calculations. The source hunk carries this prominent notice:

```text
FSV LOCAL MODIFICATION (Apache-2.0 section 4(b))
```

A separate patch artifact is intentionally omitted because the two exact
source hashes above, the single documented functional hunk, its in-source
notice, and the deterministic `VENDORED_SOURCES.sha256` manifest completely
identify the vendored state without another generated source of truth.

## Verification

From this directory:

```sh
shasum -a 256 -c VENDORED_SOURCES.sha256
```

The manifest covers every one of the 28 tracked files in `transcoder/` and
`zstd/` that form the vendored compile/include source set and its bundled Zstd
license record.
