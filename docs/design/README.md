# Design

The visual direction for the whole game. `docs/ui/` holds the rules for the Rune
overlay. Read this file first, then the topic file for the job.

## The point of view

A flat-shaded box world with direct coloured light, a baked static bounce, and a
Rune overlay drawn by the Rust shim. The player is an eight-legged box spider
with planted feet; its eyes and two abdomen marks are the only self-lit surfaces
that are not lamps. The world is not textured, rounded, blurred, or glossy; the
Rune action buttons are the only rounded edge on screen. Every world surface is
a box and every panel is a rectangle. Colour says what a thing does; it never
decorates. The overlay is a compact readout, not a poster.

Two constraints produce that look, and both are deliberate:

- The scene has one shader and one mesh. Every object is the same unit cube,
  scaled and rotated.
- The overlay is a Rune view. The Rust shim owns the layout, type, colour, and
  hit testing and draws onto the game's target; Odin sends flat data. There is
  no second text stack or overlay pipeline in the Odin tree.

The rune-fx glow is an opt-in demo, off by default. It is not part of the look
and must not become the default.

## The signature

The one choice a competitor cannot paste in: a hard-edged box interior lit by
movable coloured lamps, with soft range falloff on flat faces and a Rune readout
that stays out of the scene's way. Unlit boxes are black; only placed lamps and
emissive boxes start light. Static fixtures bake one diffuse bounce into a
lightmap for static boxes and a probe field for dynamic boxes. Dynamic lamps
contribute direct light and hard shadows only. Hard point-light shadows ground
the props and walls.

Defend it. A surface texture, a gloss, a bloom, a rounded world corner, or a
per-frame GI field removes it. The baked static indirect term is part of the
look; it is not a substitute for the lamps.

## Files

- [world.md](world.md): the scene palette, direct lights, darkness rule,
  geometry rule, and what a new prop must do.
- [motion.md](motion.md): what may move, the smoothing formula, the settle
  times, and the motions that must never exist.
- [review.md](review.md): the ordered check and the evidence rule for a visual
  change.
- [../ui/README.md](../ui/README.md): the Rune overlay, its snapshot, and its
  surfaces.

## What this folder is not

Not a mood board. Not a style guide for another engine. Not a promise of a theme
system: there is one view, and the scene is the backdrop, not the mode.
