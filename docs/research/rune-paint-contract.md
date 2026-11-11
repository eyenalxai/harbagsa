# Rune paint contract for an external Vulkan renderer

**Date:** 2026-11-10  
**Status:** Code-read research note. No GPU run, no Vulkan validation, no pixel comparison was performed. Source: `rune` commit `f18ead8`, crate version `0.0.1`.  
**Question:** If Rune runs headless and hands an external renderer its output, what is the complete drawing contract?  
**Short answer:** Rune emits a flat stream of 128-byte instanced quads (`Runtime::instances`) plus two CPU-side texture atlases (R8 glyph/icon coverage, RGBA8 images) and a small number of structural records for isolated layers, effect slots and backdrop blurs. One uber shader rasterises every ordinary primitive; layer composition, layer Gaussian blur, backdrop blur and effects are separate passes that the host must implement. Rune has no serialized “paint packet” and no public final-layer plan: the instance stream is the contract, but the layer planner’s target bounds are private and must be reconstructed. `KIND_LAYER_END` is never submitted as a draw; a host that walks the whole vector must skip it explicitly.

## Answer

Rune’s paint stage produces five things an external renderer needs:

1. **A painter-ordered instance list.** `Runtime::instances: Vec<Instance>` is public (`crates/rune/src/runtime.rs:469`); `Runtime::marks` is a parallel tag vector when `track_marks` is set (`runtime.rs:470-473`). Each `Instance` is 128 bytes, eight `vec4`-sized fields, drawn as one quad from four vertices in a triangle strip (`crates/rune/src/render.rs:201-224`, `crates/rune/src/render/metallib.rs:34-37,92-102`). There is no index buffer, depth buffer, multisampling or per-primitive pipeline. Blend is premultiplied source-over, or premultiplied One/One for a plus-lighter layer (`crates/rune/src/render.rs:84-103`).
2. **A single über fragment shader with branch-per-kind.** `shader.wgsl` handles rects, borders, outer shadows, glyphs, inset shadows, vertical gradients, segments, triangles, images, dashed borders, radial/angled gradients and layer composites (`crates/rune/src/shader.wgsl:1-8,359-545`). Kinds 8, 9, 12 and 13 are structural records; 12 and 13 discard in the shader, and 9 must simply never be drawn because Rune’s draw ranges exclude it (`crates/rune/src/shader.wgsl:69-70,399-400`; `crates/rune/src/render/layers.rs:756-759`).
3. **Two atlases.** Glyph and monochrome-icon coverage is `R8Unorm`, 2048×2048, one texture per shelf page (`crates/rune/src/render/fill.rs:128-142`, `crates/rune/src/text/atlas.rs:7,47-52`). Images, colour emoji and colour icons live in `Rgba8UnormSrgb` pages (normally 1024×1024, large images get exact-size standalone pages) (`crates/rune/src/render/pipelines.rs:129-131`, `crates/rune/src/pixels.rs:9,216-229,375-397`).
4. **Structural records for compositing.** `KIND_LAYER`/`KIND_LAYER_END` delimit offscreen scopes; `KIND_EFFECT` reserves a point in the stream for a host-defined effect; `KIND_BACKDROP_BLUR` reserves a point where the host must copy and blur what is below (`crates/rune/src/render.rs:52-80`, `crates/rune/src/runtime/paint/slots.rs:10-59`). An isolated layer needs an `Rgba16Float` target (or equivalent), a projection uniform, a composite draw of the layer texture, and optionally a Gaussian blur. A backdrop blur needs a viewport-sized copy and a downsample/upsample pyramid.
5. **A separate native-surface stream.** Videos/native surfaces are `Runtime::surfaces: Vec<SurfaceDraw>`, not `Instance`s (`crates/rune/src/runtime.rs:469`, `crates/rune/src/runtime/paint/build.rs:1059-1068`). They are drawn by `SurfaceRenderer`; a host that ignores them loses video but not ordinary UI. `El::system_material` is also native/fallback, not part of the instance shader (`crates/rune/src/runtime/paint/build.rs:843-856`).

The complete ordinary primitive contract is therefore: **instances + atlases + one über pipeline + clip maths**, with **layers, blur, backdrop copies and effects as additional compositor passes**. For a plain rect-and-glyph HUD, only the first four are required. For full visual parity, the host must either port or reimplement Rune’s layer planner, layer Gaussian, backdrop pyramid, Windfoil outline path and the separate `rune-fx`/`rune-light` renderers used by the demos.

## Evidence

All line ranges are from `rune` `f18ead8`.

### 1. Primitive kinds and how each is emitted

`KIND_*` is the discriminant in `Instance::params[1]`; the constants and their payload comments are `crates/rune/src/render.rs:35-80`.

| Kind | Value | Emitted by | What it draws |
|---|---:|---|---|
| `KIND_RECT` | 0 | `build.rs:943-1082`, `helpers.rs:306-316`, `shadow.rs:40-49`, `border.rs:22-33` | Rounded rect fill and/or border ring; per-side widths in `uv`; bands when large. |
| `KIND_SHADOW` | 1 | `build.rs:870-882`, `shadow.rs:25-73` | Analytic Gaussian outer shadow, optionally with a clear hole. |
| `KIND_GLYPH` | 2 | `content.rs:477-521`, `helpers.rs:287-303`, `blend.rs:57-120` | R8 atlas glyph/icon coverage, or a Windfoil outline glyph; tinted by `fill`. |
| `KIND_INSET` | 3 | `build.rs:1085-1097`, `border.rs:37-49` | Inset shadow inside the padding box. |
| `KIND_GRADIENT` | 4 | `build.rs:971-986` | Vertical two-stop gradient; with `params.x > 0`, a border whose colour runs top→bottom. |
| `KIND_SEGMENT` | 5 | `content.rs:64-79`, `shape.rs:7-34` | Stroke segment with butt/round caps. |
| `KIND_TRIANGLE` | 6 | `shape.rs:35-57` | Filled, antialiased triangle for vector shapes. |
| `KIND_IMAGE` | 7 | `content.rs:81-108,144-159,388-408`, `helpers.rs:287-303` | RGBA image atlas sample, rounded by `radii`, opacity `fill.a`. |
| `KIND_LAYER` | 8 | `build.rs:728-739`, `render.rs:307-313` | Begin an isolated compositor scope; no pixels itself. |
| `KIND_LAYER_END` | 9 | `render.rs:323-325`, `build.rs:1254-1260` | Close the scope; never submitted as a draw (skip it explicitly). |
| `KIND_DASHED` | 10 | `build.rs:924-934` | Dashed border ring, colour gradient top→bottom. |
| `KIND_RADIAL` | 11 | `build.rs:987-1057` | One radial or angled-linear gradient stop segment. |
| `KIND_EFFECT` | 12 | `build.rs:1102-1105`, `slots.rs:10-32` | No pixels; a host effect slot. |
| `KIND_BACKDROP_BLUR` | 13 | `build.rs:666-670`, `slots.rs:38-59` | No pixels itself; the host copies/blurs below and composites inside `rect`. |

There is no separate “placeholder” primitive. A text field’s placeholder is laid out and emitted as ordinary glyphs in the image/text path (`crates/rune/src/runtime/paint/content.rs:233-257`). “Icon” is also not a separate kind: a monochrome icon is a `KIND_GLYPH` sampling the R8 atlas, while a colour icon is a `KIND_IMAGE` from a `Pixels` buffer (`content.rs:144-159`; `blend.rs:85-120`; `text/color_icon.rs:47-76`).

#### Rect and border (`KIND_RECT`)

`KIND_RECT` is the workhorse. `build.rs` computes the snapped rect, corner radii, premultiplied fill, border colour and opacity, then emits either a fill-only instance or a ring instance. A border-only box with a uniform opaque border can be split into four bands by `bands::push_ring` (`build.rs:1076-1082`, `bands.rs:20-39`). An inset shadow can force the fill and ring into separate instances (`build.rs:1070-1077,1098-1099`). The shader’s rect branch is `shader.wgsl:405-425`: `sd_rounded` plus `border_over` (`shader.wgsl:316-328`). `params.x` is border width, `params.z` is antialias softness (normally 0, clamped to 0.5), `params.w` is the opacity the colours already carry. `uv` is `[top,right,bottom,left]` per-side widths when `uv.z >= 0` and any is nonzero; a negative `uv.z` marks a band window `[x0,y0,-x1,y1]` (`shader.wgsl:409-422,72-77`; `bands.rs:1-5`). A focus/outline ring is just another `KIND_RECT` with `fill = 0` and a border (`build.rs:1106-1124`).

#### Outer shadow (`KIND_SHADOW`)

