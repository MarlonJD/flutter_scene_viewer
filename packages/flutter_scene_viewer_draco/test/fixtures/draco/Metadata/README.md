# Deterministic Draco metadata fixture

`metadata_nested_blob.drc` is a deterministic test-only triangular mesh encoded
by `google/draco@1.5.7` source at upstream commit
`8786740086a9f4d83f44aa83badfbea4dce7a1b5`. It contains geometry metadata,
attribute metadata, two nested metadata levels, 120-byte names, and a
deterministic 4096-byte binary entry.

The generator and payload are Apache-2.0. The pinned upstream `LICENSE`
SHA-256 is
`d3709b0fb4b8a94bbb1d02b8a2e484f258b0d9c5c5a01f940391f3fe662cd1a4`.
Offline regeneration uses immutable flutter_scene_viewer source object
`8794499f9f7e72c1cd64aea7242081a2d1ed5da3`, which contains the pristine
vendored source for upstream Draco commit
`8786740086a9f4d83f44aa83badfbea4dce7a1b5`. Its deterministic fixed-path
`git archive --format=tar` SHA-256 is
`feded3996b7e9d0d40f6ef51804397083b4f66a786ecfe392f1d04e06f255841`.

Regeneration is offline and uses the same fixed archive and sorted source list
as the sequential fixture. The executable package test compiles this generator,
regenerates the payload, and requires byte equality with the checked-in bytes.

Generator SHA-256:
`198ff16d02f08e2dd4eedf62adbf7d2a6de2b6eed52cc2939a791d37b4c33aba`.

The 5332-byte payload SHA-256 is
`cc5e86aaaf9876274d773d7b71a9cdf85e263a6f50de91e842188a3cf9b922c6`.
