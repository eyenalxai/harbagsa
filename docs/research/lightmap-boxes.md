# Lightmap atlas and bake math for box geometry

Status: research for #372. No renderer code changes. This note assumes the
mixed-lighting model from `docs/research/mixed-lighting.md`: direct light and
hard shadows stay real-time, static fixtures bake their indirect bounce, and
dynamic lamps do not bounce.

## Bottom line

Use a **single 2D atlas of indirect-only light**, one tile per static box face:

- Derive the face UV in the fragment shader from local position and the local
  face normal. Do not add a UV channel or change the cube vertex layout.
- Give every static box six charts, one per face, and every instance its own
  tile. Indirect light is position-dependent, so two boxes cannot share a tile
  unless they are at the same place.
- Store a per-face **center-to-center UV rect** in a side storage buffer and put
  a slot index in `Object_Data`. Dynamic boxes get an invalid slot and read the
  baked probe field instead.
- Bake at **4 texels/m** by default, with an 8 x 8 minimum chart, a 4-texel
  dilated gutter, bilinear filtering, clamped UVs, and no mips.
- Store linear `R16G16B16A16_SFLOAT` first. Add BC6H only after the float path
  is clean and memory is measured; do not start with LDR/RGBM.
- Bake one bounce from static fixtures and static emissive boxes in a
  static-only TLAS. Do not bake direct light, direct shadows, or ambient
  occlusion.

## Fit for the current renderer

| Current fact | Consequence for the lightmap |
| --- | --- |
| `Vertex` is position + normal, 24 bytes; 24 vertices, four per face (`src/renderer/mesh.odin:6-14`) | Every face has its own normal. A face chart is natural; no shared-vertex UV problem. |
| `box.vert` already emits `v_local_position` and a world normal (`src/renderer/shaders/box.vert:29-36`) | The fragment shader can derive a face UV from local position and a flat local normal. No vertex attribute change. |
| `box.frag` shades `v_color * lit + v_color * object.color.a` with no sampler (`src/renderer/shaders/box.frag:150-154`) | Add one indirect term; the direct loop and emissive self term stay. One sampler is a new path, not a material system. |
| `Object_Data` is model, previous model, colour, 144 bytes (`src/renderer/uniforms.odin:31-51`) | Add a slot/weight or a side buffer. The model matrix already gives the world scale for the bake. |
| Draws are per object with a push-constant index (`src/renderer/draw_pass.odin:103-126`) | A per-object lightmap slot is easy; no instancing change. |
| Scene colour is `R16G16B16A16_SFLOAT` (`src/renderer/frame_targets.odin:8`) | HDR indirect values fit the existing target; no tone-map or exposure change. |
| `geometry.Box` has no id or static flag (`src/geometry/box.odin:9-18`) | The frame must emit a parallel static key; do not add renderer identity to shared geometry. |

The one-mesh design is a good fit: box faces are planar rectangles, so the chart
is the face, not a general UV unwrap. The hard part is the per-instance atlas
layout and the bake/publish lifecycle.

## Data model

```text
Lightmap_Face { uv_rect: [4]f32 }  // 16 B; 6 per slot; (u0,v0,u1,v1) texel centers
Lightmap_Slot { first_face: u32; atlas: u32 }
Object_Data { model, prev_model: Mat4; color: [4]f32;
              lightmap_slot: u32; lightmap_weight: f32; pad: [2]u32 }
```

- The face buffer is 96 bytes per static slot; 512 slots is 48 KB. It changes
  only when the atlas is republished.
- `Object_Data` grows from 144 to 160 bytes with alignment; the depth prepass
  uses the same stride.
- The atlas is one `VK_FORMAT_R16G16B16A16_SFLOAT` image, `SAMPLED` plus
  `TRANSFER_DST` on the copy path (add `STORAGE` on the storage-image path), one
  mip, one layer, in `SHADER_READ_ONLY_OPTIMAL` between bakes. The scene target
  is already RGBA16F, so the value stays linear and HDR.