`shadow.rs` expands the caster by spread and offset, keeps circular corner radii, and emits either a crisp ring/copy (`KIND_RECT`) or an analytic shadow (`KIND_SHADOW`) (`shadow.rs:25-73`). `params.z` is **half the CSS blur radius**, in device pixels (`shadow.rs:63`), not the CSS blur itself. The shader uses Evan Wallace’s rounded-box approximation: exact along x with `erf2`, four midpoint samples along y, plus a `SHADOW_INSIDE` shortcut (`shader.wgsl:111-153`). `uv.zw` optionally carries a rectangular hole relative to the rect and `radii.w` its radius; the shader multiplies by `sd_rounded` coverage (`shader.wgsl:426-435`). If the caster is opaque, `bands::push_shadow` splits the shadow into four bands so the hidden middle is not shaded (`shadow.rs:68-72`, `bands.rs:13-17`); a host may draw the whole quad and let the opaque fill cover it, at extra fill-rate.

#### Inset shadow (`KIND_INSET`)

`border.rs:37-49` emits the padding-box rect and shrunk radii; `params.x` is spread, `params.z` is again half the blur radius (or zero for a hard inset), `uv.xy` is the offset. The shader takes the element shape coverage minus a blurred/shifted copy (`shader.wgsl:493-507`). Square corners use exact pixel-area coverage (`box_cov`, `shader.wgsl:330-344`), so a hairline inset ring matches Chromium’s corner pixel.

#### Gradients (`KIND_GRADIENT`, `KIND_RADIAL`)

`El::gradient(top, bottom)` emits one `KIND_GRADIENT` with `fill = top`, `uv = bottom`, vertical interpolation over `rect.y..rect.y+rect.h` (`build.rs:971-986`, shader `shader.wgsl:508-519`). If `params.x > 0` the same instance is a border gradient: the ring runs from `border` at the top to `uv` at the bottom, over the fill, using `params.w` opacity (`shader.wgsl:509-518`).

`El::radial` (and angled linear multi-stop gradients) emits one `KIND_RADIAL` **per adjacent stop pair** (`build.rs:987-1057`). `params.x` is `t0`, `params.w` is `t1`; either is offset by `+2.0` to mark an open interior stop boundary so adjacent segments partition the quad without double-shading (`render.rs:60-63`; `shader.wgsl:438-461`). `uv.z > 0` means radial with `uv = [cx,cy,rx,ry]` in rect-local device pixels; `uv.z == 0` means an angled linear gradient with `uv.xy` the gradient vector per device pixel (`shader.wgsl:451-455`). The first/last segment may be clipped to the rounded corners; `build.rs:1003-1043` computes the segment rect/radii/uv.

#### Dashed border (`KIND_DASHED`)

`build.rs:924-934` emits a separate ring instance with `fill` top colour, `border` bottom colour, `params.x` width, and `uv.xyz = [dash, gap, phase]` in device pixels. The shader computes arc length around the rounded rect (`ring_arc`, `shader.wgsl:264-302`) and a dash coverage that stretches the period to fit a whole number of periods (`dash_cov`, `shader.wgsl:304-314`; fragment `shader.wgsl:462-472`).

#### Segments and triangles (`KIND_SEGMENT`, `KIND_TRIANGLE`)

`shape.rs:7-57` turns a vector shape into one `KIND_SEGMENT` per stroked edge and one `KIND_TRIANGLE` per triangulated fill triangle. Segment payload: `radii = [x0,y0,x1,y1]`, `params.x` half width, `params.z` round-cap flag (`shape.rs:23-32`); shader `shader.wgsl:155-181,487-488`. Triangle payload: `radii = [ax,ay,bx,by]`, `uv.xy = [cx,cy]`, `params.x` antialias-edge bitmask (`shape.rs:44-53`); shader `shader.wgsl:183-242,489-492`. The triangle `owns`/`soft` functions are written so two triangles sharing an edge do not double-shade it (`shader.wgsl:192-242`).

#### Images (`KIND_IMAGE`)

`content.rs` computes the fitted/cropped rect and calls `ImageAtlas::place`, then emits `params[0] = page`, `params[2] = premultiplied`, `uv.xy = atlas origin`, `uv.zw = span in texels`, `fill.a = opacity` (`content.rs:81-108`; `pixels.rs:254-317`). The shader manually bilinears over the image’s own texels, clamped to the image rect so atlas neighbours never bleed (`shader.wgsl:473-486`). `image_texel` handles straight versus premultiplied alpha and the sRGB-encoded target case (`shader.wgsl:249-259`). Rounded image corners use the same `sd_rounded` coverage (`shader.wgsl:437,485`).

#### Glyphs (`KIND_GLYPH`)

`Runtime::paint_content` gets `GlyphQuad`s from the text system, assigns each its ink colour, and calls `glyph_or_image` (`content.rs:477-521`). For an alpha glyph, `glyph()` emits `params = [0, KIND_GLYPH, page, coverage_exponent]`, `uv.xy = atlas origin`, `radii.x = lcd flag`, `fill = premultiplied ink` (`blend.rs:57-83`). For a colour glyph (emoji), it emits a `KIND_IMAGE` instead (`blend.rs:287-303`). For an icon, `icon_inst` emits `params[0] = turn`, `params[1] = KIND_GLYPH`, `params[2] = page`, and optionally expands `uv`/`rect` by one texel for filtered scaling/rotation (`blend.rs:85-120`). The shader’s glyph branch is `shader.wgsl:520-543`.

#### Layers and effect slots

Layer and effect emission is described in §6 and §7. `KIND_LAYER` is a begin record, `KIND_LAYER_END` a close record, and both occupy indices in the same vector as drawable instances; they must stay balanced (`render.rs:52-55`; `layers.rs:694-760`).

### 2. Instance layout, packing and attribute meanings

`Instance` is `#[repr(C)]` with exactly eight 16-byte fields, asserted to be 128 bytes (`crates/rune/src/render.rs:201-224`):

```rust
pub struct Instance {
    pub rect: [f32; 4],    // attribute 0: x, y, w, h (device px)
    pub radii: [f32; 4],   // attribute 1: TL, TR, BR, BL; negative = continuous corner
    pub fill: [f32; 4],    // attribute 2: premultiplied colour, or layer opacity in .a
    pub border: [f32; 4],  // attribute 3: border colour, or mark/outline/turn payload
    pub params: [f32; 4],  // attribute 4: [param0, kind, param2, param3]
    pub uv: [f32; 4],      // attribute 5: per-kind
    pub clip: [f32; 4],    // attribute 6: window x0, y0, x1, y1
    pub fade: [u32; 4],    // attribute 7: packed fade widths/offsets/radii
}
```

Vertex layout is eight attributes, locations 0..7, first seven `Float32x4`, last `Uint32x4`, instance step mode, stride `size_of::<Instance>()` = 128 (`crates/rune/src/render/metallib.rs:34-37,92-97`). The shader input matches exactly (`shader.wgsl:23-33`). The primitive is a triangle strip; `base_vs` derives corner `(vi & 1, vi >> 1)` from the vertex index and draws `0..4` per instance (`shader.wgsl:55-56`; `render.rs:935`).

**`rect`** is always `[x, y, w, h]` in window device pixels, top-left origin, y down. For a shadow/segment/triangle it is the bounding quad; for a layer it is the requested element bounds, not necessarily the final target bounds.

**`radii`** is per-corner `[TL,TR,BR,BL]`; a negative radius selects Apple’s continuous corner via `sd_continuous`, while a positive one is circular (`clip.wgsl:10-33`). `pack_clip_radii` clamps each corner to half the shorter clip side and stores either a uniform f32 bit pattern or a tagged 4×7-bit mixed-radii encoding (`render.rs:248-292`). The shader decodes it in `unpack_clip_radii` (`clip.wgsl:48-61`).

**`fill`** is premultiplied. CPU colours are built with `premul(c, opacity, srgb)`; `srgb` chooses `Color::premul_srgb` versus `Color::premul` (`crates/rune/src/runtime/paint/blend.rs:127-129`). For `KIND_LAYER`, only `fill.a` is used (scope opacity). For `KIND_EFFECT`, `fill.a` is always 1 because a faded slot is wrapped in a layer (`slots.rs:12-31`).

**`border`** is the border colour for ordinary primitives. For `KIND_LAYER` it is `[0, angle, pivot_x, pivot_y]` for a turned composite (`render.rs:315-321`; shader `shader.wgsl:88-94`). For `KIND_EFFECT` it carries the low/high 16 bits of the effect mark as exact floats (`slots.rs:12-17`; `render.rs:328-331`). For an outline glyph it carries `[record, hint, radius, coverage]` (`blend.rs:57-69`; `outline.wgsl:268-288`).

**`params`** is the kind dispatcher: `params[1]` is the `KIND_*` value. The other components are overloaded per kind; the authoritative table is below. Rune’s own field comment calls `params[2]` “shadow sigma” (`render.rs:209`), but it is also AA softness for rects/gradients, rotation for glyphs, page for glyphs, premultiplied flag for images, spread for insets, blur sigma for layers and bleed for effect slots.

