# Direct lighting and shadows for many point lights

**Question.** How are noise-free direct-lighting and shadow systems built for many point lights, and how does harbagsa's direct path compare?

**Date.** 2026-11-10

**Status.** Research note. Research snapshot: no code or build was changed. The
repository's code and measured evidence are the source of truth for harbagsa
numbers; external sources are cited by section or page. Stochastic and
path-traced methods are out of scope by instruction. The existing offline bake
and the existing hard ray-query shadows are the baseline, not a recommendation
to add more ray tracing.

**Method.** External PDFs were fetched on 2026-11-10 and read with
`pdftotext -layout`; quotations below were checked against that text. Engine
docs and specifications were fetched from their current URLs. Secondary
industry sources are labelled in the References.

## Answer

1. **The production pattern is two-level.** A spatial structure (2D tile, 3D
   cluster, or a hybrid) builds a per-pixel or per-cell list of lights, and a
   forward or deferred shading loop evaluates only that list. Forward+ uses 2D
   tiles and a depth prepass [1, §3–5]; clustered shading adds an exponential
   view-space depth subdivision [2, §3.1]; Light Indexed Deferred (LID) stores a
   per-tile list of light indices for a forward material pass [3][4]; DOOM
   Eternal uses a hybrid cluster + fine-tile list and lets each fragment pick
   the shorter list [5, "Light List Selection"].

2. **List storage and overflow are design parameters, not details.** The
   clustered paper uses variable-size per-cluster lists built against a light
   search tree [2, §4.4]; LID preallocates a full per-tile list and terminates
   it with a sentinel [4]; DOOM Eternal uses a fixed `LIGHTS_PER_TILE` stride
   filled by a bitfield/subgroup compaction [5, "Resolve Bitfields to Lists"];
   harbagsa uses a fixed 256-index stride per cluster and keeps the first 256
   it tests [ADR 0030; `cluster.comp`]. The last policy has no priority order.

3. **harbagsa is a legitimate LID-like variant, not canonical Forward+.** It is
   a fixed 16 × 9 × 24 cluster grid with a 256-index stride, one thread per
   cluster, and culling *before* the depth prepass. Forward+ culls after a depth
   prepass and uses the tile's actual min/max depth to tighten the tile frustum
   [1, §4.1]. At 96 lights harbagsa cannot overflow (96 < 256), so the cap is
   dormant; at more lights per cluster it drops the highest-index lights.

4. **The default point-light shadow is a six-face problem.** A cube shadow map
   renders six depth faces per point light [25, §12.2]; a shadow
   atlas packs those faces [30, "Shadow atlases"]; a dual-paraboloid map trades
   six faces for two hemispherical maps with different filtering/seam problems
   [13]. PCF is a fixed-tap depth comparison, not a physical area shadow
   [7][25, Listing 12-3]. All of these are deterministic and noise-free with
   fixed taps; their artifacts are bias/acne, Peter Panning, cube seams, and
   light bleeding, not stochastic noise.

5. **PCSS is the classical noise-free soft-shadow estimate, but it is too
   expensive for 96 lights.** It does a blocker search, estimates penumbra width
   from the light size and blocker/receiver distances, then PCFs with that width
   [11]. The original sketch used 36 blocker samples and 64 PCF samples at
   640 × 480 for 75 fps on a GeForce 7800 GTX [11, §4]. That is a hero-light
   budget, not 96 lights at 8 ms.

6. **LTC solves area-light shading, not visibility, and harbagsa has no use for
   it.** LTC evaluates the BRDF × polygon-light integral without noise [14], and
   the authors report 0.9 ms on PS4 at 1080p for diffuse + specular [14, course
   slide "Current performance"]. The same course calls area-light shadows an
   open research problem [14]. harbagsa is Lambert-only, with no specular term,
   so LTC would add cost without changing the flat look. The representative-point
   method is likewise a shading approximation (a sphere light's diffuse
   irradiance is a point light when the sphere is above the horizon) [15], not a
   shadow method.

7. **Ray-query shadows are exact for the zero-area light model and cheap for a
   one-cube BLAS, but they are not portable for free.** `VK_KHR_ray_query` is an
   optional device extension; ray queries run in any shader stage and return
   traversal results without launching shaders [18]. harbagsa builds one BLAS
   from the cube, rebuilds the TLAS every frame, and traces one
   `TerminateOnFirstHit | Opaque` ray per clustered light per fragment
   [`terms.glsl`; `acceleration_build.odin`]. At 96 lights and 1080p the measured
   full frame is 1.50–1.52 ms GPU total p50 (1.83–1.85 ms interval p50), with a
   1.116 ms scene pass and a 0.110 ms TLAS pass [evidence/perf-baseline;
   evidence/mixed-lighting]. ADR 0040's 4.29 ms shadow term is an older
   measurement and is not directly comparable.

8. **The current look is a deliberate transfer function, not a physical light
   model.** Physical point lights use candela and inverse-square falloff, with a
   finite range as a culling/windowing device [16, §4.3–4.4; 17]. glTF
   recommends `(1 − (d/r)^4) / d²` [17, "Range Property"]; Frostbite uses
   `(1 − (d/r)^4)^2 / d²` [16, Listing 4]. harbagsa uses `(1 − (d/r)^2)^2` with
   no `1/d²` [`terms.glsl`]. The design guide calls this "soft range falloff" and
   treats it as the signature [docs/design/world.md]. It is a stylised reach
   curve: brightness is nearly constant until the window closes, so the range
   control sets the lit volume, not the physical power.

9. **The main correctness risks are the emissive mask, the falloff/units gap,
   and the untested ray gate.** Every box with `emissive > 0` gets instance mask
   `0x01`, not just lamps, so all emissive geometry is non-occluding
   [`lights.odin`]. The shadow ray is traced even when the surface normal faces
   away from the light (`diffuse` is computed but not used as a gate)
   [`terms.glsl`]. Both are cheap to fix and do not change the look.

10. **The main scale risks are the cluster pass and the 256 cap.** The cluster
    pass is one thread per cluster, looping every light (O(clusters × lights)),
    with no light BVH and no depth-aware tile bounds [`cluster.comp`;
    ADR 0030]. At 96 lights that is ~332k sphere/AABB tests per frame; at 10k
    lights it is ~34.5M, and at 100k ~345M. The 256 cap is a per-cluster hard
    drop, and the overflow counter is one aggregate value, not a per-cluster or
    per-light report [`cluster.comp`; ADR 0030].

11. **The best noise-free moves preserve the hard-edged look.** Gate shadow rays
    on `diffuse > 0` and `falloff > 0`; consider a DOOM-Eternal-style hybrid
    cluster + fine-tile list; scene-tune the grid near/far and tile size;
    importance-order the 256 entries. A cube atlas with a one-tap depth compare
    is the portable fallback only if a non-RT target is required; it adds bias/seam
    artifacts and 36–144 MiB at 128–256². PCSS, LTC, VSM/ESM, and CSM are not
    fits for the 96-light path: they are either too expensive, need a shadow-map
    path, are directional-only, or soften the signature.

## Evidence

### 1. Many-light direct lighting

#### 1.1 Forward+: 2D tiles plus a depth prepass

Harada, McKee, and Yang define Forward+ as forward rendering plus a compute
light-culling stage that stores only the lights that contribute to each tile
[1, abstract]. The pipeline is depth prepass, light culling, final shading
[1, §3]. The depth prepass is not optional in their design: it supplies the
tile's minimum and maximum depth, so the tile frustum is tightened before the
light-overlap test [1, §4.1]. Their demo renders 3,072 lights at 1280 × 720 with
8 × 8 tiles [1, §5].

Two list-building strategies are given. The gather approach runs one thread
group per tile, reads each light, tests it against the tile frustum, accumulates
surviving lights in thread-local storage with local atomics, then flushes the
list [1, §4.1]. The scatter approach emits light/tile pairs, radix-sorts them by
tile, and derives per-tile offsets [1, §4.2]. The paper does not specify a fixed
per-tile cap; the thread-local buffer is the practical bound, and the paper's
own conclusion notes that a spatial (3D) subdivision might fix the long-frustum
false positives but costs more memory and ALU [1, §5]. That observation is the
door to clustered shading.

For harbagsa, the relevant difference is order: harbagsa culls before its depth
prepass, so it cannot use the tile's actual depth range [ADR 0030]. It uses the
full fixed depth slice instead. That is simpler and avoids a depth-read
dependency, but it keeps more lights than a depth-aware tile would.

#### 1.2 Clustered shading: a 3D grid with exponential depth

Olsson, Billeter, and Assarsson group view samples into clusters by 3D position
(and optionally normal), then assign lights per cluster [2, abstract]. Their
cluster key is built from the screen tile plus a depth subdivision that is
exponential in view space, so near and far clusters have comparable shape
[2, §3.1]. Clusters are discovered from the depth buffer: sort/compact the
cluster keys, then shade each unique cluster [2, §3.2]. Light assignment uses a
search tree over the lights and produces variable-size per-cluster lists
[2, §4.4].

Their headline result is the reason the technique exists: a scene with about
2,400 lights renders in 17 ms with clustered shading versus 26 ms with tiled
shading on a GTX 480, with 2.3 ms for clustering, 1.5 ms for light assignment,
and 5.6 ms for shading [2, Fig. 1]. The abstract also claims up to around one
million light sources in the extreme [2, abstract].

