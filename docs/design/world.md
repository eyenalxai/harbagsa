# The world

One shader over one mesh. `src/renderer/shaders/box.frag` shades a unit cube,
and every object in the scene is that cube, scaled and rotated. There is no
surface texture, normal map, fog, bloom, or tone map. Point lights supply direct
light; a lighting-only lightmap and baked probe volume supply static indirect.

## The palette

Colours are authored as linear RGBA floats, because the renderer shades in linear
space. This is the opposite of the 2D layer, which authors sRGB hex
([colour.md](../ui/colour.md)). Do not copy a value between the two tables.

| Surface | Linear RGBA | Source |
| --- | --- | --- |
| Clear colour | `0.012 0.016 0.024` | `src/renderer/renderer.odin` |
| Floor | `0.42 0.43 0.46` | `src/game/arena.odin` |
| Wall | `0.55 0.34 0.26` | `src/game/arena.odin` |
| Stairs, ramps, steps | `0.30 0.55 0.85` | `src/game/arena_props.odin` |
| Tunnel | `0.85 0.50 0.20` | `src/game/arena_props.odin` |
| High platform set | `0.25 0.75 0.40` | `src/game/arena_props.odin` |
| Slide lane | `0.90 0.80 0.20` | `src/game/arena_props.odin` |
| West wall | `0.60 0.35 0.80` | `src/game/arena_props.odin` |
| Ceiling | `0.20 0.23 0.27` | `src/game/arena.odin` |
| Crate, green | `0.30 0.68 0.38` | `src/game/prefabs.odin` |
| Crate, orange | `0.86 0.56 0.20` | `src/game/prefabs.odin` |
| Crate, blue | `0.26 0.48 0.84` | `src/game/prefabs.odin` |
| Debug selection | `1.00 0.80 0.20` | `src/game/debug_draw_objects.odin` |
| Spider body | `0.30 0.10 0.13` | `src/game/spider.odin` |
| Spider legs | `0.20 0.07 0.09` | `src/game/spider.odin` |
| Spider markings | `0.90 0.42 0.10`, emissive 0.55 | `src/game/spider.odin` |
| Spider eyes | `1.00 0.62 0.16`, emissive 2.4 | `src/game/spider.odin` |

Rules:

- A new arena feature takes a hue that is not already in use. The hue is how a
  player names the feature.
- Crates use their own high-chroma palette, never a wall hue, so a pushed crate
  reads against every surface.
- The debug selection amber is `1.00 0.80 0.20` in linear space. The UI accent is
  `#E6AF3A` in sRGB. They are different colours in different spaces. Keep both
  values. Do not merge them into one token.
- The spider owns the red family. No arena surface uses it, so the player never
  reads as a prop. Its four eyes and two abdomen markings are the only emissive
  surfaces that are not lamp prefabs: the eyes read at the front, and two bars on
  the abdomen carry the silhouette from behind. They use the direct, baked probe,
  and emissive self terms like any dynamic box, but they do not join the lamp
  budget and they never enter the bake. Do not add a player light; it would break
  the darkness rule.

## Direct light

Every active lamp contributes from its current transform. The clustered forward+
pass assigns each light to the camera clusters its range overlaps. The lit pass
then shades only the lights that can reach the fragment.

The formula is:

```text
static box:  albedo * (direct_point_lights + lightmap_indirect) + albedo * emissive
dynamic box: albedo * (direct_point_lights + probe_indirect)    + albedo * emissive
```

A surface receives no light unless a current point light reaches it, a baked
static bounce reaches it, or the surface is emissive. A lamp-free view is black.
There is no ambient floor or fill light; the baked layer is transport, not a
default term, and it contains no dynamic lamp.

