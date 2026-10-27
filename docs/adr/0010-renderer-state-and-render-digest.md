# Renderer state and render digest

The harness reports the renderer beside the simulation. `state.json` carries a `renderer` object and a `render_digest`. `report.json` carries a `setup` block. The simulation digest keeps a separate meaning and field set.

## Why

A simulation digest cannot tell two renders apart. It does not see the camera override, jitter, TAA history, clip height, or overlay flags. Two runs with the same player state can therefore draw different pixels. The renderer owns those values, so the harness asks it for a report instead of guessing.

## Decisions

- One `Render_Input` carries the effective inputs. The frame builder fills the camera, boxes, lights, debug lines, HUD, and view flags. The recorder fills the extent, jitter, applied atlas weight, and clip height. Uniform packing and the digest read that value.
- `renderer` holds the frame count, TAA state, jitter index, history validity, convergence frames, history read index, history weight, reset count and reason, active point-light count, cluster overflow, and applied atlas weight.
- `render_digest` is FNV-1a over the target extent, camera, boxes, emissive strengths, point lights, jitter, atlas weight, clip height, and view flags.
- `RENDER_DIGEST_FIELDS` has one row per input field. `hud` and `debug_lines` are unhashed because they draw after the resolve. A reflection test fails when a field has no row.
- `Renderer_Report` and its nested `Debug_Report` supply the JSON tags. The state schema resolves `renderer.*` from the same struct.
- `history_weight` is `count / (count + 1)` from the convergence counter.
- `setup` holds the target, extent, build revision and dirty flag, view flags, device, frames in flight, and TAA caps.
- Render fields never enter the simulation digest.

## Consequences

- A check can assert render inputs without a capture.
- A capture-free run reports `renderer.active = false` and an empty digest.
- The digest includes extent and aspect, so two sizes with one camera do not share a digest.
- Reset reasons make each history reset attributable.
