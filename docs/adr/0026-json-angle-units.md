# JSON angles are degrees with a `_deg` suffix

Every angle in a scenario, `state.json`, and `report.json` is in degrees. Every
angle key ends in `_deg`. The engine keeps radians and converts once at the
parser and the state serializer.

## Why

- The boundary grew by accident. `sun` was added for the real 0.53 degree disk
  and spoke degrees. `camera` was a thin override over `renderer.Camera` and
  spoke radians. `face` inherited the player's radians, while `editor` yaw and
  rotate inherited the editor's degrees.
- A user passed `azimuth: 0.9` expecting radians. The harness accepted it as
  0.9 degrees because 0.9 is a valid angle. Nothing warned.
- The docs stated state units and omitted command units. The same `yaw` key
  meant radians in one object and degrees in another.
- The scenario and the report are evidence that a person reads. Degrees are the
  readable unit for a sun, a field of view, and an editor rotation. Radians are
  a machine unit and belong inside the engine.

## Decisions

- **Degrees at the boundary.** Commands and state use `azimuth_deg`,
  `elevation_deg`, `diameter_deg`, `yaw_deg`, `pitch_deg`, `fov_deg`, and
  `angular_diameter_deg`.
- **Radians inside.** `renderer.Camera`, `Player`, `Debug_Camera`, and the sun
  direction stay in radians. No engine struct gains a `_deg` field.
- **One conversion per direction.** The parser converts command degrees to
  radians. `session_camera` and `sun_state` convert radians to degrees for the
  report.
- **Internal field names state their unit when they mix.** `Place_Object.yaw`
  became `yaw_rad`, `Placement_Set_Yaw.yaw` became `yaw_deg`, and
  `Object_Spawn.yaw` became `yaw_rad`.

## Consequences

- A scenario cannot silently mean the wrong unit. The key and the value agree.
- Scenario files and checks changed once. Backwards compatibility is not kept.
- `record` writes degrees. `look` deltas stay pixels and `turn`/`wheel` stay
  step counts, because they are inputs, not angles.
- The next angle field must follow the same suffix rule or it fails review.
