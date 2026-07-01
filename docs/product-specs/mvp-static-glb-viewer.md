# MVP static GLB viewer

## User story

As a Flutter developer, I want to load a GLB from a URL and let users inspect
parts and change core PBR materials without using WebView.

## Acceptance criteria

- loads GLB from bytes/assets/network;
- displays a loading/error state;
- fits camera to model bounds;
- builds a part tree from nodes;
- taps return a stable part address;
- can set/reset base-color texture, metallic, roughness, and visibility;
- records diagnostics for missing UVs and unsupported material features;
- stops rendering when idle under adaptive policy.