This is a stronger form of clustering than harbagsa's. harbagsa uses a fixed
16 × 9 × 24 grid and fixed depth slices; Olsson's clusters are data-driven from
the depth buffer, so empty space is skipped and the cluster count adapts to the
view. harbagsa's version is cheaper to implement and deterministic, but it
cannot skip empty clusters and its grid does not adapt to resolution or aspect.

#### 1.3 Light Indexed Deferred: the closest analogue

LID assigns each light an index, stores indices in a per-tile list, and then runs
a forward shading pass that reads the list. It keeps forward materials and MSAA
while getting GPU-side light selection. Trebilco's research project is from 2007
and was published as ShaderX7 chapter 2.9 [3]. Pettineo's 2012 write-up is the
clearest public description and benchmark:

> "For the light indexed deferred renderer implementation I used a depth-only
> prepass to fill the depth buffer, which was then used by a compute shader to
> compute the list of intersecting lights per-tile. This list was stored in
> either an R8_UINT or R16_UINT typed buffer (8-bit for < 255 lights, 16-bit
> otherwise), with enough space pre-allocated in the buffer to store a full light
> list for each tile. So no bitfields or linked lists or anything fancy like
> that, just a simple per-tile list terminated by sentinel value." — [4]

His 1080p results on a GTX 570 and an HD 6970 show LID competitive at 128 lights
and falling behind tiled deferred as the count rises: on the HD 6970, 128 lights
is 5.26 ms LID vs 5.71 ms tiled deferred; 512 lights is 11.67 ms vs 11.36 ms;
1024 lights is 22.22 ms vs 20.00 ms. On the GTX 570, tiled deferred wins at every
tested count. LID's advantage is MSAA, where it beats tiled deferred on the AMD
card at every count [4].

harbagsa's cluster index buffer is structurally LID with a 3D cell instead of a
2D tile and a 32-bit index instead of R8/R16. The 256-entry stride is the same
"preallocate a full list" choice, with a count instead of a sentinel
[`cluster.comp`; ADR 0030]. That is a useful sanity check: the fixed-stride
design is not novel or naive; it is a known 2007–2012 technique. The difference
is that harbagsa's cell is a cluster, not a tile, and the list is consumed by a
forward pass with one material.

#### 1.4 Clustered deferred versus clustered forward

Clustered deferred writes a G-buffer and shades clusters from it; clustered
forward uses a pre-z pass and shades in the forward pass [2, §1, §4]. Forward+
avoids the G-buffer's material restrictions and memory traffic [1, §1]. For
harbagsa, the scene has one shader and one cube mesh, so a G-buffer would buy
nothing: there is no material variety to defer, and the forward path already has
the depth prepass. A clustered deferred design would add bandwidth and a fat
G-buffer for no visual gain. The current clustered-forward choice is the simpler
fit.

Frostbite is a useful production counterpoint: it supports a hybrid engine with
both forward and deferred tiled renderers, and its light culling uses tight
bounding volumes that respect the light's shape, with all lights evaluated in one
loop to avoid re-reading the G-buffer [16, §4.11]. That is the tiled-deferred
shape of the problem: a G-buffer is worth it when materials vary, and the light
loop is organized around bandwidth. harbagsa has neither the material variety
nor the G-buffer, so the forward cluster loop is the better match.

#### 1.5 Per-object light lists

A per-object list is the oldest many-light compromise: each object receives the
lights whose bounds overlap it. Unity's default Forward path is the canonical
fixed-cap form: 9 lights per GameObject (1 main + 8 additional), with per-camera
caps of 256 additional lights on desktop/console, 32 on mobile, and 16 on
OpenGL ES 3.0 and earlier [29]. Forward+ removes the per-object limit but keeps a
per-camera limit [28].

The problem is scale with surface size. A floor or wall that spans the arena
collects every light that overlaps the arena, so the per-object list becomes an
all-light list for the largest surfaces. harbagsa's ADR 0030 rejects per-object
lists for exactly this reason [ADR 0030]. The Forward+ paper also notes that
per-pixel lists are possible but increase memory and compute, which is why
per-tile lists are the compromise [1, §3.1]. Per-object lists are a good fit for
small objects and a bad fit for the large boxes that define this arena.

#### 1.6 Index-list overflow and grid choices

There is no single industry answer. The options in the literature are:

| Scheme | Storage | Overflow behaviour | Source |
| -- | -- | -- | -- |
| Forward+ gather | thread-local storage per tile, flushed to global | bounded by the TLS size; no priority | [1, §4.1] |
| Forward+ scatter | light/tile pairs, radix sort, per-tile offsets | variable-size; no fixed cap | [1, §4.2] |
| Clustered | variable-size per-cluster list from a light search tree | no fixed cap in the paper | [2, §4.4] |
| LID | preallocated full list per tile, sentinel | list sized to the light count; R8 vs R16 | [4] |
| DOOM Eternal | fixed `LIGHTS_PER_TILE` stride, bitfield + subgroup compaction | fixed stride; sized for the scene | [5] |
| harbagsa | fixed 256-index stride per cluster, count | first 256 kept; one aggregate overflow counter | [`cluster.comp`; ADR 0030] |

DOOM Eternal is the most instructive production case because it explicitly
combines the two spatial schemes. It started with clustered binning in DOOM
2016, then found that larger scenes put distant small lights and decals into one
big cluster, and that fine tiles are bad across large depth discontinuities. Its
answer is a hybrid: 256 × 256 coarse tiles, 32 × 32 fine tiles, clusters with the
same depth distribution as the earlier renderer, and a per-fragment choice of the
shorter of the cluster list and the tile list. The slide claims "never worse than
clustered" [5, "Hybrid Binning", "Coarse Raster", "Light List Selection"]. The
binning budget is stated as "very tight (<500us)" [5].

The grid numbers in production vary widely: 8 × 8 tiles in Forward+ [1, §5];
32 × 32 fine tiles plus clusters in DOOM Eternal [5]; a 512-clustered-element
default in Godot's Forward+ renderer [31]; 2D tiles in Unity's Forward+ path
[28]; and 16 × 9 × 24 in harbagsa [`cluster.glsl`]. There is no universal grid.
The grid should match the light density, the depth complexity, and the target
resolution. A fixed grid that is tuned for 1080p is coarse at 4K; a grid tuned
for a 40 m arena wastes slices on a 200 m far plane.

#### 1.7 What the production numbers say

The absolute numbers are not comparable across GPUs and scenes, but the shape
is consistent:

- Forward+: 3,072 lights at 1280 × 720, 8 × 8 tiles [1, §5].
- Clustered: ~2,400 lights, 17 ms vs 26 ms tiled on a GTX 480; 10k lights in
  Sponza [2, Fig. 1, §5].
- LID: 128–1024 lights at 1080p on 2012 GPUs; competitive at low counts,
  behind tiled deferred at high counts [4].
- DOOM Eternal: thousands of lights/decals, hybrid binning under 500 µs, 60 fps
  on consoles [5].
- Unity: 256 additional lights per camera on desktop, 32 on mobile [29].
- Godot: 512 clustered elements default [31].
- harbagsa: 96 lights at 1080p, 1.50–1.52 ms GPU total p50 on an RX 9060 XT
  [evidence/mixed-lighting].

The lesson is that 96 lights is a small-to-moderate budget by modern standards.
The hard part is not the light count; it is the visibility term and the
per-cluster list policy at the edges of the budget.

### 2. Point-light shadows without ray tracing

#### 2.1 Cube shadow maps

A point light has no single projection direction, so the standard shadow map is a
cube: six depth faces rendered from the light position, one per axis direction.
GPU Gems 1 chapter 12 describes the full pipeline for point lights: render the
six faces, pack depth into colour channels, compare with a distance bias, and
filter with four taps [25, §12.2]. Unity HDRP confirms the production count: "A
Point Light renders six shadow maps (the number of faces in a cubemap)" [30,
"Shadow maps"].

The cost is six renders per shadowed light. At 96 lights that is 576 face
renders per frame if every light is shadowed and dynamic. Depth-only rendering
is cheap per face, but the state changes, clears, and six-face submissions add
up. Frostbite notes that ideally all lights cast shadows, but the cost makes
that unaffordable, so productions usually shadow a subset [16, §4.10.4].
harbagsa's current model shadows every clustered light. The memory is also six
faces per light:

| Face size | Per face (D32) | Per light (6 faces) | 96 lights |
| --: | --: | --: | --: |
| 128² | 64 KiB | 384 KiB | 36 MiB |
| 256² | 256 KiB | 1.5 MiB | 144 MiB |
| 512² | 1 MiB | 6 MiB | 576 MiB |

These are arithmetic from 4 bytes per depth texel; they are not a benchmark.
The point is that 96 shadowed point lights are a memory and submission problem
before they are a filtering problem.

Cube maps have a specific edge case: filtering across a cube face boundary
samples outside the selected face and clamps or wraps, which produces seams. The
`ARB_seamless_cube_map` specification describes the cause exactly: "the locations
of the individual elements required during a linear sampling do not lie within
the determined face, and their coordinates will therefore be modified by the
selected clamping and wrapping rules. This often has the effect of producing
seams or other discontinuities in the sampled texture." The extension allows
samples from adjacent faces to fix it [24]. Any cube-map fallback needs seamless
filtering (or manual face-edge handling), or the seams will be visible on flat
box faces.

