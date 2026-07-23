# Core engineering beliefs

| Belief | Why it matters here | Observable implication | Mechanical support |
| --- | --- | --- | --- |
| Preserve glTF assembly identity | Configurators need stable parts rather than flattened anonymous meshes | `nodePath` and `primitiveIndex` remain the public addressing boundary | Part registry, address, picking, and controller tests |
| Adapt the renderer; do not replace it | The package is a product-viewer layer on `flutter_scene` | Unsupported renderer behavior produces diagnostics instead of a second hidden renderer | Adapter isolation, capability policies, and repository lint |
| Asset authoring gaps stay explicit | Invented UVs or silently repaired material data make results irreproducible | Missing requirements become typed diagnostics | GLB reader, texture binding, and material tests |
| Evidence language is literal | Simulator, candidate, release, and production evidence have different risk boundaries | Handoffs use the output-contract labels and never upgrade evidence by inference | Harness gate, plans, and documentation review |
| Prefer bounded deterministic checks | Native decoding and rendering surfaces are expensive and platform-sensitive | Fast fixture tests run before broad suites; target captures stay scoped | Verification matrix and `tools/run_checks.sh` |

Change a belief only when architecture evidence, product outcomes, incidents,
or repeated review friction justify it. Record the rationale in a managed
ExecPlan.