A point light uses the surface normal and a squared range falloff. A hard shadow
ray also tests visibility for each lamp that can reach the fragment. A blocked
lamp contributes zero. The lamp has no radius, so the shadow edge is hard. The
lit pass traces against the same cube TLAS as the rest of the scene. The ray
starts just above the surface, stops just short of the lamp, and excludes lamp
boxes. This keeps a wall-mounted lamp from shading the wall it sits on.

There is no shadow map, soft-shadow sampling, or screen-space visibility pass.
The `light_shadows` renderer override exists only for paired captures and
performance runs. It is not a per-lamp editor control. A future lamp radius or
soft shadow is a new decision, not a hidden shader option.

## Indirect light

The indirect term is baked once from static inputs: the arena boxes, placed
static bodies, static fixtures, static emissive boxes, and the quality block.
Dynamic crates, the spider, dynamic lamps, the camera, TAA, and the UI never
enter the bake.

A static box owns one lightmap slot and six center-to-center face rects in a
1024 square `RGBA16F` atlas. The lit pass derives the face and UV from the local
position and local face normal; there is no vertex UV channel. The 4 texel/m
charts have an 8 x 8 minimum and a 4-texel dilated gutter.

A dynamic box samples four probes of the containing tetrahedron. The volume is
1 m by default and 2 m through the artifact quality block. The gather applies
the stored validity flag, a 0.1 x spacing normal bias, the facing weight, and
the first/second moment Chebyshev test. Invalid probes are dilated from valid
neighbours within two cells at load; a probe with no valid neighbour is skipped.

The bake key hashes the static boxes, static fixtures, quality, and tool
version. A static edit changes the key and reports `stale`; the old indirect
stays bound until a publish. A dynamic edit never changes the key. `make bake`
writes the artifact; the harness `bake reload` publishes an artifact built
while the process runs, and `bake publish` rebuilds and publishes from the
current static input. A missing or failed artifact reports its state and adds no
indirect; it never invents a fill.

The `lightmap` and `probes` renderer overrides, both default true, exist for
paired captures and performance runs. They are not per-lamp or per-room
controls. A denser grid, more rays, more bounces, or a runtime rebake is a new
decision, not a hidden shader option.

A lamp kind is part of the lamp settings. A static fixture has a static body;
a dynamic lamp has a dynamic body. The editor's body control switches the kind
with the body. The starting arena places one warm Lamp, one cool Light panel,
and one red Beacon as static fixtures in front of the spawn. New lamps default
to dynamic.

A lamp-free view with a current empty bake is black. One static fixture restores
readable direct light and its baked bounce. Moving a dynamic lamp moves its
direct light and shadow only. A sealed wall stops the bounce.

## No material texture

There is no surface sampler and no UV channel. A face is one flat colour with
one constant normal. The lightmap and probe samplers carry lighting data only;
they do not distinguish one material from another. No smooth shading exists
anywhere in the 3D scene, and no material distinguishes one box from another
except its colour and light.

## Clear colour

The clear colour is constant. It fills only a pixel that no box covers. It is not
a background pass and not a light source. A closed interior should cover it in
normal play. Plan-view and inspection captures can still expose it.

## Geometry

- Every shape is a box. A ramp is a thin box rotated about X.
- No rounded, bevelled, or non-box primitive. A curve in the world would be the
  only curve on screen.
- The arena is 40 m square with 5.5 m walls and a solid ceiling. The floor is 1 m
  thick, the walls and ceiling 0.5 m, and a crate 1 m. The ceiling spans the
  outer wall faces, so the shell has no gap.
- The arena is one closed box. There is no interior room and no path to a
  background.
- The player has no body.
- No fog and no depth cue beyond perspective and lamp range. The near plane is
  0.05 m and the far plane 200 m.

## What a new prop must do

1. Be a box.
2. Take a hue that is not in the palette.
3. Receive the same direct point lights and shadows as everything else, plus a
   static lightmap tile when it is static and probe sampling when it is dynamic.
4. Add nothing to the shader.
5. If it moves, add nothing to the camera. [motion.md](motion.md) explains why.
