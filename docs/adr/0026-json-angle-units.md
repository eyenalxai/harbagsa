# JSON angles are degrees with a `_deg` suffix

Every angle in a scenario, `state.json`, and `report.json` is in degrees. Every angle key ends in `_deg`. The engine keeps radians and converts once at the parser and state serializer.

## Why

- The boundary grew through different APIs. Camera overrides used radians, player facing inherited radians, and editor yaw and rotation used degrees.
- A numeric angle without a unit accepts a valid but wrong value without warning.
- Scenario files and reports are evidence that a person reads. Degrees are readable for a field of view and an editor rotation. Radians belong inside the engine.

## Decisions

- **Degrees at the boundary.** Commands and state use `yaw_deg`, `pitch_deg`, `fov_deg`, and `rotate_deg`.
- **Radians inside.** `renderer.Camera`, `Player`, and `Debug_Camera` stay in radians. No engine struct gains a `_deg` field.
- **One conversion per direction.** The parser converts command degrees to radians. State serialization converts radians to degrees.
- **Internal field names state their unit when they mix.** Placement and spawn data use `yaw_rad`; editor actions use `yaw_deg`.

## Consequences

- A scenario cannot silently mean the wrong unit. The key and value agree.
- `record` writes degrees. `look` deltas stay pixels and `turn`/`wheel` stay step counts because they are inputs, not angles.
- The next angle field must follow the same suffix rule.
