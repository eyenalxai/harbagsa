# Gated renderer debug overrides

The harness can change renderer inputs: TAA on or off, jitter, history
weight, clamp, depth trust, the shadow phase, the sky, ambient occlusion,
point-light shadows, and a synthetic light count. The command is
diagnostic. A build with `ENABLE_RENDERER_DEBUG=true`, or a run with
`--debug-renderer`, accepts it. Every other build rejects it with an error
that names both gates.

## Why

The TAA investigation changed one input at a time and compared the result. Each
change meant a source edit and a rebuild, or a shader patch. A gated command
turns the causal matrix into a scenario, which is repeatable and recorded.

The overrides must not become a product feature. A player must not be able to
turn off the clamp or freeze the sun phase in a shipped build, and a release
must not carry a reachable code path that does. A compile-time define keeps the
surface out of a release; the runtime flag lets the debug harness binary use it
without a second build.

## Decisions

- `Renderer_Debug` holds the override values. `active` is false by default, so
  the renderer ignores every field until the command sets it.
- A command is a sparse `Renderer_Debug_Patch`, not a second override struct.
  One table lists each key, its type, and its range. A `null` value adds that
  field to the reset set. The scene snapshot, the command parser, the schema, and
  the reset path read the same patch and table.
- A scene snapshot writes every effective override field, including `gi`, so a
  repro restores the exact debug state. `history_weight` stays out of a snapshot
  when it is automatic, because there is no fixed value to restore.
- A first command copies the current effective state into the patch, so an
  omitted field keeps its value.
- A change to the override resets the history with reason `debug_override`. The
  shadow phase is included: a new phase changes the sun samples the resolve
  averages, so the old history no longer describes the same input. A light
  change resets for the same reason: the new light contribution differs from
  the image the history holds.
- `clear` restores the defaults and turns TAA, the sky, and the ambient
  occlusion on. A scenario can therefore end in the product configuration
  regardless of the path it took.
- `light_shadows` disables the point-light shadow rays without removing the
  light contribution, so the shadow cost is measurable on its own.
- `synthetic_lights` replaces the frame's light list with 0 to 8 fixed test
  lights, so the point-light cost is measurable without placing lamps.
- `sky` turns the sky pass on or off. The sky is a background, not a light.
  `ao` turns the occlusion rays on or off; they scale the sun and the point
  lights, so the contact term can be measured apart from the direct light.
  `ao_radius` and `ao_strength` tune the same term without a rebuild.
- `clip_height` discards fragments above a world height, so a top-down camera
  can read a plan through the roof. The discard needs the Vulkan 1.3 shader
  demote feature, which the device check requires and the logical device enables.
- The resolve takes the overrides as push constants. A fixed weight replaces
  `count / (count + 1)`; a flag skips the clamp; a flag forces the depth trust.
- The renderer report carries the override struct, so a scenario asserts the
  inputs as well as the image.

## Considered Options

- **Source edits per probe**: exact, but slow and not repeatable. A scenario is
  the unit the investigation needs.
- **Only a build define**: no runtime cost, but every probe needs a rebuild.
- **Only a runtime flag**: simple, but a release build would carry a reachable
  path that changes TAA behavior.
- **A separate debug renderer binary**: two renderers to keep in step. A gate on
  one renderer is smaller.

## Consequences

- The default `make build` agent rejects the command. Use `--debug-renderer`
  or add `-define:ENABLE_RENDERER_DEBUG=true`.
- The shader has three more push constants. A push constant update is already
  one call per resolve.
- The clear path resets the history. A scenario that uses the command and then
  measures pixels must account for the reset.
- `scenarios/perf-lamps.json` uses the synthetic lights and the shadow switch to
  report the paired point-light shadow cost.