#### 2.2 Shadow atlases

An atlas packs many lights' faces into one texture, which reduces bindings and
lets the renderer pack and rescale individual maps. Unity HDRP's punctual shadow
atlas is the clearest production description: one atlas for punctual shadows,
default 4096 × 4096, and a point light consumes six maps [30, "Shadow atlases"].
The page gives the capacity example: a 4096² atlas fits sixteen 1024² maps, or
two 2048² plus four 1024² plus eight 512² plus thirty-two 256² [30].

At 96 point lights × 6 faces = 576 faces, a 4096² atlas holds 256 faces at 256²,
so the full set needs 2.25 atlases (144 MiB). A cube array is the alternative
packing: one layer per light, no atlas allocation, but still six faces and the
same memory. That is the concrete reason a 96-light cube-map path is not a
drop-in replacement for the current ray path. Caching static lights helps: a
static fixture's faces do not need re-rendering when only the camera moves. But
harbagsa has dynamic lamps and moving crates, so a cache would be partial at
best.

#### 2.3 Dual-paraboloid shadow maps

A dual-paraboloid map replaces the six cube faces with two hemispherical
paraboloid projections, one for each direction along the light's axis [13]. It
cuts the face count from six to two and can be cheaper to render and store. The
trade is a non-uniform texel distribution and a seam at the hemisphere boundary,
plus the usual vertex interpolation issues of a non-linear projection. It is a reasonable portable
option when memory is tight and the shadow filter can tolerate the distortion,
but it is not what modern engines use for point lights; the cube atlas is the
more common production choice [30].

#### 2.4 PCF: fixed taps, deterministic, not physically soft

Percentage-Closer Filtering samples the shadow map at several offsets, performs
the depth comparison at each sample, and averages the *results* [7]. GPU Gems 1
shows the four-tap point-light version and notes that the comparison must happen
before the average: "we first compare the squared distances and then average the
results of the comparison. This is called percentage-closer filtering" [25,
Listing 12-3]. It also notes the limitation: "the shadows are of course not
accurate soft shadows, because they do not take into account the relationships
between occluders, receivers, and the size of the light source" [25, §12.2].

PCF is deterministic and noise-free with a fixed tap pattern. It is also
band-limited: a larger kernel needs more taps to avoid banding, and each tap is
a depth comparison plus a fetch [25, §12.2]. The companion GPU Gems chapter is
entirely about this shadow-map antialiasing problem [27]. For a flat box scene, a
single tap already gives a hard, aliased edge; four taps give a slightly soft,
still hard-edged look. TAA can resolve the remaining edge aliasing over frames,
as harbagsa already does.

#### 2.5 PCSS: blocker search plus penumbra estimate

Percentage-Closer Soft Shadows adds two steps to PCF [11]:

1. **Blocker search.** Sample the shadow map in a region sized by the light and
   the receiver, and average the depths closer to the light than the receiver.
2. **Penumbra estimate.** Using a parallel-planes approximation,
   `w_penumbra = (d_receiver − d_blocker) · w_light / d_blocker`.
3. **Filtering.** PCF with a kernel proportional to the penumbra estimate.

The original sketch reports 36 blocker samples and 64 PCF samples at 640 × 480,
running at about 75 fps on a GeForce 7800 GTX [11, §4]. It uses a single shadow
map sample, so it is an approximation of the area light's visibility, not a
multi-sample solution. With fixed tap patterns it is deterministic and
noise-free; with random rotation it becomes stochastic, which the brief excludes.

PCSS is the right tool for a few hero lights with a meaningful radius. It is the
wrong tool for 96 point lights at 8 ms: at 100 taps per light and even 20 lights
per pixel, the tap count is in the billions per frame. The algorithm also needs a
light size; harbagsa's point lights have none, so adding PCSS would first require
a new light-shape decision.

#### 2.6 VSM, SAVSM, ESM, and MSM

Variance Shadow Maps store the first and second depth moments per texel, then use
Chebyshev's inequality to estimate visibility. Because the moments are linear,
the map can be filtered with hardware filtering or a blur [8][26, §8.4]. The
price is light bleeding: light appears in areas that should be fully shadowed,
especially where the occluder/receiver depth ratio is large. The GPU Gems 3
chapter is direct about the limit: "this problem cannot be completely solved
without taking more samples (which degenerates into brute-force
percentage-closer filtering)" [26, §8.4.3]. It also describes Peter Panning: a
bias large enough to stop acne pulls the shadow away from its caster [26, §8.3.1].

Summed-Area VSM adds a summed-area table and a light-bleeding reduction function
[26, §8.5]. Exponential Shadow Maps replace the depth test with an exponential
function that can be pre-filtered; the authors report 8× less memory than
convolution shadow maps and less contact-point leaking than VSM, while still
needing care for light leaking [9, Fig. 1, abstract]. Moment Shadow Maps use
higher-order moments to reconstruct a filtered hard shadow with fewer artifacts,
at the cost of more memory and math [10].

All four are deterministic and noise-free. Their failure modes are bias,
bleeding, and ringing, not stochastic noise. They are a good fit for a shadow-map
path with a few lights and a need for cheap filtering; they are not a reason to
replace harbagsa's exact ray-query visibility with an approximate moment test.

#### 2.7 Cascaded shadow maps are directional-only

Cascaded Shadow Maps split the camera frustum into depth ranges and render a
separate shadow map per range, giving higher resolution near the viewer. NVIDIA's
guide states the use case plainly: "CSM are usually used for shadows cast by the
sun over a large terrain" [12]. The split points should be exponentially
distributed, and with the usual 1–4 splits the resolution change makes the split
points visible [12, §2].

CSM does not solve a point light: a point light is omnidirectional, and its
shadow map is a cube, not a cascade. harbagsa has no directional light at all
[ADR 0041], so CSM is out of scope. It is mentioned here only to close the
"cascades" branch of the brief.

#### 2.8 Contact shadows are a supplement, not a visibility term

Unreal's contact shadows are a per-pixel, per-light screen-space depth-buffer ray
march: "you're directing the renderer to execute a per-pixel screen space
algorithm on a per-light basis" and "performing scene depth buffer ray marching"
[32]. They add contact darkening that a shadow map or a coarse ray might miss.
They are not a complete visibility term: an occluder outside the depth buffer
cannot cast, and the sample count is fixed, so "you'll see more noise (artifacts)
as you increase the Contact Shadow's length" [32].

ADR 0040 already rejects contact shadows as the sole term for the same reason:
they cannot supply a long shadow from an off-screen box [ADR 0040]. They remain a
cheap deterministic supplement if the flat look wants a darker contact line.

#### 2.9 Artifacts and fixes

| Artifact | Cause | Standard fix | Source |
| -- | -- | -- | -- |
| Shadow acne | Depth bias too small; texels span a large depth range | Slope-scaled bias; normal offset; more depth precision | [26, §8.3.1] |
| Peter Panning | Bias large enough to detach the shadow | Slope-scaled bias; moment/variance representation | [26, §8.3.1] |
| Cube seams | Linear filtering crosses a cube face boundary | Seamless cube-map filtering; manual face-edge handling | [24] |
| Light bleeding | VSM/ESM moment reconstruction includes occluded light | Variance clamp; SAVSM light-bleeding reduction; MSM; ESM threshold/fallback | [26, §8.4.3; 9; 10] |
| Cascade split visible | Resolution changes sharply at a split | Blend/stabilise cascades; fewer splits; matched texel density | [12, §2] |
| PCF banding | Too few taps for the kernel size | More taps; smaller kernel; TAA | [25, §12.2] |
| Contact-shadow noise | Fixed sample count over a long screen-space ray | Shorter length; more samples; treat as contact-only | [32] |

#### 2.10 Which techniques are deterministic and noise-free

| Technique | Noise-free? | Soft? | Main limitation |
| -- | -- | -- | -- |
| Cube map, 1 tap | Yes | No (hard) | Acne, bias, seams |
| Cube map + PCF (fixed taps) | Yes | Filtered, not physical | Banding, bias, Peter Panning |
| Cube atlas + PCF | Yes | Filtered | Atlas capacity, 6 faces/light |
| Dual-paraboloid + PCF | Yes | Filtered | Seam, non-uniform texels |
| PCSS (fixed taps) | Yes | Contact-hardening | 36 + 64 taps, needs light size |
| VSM / SAVSM | Yes | Filterable | Light bleeding, bias |
| ESM | Yes | Filterable | Light leaking, exponential overflow care |
| MSM | Yes | Filtered hard | Memory/math |
| CSM | Yes | PCF/filtered | Directional only |
| Contact shadows (fixed steps) | Yes at short lengths | Contact darkening | Screen-space, incomplete |
| Ray query, 1 ray | Yes | No (hard) | Aliasing, RT hardware |
| Ray query, N fixed rays | Yes (banded) | Yes | N× cost |
| Stochastic PCSS/ray soft | No | Yes | Excluded by the brief |

### 3. Soft shadows for point and area lights

