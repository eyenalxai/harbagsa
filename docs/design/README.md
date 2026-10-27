# Design

The visual direction for the whole game. `docs/ui/` holds the rules for the 2D
layer. Read this file first, then the topic file for the job.

## The point of view

A flat-shaded box world with direct coloured light and overlay text drawn at the
exact size of its pixels. Nothing is textured, rounded, blurred, or glossy.
Every surface is a box and every panel is square. Colour says what a thing does;
it never decorates. The type carries the personality, because nothing else does.

Two constraints produce that look, and both are deliberate:

- The scene has one shader and one mesh. Every object is the same unit cube,
  scaled and rotated.
- The overlay rasterizes text at the device pixel size from a coverage atlas
  built from variable Geist and Geist Mono, not from a distance field. ADR 0007
  records why.

## The signature

The one choice a competitor cannot paste in: a hard-edged box interior lit by
movable coloured lamps, with soft range falloff on flat faces and overlay text
that is exact on the pixel grid. A small ambient floor keeps unlit colour
readable. Hard point-light shadows ground the props and walls. No cached lighting
competes with the lamps.

Defend it. A texture, a gloss, a bloom, a baked light, or a rounded corner
removes it.

## Files

- [world.md](world.md): the scene palette, direct lights, ambient floor,
  geometry rule, and what a new prop must do.
- [motion.md](motion.md): what may move, the smoothing formula, the settle
  times, and the motions that must never exist.
- [review.md](review.md): the ordered check and the evidence rule for a visual
  change.
- [../ui/README.md](../ui/README.md): the 2D layer, its tokens, and its rows.

## What this folder is not

Not a mood board. Not a style guide for another engine. Not a promise of a theme
system: there is one theme, and the scene is the backdrop, not the mode.