**`uv`** is fully kind-dependent: border side widths or band window (`KIND_RECT`), hole rect (`KIND_SHADOW`), atlas origin/span (`KIND_GLYPH`, `KIND_IMAGE`), gradient vector or radial centre/radii (`KIND_RADIAL`), dash/gap/phase (`KIND_DASHED`), effect payload (`KIND_EFFECT`), cache signature (`KIND_LAYER`).

**`clip`** is `[x0,y0,x1,y1]` in absolute window device pixels; `NO_CLIP = [-1e6,-1e6,1e6,1e6]` (`render.rs:246`). `clip_alpha` multiplies four hard-edge ramps, then a rounded-corner mask if `fade[3] != 0` (`clip.wgsl:63-83`).

**`fade`** packs four half-float edge widths in words 0–1, four 8-bit normalized “origin offset” values in word 2, and the clip-radius word in word 3 (`render.rs:226-237`; `clip.wgsl:63-82`). A positive width is a smoothstep feather; a negative width is a linear ramp (`clip.wgsl:37-46`). The offset word lets the shader reconstruct a sub-pixel-shifted hard edge without carrying a separate `fade_origin`. Layer records may leave all four words zero (`render.rs:214-221`).

**Exact per-kind payload table:**

| Kind | `rect` | `radii` | `fill` | `border` | `params` | `uv` |
|---|---|---|---|---|---|---|
| RECT 0 | box | corners | fill premul | border premul | `[bw, kind, soft, opacity]` | sides `[t,r,b,l]` or band `[x0,y0,-x1,y1]` |
| SHADOW 1 | shadow box | circular corner in `.x`; `.w` hole radius | shadow colour | — | `[0, kind, sigma, 1]` | hole `[dx,dy,w,h]` or 0 |
| GLYPH 2 | glyph quad | atlas: `.x` lcd flag; outline: `[pen_x,pen_y,scale,zoom]` | ink premul | outline record/hint/radius/coverage, or 0 | `[rotation, kind, atlas page, coverage exponent]` | atlas `[x,y]`, optional span `[w,h]` |
| INSET 3 | padding box | inner corners | shadow colour | — | `[spread, kind, sigma, 1]` | offset `[dx,dy,0,0]` |
| GRADIENT 4 | box | corners | top colour | bottom colour (or border gradient) | `[bw, kind, soft, opacity]` | bottom colour (or 0 for border gradient) |
| SEGMENT 5 | bounds | `[x0,y0,x1,y1]` | stroke colour | — | `[half_width, kind, round_cap, 1]` | — |
| TRIANGLE 6 | bounds | `[ax,ay,bx,by]` | fill colour | — | `[aa_mask, kind, 0, 1]` | `[cx,cy,0,0]` |
| IMAGE 7 | image box | corners | `.a` opacity | — | `[image_page, kind, premultiplied, 1]` | `[x,y,w,h]` in texels |
| LAYER 8 | element bounds | cutout hole `[cx,cy,inner,outer]` | `.a` opacity | `[0,angle,pivot_x,pivot_y]` | `[plus_lighter, kind, blur_sigma, cache_flag]` | cache signature or 0 |
| LAYER_END 9 | — | — | — | — | `[0,kind,0,0]` | — |
| DASHED 10 | box | corners | top colour | bottom colour | `[bw, kind, soft, 1]` | `[dash,gap,phase,0]` |
| RADIAL 11 | segment box | corners | colour at t0 | colour at t1 | `[t0, kind, soft, t1]` | radial `[cx,cy,rx,ry]` or linear `[dx,dy,0,0]` |
| EFFECT 12 | element box | corners | `.a = 1` | mark low/high | `[backdrop, kind, bleed, scale]` | effect data |
| BACKDROP_BLUR 13 | element box | signed corners | `.a` opacity | — | `[sigma, kind, 0, scale]` | — |

### 3. Shaders, bind groups, textures, samplers

#### The main pipeline

The über pipeline has exactly one bind group in the ordinary case, group 0 (`crates/rune/src/render/metallib.rs:65-89`; `pipelines.rs:38-54`):

| Binding | Resource | Notes |
|---:|---|---|
| 0 | `Globals` uniform | `vec2 viewport; vec2 pad; vec4 flags`; `flags.x` = sRGB-encoded blending for the image path. 32 bytes. |
| 1 | glyph atlas `texture_2d<f32>` | `R8Unorm`, `filterable: false`; sampled only with `textureLoad`. |
| 2 | image/layer texture `texture_2d<f32>` | `Rgba8UnormSrgb` image page, or `Rgba16Float` layer target, or a 1×1 stand-in. |
| 3 | `projection` uniform `vec4` | `[origin_x, origin_y, width, height]`; zero width selects the viewport. |
| 4 | outline store `texture_2d<u32>` | Windfoil only; `Rgba32Uint`; Classic has four bindings. |

Bindings and WGSL declarations: `shader.wgsl:10-21`; layout entries: `metallib.rs:65-81`; Windfoil’s fifth binding: `render/variant.rs:76-85`. The texture sample type is `Float { filterable: false }` for bindings 1 and 2; **there is no sampler in the über pipeline**. All filtering is manual `textureLoad` interpolation. The outline texture is `Uint` (`variant.rs:79-84`). There are **no push constants / immediate-data blocks** in the cited Rune pipeline layouts: they use `immediate_size: 0` (`metallib.rs:84-90`; `layer_blur.rs:54-56`; `backdrop_blur.rs:133-137`). Per-draw values come from instance attributes or from uniforms; `rune-fx` uses dynamic uniform offsets, not push constants.

Auxiliary bind groups used by the separate paths:

| Pass | Group | Bindings |
|---|---:|---|
| Layer Gaussian | 0 | 0 `texture_2d<f32>` source; 1 filtering sampler; 2 `Uniforms` (128 taps + config + mapping). |
| Backdrop pyramid | 0 | 0 source texture; 1 “fine” texture; 2 filtering sampler; 3 `Level` uniform with dynamic offset. |
| Backdrop composite | 0 | the über group above (globals, atlas, layer/stand-in, projection). |
| Backdrop composite | 1 | 0 blurred texture; 1 filtering sampler; 2 `Level` uniform with dynamic offset. |
| Windfoil atlas fill | 0 | the über group with the atlas/image slots replaced by 1×1 stand-ins and the outline store bound. |

Sources: `layer_blur.rs:43-53,66-69`; `backdrop_blur.rs:94-128,200-211`; `backdrop_composite.wgsl:12-24`; `render/fill.rs:18-24,62-64`.

`Globals` is written with viewport dimensions and the sRGB flag (`upload.rs:240-248`). The frame’s projection is a 16-byte zero region after the globals in the same buffer; a layer has its own 16-byte projection buffer (`pipelines.rs:17-22,163-167`; `layers.rs:480-485,508`). `base_vs` uses `projection.zw` as target size and `projection.xy` as origin when `projection.z > 0`, otherwise the viewport and origin zero (`shader.wgsl:96-98`). All geometry and clip coordinates remain absolute window pixels; the projection only changes the final NDC mapping.

Blend state: `Blend::SourceOver` is `PREMULTIPLIED_ALPHA_BLENDING`; `Blend::PlusLighter` is One/One on colour and alpha (`render.rs:92-102`). The Windfoil subpixel pipeline is a special dual-source blend (`One`/`OneMinusSrc1` for colour, `One`/`OneMinusSrcAlpha` for alpha) (`variant.rs:284-315`).

**sRGB encoding:** `Renderer::set_format` sets `srgb_blend = !format.is_srgb()` (`pipelines.rs:205-217`). With `srgb_blend = false`, the shader writes linear premultiplied colours into an `*Srgb` target and the hardware encodes. With `srgb_blend = true`, the CPU has already premultiplied in sRGB encoding and the shader writes sRGB-encoded values into a non-sRGB target; `image_texel` explicitly decodes/re-encodes image texels in that case (`shader.wgsl:249-259`; `upload.rs:244-247`). Offscreen layer targets are `Rgba16Float` and hold whichever encoding the frame uses (`layers.rs:6-8`; `render.rs:160-165`).

#### Which paths need which shader files

- **Plain rect / border / glyph / image / shadow / gradient / segment / triangle:** only `clip.wgsl` + `shader.wgsl` (`pipelines.rs:9`, `metallib.rs:56-58`). No other shader.
- **Layer composite:** the same über shader, fragment branch `params.y == 8` (`shader.wgsl:359-398`). The layer texture is bound at group 0 binding 2; the projection is the parent target’s projection. No separate shader is needed for a plain layer composite.
- **Layer Gaussian blur:** `layer_blur.wgsl` plus `render/layer_blur.rs` (`layer_blur.wgsl:1-10`; `render/layer_blur.rs:37-71`).
- **Backdrop blur:** `backdrop_blur.wgsl` for the down/up pyramid (`render/backdrop_blur.rs:129-154`), and `backdrop_composite.wgsl` (with `clip.wgsl` prepended) for the final cut-out (`render/backdrop_blur.rs:155-163`; `backdrop_composite.wgsl:1-4`).
- **Windfoil outline glyphs:** `outline.wgsl` appended to `shader.wgsl`, plus binding 4 (`outline.wgsl:1-13`; `variant.rs:14-22,76-85`). Classic only uses `shader.wgsl`.
- **Windfoil subpixel text:** the same Windfoil source plus a dual-source fragment variant (`variant.rs:25-63,284-315`).
- **Windfoil atlas fill:** the same über vertex/fragment shader, rendered into `R8Unorm` with no blending (`render/fill.rs:26-48,111-126`).