#### 3.1 PCSS is the reference noise-free soft-shadow estimate

PCSS's contribution is the penumbra estimate, not a new sampling scheme: it
turns the light size and the blocker/receiver geometry into a filter width, then
uses ordinary PCF [11]. With fixed taps it is deterministic and noise-free, but
it is a *single* shadow-map sample, so it cannot reproduce the colour gradient or
the full visibility integral of a large area light. It is the right choice for a
hero lamp with a radius and a shadow map; it is not a 96-light technique.

#### 3.2 Representative point: one point on the light, for shading

The representative-point method replaces the area light with the point on its
surface that contributes most to the shading point, then evaluates the ordinary
BRDF [15, "Representative Point"]. Unreal's notes give the useful special case:
"Irradiance for a sphere light is equivalent to a point light if the sphere is
above the horizon" [15]. The method is a shading approximation; it does not
produce a soft shadow by itself. A single shadow ray from the representative
point gives a hard shadow from that point, not the area light's penumbra.

For harbagsa this is mostly irrelevant: the renderer has no specular term, and a
sphere light above the horizon has the same diffuse irradiance as a point light
[15]. Adding a representative point would not change the flat Lambert look; it
would only add a light-shape concept without a visible payoff.

#### 3.3 LTC: noise-free area-light shading, no visibility

Linearly Transformed Cosines evaluate the product of a BRDF and a polygonal light
in closed form by transforming the clamped-cosine distribution [14]. The authors
describe the goal as evaluating the product "in a fast and noise free way"
[14, course slide "Enter: Linearly Transformed Cosines"]. The course reports
0.9 ms on PS4 at 1080p for diffuse + specular [14, "Current performance"], and
the same course calls area-light shadows an open research problem [14, "The
elephant in the room"].

LTC is a shading solution. It assumes the light is unoccluded; visibility is a
separate term. It is also aimed at glossy materials. harbagsa has no specular
and no area lights, so LTC has no job here. It would become relevant only if the
look gained a specular term or a real area-light shape, and it still would not
solve the shadow.

#### 3.4 Deterministic multi-sample patterns

The only noise-free way to get a true area-light penumbra with ray queries is to
take a fixed set of samples on the light and average the visibility. A
stratified disk or a fixed Poisson set is deterministic; a 4- or 8-ray pattern
is the usual low end. The cost is linear in the ray count, and the result is
banded rather than noisy: with 4 rays there are only 5 possible visibility
levels per light, so a penumbra becomes visible steps.

This is feasible for one or two hero lamps, not for 96. If the current shadow
term is roughly 1 ms of the 1.5 ms frame (an assumption; the evidence does not
isolate it), 4 rays per light would put the shadow term near 4 ms and the frame
near 5.5 ms; 8 rays would exceed the 8 ms budget before shading. The numbers are
a model, not a measurement [evidence/mixed-lighting]. The qualitative conclusion
holds: multi-ray soft shadows are a hero-light feature.

#### 3.5 What is feasible without noise

Feasible and cheap: fixed-tap PCF on a shadow map; VSM/SAVSM/ESM/MSM on a
shadow map; LTC for area-light shading; representative point for shading;
fixed 2–4 ray area sampling for a hero lamp.

Feasible but expensive: PCSS at high tap counts; fixed 8+ ray area sampling.

Not feasible for 96 lights at 8 ms: anything that multiplies taps or rays by the
full light count, and anything that needs temporal accumulation to hide noise.

### 4. Ray-query shadows

#### 4.1 API and hardware requirements

`VK_KHR_ray_query` is an optional, ratified *device extension* rather than part
of the Vulkan 1.3 core feature set. It depends on
`VK_KHR_acceleration_structure` (and `VK_KHR_spirv_1_4` or Vulkan 1.2) [18]. Ray queries are available in graphics, compute, and ray
tracing pipelines, and they return traversal results to the calling shader
rather than launching new shaders [18]. The extension's own example is a shadow
ray: initialize the query with `gl_RayFlagsTerminateOnFirstHitEXT`, proceed, and
test whether the committed intersection is none [18].

On the DXR side, the same model is two-level: bottom-level acceleration
structures hold geometry, and a top-level structure holds instances of them
[22]. Each instance has an 8-bit `InstanceMask`; the ray's 8-bit
`InstanceInclusionMask` is ANDed with it, and a zero result skips the instance.
The DXR spec explicitly names shadow determination as a use: "culling objects
that an app doesn't want to contribute to a shadow determination but otherwise
remain visible" [22, "Instance masking"]. That is exactly harbagsa's mask trick.

Hardware support is not universal. Ray query needs an RT-capable GPU and driver.
NVIDIA's Ada whitepaper describes the RT core as dedicated hardware for BVH
traversal and ray-box/ray-triangle intersection, with 2× ray-triangle throughput
over Ampere and Shader Execution Reordering for incoherent rays [23, "Ray
Tracing"]. The same whitepaper gives a ray-budget scale: Battlefield V used 39
ray-tracing operations per pixel in a typical scene, while Cyberpunk 2077's
Overdrive mode pushed over 600 [23, p. 15]. harbagsa's one shadow ray per
clustered light is in the low tens per pixel, which is modest by that scale.

#### 4.2 TLAS/BLAS build and update

harbagsa's acceleration structure is deliberately simple: one BLAS built from the
cube vertex/index buffers, and one TLAS built every frame from the current box
transforms, with instance capacity growing with the box count [ADR 0040;
`acceleration_build.odin`]. The BLAS build uses `PREFER_FAST_TRACE`; the TLAS
build uses `MODE_BUILD` and `PREFER_FAST_TRACE` [`acceleration_build.odin`].

Vulkan's build modes matter for the comparison. `MODE_BUILD` constructs the
structure; `MODE_UPDATE` updates an existing structure from a source structure,
and the update path has its own scratch size separate from the build path
[19][21]. `PREFER_FAST_TRACE` and `PREFER_FAST_BUILD` are mutually exclusive
[21]. A per-frame TLAS with a stable instance topology could use `UPDATE` and a
fast-build hint; a scene with moving/added/removed boxes needs `BUILD` unless
the topology is stable. harbagsa chooses `BUILD` every frame, which is correct
for arbitrary box changes and costs about 0.110 ms at 1080p with 96 lights and
the arena boxes [evidence/perf-baseline]. ADR 0040 recorded about 0.30 ms on an
earlier build [ADR 0040]; the current evidence is the number to use.

The BLAS is the quiet win: because every object is the same cube, there is one
12-triangle BLAS for the whole scene. A general scene would need a BLAS per mesh
or per object, and the build/update cost would grow with geometry. This is a
large part of why the ray-query path is cheap here and would not be equally cheap
in a mesh-heavy scene.

#### 4.3 Cost model

A first-order model:

```
rays/frame   = covered pixels × average lights per cluster × shadow-ray fraction
ray cost     = BVH traversal (box tests) + triangle test + divergence penalty
TLAS cost    = instance count × build/update cost
BLAS cost    = triangle count × build/update cost (amortised if static)
memory       = AS storage + scratch + instance buffer
```

The per-ray cost is not a constant. Coherent rays (neighbouring pixels hitting
the same boxes, the same light) amortise BVH traversal and texture/buffer
fetches; incoherent rays diverge and leave lanes idle. The Ada whitepaper makes
this point for secondary rays generally: they "tend to shoot in different
directions and hit different materials, resulting in secondary hit shaders being
less ordered and less efficient" [23, "Ray Tracing"]. Shader Execution Reordering
is NVIDIA's answer, and it is a hint that divergence is a first-class cost
[23].

harbagsa's shadow rays are relatively coherent within one light (all pixels of a
box face trace toward the same lamp) but divergent across the per-pixel light
loop (different pixels have different cluster lists and different occluders).
The measured frame does not expose a ray count, so the honest statement is:
1.116 ms for the scene pass at 96 lights and 1080p, with the TLAS at 0.110 ms
[evidence/perf-baseline]. If a pixel sees ~20 lights, that is ~41M rays for
2.07M pixels; the combined shading + ray rate is ~37 Gr/s. That is a rough
order-of-magnitude estimate, not a counter reading.

Shadow maps have a different cost shape. The per-pixel cost is `taps × lights in
cluster`, which is bandwidth/latency bound and independent of caster triangle
count; the per-light cost is six face renders (or two for dual-paraboloid) plus
the atlas update. At 96 lights, 576 face renders at 256² write 37.7M depth
samples per frame, before any PCF taps. Whether that is cheaper than 41M short
rays depends on the face-render path, the caster count, and whether the maps can
be cached. For a static light and static caster, a cached map makes the face
cost zero; for a moving lamp and moving crates, it does not.

#### 4.4 When ray queries beat shadow maps, and vice versa

**Ray queries tend to win when:**

- the caster set is small and coherent (one cube BLAS here), so traversal is
  short and the TLAS build is cheap;
- lights and geometry move every frame, so a shadow-map cache would be
  invalidated constantly;
- the light count is high but locally bounded, so the cluster list keeps the
  ray count near the number of lights that actually reach the surface;
- the hardware is guaranteed to expose ray query, and the look wants hard,
  unbiased edges with no acne or seams;
- the team values one visibility path over a per-light shadow-map subsystem.

**Shadow maps tend to win when:**

- the target has no ray-query support (mobile, older GPUs, some integrated
  parts), or the product needs a portable fallback;
- lights and casters are mostly static, so a cached atlas costs almost nothing
  per frame;
- the look wants filtered or soft shadows (PCF/PCSS/VSM), which are cheap on a
  map and expensive on rays;
- the caster geometry is high-poly and the shadow pass can be depth-only with
  low overdraw; the per-pixel sampling cost is then independent of triangle
  count, though the shadow pass's rasterization still scales with geometry;
- many lights can share a few atlas pages, or the light count is small enough
  that six faces per light is affordable.

No vendor document gives a numeric crossover for "96 point lights with one cube
BLAS." The decision is workload-specific. What the evidence supports is narrower:
for harbagsa's exact case, one 12-triangle BLAS, 96 local lights, and a hard-edge
look, the ray-query path is simple, exact, and fits the budget. A 96-light
cube-map path would add 576 face renders and 36–144 MiB before filtering, which
is a real cost, not a free portability win.

### 5. Light units, falloff, and energy

#### 5.1 Units

Physical light units are photometric or radiometric. Frostbite's table maps
radiant flux to lumen, radiant intensity to candela, and irradiance to lux
[16, Table 5]. glTF is explicit for point lights: "`point` and `spot` lights use
luminous intensity in candela (lm/sr)" [17, "Light Shared Properties"]. PBRT
gives the same
radiometric/photometric pairs and the candela definition [33, §4.1.1].

harbagsa has no units. A light's `intensity` is an arbitrary scalar (the editor
range is 0.2–4.0) and its `range` is a distance in metres [`src/game/lights.odin`].
There is no exposure or tone mapping; the scene target is RGBA16F, the output is
sRGB, and values above 1 clip [docs/design/world.md; `frame_targets.odin`]. That
is a coherent stylised pipeline, but it cannot be compared to a real luminaire
or reused as a physically calibrated rig. Intensity ratios are consistent only
within this renderer.