- The sampler is `LINEAR/LINEAR/NEAREST`, `CLAMP_TO_EDGE`, `maxLod = 0`, the
  same shape the text atlas uses (`src/renderer/text_atlas_resources.odin:23-35`).
- Add a combined-image-sampler at scene descriptor binding 11. The set uses 0-10
  (`src/renderer/uniforms.odin:55-65`); the pool needs one more descriptor per
  frame in flight.
- The bake writes a storage image if RGBA16F storage is supported and the
  storage-image feature is enabled, or writes a storage buffer and copies it to
  the atlas image. The first avoids a full-size temporary buffer; the second is
  the portable fallback. Pick one, report it, and do not silently switch.

`lightmap_slot` is the only per-frame data. A static box with no current tile
has an invalid slot and falls back to probe indirect with a visible
`bake_missing` state; it never silently renders black.

### Why every static instance gets its own tile

Indirect light depends on world position and on what each surface can see. Two
crates at different positions need different bounced light even if their meshes
are identical. Unity solves this with a per-renderer lightmap scale and offset
into a shared atlas: the mesh stores one lightmap UV layout, and each renderer
supplies a different atlas transform
([Unity lightmap UVs](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/lighting-gi-uvs/uvs),
[Renderer.lightmapScaleOffset](https://docs.unity3d.com/6000.6/Documentation/ScriptReference/Renderer-lightmapScaleOffset.html)).
Harbagsa has no stored lightmap UVs, so the equivalent is six procedural face
UVs plus six per-instance rects. Do not share a tile between two instances
unless they are at exactly the same transform with the same visibility.

## Bake space

The bake is in world space, not a UV unwrap. For each static face:

```text
n,t,b = world face normal and tangent axes; w,h = 2 * half_extents on t,b
tw = max(8, ceil(w*density)); th = max(8, ceil(h*density))
tile = pack(tw + 2*pad, th + 2*pad)
for y,x:
  s=(x+0.5)/tw; t=(y+0.5)/th
  p = face_origin + t_axis*(s-0.5)*w + b_axis*(t-0.5)*h + n*pushoff
  atlas[tile.x+pad+x, tile.y+pad+y] = integrate_hemisphere(p,n,rays)
dilate(tile,pad)
```

- `density` starts at 4 texels/m. `tw` and `th` use the effective density
  `tw / w`, so non-square faces keep a consistent blur.
- `pack` is a deterministic shelf packer: sort by height or area, place rows,
  align tile origins to 4 texels if BC6H is enabled. Never wrap a UV; if the
  atlas overflows, grow it or fail loudly.
- `integrate_hemisphere` uses the current fixed 64-ray spherical Fibonacci set
  and cosine weighting. The stored value is the cosine-weighted average
  incident radiance, `sum(radiance*cos)/sum(cos)`, not physical irradiance.
  That is the quantity the current probe gather adds under albedo
  (`src/renderer/shaders/probe_blend.comp`, `src/renderer/shaders/probe_gather.glsl`).
  Keeping the convention preserves the direct/indirect balance.
- A hit is shaded with `albedo * (direct_from_static_fixtures + emissive)`, using
  the same point-light falloff and hard-shadow visibility check as the frame. A
  miss returns zero. There is one bounce; the hit's indirect is not traced
  further.
- A backface hit contributes zero radiance but still counts as an occluder; the
  current probe path uses a negative distance to exclude it from the sum.
- `pushoff` starts around 0.005-0.01 m and must stay small relative to the
  thinnest box (0.2 m steps, 0.5 m walls); tune it with captures.
- Sample texel centers, not corners. The first and last centers are half a texel
  inside the face; the geometric edge is not sampled directly. If a seam
  appears, add a one-texel edge row sampled at the exact edge, or supersample
  the edge texel 2x2/4x4. Unity's lightmapper defaults to 4 anti-aliasing
  samples per texel (2x2) and provides `Pushoff` and `Backface Tolerance` for
  these cases
  ([Lightmap Parameters](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-reference/class-lightmap-parameters)).

### UV mapping

The face UV is procedural and must be identical in the bake and the shader:

```text
face = local face normal (+X, -X, +Y, -Y, +Z, -Z)
s,t  = the two local position components on that face, remapped to [0, 1]
uv   = mix(uv_rect.xy, uv_rect.zw, vec2(s, t))
```

`uv_rect` is **center-to-center**: `(u0, v0)` is the first texel center and
`(u1, v1)` the last. At `s = 0` the sample is the first center, at `s = 1` the
last; hardware bilinear never leaves the chart. An edge-to-edge rect with a
half-texel offset applied in one place and not the other is the most common
one-texel seam. The `s/t` orientation per face is arbitrary but must be the same
in the bake and the shader; a mirrored orientation looks like a lighting bug.

## Resolution, filtering, seams, padding, dilation

| Rule | Recommendation | Why |
| --- | --- | --- |
| Texel density | 4 texels/m default; 8 maximum | 0.25 m texels at 4/m; indirect is low-frequency. The probe spacing is 2 m. |
| Minimum chart | 8 x 8 texels | A 1 m crate at 4/m is 4 x 4; without a floor it becomes a blur. |
| Maximum chart | 512 x 512 texels | A 40 m wall at 8/m is 320 x 44; the floor is 320 x 320. |
| Atlas | 2048 x 2048 first; 4096 if needed | 4.19M texels; the arena's chart area is far below it at 4/m. |
| Padding | 4 texels per side | Unreal's minimum for DXT 4x4 blocks; also enough for bilinear ([Understanding Lightmapping](https://dev.epicgames.com/documentation/unreal-engine/understanding-lightmapping-in-unreal-engine?lang=en-US)). |
| Dilation | 4 texels, copy nearest edge value | Fills the gutter so a 4x4 block or bilinear tap never sees another chart or black. |
| Filter | Bilinear, no aniso | Flat faces and a low-frequency signal; aniso adds nothing. |
| Mips | None; `maxLod = 0` | Chart borders bleed at lower mips. |
| UV clamp | Clamp to the center-to-center rect | Prevents a tap outside the chart even if the gutter is wrong. |

Unity's default padding is 2 texels and its default maximum atlas is 1024
(`Lightmap Padding`, `Max Lightmap Size` in the
[Lightmapping settings reference](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/lightmaps-reference));
Unreal recommends at least 4 and Lightmass pads the atlas edge itself
([Understanding Lightmapping](https://dev.epicgames.com/documentation/unreal-engine/understanding-lightmapping-in-unreal-engine?lang=en-US)).
Take the stricter 4-texel rule; it keeps BC6H possible without a second packing
scheme.

### Seams

- A **hard lighting edge** between two faces of a box is correct. The faces have
  different normals, so the indirect and direct terms differ. Do not stitch a
  floor chart to a wall chart.
- A **thin dark or bright line** at a chart border is a filtering or packing
  error. It comes from sampling the gutter, a half-texel offset, or a chart that
  shares a texel with its neighbor. Center-to-center rects, a 4-texel dilated
  gutter, and a clamp remove it.

For two coplanar static boxes that abut (stairs, wall segments), the shared edge
should produce the same value from both sides. Use the same density and sample
rule. If a line remains, add a one-texel edge row sampled at the exact shared
edge, or stitch the two charts as one planar chart. Unity's `Edge Stitching` is
for continuous charts, not the 90-degree edge between a floor and a wall
([Lightmap Parameters](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-reference/class-lightmap-parameters)).
Unreal calls overlapping and wrapping charts the two errors that produce light
and shadow artifacts; the packer must guarantee neither
([Understanding Lightmapping](https://dev.epicgames.com/documentation/unreal-engine/understanding-lightmapping-in-unreal-engine?lang=en-US)).

### Dilation and invalid texels

A box face is a rectangle, so every interior texel is valid unless the face is
partially buried in another static box. After the bake, copy the nearest valid
chart-edge value outward into the 4-texel gutter. If a texel center is inside
another static box, mark it invalid and clone the nearest valid value, as
Unity's texel-validity rule does
([Lightmap Parameters](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-reference/class-lightmap-parameters)).
Do not average across charts; averaging is a blur and creates a seam. Lightmass
pads around lightmap edges when it packs the atlas
([Understanding Lightmapping](https://dev.epicgames.com/documentation/unreal-engine/understanding-lightmapping-in-unreal-engine?lang=en-US));
Harbagsa is doing that padding explicitly.

## Format, exposure, gamma

Use **linear HDR**, not an LDR lightmap:

- `VK_FORMAT_R16G16B16A16_SFLOAT` is a 64-bit, four-component, 16-bit float
  format; alpha is unused and can stay 1.0. It filters in hardware and needs no
  decode ([VkFormat](https://registry.khronos.org/vulkan/specs/latest/man/html/VkFormat.html)).
- Indirect light can exceed 1 near a bright lamp or an emissive box. Unity's
  RGBM covers about 0..34.49 linear and dLDR only 0..2 before clamping; both are
  lossy against a bright bounce
  ([Unity lightmap data format](https://docs.unity.com/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmap-data/lightmaps-technical-information)).
- A float lightmap stays linear. An `_SRGB` format is still 8-bit and clamped;
  do not use it for HDR indirect ([VkFormat](https://registry.khronos.org/vulkan/specs/latest/man/html/VkFormat.html)).
- No separate exposure. The lightmap is in the same linear scale as the direct
  term. If the bounce needs tuning, expose one global `indirect_scale` (default
  1.0), analogous to Unity's `Indirect Intensity`
  ([Lightmapping settings](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/lightmaps-reference)).
  A display exposure on the lightmap alone would break the direct/indirect
  balance.
- The output already has a stable dither for the 8-bit target
  (`docs/adr/0020-output-dither-for-the-8-bit-target.md`). A float lightmap
  leaves that dither as the only quantization step; an 8-bit lightmap adds a
  second, larger quantization before the resolve.

### Compression

Start uncompressed. `VK_FORMAT_BC6H_UFLOAT_BLOCK` is 8 bits per pixel, HDR, no
alpha, 4x4 blocks, and decodes before texture filtering
([BC6H Format](https://learn.microsoft.com/en-us/windows/win32/direct3d11/bc6h-format)).
Unity reports BC6H quality above DXT5 + RGBM and the same memory as DXT5
([Unity lightmap data format](https://docs.unity.com/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmap-data/lightmaps-technical-information)),
but smooth flat faces are where 4x4 blocks are easiest to see. Unreal notes that
compression artifacts are less noticeable in indirectly lit areas, which is the
argument for trying BC6H later
([CPU Lightmass](https://dev.epicgames.com/documentation/unreal-engine/cpu-lightmass-global-illumination-in-unreal-engine?lang=en-US)).

If BC6H is used, check `textureCompressionBC` at device creation (it covers all
BC formats, including BC6H,
[VkPhysicalDeviceFeatures](https://registry.khronos.org/vulkan/specs/latest/man/html/VkPhysicalDeviceFeatures.html));
align charts to 4 texels, keep the 4-texel gutter, dilate before compression,
and compare captures against the float atlas. A 2048² RGBA16F atlas is 32 MiB;
BC6H is 4 MiB. If blocks show, keep float and raise the atlas size. Mips are off;
blur the bake or widen the filter before generating mips across chart borders.

## Indirect only: the direct question

Bake **indirect only**. Direct light and hard shadows stay real-time.

- The map is low-frequency. Ramamoorthi and Hanrahan show that diffuse
  irradiance is insensitive to high-frequency lighting and is well approximated
  by nine coefficients, with average error around 1%
  ([paper](https://cseweb.ucsd.edu/~ravir/papers/envmap/envmap.pdf)). A
  4-texels/m indirect map is already far above that frequency.
- Direct light is the opposite: a hard shadow edge is a step. At 4 texels/m a
  1 m shadow edge is only 4 texels wide; it would be visibly blurred, and the
  direct light would also be added twice if the real-time pass stays on.
- There is no blocker for indirect-only. The only failure mode is a requirement
  to freeze direct light too, which is the opposite of the chosen mixed model.

Do not bake ambient occlusion for the first version. AO is a visibility term for
an ambient light that does not exist here; it darkens independently of the lamps
and reads as a surface texture on a flat face. It is a separate decision.

## Emissive static boxes, dynamic crates, and the spider

- **Static emissive box**: a bake source and a reflector. Emitted radiance is
  `albedo * emissive`, the same term the current probe hit shade adds
  (`src/renderer/shaders/probe_ray.comp`). Its own self-emissive term stays
  real-time in `box.frag`, so the bake must not add the box's own emission back
  onto its own texels.
- **Static fixture body**: a static box with a point light. The light is a bake
  source; the body's emission is the open double-count question from #371.
- **Static crate or prop**: a reflector and occluder in the bake; it gets a tile
  like any other static box.
- **Dynamic crate**: no tile. It reads probes, receives real-time direct, and
  emits its self term. It does not cast into the bake, so it leaves no indirect
  shadow; its real-time direct shadow is still there.
- **Dynamic lamp body**: no tile. It reads probes, receives direct, emits its
  self term, and is excluded from the bake source list.
- **Spider body, legs, eyes, and markings**: dynamic. They read probes and keep
  their self-emissive terms. They do not bake, even though the eyes and markings
  are emissive. The design guide's "they enter the probe field like any emissive
  box" becomes "they are dynamic, so they self-glow but do not bounce."
- **Dynamic crate near a wall**: the wall keeps baked indirect that ignores the
  crate. This is accepted; the direct shadow still grounds the crate. Adding a
  dynamic occlusion term would be dynamic GI by another name.

## Impact on the flat-shaded look

The lightmap is **lighting data, not a surface texture**. It carries no albedo,
pattern, tiling, normal, or material detail. The face still has one constant
colour and one constant normal; the only new variation is a smooth indirect
gradient on top of the direct light. The hard direct shadow, the palette, and
the flat faces remain the signature.

The risks are artifacts that make the map read as a texture: 4x4 compression
blocks, a one-texel seam, LDR banding, baked direct shadows that double and blur
the real-time ones, baked AO, or a blotchy bake. The controls are the rules
above: float format, 4-texel dilation, bilinear, center-to-center rects, no
mips, no baked direct, no baked AO, and 64+ rays with a light filter if needed.

`docs/design/README.md` currently says "Nothing is textured" and "A texture ...
or a baked light ... removes it"; `docs/design/world.md` says "There is no
texture" and "A static or baked lamp is not an alternate mode." Those sentences
must be revised, not ignored. The intended wording is: **no surface texture; one
lighting-data texture is allowed; no dynamic GI.** The `GLOSSARY.md` entries for
`Probe pass`, `Probe atlas`, `Lamp prefab`, and `Body mode` also change; see
`docs/research/mixed-lighting.md`.

## Code seams

| Area | Change |
| --- | --- |
| `src/renderer/mesh.odin` | No change. The face normal and local position are enough. Do not add a UV attribute. |
| `src/renderer/shaders/box.vert` | Pass a flat local normal (or a face id) alongside the existing local position. No vertex buffer change. |
| `src/renderer/shaders/box.frag` | Add binding 11, the face UV, the face rect lookup, the atlas sample, and the dynamic/static indirect branch. Keep the direct loop and emissive term. |
| `src/renderer/uniforms.odin` | Add `Lightmap_Face`, the slot/weight in `Object_Data`, binding 11, and the pool size. |
| `src/renderer/scene.odin`, `scene_buffers.odin` | Create/destroy the atlas image, sampler, face buffer, descriptor binding; write the image descriptor, grow the face buffer with the static slot count, bind per frame. |
| `src/renderer/images.odin` | Upload/copy the float atlas and check format features; reuse the existing image creation and barrier helpers. |
| `src/renderer/scene_object_data.odin` | Fill the slot/weight from the frame's static keys; invalid for dynamic boxes. |
| `src/renderer/render_digest.odin`, `taa.odin` | Include the lightmap version/key; reset TAA on atlas publish. |
| `src/frame/frame.odin` | Emit a parallel static key per box so the renderer can map a box to a slot without changing `geometry.Box`. |
| `src/perf/perf.odin`, `format.odin` | Remove `Probe` from the frame pass list; add a separate `bake_ms`/`bake_lights` block. |
| `src/harness/state*.odin`, `schema*.odin` | Expose atlas size, texel count, version, dirty/missing state, and bake time; optionally a lightmap debug capture. |
| `docs/design/*`, `GLOSSARY.md`, `README.md`, `docs/adr/` | Update the no-texture/no-baked-light wording; new ADR supersedes 0039 and 0042, while 0040 and 0041 stay in force. |

No general texture system is needed. One sampled image, one sampler, one
descriptor, and one face buffer are enough.

## Known artifacts

| Artifact | Cause | Control |
| --- | --- | --- |
| Light bleed across chart edges | Bilinear or compression reads the gutter or a neighboring chart | 4-texel padding per side, 4-texel dilation, center-to-center UV, clamp. |
| Thin seam line at a face edge | Half-texel offset or sampling outside the chart | Center-to-center rect; same sample rule in bake and shader; edge supersample. |
| Compression blocks | BC6H 4x4 blocks on a smooth gradient | Float first; 4-texel alignment and dilation; compare captures before BC6H. |
| Acne / self-shadow | Ray origin on the surface | 0.005-0.01 m pushoff, tmin 0.001, backface handling. |
| Thin visual-only marker | Pushoff is larger than the half thickness; the texel starts inside or outside | Use a smaller pushoff below 0.05 m thickness, or skip its tile and use probes. |
| Light leak through thin walls | Pushoff too large or a probe on the far side | Keep pushoff small relative to the thinnest box; keep probe depth/facing rejection. |
| Double-counted direct or emission | Bake includes the receiver's direct or its own emissive | Indirect only; skip the receiver's direct; exclude self-emission. |
| Stale atlas after a static edit | Bake key not rebuilt | Version/key in digest and state; rebake before capture. |
| Black dynamic object | Probe volume missing or an unbaked box with no fallback | Cover the arena; unbaked static falls back to probes with `bake_missing`. |
| Textured look | Baked direct/AO, compression, or a visible seam | No baked direct/AO; float; dilation; limit the indirect scale. |

## Rejected alternatives

| Alternative | Why rejected |
| --- | --- |
| Per-vertex lightmap on the cube corners | Four corners per face give a linear gradient; a large floor or wall loses the bounce shape. |
| One tile per box shared by all six faces | The charts overlap or the face texel density is stretched; a 4 x 3 wall and a 0.5 m side cannot share one square. |
| Bake direct + indirect | Direct needs a much higher resolution for hard shadows, doubles with the real-time pass, and contradicts the mixed model. |
| LDR / RGBM / dLDR | Range clamp and banding; indirect can exceed 1; flat faces show it. |
| BC6H from the start | 4x4 block artifacts on smooth gradients; prove the float path first. |
| Baked AO | Not transport; darkens independently of the lamps; reads as a texture. |
| World-space 3D texture for static surfaces | Static surfaces are 2D; a volume wastes memory and blurs. Probes are the 3D representation for dynamic objects. |
| Per-frame atlas repack | A guaranteed hitch and a new descriptor every frame. |
| Add UV2 to the cube mesh | The atlas transform is per instance and per face; procedural UV avoids a vertex layout change. |
| General material texture system | The only new texture is lighting data; no albedo/normal/specular path is needed. |

## Open decisions for the owner

1. **Density and atlas size.** 4 texels/m and 2048² is the starting point; 8/m
   and 4096² are measured options. 1024² saves 24 MB but leaves less headroom.
2. **Per-face rects vs a 3 x 2 cell.** Six rects keep density uniform; a square
   cell stretches non-square faces. Recommendation: six rects.
3. **Side buffer vs push constants.** Six rects are 96 bytes and fit the
   128-byte push-constant minimum; a side buffer is future-proof for instancing.
   Recommendation: side buffer.
4. **Single atlas vs texture array.** One 2048² atlas covers the arena; add an
   `atlas` field now and use a texture array only for a second room.
5. **Mips and padding.** Recommendation: no mips; 4 texels strict, 2 is
   enough for float + bilinear but 4 keeps BC6H possible without a repack.
6. **Fixture emissive double count.** Body emission plus point light? Keep parity
   with the current probe first, expose a scale, and compare captures.
7. **Unbaked static fallback.** Recommendation: probe indirect plus
   `bake_missing`; never silent black.
8. **Lightmap debug capture.** Recommendation: a debug-only atlas capture; it is
   the fastest way to inspect seams and compression.
9. **Indirect scale.** Recommendation: one global `indirect_scale` (default
   1.0), like Unity's `Indirect Intensity`, so bounce can be tuned without a
   bake.
10. **Baked AO and edge texels.** Recommendation: no baked AO; center samples
    plus 2x2 edge supersampling, adding an edge row only if a capture shows a
    line.
11. **Bake trigger.** Shared with #371: commit-time off-frame bake, explicit
    command, or next-frame automatic; the atlas publish policy follows.
12. **Design-guide exception.** Approve "no surface texture; one lighting-data
    texture; no dynamic GI" before implementation.

## Primary sources

- Unity lightmap UVs and per-renderer atlas transform: [Introduction to Lightmap UVs](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/lighting-gi-uvs/uvs), [Renderer.lightmapScaleOffset](https://docs.unity3d.com/6000.6/Documentation/ScriptReference/Renderer-lightmapScaleOffset.html).
- Unity lightmap settings, padding, filtering, compression: [Lightmapping settings](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/lightmaps-reference), [Lightmap Parameters](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-reference/class-lightmap-parameters), [Lightmap data format](https://docs.unity.com/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmap-data/lightmaps-technical-information).
- Unreal lightmap UVs, padding, and compression: [Understanding Lightmapping](https://dev.epicgames.com/documentation/unreal-engine/understanding-lightmapping-in-unreal-engine?lang=en-US), [CPU Lightmass](https://dev.epicgames.com/documentation/unreal-engine/cpu-lightmass-global-illumination-in-unreal-engine?lang=en-US).
- BC6H: [Microsoft BC6H Format](https://learn.microsoft.com/en-us/windows/win32/direct3d11/bc6h-format).
- Vulkan formats and compression feature: [VkFormat](https://registry.khronos.org/vulkan/specs/latest/man/html/VkFormat.html), [VkPhysicalDeviceFeatures](https://registry.khronos.org/vulkan/specs/latest/man/html/VkPhysicalDeviceFeatures.html).
- Irradiance frequency and probes: [Ramamoorthi and Hanrahan](https://cseweb.ucsd.edu/~ravir/papers/envmap/envmap.pdf), [Greger et al., The Irradiance Volume](https://www.sci.utah.edu/~bigler/images/msthesis/The%20irradiance%20volume.pdf).
- Repository code and decisions: `src/renderer/`, `src/frame/frame.odin`, `docs/adr/0020-output-dither-for-the-8-bit-target.md`, `docs/adr/0042-single-volume-ddgi.md`, `docs/research/mixed-lighting.md`.