#### Atlas and target formats

| Resource | Format | Size | Where |
|---|---|---|---|
| Glyph/icon alpha atlas, page 0 | `R8Unorm` | 2048×2048 | `render/fill.rs:128-142`, `text/atlas.rs:7` |
| Glyph/icon alpha atlas, pages 1.. | `R8Unorm` | 2048×2048 | `upload.rs:218-228` |
| Image/colour atlas page | `Rgba8UnormSrgb` | 1024×1024 or exact large | `pipelines.rs:129-131`, `pixels.rs:9,375-397` |
| Outline store | `Rgba32Uint` | 1024×N rows | `render/outlines.rs:10-15` |
| Isolated layer target | `Rgba16Float` | 64-px bucket | `render/layers.rs:6-8,427-490` |
| Backdrop copy | frame format | viewport size | `render/pass.rs:199-224` |
| Backdrop blur pyramid | `Rgba16Float` | 7 mips, half res | `render/backdrop_blur.rs:12-25,252-289` |
| Layer blur scratch | `Rgba16Float` | layer bucket | `render/layer_blur.rs:73-95` |

`TextureSampleType::Float { filterable: false }` is why the host does not need samplers for the main path. The layer blur and backdrop blur do use filtering samplers (`render/layer_blur.rs:66-69`; `render/backdrop_blur.rs:164-169`).

### 4. Text: glyph quads, atlas, UVs and phases

A `GlyphQuad` is `rect` in device px, `uv` with the page packed into `y` (`page * 2048 + y`), `ink`, `byte`, `color` and `lcd` (`text/atlas.rs:128-154`). `glyph_uv_page` splits the packed y into a page index and local y (`runtime/paint/blend.rs:52-55`). The instance’s `params[2]` is the page, `uv.xy` is the local atlas origin, and `params[3]` is the coverage exponent (`blend.rs:71-82`).

**Atlas format and page count.** The alpha atlas is `R8Unorm`, 2048×2048 per page (`text/atlas.rs:7`, `render/fill.rs:128-142`). Page 0 is `Atlas::data`; pages 1.. are `Atlas::pages[page-1]` (`text/atlas.rs:181-202,215-223`). `MAX_STEADY_PAGES = 2`, `MAX_OVERFLOW_PAGES = 8`; eviction is shelf/age based (`text/atlas.rs:47-52,290-328`). `page_count()` is at least 1. The atlas is **not R8-only overall**: subpixel masks are still R8 but store three texels per pixel (`AtlasGlyph.lcd`, `text/atlas.rs:33-45,281-294`); colour emoji are RGBA in the image atlas (`text/atlas.rs:156-179`; `content.rs:477-521`).

**Glyph production.** `TextSystem::glyphs_in_band` walks a laid-out paragraph, gets each glyph run, computes the baseline and pen, and calls `push_glyph` (`text/glyph_emit.rs:47-99`). `push_glyph` keys the mask by font, glyph, size, variation coords, x phase, y phase, dilation, Apple smoothing, skew and bold (`glyph_emit.rs:128-140`; key fields `atlas.rs:12-31`). It either finds an existing atlas entry, emits a colour glyph from `color_glyphs`, or rasterizes a mask (`glyph_emit.rs:141-231`). `atlas_quad` turns the entry into a `GlyphQuad`: `rect = [fx + left, gy - top, w, h]`, `uv = [x, page*2048 + y]` (`glyph_emit.rs:281-294`). For a subpixel mask, the width is `a.w / 3` (`glyph_emit.rs:282-286`).

**Phases.** The x phase is in sixtieths of a device pixel (`coretext_match::PHASES = 60.0`); the y phase is in quarters (`GLIDE_PHASES = 4`) (`coretext_match.rs:191-216`; `glyph_emit.rs:7,256-271`). `place` quantizes the pen, computes a whole-pixel `fx` and a phase `subpx`/`subpy`, and the **phase is part of the atlas key**, so a different phase is a different mask entry. The instance carries only the chosen atlas origin; there is no phase field in `Instance`. `zoom_glyph` handles scaled/moving glyphs: for an alpha glyph it stores the original atlas footprint in `uv.zw`, and the shader then does a manual bilinear sample over that span (`helpers.rs:265-283`; `shader.wgsl:528-537`).

**Coverage exponent.** `params[3]` is `coverage_exponent(fill)`; the shader computes `pow(cov, params.w)` (`blend.rs:288-291`; `shader.wgsl:542`; `coretext_match.rs:232-242`). On macOS/iOS and for DirectWrite/Windfoil it is 1.0; on other grayscale text it ranges between 1.12 and 0.45 by ink luminance. A host that skips the exponent will render light-on-dark text too heavy.

**Placeholder.** Text-field placeholders are shaped and emitted through the same glyph path; there is no separate primitive (`content.rs:233-257`).

**Outline text (Windfoil).** If the text system is told the renderer draws outlines, glyphs whose scale is moving (and the landing frame) use `Outline` records instead of atlas masks (`text/outline/path.rs:1-67`; `text/windfoil.rs:57-74`). The `KIND_GLYPH` payload becomes `radii = [pen_x, pen_y, scale, zoom]`, `border = [record, hint, radius, coverage]`, `uv = 0` (`blend.rs:57-69`). The outline store is `Rgba32Uint` and the shader integrates quadratic pieces (`outline.wgsl:4-13,78-156,178-262`). This is optional for static UI but required for exact moving/scaled text parity.

**GPU-filled masks.** When Windfoil is active, at-rest masks can be queued and filled on the GPU into the R8 atlas instead of being uploaded from CPU; the CPU page keeps zeros where such a mask lives (`text/atlas_fill.rs:1-151`; `render/fill.rs:111-158`). A host that reads only `Atlas::data` must either force the CPU path or implement the fill pass. This is a real trap for a headless consumer.

### 5. Images and icons

**Image atlas.** `ImageAtlas` has stable shelf pages of `IMAGE_ATLAS_SIZE = 1024`; an image larger than 1024 on either axis gets an exact-size standalone page (`pixels.rs:9,216-229,375-397`). `place_at` chooses a mip level by drawn device size, copies the frame into the page, and returns `Placed { rect, page, premultiplied }` (`pixels.rs:262-317`). `premultiplied` is true when the source is a decoded `ImageCache` mip chain (linear-premultiplied pixels), false for raw `Pixels::set` RGBA (straight alpha sRGB) (`pixels.rs:317`; `image.rs:18-19`; `render/pipelines.rs:129-131`). `Instance.params[0]` selects the page; `params[2]` is the premultiplied flag; `uv.xy` is the page origin and `uv.zw` the texel span (`content.rs:97-107`). The shader’s `image_texel` performs the straight/premultiplied and sRGB conversion (`shader.wgsl:249-259`).

**Icons.** `El::icon` is rasterised to 8-bit coverage and placed in the R8 atlas; `icon_coverage` produces a row-major coverage buffer and `rasterize_icon` pads one transparent texel around it (`text/icon.rs:145-172,188-283`). `icon_quad`/`icon_quad_facing` returns a `GlyphQuad` (`text.rs:985-1010`). `icon_inst` emits a `KIND_GLYPH` with `params[0]` as rotation and a one-texel apron when scaled/turned (`blend.rs:85-120`). Colour icons are rasterised by `color_icon` into `Pixels` and then go through the image atlas as `KIND_IMAGE` (`text/color_icon.rs:47-76`; `content.rs:144-159`).

**Page batching.** The renderer splits draws whenever the image page or glyph page changes (`upload.rs:313-348`). `KIND_IMAGE` uses `params[0]`; `KIND_GLYPH` uses `params[2]`. Page 0 is served by the base bind group (glyph page 0 in binding 1, image page 0 or stand-in in binding 2); glyph pages ≥1 get a bind group with that page texture in **both** binding 1 and binding 2 (`pipelines.rs:147-174`; `upload.rs:218-223`; `render.rs:918-932`). A host must preserve this batching or use a texture array with a page index; it cannot mix an image and a secondary glyph page in one draw.

### 6. Layers: allocation, isolation, composition, blur, cache

**When a layer record exists.** `build.rs` opens a layer only when the element needs one: a partial opacity over multiple paints, a dissolve/plus-lighter parent, a subtree blur, a rounded clip that cannot be folded into a primitive clip, a cutout, a rotated subtree, an effect slot that needs opacity, a `cache`, or a soft clip over multiple paints (`build.rs:298-301,627-739,714-727`; `render/layers.rs:577-582`). A plain opaque element with one paint emits no layer.

