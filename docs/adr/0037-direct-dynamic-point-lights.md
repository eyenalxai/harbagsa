# Direct dynamic point lights

> Shadow visibility is added by [ADR 0040](0040-hard-point-light-shadows.md). The ambient floor is removed by [ADR 0041](0041-absolute-darkness.md). One-bounce indirect light is added by [ADR 0042](0042-single-volume-ddgi.md). The no-shadow, no-indirect, and ambient-floor statements in this decision describe the state at the time.

The renderer uses one direct-light model: a constant ambient floor, current point lights, and emissive boxes. It has no directional light, background pass, shadow visibility term, indirect light cache, or ray-traced reference. This supersedes every earlier lighting decision that required those systems.

## Considered Options

- **Ray-query direct and indirect lighting**: rejects the product goal. The acceleration structures, probe updates, visibility sampling, leak controls, and reference estimator cost more maintenance than the desired look needs.
- **Baked or static lighting**: rejected. Every point-light contribution must follow the current object transform and light settings.
- **No ambient term**: rejected. A surface outside every lamp range still needs readable albedo. The ambient floor supplies that readability without claiming to be global illumination.

## Consequences

- Clustered forward+ remains. The pass order is cluster assignment, depth prepass, lit scene, TAA resolve, and overlay.
- A point light uses its normal and range terms without a visibility term. Light can cross a wall. This is an accepted rendering simplification, not a leak to fix with a new visibility system.
- The renderer needs Vulkan 1.3 dynamic rendering and shader demote. It does not need acceleration structures, ray queries, buffer device addresses, or deferred host operations.
- Harness state, snapshots, scenarios, and performance reports expose only the remaining renderer inputs and passes. Removed commands and fields have no compatibility aliases.
- A lamp-free view stays black, and a light transform change moves the image and the digest.
