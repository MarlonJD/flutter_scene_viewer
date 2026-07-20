# Deterministic sequential Draco fixture

`sequential_quantized_generic.drc` is a deterministic test-only mesh encoded
by `google/draco@1.5.7` source at upstream commit
`8786740086a9f4d83f44aa83badfbea4dce7a1b5`. The source geometry and encoder
options are preserved in `generate_fixture.cc`: two triangles, quantized float
positions, a scalar `uint16` generic attribute, an unquantized scalar `float`
generic attribute, sequential mesh encoding, and compressed sequential
connectivity.

The generator and produced payload are Apache-2.0. The pinned upstream
`LICENSE` SHA-256 is
`d3709b0fb4b8a94bbb1d02b8a2e484f258b0d9c5c5a01f940391f3fe662cd1a4`.
The production checkout is intentionally decoder-pruned, so regeneration uses
the immutable flutter_scene_viewer repository source object
`8794499f9f7e72c1cd64aea7242081a2d1ed5da3`. That project object contains the
pristine vendored payload identified above; it is not an upstream Draco Git
commit. Its deterministic commit-plus-path `git archive --format=tar` SHA-256
is `feded3996b7e9d0d40f6ef51804397083b4f66a786ecfe392f1d04e06f255841`.

Regeneration compiles the fixed archive without enabling encoder code in the
package build. The compile list is every `.cc` below `src/draco`, sorted by
path, except basenames containing `test` and the `javascript`, `tools`, and
`unity` subtrees:

```sh
fixture_source=$(mktemp -d)
git archive --format=tar \
  8794499f9f7e72c1cd64aea7242081a2d1ed5da3 \
  packages/flutter_scene_viewer_draco/third_party/draco | \
  tar -x --strip-components=4 -C "$fixture_source"
clang++ -std=c++17 -I"$fixture_source/src" generate_fixture.cc \
  $(find "$fixture_source/src/draco" -name '*.cc' \
    ! -name '*test*' ! -path '*/javascript/*' ! -path '*/tools/*' \
    ! -path '*/unity/*' | sort) \
  -o "$fixture_source/generate_fixture"
"$fixture_source/generate_fixture" sequential_quantized_generic.drc
```

The generator SHA-256 is
`e651166cac6509017ad8cdb80cc3ed43020229b4f2357c7d8b602fc5caa2bfe8`.
The 132-byte output SHA-256 is
`5113cbc836363cae9a59526d983e12ee95d32cf2f342bf192be7b2fdc2321b33`.
The byte header records Draco bitstream 2.2, triangular mesh geometry, and
`MESH_SEQUENTIAL_ENCODING`. The generator explicitly sets
`compress_connectivity` to `true`.
