# Bake inputs are authored, not edited at runtime

A bake input is an arena box, a placed static body, or a static fixture. The
runtime editor does not move, rotate, delete, duplicate, flip, or place one. A
bake input is changed in the scene source or through the harness `scene`/`place`
command, then the bake is published. Dynamic bodies and dynamic lamps remain
editable at runtime.

## Why

- The bake key hashes the canonical static boxes, the active static fixtures,
  the quality, and the tool version. Any runtime change to one of those inputs
  makes the artifact stale. The slot key also hashes the box transform, so a
  moved static box loses its tile and falls back to direct light even before the
  next bake.
- The glossary already says a static placed object never moves. The editor's
  move, rotate, delete, duplicate, body-flip, lamp-kind, and placement paths did
  not check the body mode, so the runtime could create that stale state. The
  rule now matches the documented model.
- Static lighting is authored once and baked. Moving a static fixture or a
  static box at runtime is the same kind of change as moving the arena geometry:
  it needs a new artifact, not a live edit.
- Dynamic objects are a different class. They are not bake inputs, they can move
  under physics, and they read the probe field. Refusing their edits would
  remove the editor's actual runtime job.

## Decisions

- **Runtime guard.** The editor refuses move, rotate, delete, duplicate, body
  flip, lamp-kind flip, light edits, and static placement for a bake input. The
  drag, wheel, pointer, keyboard, and harness `editor` paths share the guard. The refusal is
  `bake inputs are authored, not created or edited at runtime`.
- **Creation is guarded too.** A runtime placement cannot create a static body
  or a static fixture. A body conversion cannot create a static body, and a lamp
  kind change cannot create a static fixture.
- **Authoring path.** The scene source and the harness `scene`/`place` commands
  may create or change static objects; `bake` republishes the artifact. The
  `place` command is an authoring command, not the debug editor.
- **Dynamic edits.** Dynamic bodies can be moved, rotated, deleted, duplicated,
  and placed. Dynamic lamps can change colour, intensity, and range. Their body
  mode and lamp kind are authoring properties.
- **Undo/redo.** Static edits never enter the history, and the authoring
  `place`/`remove`/`scene` commands clear it. An undo cannot cross a static input
  change.
- **Slot-key fallback.** The slot key keeps the transform check. A mismatch
  between an authored box and the loaded artifact still falls back to direct
  light instead of sampling a chart baked for another position. The fallback is
  a data-integrity guard, not a runtime editing path.

## Considered options

- **Auto-flip a static object to dynamic and mark the bake stale.** Rejected.
  It makes a runtime edit look like a supported workflow and blurs the two
  classes the bake depends on.
- **Allow the move and rebake automatically.** Rejected. A bake takes seconds
  and blocks the runtime; hiding that cost makes the stale state invisible.
- **Keep the direct-only fallback and allow the move.** Rejected. The fallback
  is a safety net, not a licence to edit a bake input.
- **Refuse dynamic edits too.** Rejected. Dynamic objects are not bake inputs;
  the editor exists to move them.

## Consequences

- A static scene is authored in the source or the harness, then baked. The
  debug editor cannot create or change a bake input.
- A runtime attempt to edit a bake input returns an explicit error; the object
  and the artifact stay unchanged.
- The initial arena and the initial static fixtures are read-only in debug mode.
  Their light settings and transforms are source data.
- The `bake-static-move` evidence authors a replacement with `remove`/`place`
  and republishes; the runtime refusal is surfaced by the harness editor error.