**Isolation test.** `isolates(index)` is the authoritative condition (`layers.rs:577-582`):

```text
cache.is_some()
|| opacity != 1
|| blend != SourceOver
|| additive_parent
|| blur != 0
|| fade[3] != 0
|| clip != NO_CLIP
|| turn.is_some()
|| hole[3] != 0
```

If the device’s feature breaker refuses isolation, plus-lighter or layer blur, `check_layer_features` downgrades accordingly: blend to source-over and blur to zero, and the layer may draw inline (`layers.rs:555-573`; `breaker.rs`). A target is allocated only for `Show::Render` or a retained `Show::Cached` layer; `Show::Inline`, `Hidden`, `Covered` get none (`layers.rs:107-120,414-490,546-547`). A layer that is `Show::Inline` can still have a clip; it is applied with a scissor and/or the shader clip, not a target.

**Target bounds.** This is the most important private calculation. `Instance::begin_layer` stores the element `rect` (`render.rs:307-313`), but `prepare_layers` computes the final target rectangle by unioning each primitive’s bounds with a per-kind grow, intersected with the instance clip (`layers.rs:335-355`):

- glyph: grow 0 (rotated glyphs use their turned bounding box);
- shadow: `sigma * 3 + 1`;
- effect: `bleed + 1`;
- rect/gradient/dashed/radial: `1 + softness * 2`;
- everything else: 1.

It then expands by `ceil(3 * blur)`, clips to the viewport/ancestor limit, floors/ceils to whole pixels, and buckets the texture to 64-pixel multiples (`layers.rs:293-355,427-490`). The composite quad uses the actual `bounds`, not the bucket size; `uv.zw` is set to the old content size only when a cached texture’s content size differs from the new rect (`layers.rs:389-395,510-515`).

**Rendering a layer.** `encode_layers_timed` iterates plans in reverse (children before parents), opens a pass on the layer texture, clears to transparent, sets the viewport to the layer size, draws the layer’s instance range with `draw_layer_range`, then optionally runs the Gaussian (`layers.rs:694-721`). The layer’s projection buffer is `[x,y,w,h]`, so absolute instance coordinates map into the offscreen texture (`layers.rs:480-485,508`). The layer content is drawn with the same über shader, with `fragment` still using absolute `p`/`screen` coordinates.

**Compositing.** `draw_layer_range` draws ordinary primitives in order; when it reaches a layer begin, it either draws the layer composite (`Show::Render`/`Cached`) or recurses inline (`layers.rs:723-760`). The composite is a four-vertex draw of a one-instance buffer whose `Instance` is `Instance::begin_layer(bounds, clip, spec)` with `fill.a = opacity`, `params[0] = 1` for plus-lighter, and optionally `turned()`/`radii = hole`; its `LayerSpec` is otherwise default, so the **composite quad’s `params[2]` is 0**. The blur sigma lives on the begin-layer marker emitted by paint (`build.rs:731-735`), not on the composite quad (`layers.rs:509-515`). The fragment branch `params.y == 8` samples the layer texture from group 0 binding 2, reconstructs screen position with `projection.xy`, applies `fill.a`, `clip_alpha` and `hole_alpha`, and clamps before opacity for plus-lighter (`shader.wgsl:359-398`).

**Group opacity** is the layer’s `fill.a`: `Instance::begin_layer` stores `spec.opacity.clamp(0,1)` (`render.rs:307-313`), and `build.rs` passes `paint_own * pinh.paint_opacity` (`build.rs:728-737`). Nested layers compose inside-out. `El::group_opacity` is **not** a layer by itself: it is a per-leaf paint factor (`visuals.rs:538-541`; `tracks.rs:43-48`), though it can push a multi-paint leaf into the isolate path because `paint_own < 1` (`build.rs:298-301`).

**Layer blur.** `LayerSpec.blur` is Gaussian sigma in device pixels, clamped to 64 (`render.rs:111-116`; `layer_blur.rs:5-6`). `layers.rs` converts the instance’s `params[2]` with `layer_blur::sigma` (`layers.rs:261,492-507`). The pipeline renders:
- sigma ≤ 3: two full-resolution passes, horizontal then vertical;
- wider: four passes: an area downsample (`MODE=2`), horizontal, vertical, and a reconstruction (`MODE=3`).

Uniforms carry up to 128 taps and a reduced-resolution mapping; `prepare` subtracts the box/linear variance from the Gaussian and `MODE`/`ADDITIVE` are pipeline constants (`layer_blur.rs:97-123,136-202`; `layer_blur.wgsl:1-10,42-66`). The final pass writes back into the layer texture so the composite binding stays stable (`layer_blur.rs:1-3,97-123`).

**Cached subtrees.** `El::cache()` sets a visual flag (`visuals.rs:304-307`). The layer marker’s `params[3]` becomes 1, `radii` holds the packed node id and `uv` the signature (`cache_layer.rs:312-318`). The planner treats the marker as a cache key, may reuse a retained texture (`Show::Cached`), or draws it live (`layers.rs:262,369-397,431-456`). The budget defaults to 64 MiB, max dimension 4096, LRU eviction (`layers.rs:9-12,180-188,517-524`). A host can ignore caching entirely and draw the contents every frame; visual output is the same, only the retained texture optimization is lost. If it keeps caches, it must reproduce the signature and `params[3]` semantics or simply key on the node id and rebuild when needed.

**Turned layers** use `border = [0, angle, pivot_x, pivot_y]` and the composite shader samples the upright texture with a bilinear inverse rotation, with nothing outside the layer (`shader.wgsl:88-94,367-379`). **Cutout holes** use `radii = [cx,cy,inner,outer]` and `hole_alpha` (`shader.wgsl:346-351,397`). Both require a layer target and composite pass.

### 7. Effects: `rune-fx` and `rune-light`

**Rune’s paint stage does not paint effects.** `El::effect` emits only `KIND_EFFECT`, a placeholder with `rect`, `radii`, `clip`, `fade`, a mark and a 4-float payload (`slots.rs:10-32`; `render.rs:64-74`). The über shader discards it (`shader.wgsl:69-70,399-400`). A faded effect gets an enclosing `KIND_LAYER` so the host’s pixels take the opacity (`slots.rs:22-31`). The host is called at the slot through `Renderer::draw_with`/`draw_range_with`/`encode_layers_with` with an `EffectSite` containing `mark`, `data`, `scale`, `format`, `origin`, `size`, `in_layer`, `srgb_blend` and an optional backdrop copy (`render.rs:138-199,786-937`; `pass.rs:52-80`).

**`rune-fx` is a separate instanced renderer with its own shaders and passes.** It has an `FxRenderer` with one pipeline per effect family/blend/target format, a storage buffer of effect instances, a motion-pose buffer, group 0 (globals + two storage buffers) and group 1 (backdrop, source, blurred source, sampler, encoding uniform) (`crates/rune-fx/src/renderer.rs:1-3,151-187,201-236`; `pipes.rs:1-14`). Each `FxLayer` is one quad; `draw_layer_in` sets a pipeline, two bind groups, and draws `0..4, instance..instance+1` into the caller’s pass, shifting the viewport by the layer origin (`renderer.rs:420-443`). Effect families are shaders `glow`, `pulse`, `electric`, `fire`, `distort`, `motion`, `extras`, `fill` composed with `common.wgsl` and `clip.wgsl` (`pipes.rs:10-18`; `src/shaders/`). Frosted lenses need a backdrop copy and a half-resolution mip pyramid (`FxRenderer::blur_backdrop`, `renderer.rs:471-507`; `BLUR_MIPS=6`). Blend modes `Multiply`/`Overlay`/`SoftLight` read the backdrop (`crates/rune-fx/src/lib.rs:321-346`). So an external renderer that wants demo parity must port those family shaders and the backdrop/mask pyramids, or accept missing effects.

**`rune-light` is a separate multi-pass renderer.** It does not consume Rune `Instance`s directly; it consumes a `Scene` of `Prim` (rect, radii, z/bevel, gloss/roughness, flags, emission, albedo) and `Light` values (`crates/rune-light/src/lib.rs:39-55,148-160`; `Prim::from_rune` at 142-145). `LightRenderer::render` records: a G-buffer pass (two targets), a half-resolution field compute pass, a half-resolution soft-shadow compute pass, optional eighth-resolution GI radiance cascades (scene, cascades, fluence), and a full-resolution composite pass (`crates/rune-light/src/render.rs:1-17,95-235`; `GI_SCALE = 0.125` at `crates/rune-light/src/lib.rs:372`). `GlassRenderer` is another separate renderer: it takes `Glass`/`GlassLight`, a backdrop and a fluence texture, runs a frost pyramid and a glass composite (`crates/rune-light/src/glass.rs:288-310`; shaders `glass.wgsl`, `common.wgsl`). Demos feed it a UI base texture and a separate text texture; `LightRenderer::render` explicitly takes `base` (UI without text) and `text` (premultiplied) (`crates/rune-light/src/render.rs:6-16`; `examples/site-scenes/src/main.rs:259-320`).