#### 5.2 Inverse-square and finite range

A physical point light obeys `E = I / d²`; the finite range is a culling and
windowing device, not a physical law. Frostbite states the reason directly: "One
issue with the inverse square law is that it never reaches zero. For performance
reasons, the renderer must implement a finite light range to support light
culling algorithms. At a certain limit, the illuminance should smoothly reach
zero." [16, §4.4]. glTF's range is a hint: "a distance cutoff at which the
light's intensity may be considered to have reached zero", and within the range
attenuation should follow inverse-square as closely as possible [17, "Range
Property"].

The recommended curves differ in the window, not the `1/d²`:

| Source | Attenuation |
| -- | -- |
| glTF recommended | `max(min(1 − (d/r)^4, 1), 0) / d²` [17] |
| Frostbite | `(1 − (d/r)^4)^2 / d²` [16, Listing 4] |
| harbagsa | `(1 − (d/r)^2)^2`, no `1/d²` [`terms.glsl`] |

The first two keep the inverse-square core and taper only near the range edge.
harbagsa's curve is a different transfer function: at `d = 0.5r` it is 0.5625,
at `d = 0.9r` it is 0.0361, and the `1/d²` term is absent. The result is much
flatter than inverse-square: at `r = 8 m`, a surface 1 m from the lamp and one
6 m away differ by about 5× (0.969 vs 0.191), where inverse-square would differ
by 36×. That is a useful stylised "reach" control, but it is not an
energy-preserving light. Doubling the range at fixed intensity extends the
bright region; it does not spread the same power over more area.

This is the largest gap between the renderer and the physical-units literature.
It is also deliberate: the design guide calls the look "soft range falloff" and
lists it as part of the signature [docs/design/README.md], and the ADR history
chose this direct-light model [ADR 0037; ADR 0041]. The research finding
is not "change it"; it is "do not describe it as physically based, and do not
compare its intensity values to candela or lumen."

#### 5.3 Window functions

Frostbite's guide is the best short explanation of why the window shape matters.
A linear lerp to zero has a hard cutoff; a threshold/remap has a non-zero
gradient at zero; a window raised to a power gives zero gradient at the range
edge [16, §4.4, Fig. 25]. Frostbite adopts the `n = 4` window [16, §4.4]. glTF's
recommended `(1 − (d/r)^4)` is the same family without the outer square [17].
harbagsa's `(1 − (d/r)^2)^2` is the same family with `n = 2` and an outer
square. All are smooth at the edge; the difference is how much of the range is
dimmed and how the light reads at mid-distance.

#### 5.4 Colour management and HDR

The rendering pipeline should shade in linear space and encode with sRGB
[16, §4.1]. Vulkan's `VK_COLOR_SPACE_SRGB_NONLINEAR_KHR` is the standard sRGB
presentation space [34]. harbagsa follows the linear-shade/sRGB-output rule, but
it has no tone map or exposure. The scene target is RGBA16F, so the shader can
hold values above 1, but the 8-bit output clips them. Overlapping bright lamps
therefore clip to white rather than rolling off. For a flat, high-contrast look
that is acceptable; for a physically calibrated HDR pipeline it is the missing
piece. It also means "intensity" is display-referred in practice, not a
photometric quantity.

### 6. harbagsa compared

#### 6.1 What the code actually does

| Element | Implementation | Source |
| -- | -- | -- |
| Cluster grid | 16 × 9 × 24, near 0.05 m, far 200 m, log2 depth slices | `cluster.glsl` |
| Cluster count | 3,456 | `cluster.glsl` |
| List stride | 256 indices per cluster; 3.375 MiB index buffer | `cluster.glsl`; arithmetic |
| Assignment | One thread per cluster; loops every light; sphere vs cluster AABB | `cluster.comp` |
| Overflow | Keeps the first 256 tested; one aggregate counter at `counts[CLUSTER_COUNT]` | `cluster.comp` |
| Pass order | Cluster → depth → scene → TAA → overlay | [ADR 0030] |
| Lit lookup | `gl_FragCoord` + view depth → cluster → list | `terms.glsl` |
| Direct term | `intensity × N·L × (1 − (d/r)^2)^2 × visibility`; no `1/d²` | `terms.glsl` |
| Shadow | One `TerminateOnFirstHit + Opaque` ray per light, TMin 0.001, end bias 0.001 | `terms.glsl` |
| Masks | Emissive boxes `0x01`; other boxes `0xFF`; shadow rays test `0x02` | `lights.odin`; `terms.glsl` |
| TLAS | One cube BLAS; TLAS rebuilt every frame with `BUILD`, `PREFER_FAST_TRACE` | `acceleration_build.odin` |
| Emissive | `albedo × emissive`; not a direct light | `box.frag` |
| TAA | Jittered history resolve; no shadow denoiser | [ADR 0004] |

The cluster pass is small in absolute terms: 3,456 threads (54 workgroups of 64)
and 96 lights, so 331,776 sphere/AABB tests per frame. It is not the current
bottleneck. It is the part that scales worst if the light count grows, because
it has no light BVH and no depth-aware tile bounds.

One correctness strength is worth stating: the falloff is exactly zero at
`range`, so the range sphere is the exact support of the light. The cluster test
uses that sphere, and the shader skips `distance >= light.color.w`. The culling
therefore does not drop any light that could contribute; its error is only the
conservative sphere/AABB overlap, not a truncated falloff.

#### 6.2 Measured cost, and what the numbers mean

The current evidence is the paired 96-light run at 1080p:

| Measure | Value | Source |
| -- | --: | -- |
| GPU total p50, `direct` variant | 1.50–1.52 ms | [evidence/mixed-lighting] |
| Frame interval p50 | 1.83–1.85 ms | [evidence/mixed-lighting] |
| Scene pass p50 | 1.116 ms | [evidence/perf-baseline] |
| TLAS pass p50 | 0.110 ms | [evidence/perf-baseline] |
| 8 ms budget at 60 Hz | 8.0 ms | Brief; [evidence/mixed-lighting] |

The scene pass is not the shadow term. It includes direct shading, the cluster
list reads, the shadow rays, and the emissive/indirect composition. The evidence
does not isolate the shadow term, so do not quote 1.116 ms as "the cost of
shadows." The honest statement is: the whole direct frame is 1.50–1.52 ms GPU
total, which is about 19% of the 8 ms renderer budget and about 9% of a 16.7 ms
60 Hz frame.

ADR 0040 records a different number: a 4.29 ms shadow term, a 5.94 ms full frame
with shadows, 1.65 ms without, and about 0.30 ms for the TLAS [ADR 0040]. That
measurement predates the current mixed-lighting evidence and the perf readback
fix [evidence/perf-baseline]. It is a historical measurement, not a paired
measurement of the current build. The difference is large enough that it should
be treated as a scenario/build difference, not as noise. See Conflicts.

#### 6.3 Correctness risks

1. **No inverse-square.** The light is a stylised reach volume, not a physical
   lamp. Intensity has no unit, and range changes the total light rather than
   redistributing it [§5.2]. If the product ever needs physical ratios or
   reusable lighting rigs, this is the gap. If the flat look is the goal, document
   it as a deliberate curve, not as "physically based."

2. **Every emissive box is non-occluding.** `box_instance_mask` returns `0x01`
   for `box.emissive > 0`, not for "this box is a lamp" [`lights.odin`]. The
   comment says "A lamp must not block its own point light", but the predicate is
   broader. A glowing panel or a crate with emissive trim stops casting shadows.
   A separate `is_lamp` flag, or a second mask bit that
   means "exclude from its own light only", would be more precise. The current
   global exclusion is a pragmatic way to avoid a lamp self-shadow fan, but it
   also makes emissive geometry transparent to every other light.

3. **Shadow rays are traced for back-facing lights.** The shader computes
   `diffuse = max(dot(normal, direction), 0.0)` but does not use it to gate the
   `if (trace_shadows...)` block [`terms.glsl`]. On a box face, roughly half of
   the cluster's lights are behind the surface; those rays cannot change the
   result. Gating on `diffuse > 0` (and on `falloff > 0` / `intensity > 0`) is a
   pure win. It does not change the image, only the ray count.

4. **The 256 cap is first-in-buffer-order, not importance order.** At 96 lights
   the cap cannot be reached, so this is dormant. At 257+ lights in one cluster,
   the last lights uploaded are dropped, which may be the brightest ones. The
   overflow counter is a single aggregate, not a per-cluster count
   [`cluster.comp`; ADR 0030]. ADR 0029's rule is "A silent drop is a correctness
   bug" [ADR 0029]; the counter makes it non-silent in the report, but not in the
   frame, and it does not say which lights were lost.

5. **Culling before depth.** The cluster pass runs before the depth prepass
   [ADR 0030], so it uses the full fixed depth slice rather than the tile's
   actual min/max depth. Forward+ uses the depth prepass to tighten the tile
   frustum [1, §4.1]. harbagsa's order avoids a depth-read dependency but keeps
   more lights than necessary, especially in long views and at high resolution.

6. **Fixed grid, fixed aspect.** `CLUSTER_X/Y` are constants; the tile size in
   pixels is resolution-dependent but the cluster count is not. At 1080p a tile
   is 120 × 120; at 4K it is 240 × 240. The depth slices are fixed to 0.05–200 m;
   the arena is 40 m, and four of the 24 slices start beyond 50 m. The grid is
   tuned for one arena and one aspect, not for arbitrary scenes.

7. **TLAS build flag.** A per-frame `BUILD` with `PREFER_FAST_TRACE` optimises
   traversal at the expense of build time. If the TLAS build ever becomes a
   bottleneck, `PREFER_FAST_BUILD` is the first experiment; if the instance
   topology is stable, `MODE_UPDATE` is the second [19][21]. At 0.110 ms this is
   not urgent.

8. **No soft-shadow path.** The renderer has no lamp radius and no shadow-map
   path. That is consistent with the design's hard-edge look [docs/design/world.md],
   but it means a future request for soft shadows is a new architecture decision,
   not a shader toggle. PCSS needs a shadow map; multi-ray soft shadows multiply
   the current ray cost.

9. **Clipping, not tone mapping.** Without exposure/tonemap, overlapping bright
   lamps clip to white. The flat look tolerates it; a scene with many close
   lamps will lose colour separation in the bright areas. This is a colour
   management consequence, not a shadow bug.

10. **Direct and indirect follow different light sets.** Dynamic lamps contribute
    direct light and hard shadows, but no indirect; the baked bounce contains
    only static fixtures and static emissive boxes [ADR 0045]. A moving lamp
    therefore lights a wall directly but does not add the corner bounce a static
    fixture would. A scene lit mainly by dynamic lamps will have darker corners
    and less fill than the same scene with static fixtures, and the mismatch
    changes when a lamp is toggled between kinds.

#### 6.4 Scale risks

The cluster pass is O(clusters × lights) and has no acceleration structure over
lights. At 96 lights the cost is trivial; at 10k it is ~34.5M tests, and at 100k
~345M. The pass is one thread per cluster, so it also has poor occupancy if the
cluster count is small relative to the GPU. Olsson's search tree [2, §4.4] or
Harada's scatter/radix approach [1, §4.2] would scale better if the light count
grows by orders of magnitude.

The 256 cap is the second scale limit. A scene with 300 lights can put more than
256 in a single cluster if they overlap; the cap then drops lights. The current
target is 96, so this is a future risk, not a present one. A cap that is a
buffer bound should either be paired with an importance sort or with a
variable-size list; the current first-N policy is the least fair of the options.

The fixed grid is the third. At 4K the tile is 240 × 240, and a 2 m light grid
means one to several lights per tile even before depth; the 3D slices help, but the
screen-space false positive rate grows with resolution. At 21:9 the 16 × 9 grid
produces non-square tiles. A resolution-adaptive grid (fixed pixel tile size,
variable cluster count) or a hybrid tile + cluster selector [5] would age
better.

The TLAS build is the fourth. It scales with the instance (box) count, and the
current arena is small. A 10k-box scene would make the per-frame
build a real cost; `UPDATE`/`FAST_BUILD` and instance culling would be the
levers.

#### 6.5 Portability risks

Ray query is optional. A Vulkan 1.3 device is not required to expose
`VK_KHR_ray_query`; the renderer rejects devices without it and has no fallback
[ADR 0040]. That is a deliberate product decision, but it means the renderer
cannot run on mobile/tile GPUs, older discrete GPUs, or any driver that does not
expose the extension. The acceleration-structure path also needs buffer device
addresses, the acceleration-structure feature, and (per ADR 0040) deferred host
operations. These are not universally available.

A portable fallback would be a cube atlas with a one-tap depth compare (hard
edges) or four-tap PCF (slightly soft), plus normal-offset/slope-scaled bias and seamless
cube filtering. It would preserve the look better than a VSM/ESM path and would
avoid light bleeding. The cost is 6 faces per shadowed light, 36–144 MiB at
128–256², and a new per-light shadow state. It is a real subsystem, not a
weekend shader.

#### 6.6 Noise-free alternatives and a fair cost comparison

The table assumes the current 96-light, 1080p target and the 8 ms budget. The
harbagsa numbers are measured; the alternatives are estimates from the cited
mechanisms, not benchmarks of this renderer.

| Option | Look | Per-frame cost at 96 lights | Memory | Deterministic | Fit |
| -- | -- | -- | -- | -- | -- |
| Current ray query | Hard, exact | 1.50–1.52 ms GPU total; 0.110 ms TLAS | AS + instances | Yes | Baseline; best fit |
| Current + ray gating (`diffuse > 0`) | Unchanged | Cuts shadow rays roughly in half on box faces (model) | None | Yes | First optimisation; do it |
| Hybrid cluster + fine-tile list [5] | Unchanged | Fewer lights/pixel at depth discontinuities; ~0.1–0.3 ms added binning (model) | Small | Yes | Good if light count/resolution grows |
| Scene-tuned grid (near/far, tile size) | Unchanged | Fewer false positives; cluster pass unchanged | None | Yes | Cheap, low risk |
| Importance-ordered 256 cap | Unchanged at 96; better at 300+ | Sort cost in cluster pass | None | Yes | Needed if >256/cluster |
| Cube atlas + 1 tap | Hard, with bias/seams | 576 face renders + 1 tap/light; order 1–10 ms depending on face path (model) | 36–144 MiB | Yes | Portable fallback |
| Cube atlas + 4-tap PCF | Slightly soft | 4× taps + 576 faces | 36–144 MiB | Yes | Portable, changes edge look |
| PCSS (fixed taps) | Contact-hardening soft | 36 + 64 taps per light; far above 8 ms for 96 (model) | Shadow maps | Yes | Hero lamps only |
| Fixed 4-ray area shadows | Soft, banded | ~4× the shadow term; borderline 8 ms | None | Yes (banded) | One or two hero lamps |
| VSM / SAVSM / ESM | Filterable soft | 2-channel sample/light + face renders | 2× VSM maps | Yes | Not needed for flat boxes; bleeding |
| CSM | Hard/filtered | N cascades, directional only | N maps | Yes | N/A (no directional light) |
| LTC | Area-light shading | 0.9 ms PS4-class in its own area-light demo, not 96 lights [14] | LUT | Yes | N/A (no specular/area lights) |
| Representative point | Shading only | One point per light | None | Yes | N/A (diffuse sphere = point) |
| Contact shadows | Contact darkening | 1 depth march/light/pixel | None | Yes at short lengths | Supplement only; incomplete |
| Stochastic soft shadows | Soft | Denoiser + multiple samples | History | No | Excluded |

The fair comparison is not "ray query 1.5 ms vs shadow maps free." Shadow maps
have a per-frame face-render cost and a memory cost; ray query has a per-ray
cost and a hardware requirement. At 96 dynamic lights on a one-cube BLAS, the
ray path is the smaller system and the measured budget is comfortable. At 4
static lights on a low-end GPU, cube maps are the smaller system and the
portable choice. The crossover is scene-dependent; the table gives the cost
drivers rather than a false precision.

#### 6.7 Recommendation

Keep the hard ray-query shadow for the current 96-light target. This is a keep
decision for the existing baseline, not a proposal to add ray tracing elsewhere.
It is the exact visibility term for a zero-area light, it has no bias/acne/seam
pathology, and it fits the 8 ms budget with room. The design guide treats the hard edge as part of
the signature [docs/design/world.md]; do not add PCF/PCSS "for quality" without a
design decision to soften the look.

Do the cheap correctness/performance fixes first:

- Gate the shadow ray on `diffuse > 0`, `falloff > 0`, and `intensity > 0`.
  This is image-identical and cuts the ray count on box faces.
- Replace the `emissive > 0` mask predicate with an explicit lamp flag, or add a
  second mask bit for "excluded from its own light only", so non-lamp emissive
  geometry still occludes.
- Report per-cluster overflow (or at least the max count), not one aggregate, so
  a future light-count increase is diagnosable.
- If the light count or resolution grows, add the DOOM-Eternal-style hybrid
  cluster + fine-tile list and/or move the cluster pass after depth to use the
  tile's min/max depth. Both preserve the look.

Add a cube atlas + one-tap depth-compare fallback only if a non-RT target becomes a
product requirement. Budget 36–144 MiB and 576 face renders at 96 lights; use
seamless cube filtering, slope-scaled bias, and normal offset; do not use
VSM/ESM (light bleeding) or PCSS (cost) for the fallback's default path.

Do not add LTC, representative point, VSM/ESM, or CSM to the 96-light path. LTC
and representative point solve shading problems the flat Lambert look does not
have; VSM/ESM trade exactness for filterability the look does not need; CSM is
directional-only. If soft shadows are requested later, treat it as a new design
decision. The noise-free options are a fixed multi-sample area shadow for one or
two hero lamps, or a shadow-map PCSS path for a few lights; neither belongs in
the 96-light cluster loop.

## Conflicts

**1. ADR 0040's 4.29 ms shadow term vs the current 1.50–1.52 ms full frame.**
ADR 0040 records "The measured shadow term is 4.29 ms at 1080p for a dense
96-light grid", "The full frame is 5.94 ms with shadows on and 1.65 ms with them
off", and "The TLAS pass is about 0.30 ms" [ADR 0040]. The current evidence
records 1.50–1.52 ms GPU total p50 and 1.83–1.85 ms interval p50 for the
`direct` variant at 96 lights/1080p, with a 1.116 ms scene pass and a 0.110 ms
TLAS [evidence/mixed-lighting; evidence/perf-baseline]. These are not the same
measurement: the ADR predates the current mixed-lighting run and the perf
readback fix, and the scenario/build differ. The historical shadow evidence at
commit `c668033` also counted the depth prepass inside the scene pass and called
the 96-light grid "a dense worst case for overlap, not a typical room"; the
current pass list separates depth from scene. Use the current evidence for the
budget; treat 4.29 ms as a historical measurement, not as a paired delta on
today's build.

**2. "1.5–1.9 ms direct" conflates three numbers.** The brief's range spans the
GPU total (1.50–1.52 ms), the frame interval (1.83–1.85 ms), and the scene pass
(1.116 ms). Only the GPU total is the renderer's 8 ms budget line; the interval
includes submit/present. Do not call 1.5 ms "the shadow term" or 1.116 ms "the
shadow cost." The evidence has no isolated shadow delta for the current build.

**3. ADR 0040 says "lamp box" mask; the code masks every emissive box.**
ADR 0040: "Give a lamp box instance mask `0x01`. Other boxes use `0xFF`. Shadow
rays test `0x02`." [`lights.odin`] returns `0x01` for `box.emissive > 0`, which
includes non-lamp emissive surfaces (the spider markings, any glowing prop). The
comment says "A lamp must not block its own point light", but
the implementation is broader. This is an implementation/documentation mismatch
and a real occlusion gap.

**4. ADR 0040 says "trace only after the normal test"; the shader does not gate
on it.** The ADR's wording implies the normal test decides whether to trace.
`terms.glsl` computes `diffuse` before the shadow block but traces regardless of
`diffuse`. The image is unchanged for back-facing lights, but the ray count is
higher than the ADR's description suggests. See §6.3 item 3.

**5. ADR 0030 says a cluster "reports the overflow"; the code reports one
aggregate.** ADR 0030: "A cluster over 256 lights keeps the first 256 and
reports the overflow." `cluster.comp` increments
`cluster_counts.counts[CLUSTER_COUNT]`, a single slot after the 3,456 cluster
counts. `state.cluster_overflow` is that one value [state.odin]. It cannot say
which cluster overflowed or which lights were dropped. At 96 lights it is dead
code; at 300+ it is a weak diagnostic.

**6. ADR 0029's "no silent drop" vs the 256 cap.** ADR 0029 says "A silent drop
is a correctness bug" and claims the live paths handle 300 objects and 96 lights
[ADR 0029]. The 256-per-cluster cap is a content drop above 256 lights in one
cluster; it is counted, but not surfaced per frame. The scene can accept more
lights than a cluster can hold. This is a tension between the unbounded-scene
goal and the fixed-stride list, not a bug at the current 96-light target.

**7. "Clustered forward+" vs canonical Forward+ order.** ADR 0030 calls the
renderer "clustered forward+" and puts the cluster pass before the depth prepass.
Harada's Forward+ puts the depth prepass first and uses its min/max depth to
tighten the tile frustum [1, §3–4]. harbagsa is a clustered forward renderer, but
its culling is not depth-aware. The label is defensible; the culling is a
simplification, not the paper's order.

**8. Physical-units literature vs the design guide's stylised falloff.** glTF
and Frostbite use inverse-square with a finite-range window [16][17]; harbagsa
uses a window-only curve [`terms.glsl`]. The design guide explicitly treats
"soft range falloff" as the signature [docs/design/README.md; docs/design/world.md].
This is not an internal contradiction: the renderer is stylised, and the guide is
consistent. It is a conflict only if someone reads "point light" as "physical
point light" or compares intensity values to candela. This note uses "falloff"
in the design-guide sense; it is a stylised reach curve, not a physical
falloff.

## Not found

- No primary source gives a numeric crossover for per-pixel ray queries vs
  shadow maps at 96 point lights. The decision rules in §4.4 are derived from the
  mechanics and the measured harbagsa point, not from a vendor benchmark.
- AMD and Intel ray-tracing whitepapers were not retrievable on 2026-11-10
  (blocked/redirected); the hardware cost discussion relies on NVIDIA's Ada
  whitepaper [23] plus the Khronos/DXR specs. No AMD/Intel RT-core throughput
  numbers are quoted.
- "Light Indexed Deferred Rendering" has no peer-reviewed paper located; the
  primary description is Trebilco's ShaderX7 chapter/research project [3] and
  Pettineo's industry write-up [4]. It is labelled industry, not academic.
- The Exponential Shadow Maps DOI from secondary listings
  (`10.1145/1375714.1375741`) does not resolve and Crossref has no record; the
  paper is cited from its PDF [9], without page numbers.
- No primary page number/DOI was found for Harada et al.; it is cited from the
  author-hosted PDF [1] and the Eurographics 2012 copyright line.
- No verified page/quote for dual-paraboloid seam behaviour was obtained; the
  technique and DOI are verified [13], and the seam/non-uniform-texel statement
  is labelled as a known tradeoff, not a quotation.
- Godot's cluster grid dimensions and per-cluster list policy were not found; the
  docs only state the 512-clustered-element default [31].
- DOOM Eternal's exact `LIGHTS_PER_TILE` value was not found; the slides show the
  compaction mechanism, not the number [5].
- The current renderer does not expose a shadow-ray count, so the per-ray cost
  estimates in §4.3 are models, not measurements. The 4.29 ms ADR number's
  scenario/camera is not documented beyond "dense 96-light grid" [ADR 0040].

## References

Peer-reviewed papers and course papers:

[1] T. Harada, J. McKee, J. C. Yang. "Forward+: Bringing Deferred Lighting to the
Next Level." Eurographics 2012 Short Papers. PDF:
<https://takahiroharada.files.wordpress.com/2015/04/forward_plus.pdf>.
Accessed 2026-11-10.

[2] O. Olsson, M. Billeter, U. Assarsson. "Clustered Deferred and Forward
Shading." High Performance Graphics 2012, pp. 87–96. DOI:
<https://doi.org/10.2312/EGGH/HPG12/087-096>. PDF:
<https://www.cse.chalmers.se/~uffe/clustered_shading_preprint.pdf>.

[6] L. Williams. "Casting Curved Shadows on Curved Surfaces." SIGGRAPH 1978,
pp. 270–274. DOI: <https://doi.org/10.1145/800248.807402>.

[7] W. T. Reeves, D. Salesin, R. L. Cook. "Rendering Antialiased Shadows with
Depth Maps." SIGGRAPH 1987, pp. 283–291. DOI:
<https://doi.org/10.1145/37401.37435>.

[8] W. Donnelly, A. Lauritzen. "Variance Shadow Maps." I3D 2006, pp. 161–165.
DOI: <https://doi.org/10.1145/1111411.1111440>.

[9] T. Annen, T. Mertens, H.-P. Seidel, E. Flerackers, J. Kautz. "Exponential
Shadow Maps." Graphics Interface 2008. PDF:
<https://jankautz.com/publications/esm_gi08.pdf>.

[10] C. Peters, R. Klein. "Moment Shadow Mapping." I3D 2015, pp. 7–14. DOI:
<https://doi.org/10.1145/2699276.2699277>.

[11] R. Fernando. "Percentage-Closer Soft Shadows." SIGGRAPH 2005 Sketches,
p. 35. DOI: <https://doi.org/10.1145/1187112.1187153>. PDF:
<https://developer.download.nvidia.com/shaderlibrary/docs/shadow_PCSS.pdf>.

[13] B. Osman, M. Bukowski, C. McEvoy. "Practical Implementation of Dual
Paraboloid Shadow Maps." SIGGRAPH 2006 Symposium on Videogames, pp. 103–106.
DOI: <https://doi.org/10.1145/1183316.1183331>.

[14] E. Heitz, J. Dupuy, S. Hill, D. Neubelt. "Real-Time Polygonal-Light Shading
with Linearly Transformed Cosines." ACM Transactions on Graphics 35(4), 2016,
pp. 1–8. DOI: <https://doi.org/10.1145/2897824.2925895>. Course slides:
<https://blog.selfshadow.com/publications/s2016-advances/s2016_ltc_rnd.pdf>.

Industry and engine sources:

[3] D. Trebilco. "Light Indexed Deferred Rendering." ShaderX7, chapter 2.9;
research project from 2007. Repository and README:
<https://github.com/dtrebilco/lightindexed-deferredrender>.

[4] M. Pettineo. "Light Indexed Deferred Rendering." The Danger Zone,
2012-03-31. <https://mynameismjp.wordpress.com/2012/03/31/light-indexed-deferred-rendering/>;
static copy: <https://therealmjp.github.io/posts/light-indexed-deferred-rendering/>.

[5] J. Geffroy, A. Gneiting, Y. Wang. "Rendering the Hellscape of DOOM Eternal."
SIGGRAPH 2020 Advances in Real-Time Rendering course. PDF:
<https://advances.realtimerendering.com/s2020/RenderingDoomEternal.pdf>.

[12] R. Dimitrov. "Cascaded Shadow Maps." NVIDIA, August 2007. PDF:
<https://developer.download.nvidia.com/SDK/10.5/opengl/src/cascaded_shadow_maps/doc/cascaded_shadow_maps.pdf>.

[15] B. Karis. "Real Shading in Unreal Engine 4." SIGGRAPH 2013 course
"Physically Based Shading in Theory and Practice". PDF:
<https://cdn2.unrealengine.com/Resources/files/2013SiggraphPresentationsNotes-26915738.pdf>.

[16] S. Lagarde, C. de Rousiers. "Moving Frostbite to Physically Based Rendering
3.0." SIGGRAPH 2014 course. PDF:
<https://seblagarde.files.wordpress.com/2015/07/course_notes_moving_frostbite_to_pbr_v32.pdf>.

[23] NVIDIA. "NVIDIA Ada GPU Architecture." Whitepaper, 2022. PDF:
<https://images.nvidia.com/aem-dam/Solutions/geforce/ada/nvidia-ada-gpu-architecture.pdf>.

[25] P. S. Gerasimov. "Chapter 12. Omnidirectional Shadow Mapping." GPU Gems
(Addison-Wesley, 2004).
<https://developer.nvidia.com/gpugems/gpugems/part-ii-lighting-and-shadows/chapter-12-omnidirectional-shadow-mapping>.

[26] A. Lauritzen. "Chapter 8. Summed-Area Variance Shadow Maps." GPU Gems 3
(Addison-Wesley, 2007).
<https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows/chapter-8-summed-area-variance-shadow-maps>.

[27] NVIDIA. "Chapter 11. Shadow Map Antialiasing." GPU Gems (Addison-Wesley,
2004).
<https://developer.nvidia.com/gpugems/gpugems/part-ii-lighting-and-shadows/chapter-11-shadow-map-antialiasing>.

[28] Unity. "Forward and Forward+ rendering paths in URP." Unity 6000.0 Manual.
<https://docs.unity.com/en-us/engine/6000.0/manual/render-pipelines/universal-render-pipeline/introduction/urp-concepts/rendering-paths/forward-rendering-paths>.

[29] Unity. "Light limits in URP." Unity 6000.0 Manual.
<https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/light-limits-in-urp>.

[30] Unity. "Shadows in the High Definition Render Pipeline." HDRP 14.0
manual. <https://docs.unity3d.com/Packages/com.unity.render-pipelines.high-definition@14.0/manual/Shadows-in-HDRP.html>.

[31] Godot Engine. "3D lights and shadows." Stable documentation.
<https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html>.

[32] Epic Games. "Contact Shadows in Unreal Engine." UE 5.9 documentation.
<https://dev.epicgames.com/documentation/en-us/unreal-engine/contact-shadows-in-unreal-engine>.

Specifications:

[17] Khronos Group. "KHR_lights_punctual." glTF 2.0 extension.
<https://github.com/KhronosGroup/glTF/blob/main/extensions/2.0/Khronos/KHR_lights_punctual/README.md>.

[18] Khronos Group. "VK_KHR_ray_query." Vulkan specification, revision 1,
2020-11-12.
<https://registry.khronos.org/vulkan/specs/latest/man/html/VK_KHR_ray_query.html>.

[19] Khronos Group. "VK_KHR_acceleration_structure." Vulkan specification.
<https://registry.khronos.org/vulkan/specs/latest/man/html/VK_KHR_acceleration_structure.html>.

[20] Khronos Group. "VkPhysicalDeviceAccelerationStructurePropertiesKHR."
<https://registry.khronos.org/vulkan/specs/latest/man/html/VkPhysicalDeviceAccelerationStructurePropertiesKHR.html>.

[21] Khronos Group. "VkAccelerationStructureBuildGeometryInfoKHR."
<https://registry.khronos.org/vulkan/specs/latest/man/html/VkAccelerationStructureBuildGeometryInfoKHR.html>.

[22] Microsoft. "DirectX Raytracing (DXR) Functional Specification."
<https://microsoft.github.io/DirectX-Specs/d3d/Raytracing.html>.

[24] Khronos Group. "ARB_seamless_cube_map." OpenGL extension #65, 2009.
<https://registry.khronos.org/OpenGL/extensions/ARB/ARB_seamless_cube_map.txt>.

[33] M. Pharr, W. Jakob, G. Humphreys. *Physically Based Rendering: From Theory
to Implementation*, 4th ed., "Radiometry, Spectra, and Color."
<https://pbr-book.org/4ed/Radiometry,_Spectra,_and_Color/Radiometry>.

[34] Khronos Group. "VkColorSpaceKHR." Vulkan specification.
<https://registry.khronos.org/vulkan/specs/latest/man/html/VkColorSpaceKHR.html>.

Repository sources:

- `src/renderer/shaders/terms.glsl` — direct term, falloff, shadow ray,
  instance mask, 0.002 m origin offset, 0.001 m TMin/end bias.
- `src/renderer/shaders/box.frag` — `albedo × (direct + indirect) + albedo ×
  emissive`; no ambient floor.
- `src/renderer/shaders/cluster.glsl` — 16 × 9 × 24, 0.05–200 m, 256 stride.
- `src/renderer/shaders/cluster.comp` — one thread per cluster, all-light loop,
  first-256 cap, aggregate overflow counter.
- `src/renderer/lights.odin` — light layout, `LAMP_INSTANCE_MASK`/`BOX_INSTANCE_MASK`,
  `emissive > 0` predicate, synthetic 96-light grid (2 m spacing, y = 2.6,
  range 8, intensity 3).
- `src/renderer/acceleration_build.odin` — one cube BLAS, per-frame TLAS,
  `MODE_BUILD`, `PREFER_FAST_TRACE`.
- `src/renderer/state.odin` — `cluster_overflow` report field.
- `src/renderer/frame_targets.odin` — `SCENE_COLOR_FORMAT` is RGBA16F.
- `src/game/lights.odin` — intensity 0.2–4.0, range 2–20.
- `docs/adr/0004-temporal-anti-aliasing.md` — TAA history resolve.
- `docs/adr/0029-unbounded-scene-capacity.md` — "A silent drop is a correctness
  bug"; 300 objects, 96 lights.
- `docs/adr/0030-clustered-forward-plus.md` — grid, pass order, 256 cap,
  "first 256", "reports the overflow".
- `docs/adr/0040-hard-point-light-shadows.md` — 4.29 ms shadow term, 5.94 ms
  frame, 0.30 ms TLAS, mask/ray flags, "trace only after the normal test".
- `docs/adr/0037-direct-dynamic-point-lights.md` — the no-shadow, no-indirect,
  ambient-floor state at the time; historical.
- `docs/adr/0041-absolute-darkness.md` — no ambient floor.
- `docs/adr/0045-mixed-static-baked-indirect.md` — static indirect, dynamic
  direct, bake key/status.
- `docs/evidence/perf-baseline.md` — 96-light 1080p: GPU total 1.506 ms,
  scene 1.116 ms, TLAS 0.110 ms.
- `docs/evidence/mixed-lighting.md` — 96-light paired run: 1.50–1.52 ms GPU
  total p50, 1.83–1.85 ms interval p50, 8 ms budget.
- `docs/design/world.md` and `docs/design/README.md` — "soft range falloff",
  "the lamp has no radius", "no shadow map", "nothing is textured, rounded,
  blurred, or glossy".
- `scenarios/perf-mixed.json` — 96 synthetic lights, 1920 × 1080, `direct`
  baseline.
