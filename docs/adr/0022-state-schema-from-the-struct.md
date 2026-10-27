# The state schema is the State struct

The harness state document, the check paths, and the simulation digest read the
`State` struct and its tags. There is no second field table and no hand-written
leaf resolver.

## Why

The state document had four descriptions: the build, the JSON tags, 596 lines of
check resolvers, and the digest field list. A new field needed a build edit, a
tag, a resolver case, a digest line, and often a doc line. The copies drifted:
the old top-level table had ten objects, but every leaf still needed its own
case.

The struct already names every field and its JSON name. A reflection walk can
resolve a check path against the same value the JSON writer emits, and a second
walk can hash the same fields. The only policy the walk needs is a way to keep a
render-only field out of the simulation digest.

## Decisions

- `State` and its `json` tags are the schema. `state_schema.odin` walks the
  struct, the nested objects, the slices, and the arrays. A path segment is the
  JSON name; a slice segment is an index. `objects.<id>` is the one special
  case, because the document addresses objects by id; `objects.count` is the
  other.
- `state_build_sections` builds only the sections a check names. `state_build`
  is the full document. `digest` is the only check that asks for every section.
- `state_build_sections` is pure: the HUD and menu update happens in
  `session_refresh_hud` before the build, not inside it.
- `digest:"-"` excludes a field from the simulation digest. The camera, debug
  state, rows, settle, renderer, render digests, object scale and spawn age,
  menu status/item/blocked are excluded. The digest covers the frame, the
  player, the objects, the settings, and the menu open/selected fields.
- The JSON names come from the same tags. The reply envelope stays hand-written
  because `json.marshal` does not dereference a pointer to a struct; the state
  itself is marshaled by value.

## Consequences

- A new state field is one struct field, one build line, and a `digest:"-"`
  only when it is render-only. The JSON, check, and digest see it.
- The digest changes once because it now walks struct order and includes every
  untagged field. The state digests in old runs are not comparable with new
  runs; the scenarios pin checks, not digest values.
- `tests/harness/schema.odin` walks every leaf of the `State` type and resolves
  it, so a field without a working path fails the suite.
- The old `state_fields.odin`, `state_field_leaves.odin`,
  `state_debug_fields.odin`, `state_renderer.odin`, and `check_objects.odin` are
  gone.