Thus “materials and glass” parity is not an extension of the instance shader. It is porting two additional rendering systems: `rune-fx`’s effect family shaders and `rune-light`’s lighting/glass passes, or replacing them with an equivalent that matches the demo look.

### 8. Kit coverage: what `rune-kit` actually uses

A grep across `crates/rune-kit/src` shows the following API usage counts: `fill` 129, `radius` 98, `border` 29, `layer_opacity` 11, `group_opacity` 11, `box_shadow` 11, `outline` 10, `gradient` 6, `pixels` 5, `icon` 3, `clip_fade`/`clip_fade_linear` 3, `border_sides` 1, `cutout_circle` 1, `mirror_in_rtl` 2. There are **no** uses of `backdrop_blur`, `effect`, `effect_data`, `cache`, `native_surface`, `blur`, `border_dash`, or `shape` in `rune-kit/src`.

Representative components:

- **Button/action** (`actions.rs:132-143`): `fill`, `box_shadow` (outer and inset ring), optional two-stop `gradient` sheen, and `outline` focus ring. Disabled state uses `layer_opacity` (`actions.rs:373,526`).
- **Card** (`card.rs:54-91`): fill, radius, text glyphs, icon glyph, optional accent rule.
- **Switch** (`switch.rs:151-192`): fill, radius, vertical `gradient`, `border`, shadows (via `shadows`).
- **Radio** (`radio.rs:66-92`): fill, radius, gradient, inset shadow, outline, disabled `layer_opacity`.
- **Segmented control** (`segmented.rs:76-144`): fill, radius, shadows, outline, disabled `layer_opacity`.
- **Text input** (`text_input.rs:30-35,369,680`): fill/radius/border, `outline` for focus/danger, disabled `layer_opacity`.
- **Markdown image** (`markdown/image.rs:60,76`): `pixels` images (image atlas), radius; broken-image placeholder is also `pixels`.
- **Table** (`markdown/table.rs:264,318,321`): inset shadows, `border_sides`, box shadows.
- **Tab strip** (`shell/tab_strip/tab.rs:209,237`): `cutout_circle` (requires a layer), `clip_fade_linear` (soft clip; may or may not isolate depending on paint count).
- **Toolbar** (`shell/toolbar.rs:51,89`): `system_material` (native/fallback, not the instance shader).

**Answer for kit:** drawing all of `rune-kit` needs **layers**, because of disabled `layer_opacity` states, the tab avatar `cutout_circle`, and possibly a multi-paint soft clip. It does **not** need offscreen Gaussian/backdrop blur passes: the only “blur” in kit is `box_shadow`’s analytic shadow, which is `KIND_SHADOW` in the main pass. It needs rects, borders/outline rings, inset/outer shadows, vertical two-stop gradients, glyphs, icons and images. It does not need `KIND_RADIAL`, `KIND_DASHED`, `KIND_SEGMENT`, `KIND_TRIANGLE`, effects, rune-light or glass. The one native-material exception is the shell toolbar’s `system_material`; headless output uses its fallback fill, and a windowed host would need the platform material view for exact parity.

### 9. Minimum viable renderer: plain rect and glyph UI

The smallest correct path, in order:

1. **Build a frame.** Call Rune’s `Runtime::frame` (or the app’s frame builder). Read `rt.instances`, `rt.text.atlas`, and `rt.images` (`runtime.rs:469`; `text/atlas.rs:215-223`; `pixels.rs:216-229`). For a plain UI, only glyph atlas page 0 is needed. `Instance::params[1]` selects the kind; skip 8, 9, 12, 13 for this path.
2. **Upload instances.** One vertex buffer, stride 128, instance step, attributes 0–7 as above (`metallib.rs:34-37,92-97`). Upload the whole vector. There is no index buffer.
3. **Create the main pipeline.** Vertex `vs` and fragment `fs` from `clip.wgsl` + `shader.wgsl`; triangle strip; no depth; blend premultiplied source-over. Use the target’s format; for an `Rgba8UnormSrgb` target, use `srgb_blend = false` (`pipelines.rs:94-127,205-217`). If you use a non-sRGB target, set `srgb_blend = true` and make sure CPU instances were built with sRGB premultiplication, or convert.
4. **Create bind group 0.** Globals uniform (viewport + `flags.x = srgb_blend`), glyph atlas page 0 as `R8Unorm` at binding 1, a 1×1 RGBA stand-in at binding 2, a 16-byte zero projection at binding 3 (`pipelines.rs:147-174`; `render.rs:17-22`). No sampler. If you want images later, use the image page bind group instead and batch by page.
5. **Upload the glyph atlas.** `Atlas::data` is the full 2048×2048 R8 page; upload rows or the whole texture. If pages >0 exist, create one texture per page and bind by `params[2]` (`upload.rs:211-228`; `atlas.rs:215-223`). For a plain UI at rest, page 0 is normally enough.
6. **Draw one pass.** Clear to the app’s clear colour; bind the pipeline and group 0; set the vertex buffer; `draw(0..4, 0..instance_count)` (`render.rs:909-937`). The shader applies the clip; you may also set a scissor to the clip rect for coarse culling. All coordinates are device pixels; do not apply a point-to-pixel transform again.
7. **Implement two fragment branches.** For rect: `sd_rounded` + `border_over` or plain coverage (`shader.wgsl:405-425`; `clip.wgsl:21-33,63-83`). For glyph: atlas `textureLoad` at `uv + floor(screen - rect.xy)`, `pow(cov, params.w)`, tinted by premultiplied `fill` (`shader.wgsl:520-543`). Include `clip_alpha` exactly; it is the difference between a correct HUD and clipped corners/feathers that are subtly wrong.
8. **Skip structural records.** Skip 8, 9, 12 and 13 in the minimum path; in particular, never submit kind 9 as a draw, because the shader has no dedicated branch for it. `KIND_EFFECT`/`KIND_BACKDROP_BLUR` discard in the shader, but skipping them before the draw is cheaper (`shader.wgsl:69-70,399-400`; `render/layers.rs:756-759`).
9. **If the UI uses images**, add the image atlas bind group and split draws at `KIND_IMAGE` page changes (`upload.rs:313-348`; `render.rs:918-932`). If it uses only rects/glyphs, no image code is needed.

That is the whole minimum: **one pass, one pipeline, one bind group, one 128-byte instance buffer, one R8 texture, no sampler, no offscreen targets**.

### 10. Full parity renderer: additional targets and passes

Beyond the minimum, a full renderer needs:

- **Layer targets and composite.** Allocate `Rgba16Float` targets in 64-pixel buckets with a projection uniform; clear transparent; draw layer contents; composite with the kind-8 branch; apply opacity, clip/fade, rounded clip, cutout and turn (`layers.rs:6-8,414-515,694-760`; `shader.wgsl:359-398`). Compute target bounds from the union of primitive bounds and per-kind grow; do not trust the layer marker’s `rect` (`layers.rs:335-355`).
- **Layer Gaussian.** Two or four passes with `layer_blur.wgsl` and its 128-tap uniforms; sigma clamped to 64 (`layer_blur.rs:5-15,97-123,136-202`).
- **Backdrop copy and blur.** A per-format viewport-sized copy texture; split the pass at each `KIND_BACKDROP_BLUR`, copy the target up to the record, run the 7-mip half-resolution 13-tap down / 9-tap up pyramid, and composite the result with `backdrop_composite.wgsl` inside the rounded rect/clip. Rune caps backdrop blurs at four per frame; elements past the cap draw only their fill (`backdrop_blur.rs:9-25,292-335,338-442`; `pass.rs:86-177`; `backdrop_blur.wgsl:1-71`; `backdrop_composite.wgsl:1-69`).
- **Effects.** Interpret `KIND_EFFECT` per `El::effect` mark/data; either port `rune-fx`’s family shaders, mask pyramid, frosted-lens blur and blend modes, or replace them (`rune-fx/src/renderer.rs:151-187,420-507`; `rune-fx/src/pipes.rs:1-18`). A faded effect is already inside a layer; a non-faded one draws in the open pass at the slot.
- **Outline text.** If exact moving/scaled text is required, add the `Rgba32Uint` outline store, binding 4, and `outline.wgsl`; otherwise force the text system to the atlas path (`outline.wgsl:4-13`; `render/outlines.rs:10-15`; `variant.rs:76-85`).
- **Subpixel text.** Optional dual-source pipeline (`variant.rs:25-63,284-315`); otherwise grayscale atlas coverage still works.
- **Windfoil atlas fill.** If outlines are enabled, either implement the fill pass into the R8 pages or ensure the atlas is CPU-filled before reading it (`render/fill.rs:111-158`; `text/atlas_fill.rs:1-151`).
- **rune-light / glass.** Port or replace the G-buffer, field, shadow, GI and composite passes and the glass renderer (`rune-light/src/render.rs:95-235`; `glass.rs:288-310`).
- **Native surfaces/materials.** Implement `SurfaceRenderer` for `Runtime::surfaces`, and the platform material view or its fallback for `El::system_material` (`runtime.rs:469`; `build.rs:843-856,1059-1068`).
- **Encoding consistency.** Every target (frame, layer, blur scratch, backdrop) must agree on linear-versus-sRGB-encoded premultiplied values; `EffectSite::srgb_blend` tells a compositor which one the pass uses (`render.rs:160-165`; `layers.rs:6-8`).

