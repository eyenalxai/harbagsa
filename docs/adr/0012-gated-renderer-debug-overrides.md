# Gated renderer debug overrides

The harness can change renderer inputs: TAA, jitter, history weight, clamp, depth trust, synthetic light count, plan-view clip height, shadow rays, the static lightmap, and the probe field. A build with `ENABLE_RENDERER_DEBUG=true`, or a run with `--debug-renderer`, accepts the command. Every other build rejects it.

## Why

Renderer investigation needs one input changed at a time without a source edit and rebuild. The overrides are diagnostic, not player settings. Compile-time and runtime gates keep them out of normal play.

## Decisions

- `Renderer_Debug` holds the values. `active` is false by default.
- A command is a sparse `Renderer_Debug_Patch`. One table lists each key, type, and range. A `null` value restores that field's default.
- The scene snapshot, command parser, schema, and reset path share the patch and table.
- A snapshot writes every effective field. Automatic history weight stays out because it has no fixed value to restore.
- An omitted field keeps its live value. Every effective change resets TAA history with reason `debug_override`.
- `clear` restores the product defaults.
- `synthetic_lights` replaces the frame's light list with a generated field of any requested count.
- `clip_height` discards fragments above a world height for plan views. It needs the Vulkan 1.3 shader demote feature.
- The resolve takes its overrides as push constants. The renderer report exposes every override.

## Consequences

- The default agent rejects the command unless the scenario declares the gate or the user passes `--debug-renderer`.
- Synthetic lights measure direct point-light cost.
- Removed lighting systems have no override fields and no compatibility aliases.
