# Dynamic-only lamps

> Superseded by [ADR 0045](0045-mixed-lighting.md). Lamps now have a kind: a
> static fixture uses a static body and a dynamic lamp uses a dynamic body. The
> body control and the kind always move together. This page records the old
> rule.

Every lamp prefab uses a dynamic body. The Lamp, Light panel, and Beacon cannot become static through placement, palette selection, body conversion, duplication, undo, redo, or scene loading. Non-lamp prefabs keep both body modes.

## Why

A static lamp is a light that cannot follow the simulation. The lighting model promises that each frame reads the current object transform. Allowing static lamps creates a second, apparently fixed light source and breaks the user-facing rule that lighting is always dynamic. Normalizing creation and refusing conversion keeps the rule in the game layer, where every path meets it, instead of repeating checks in the palette, harness, and scene loader.

## Decisions

- `prefab_body_mode` normalizes every spawned lamp to dynamic. This covers exact placement, palette placement, duplication, history restore, and scene loading.
- `prefab_accepts_body` rejects a static body conversion for a lamp. The editor returns `Lamp_Must_Be_Dynamic`.
- The palette body state normalizes a lamp selection to dynamic. Flipping a lamp body fails instead of silently doing nothing.
- The starting arena holds one of each lamp prefab, plus the three crates.

## Consequences

- A scene file or place command may request `static` for a lamp, but the resulting object is dynamic.
- Old scene files with static lamps still load. They become dynamic before the first frame.
- Creation, conversion, palette rejection, and initial light movement follow the same rule. The place, scene, and editor paths agree.
- The starting lamps respond to their bodies.