## Conflicts

These are places where a comment or README disagrees with the implementation, or where a name is misleading enough to cause a port bug.

1. **README says `rune-kit` disabled controls use `El::dim`, but the code uses `layer_opacity`.** The README section on isolated opacity says kit uses leaf dimming for disabled controls (`crates/rune/README.md:2170-2180`), while `rune-kit` calls `layer_opacity` in `actions.rs:373,526`, `radio.rs:89`, `segmented.rs:144`, `switch.rs:94`, `text_input.rs:30-35,369,680`, `popup_list.rs:268`, `menu.rs:239`, and `select.rs:325`. `layer_opacity` is documented in code as “Fade the whole subtree as one composited layer” (`el/visuals.rs:278-292`). The code is authoritative: disabled kit controls can allocate layers, contrary to the README’s “kit uses this [dim]” claim. This matters for the minimum renderer: a kit UI without layers will not match disabled states.
2. **`Instance::params[2]` is described as “shadow sigma,” but it is a different quantity in almost every kind.** The field comment is `render.rs:209`; the actual uses are AA softness (`KIND_RECT`/`KIND_GRADIENT`/`KIND_DASHED`/`KIND_RADIAL`), shadow/inset sigma, glyph rotation, glyph atlas page, image premultiplied flag, segment cap flag, layer blur sigma, and effect bleed. Only a per-kind table is safe. In particular, for `KIND_SHADOW` and `KIND_INSET`, `params[2]` is **half the CSS blur radius**, not the CSS blur (`shadow.rs:63`; `border.rs:44`).
3. **`KIND_IMAGE`’s doc comment omits two payload fields that the shader uses.** It says `uv.xy` origin, `uv.zw` size, and `fill.a` opacity (`render.rs:49-51`), but the actual instance also carries `params[0]` (image page) and `params[2]` (premultiplied flag) (`content.rs:97-104`). A port that ignores `params[2]` will darken straight-alpha images or double-premultiply decoded mips.
4. **`KIND_GLYPH`’s doc comment does not mention `radii.w`’s outline-zoom role or `params[0]`’s icon rotation.** `render.rs:37` only says glyph; `blend.rs:57-69` and `outline.wgsl:268-288` show the outline payload, and `blend.rs:85-120` shows `params[0]` as icon turn. A host that assumes every kind-2 is a static atlas glyph will mishandle icons and moving text.
5. **Rune-ref’s layer representation differs from the production `Instance`.** `rune-ref` stores a layer’s clip radii in `Primitive.border` and its turn in a sidecar (`crates/rune-ref/src/lib.rs:25-36`), and its adapter converts them to/from `fade[3]`/`border` when crossing to the production `Instance` (`rune-ref/src/gpu.rs:8-52`). This is not a bug, but it is evidence that the production ABI uses `fade[3]` for layer clip radii and `border[1..4]` for turn; do not copy the ref struct layout as the GPU ABI.
6. **The README’s claim that `rune-ref` “covers only flat primitive kinds 0–4 and rejects layer records” is stale for this commit.** `rune-ref` now supports layers 8/9 and kinds 10/11, treats kind 12 as a no-op, and rejects only unsupported layer blur and kinds 5/6/7/13 in its CPU path (`rune-ref/src/lib.rs:87-148`, `shader.rs:293-314`). The production renderer supports all kinds. Use the code, not the README, when deciding what a replay must handle (`crates/rune/README.md:2216`).

## Feature, data, shader and pass table

“Extra pass” means beyond the single main render pass. “No” does not mean zero cost; it means the feature is a branch or draw in the main pass.

| Feature | Data emitted | Shader path | Extra pass? | Source lines |
|---|---|---|---|---|
| Rounded rect fill | `KIND_RECT`, `fill` premul, `radii` | `fs` kind<0.5, `sd_rounded` | No | `render.rs:35`; `build.rs:1076-1082`; `shader.wgsl:405-425` |
| Rect border / outline ring | `KIND_RECT`, `border`, `params.x`, `uv` sides | `border_over` | No | `build.rs:943-1099`; `shader.wgsl:316-328,409-422` |
| Outer shadow | `KIND_SHADOW`, `params.z` sigma, optional hole | analytic `shadow`/`erf2` | No | `shadow.rs:25-73`; `shader.wgsl:111-153,426-435` |
| Inset shadow | `KIND_INSET`, spread/sigma/offset | `box_cov`/`shadow` | No | `border.rs:37-49`; `shader.wgsl:493-507` |
| Vertical gradient | `KIND_GRADIENT`, top/bottom colours | mix over y | No | `build.rs:971-986`; `shader.wgsl:508-519` |
| Multi-stop radial/linear gradient | one `KIND_RADIAL` per stop pair | radial/linear stop segment | No (multiple draws) | `build.rs:987-1057`; `shader.wgsl:438-461` |
| Dashed border | `KIND_DASHED`, dash/gap/phase | `ring_arc`/`dash_cov` | No | `build.rs:924-934`; `shader.wgsl:264-314,462-472` |
| Stroke segment | `KIND_SEGMENT`, endpoints/half-width | `segment` | No | `shape.rs:7-34`; `shader.wgsl:155-181,487-488` |
| Filled triangle | `KIND_TRIANGLE`, three points + AA mask | `triangle` | No | `shape.rs:35-57`; `shader.wgsl:183-242,489-492` |
| Atlas glyph | `KIND_GLYPH`, `params[2]=page`, `uv.xy` | atlas `textureLoad` + `pow` | No | `blend.rs:57-83`; `shader.wgsl:520-543` |
| Outline glyph | `KIND_GLYPH`, `radii.w>0`, `border` record | `outline.wgsl` branch | No (needs outline store; fill pass for masks) | `blend.rs:57-69`; `outline.wgsl:272-313` |
| Monochrome icon | `KIND_GLYPH`, `params[0]` turn, R8 atlas | glyph branch + rotation | No | `blend.rs:85-120`; `shader.wgsl:81-87,520-543` |
| Colour icon / emoji | `KIND_IMAGE`, image page, premult flag | image branch | No | `content.rs:144-159`; `helpers.rs:287-303`; `shader.wgsl:473-486` |
| Image | `KIND_IMAGE`, `uv.xy/zw`, fill.a | manual bilinear + sd coverage | No | `content.rs:81-108`; `shader.wgsl:249-259,473-486` |
| Layer composite | `KIND_LAYER`/`END`, opacity/blur/turn/hole | kind 8 texture sample | Yes | `build.rs:728-739`; `layers.rs:694-760`; `shader.wgsl:359-398` |
| Layer Gaussian | `params[2]` sigma, blur scratch | `layer_blur.wgsl` modes | Yes (2 or 4) | `layers.rs:492-515`; `layer_blur.rs:97-123,136-202` |
| Backdrop blur | `KIND_BACKDROP_BLUR`, sigma/opacity | `backdrop_blur` + composite | Yes (copy + pyramid + composite) | `slots.rs:38-59`; `backdrop_blur.rs:338-442`; `backdrop_blur.wgsl`; `backdrop_composite.wgsl` |
| Effect slot | `KIND_EFFECT`, mark/data/bleed/scale | none in über; host hook | Yes (host-defined) | `slots.rs:10-32`; `render.rs:138-199,876-905` |
| Cutout hole | layer `radii=[cx,cy,inner,outer]` | `hole_alpha` | Yes (layer) | `build.rs:696-707`; `shader.wgsl:346-351,397` |
| Turned layer | layer `border=[0,angle,pivot]` | bilinear inverse turn | Yes (layer) | `render.rs:315-321`; `shader.wgsl:88-94,367-379` |
| Cached subtree | layer `params[3]=1`, `radii` id, `uv` sig | composite from retained texture | Yes (optional; can draw live) | `cache_layer.rs:312-318`; `layers.rs:369-397,431-456` |
| Plus-lighter layer | layer `params[0]=1` | clamp then One/One | Yes (layer) | `render.rs:84-103`; `shader.wgsl:394-396`; `layers.rs:614-616` |
| Native surface/video | `SurfaceDraw`, not `Instance` | `SurfaceRenderer` | Yes (separate renderer) | `runtime.rs:469`; `build.rs:1059-1068` |
| System material | native view or fallback fill | not über | Yes (platform) | `build.rs:843-856`; `runtime.rs:469` |

## Rough GLSL port size per shader path

These are translation estimates, not measured outputs. “Host” means pipeline/descriptor/pass code outside the shader.

