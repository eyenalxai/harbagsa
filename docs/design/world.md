# The world

One shader over one mesh. `src/renderer/shaders/box.frag` shades a unit cube,
and every object in the scene is that cube, scaled and rotated. There is no
texture, normal map, fog, bloom, or tone map. One directional sun casts
ray-query shadows.

## The palette

Colours are authored as linear RGBA floats, because the renderer shades in linear
space. This is the opposite of the 2D layer, which authors sRGB hex
([colour.md](../ui/colour.md)). Do not copy a value between the two tables.

| Surface | Linear RGBA | Source |
| --- | --- | --- |
| Sky | `0.10 0.45 0.75` | `src/renderer/renderer.odin:18` |
| Floor | `0.42 0.43 0.46` | `src/game/arena.odin:29` |
| Wall | `0.55 0.34 0.26` | `src/game/arena.odin:30` |
| Stairs, ramps, steps | `0.30 0.55 0.85` | `src/game/arena_props.odin:86` |
| Tunnel | `0.85 0.50 0.20` | `src/game/arena_props.odin:87` |
| Dive set | `0.25 0.75 0.40` | `src/game/arena_props.odin:88` |
| Slide lane | `0.90 0.80 0.20` | `src/game/arena_props.odin:89` |
| Mantle wall | `0.60 0.35 0.80` | `src/game/arena_props.odin:90` |
| Crate, green | `0.30 0.68 0.38` | `src/game/arena.odin:32` |
| Crate, orange | `0.86 0.56 0.20` | `src/game/arena.odin:33` |
| Crate, blue | `0.26 0.48 0.84` | `src/game/arena.odin:34` |
| Sun light | `1.00 0.98 0.94` | `src/renderer/shaders/box.frag:32` |
| Ambient | `0.24 0.25 0.28` | `src/renderer/scene.odin:20` |
| Debug selection | `1.00 0.80 0.20` | `src/game/debug_draw_crates.odin:6` |

Rules:

- A new arena feature takes a hue that is not already in use. The arena carries
  seven, and the hue is how a player names the feature.
- Crates use their own high-chroma palette, never a wall hue, so a pushed crate
  reads against every surface.
- The debug selection amber is `1.00 0.80 0.20` in linear space. The UI accent is
  `#E6AF3A` in sRGB. They are different colours in different spaces. Keep both
  values. Do not merge them into one token.

## One sun

The sun is one directional light. Its angular diameter is a scene input, not a
renderer constant: it defaults to the real 0.53°
(`src/game/debug_mode.odin:11`) and the harness `sun` command can change it. A
wider disk widens every penumbra, so the shadow stops reading as a shadow. The
shader takes 16 samples on a Vogel disk, so a penumbra has 17 levels and softens
with blocker distance.

The sun is the only light with a direction. Ambient is one flat value, not a
hemisphere and not occluded. The whole shading line is:

```text
albedo * (ambient + diffuse * sun * visibility)
```

If a surface must look different, change its albedo. Do not add a lighting term.

## No texture

There is no sampler in the scene shader. A face is one flat colour with one
constant normal. No smooth shading exists anywhere in the 3D scene, and no
material distinguishes one box from another except its colour.

## The sky

The sky is the clear colour, not a shader. `DEFAULT_CLEAR_COLOR` is
`(0.10, 0.45, 0.75)`, written linear into an RGBA16F target. The sRGB attachment
encodes it to about `#59B3E1`. There is no gradient, skybox, or cloud.

The sky is the only large field of one colour in the frame. Do not give it a
gradient; the penumbra already provides the only soft edge.

## Geometry

- Every shape is a box. A ramp is a thin box rotated about X.
- No rounded, bevelled, or non-box primitive. A curve in the world would be the
  only curve on screen.
- The arena is 40 m square with 4 m walls: 51 static boxes and 3 crates at
  spawn. The floor is 1 m thick, the walls 0.5 m, and a crate 1 m.
- The player has no body and casts no shadow.
- No fog and no depth cue beyond perspective. The near plane is 0.05 m and the
  far plane 200 m.

## What a new prop must do

1. Be a box.
2. Take a hue that is not in the palette.
3. Cast and receive the same sun shadow as everything else.
4. Add nothing to the shader.
5. If it moves, add nothing to the camera. [motion.md](motion.md) explains why.