| Path | WGSL source | GLSL estimate | Notes |
|---|---|---:|---|
| Clip/SDF/fade/continuous corners | `clip.wgsl` 83 lines | ~120 lines | Must be exact; shared by every path. |
| Rect + border + `box_cov` | `shader.wgsl:316-425` | ~220-260 lines | `border_over` and per-side border are the bulk. |
| Analytic shadow/inset | `shader.wgsl:111-153,330-344,493-507` | ~150-190 lines | `erf2`, 4-sample loop, exact square-corner area. |
| Segment | `shader.wgsl:155-181` | ~35-45 lines | Small but easy to get the thin-stroke weighting wrong. |
| Triangle | `shader.wgsl:183-242` | ~80-100 lines | `owns`/`soft` tie-breaking is the hard part. |
| Gradient (vertical/radial/dashed) | `shader.wgsl:264-314,436-486,508-519` | ~220-280 lines | Arc length, dash period fitting and stop partitions. |
| Image | `shader.wgsl:249-259,473-486` | ~50-70 lines | Straight/premultiplied and sRGB handling. |
| Glyph atlas | `shader.wgsl:520-543` | ~45-60 lines | Manual bilinear, coverage exponent. |
| Layer composite | `shader.wgsl:359-398` | ~70-90 lines | Hole, turn, resize, plus-lighter clamp. |
| Layer Gaussian | `layer_blur.wgsl` 67 lines + `render/layer_blur.rs` 202 lines | ~120-160 shader; ~250-350 host | 2/4 passes, 128 taps, variance subtraction. |
| Backdrop blur | `backdrop_blur.wgsl` 71 + `backdrop_composite.wgsl` 69 + `render/backdrop_blur.rs` 447 | ~220-280 shader; ~550-750 host | 7-mip pyramid, dynamic offsets, scissor, copy/split. |
| Outline glyphs (Windfoil) | `outline.wgsl` 313 lines | ~450-550 lines | Quadratic integration, hinting, Slug fallback. |
| Subpixel dual-source variant | `variant.rs:25-63,284-315` | ~60-90 lines | Only if exact subpixel text is required. |
| `rune-fx` families | `rune-fx/src/shaders/*` 2228 lines | ~2800-3500 lines | Eight families + common + blur/mip; host passes extra. |
| `rune-light` lighting | `rune-light/src/shaders/*` 1231 lines (7 shaders) | ~1700-2100 lines | G-buffer, field, shadow, GI, composite; host Rust is another ~1.7k lines. |
| Glass | `rune-light/src/glass.rs` + `glass.wgsl` | ~500-700 lines | Frost pyramid, refraction, lights. |

## The three hardest parts of the port

1. **Reconstructing Rune’s layer planner and compositor.** The `KIND_LAYER` record carries the element rect, not the final target rectangle. `prepare_layers` privately unions primitive bounds using per-kind growth, clips them, expands by `3*sigma`, buckets to 64 pixels, decides `Inline` versus `Render` versus `Cached`, binds the parent projection, and orders child passes before parent composites. A host that naively allocates the marker rect will clip shadows, glows and blur; a host that ignores `Show::Inline` will allocate needless targets; a host that mishandles nested scopes will break painter order. This is the largest reverse-engineering surface (`layers.rs:226-550,694-760`; `build.rs:728-739`).
2. **Exact antialiasing and colour math.** Rune’s pixel parity depends on the exact SDF formulas (`sd_rounded`, `sd_continuous`), `border_over`’s Chromium bleed rule, `erf2` shadow approximation, exact square-corner coverage, triangle edge ownership, dash arc length, gradient stop partitioning, packed fade offsets and the coverage exponent. Replacing any of these with a “visually equivalent” formula changes edge pixels, which is exactly where a port is judged. The clip/fade ABI is especially easy to get subtly wrong because widths are half-floats, offsets are 8-bit unorm, and a negative width means a linear ramp (`clip.wgsl:37-83`; `render.rs:226-292`).
3. **Text and texture resource semantics.** The R8 atlas is page-based, phased, and optionally GPU-filled from outlines; the image atlas is a different format with straight-versus-premultiplied sources; colour emoji and colour icons jump from `KIND_GLYPH` to `KIND_IMAGE`; page changes split draws; and the main shader uses `textureLoad`, not samplers. A host must reproduce the atlas residency, page bindings, coverage exponent, glyph outline fallback and sRGB image conversion to match text. This is more than “sample an R8 texture” (`text/atlas.rs:7,290-413`; `glyph_emit.rs:114-294`; `blend.rs:52-129`; `shader.wgsl:249-259,520-543`).

## Not found

- **No serialized paint packet / public layer plan.** `instances` and `marks` are public, but the final layer `rect`, `Show` state, target bucket, blur scratch and cache residency are private to `render::layers`. An external process must reconstruct them from the records (`runtime.rs:469-473`; `layers.rs:33-151,226-550`).
- **No public accessor for system-material draws.** `Runtime::materials` is `pub(crate)` (`runtime.rs:469-478`); headless output uses the fallback fill, so a separate process cannot reproduce native macOS materials from the runtime alone.
- **No Vulkan/GLSL/SPIR-V implementation.** The repository contains WGSL plus precompiled DXBC/Metal libraries; there is no GLSL or SPIR-V path (`crates/rune/src/shader.wgsl`, `clip.wgsl`, `outline.wgsl`, `backdrop_blur.wgsl`, `backdrop_composite.wgsl`, `layer_blur.wgsl`; `render/metallib.rs`, `render/dxbc.rs`).
- **No runtime verification.** I did not run Rune, the headless harness, Vulkan validation, or a pixel comparison. The line counts are estimates. I did not verify the layer planner’s behaviour on a real device with the feature breaker refusing isolation/blur/plus-lighter.
- **No full read of `render/breaker.rs`.** The feature-downgrade behaviour is inferred from `check_layer_features` and its use of `breaker::Feature` (`layers.rs:555-573`), not from a complete read of the breaker state machine.
- **No full read of every `rune-kit` component.** Kit coverage is based on systematic grep plus representative files; a component could use an API through a helper not caught by the grep.
- **No full read of every `rune-fx`/`rune-light` shader.** I read the renderer/pass structure and shader inventory, not every line of all 2,228 + 1,231 WGSL lines.
- **No platform text parity.** Exact CoreText/DirectWrite/Windfoil mask generation, dilation, hinting and subpixel filters live in platform-specific code I did not fully read; the atlas/outline ABI is documented here, but mask appearance is platform-dependent.
- **No native-surface/video port.** `SurfaceRenderer` and the native-surface upload/format handling were not investigated beyond the fact that they are a separate stream.
- **No GPU-spring path.** `Renderer::with_springs` uses a second bind group and a different vertex entry; it is outside the ordinary paint contract and was not analysed.

## References

Primary code (all paths relative to `rune` `f18ead8`):

- `crates/rune/src/render.rs` — `Instance`, kinds, packing, draw APIs, layer records.
- `crates/rune/src/render/layers.rs` — layer planning, target allocation, isolation, composite ordering.
- `crates/rune/src/render/layer_blur.rs` — layer Gaussian pipeline and uniforms.
- `crates/rune/src/render/backdrop_blur.rs` — backdrop copy/pyramid/composite.
- `crates/rune/src/render/pass.rs` — pass splitting and backdrop texture pooling.
- `crates/rune/src/render/pipelines.rs`, `render/metallib.rs`, `render/variant.rs` — bind groups, vertex layout, Windfoil variants.
- `crates/rune/src/render/fill.rs`, `render/outlines.rs` — atlas fill and outline store.
- `crates/rune/src/runtime/paint/build.rs` — paint emission.
- `crates/rune/src/runtime/paint/{content,shadow,border,slots,shape,bands,blend,helpers,cache_layer}.rs` — primitive emission helpers.
- `crates/rune/src/text/{atlas,glyph_emit,color_icon,icon,coretext_match}.rs`, `text/outline/*`, `text/atlas_fill.rs` — text and icon resources.
- `crates/rune/src/pixels.rs`, `crates/rune/src/image.rs` — image atlas and premultiplied mips.
- `crates/rune/src/shader.wgsl`, `clip.wgsl`, `outline.wgsl`, `backdrop_blur.wgsl`, `backdrop_composite.wgsl`, `layer_blur.wgsl` — shader paths.
- `crates/rune-fx/src/{renderer,pipes,lib}.rs`, `crates/rune-fx/src/shaders/*` — effect renderer.
- `crates/rune-light/src/{lib,render,glass}.rs`, `crates/rune-light/src/shaders/*` — lighting and glass.
- `crates/rune-ref/src/{lib,shader,gpu}.rs` — independent scalar reference for the same primitive ABI (useful cross-check, not the production renderer).
- `crates/rune-kit/src/*` — component paint usage.
- `crates/rune/src/runtime.rs` — public runtime fields (`instances`, `marks`, `surfaces`, `images`, `text`).

Secondary code examples used only to show integration shape, not as behavioural evidence: `examples/showreel/src/gfx.rs`, `examples/lab/src/gfx/*`, `examples/site-scenes/src/main.rs`.
