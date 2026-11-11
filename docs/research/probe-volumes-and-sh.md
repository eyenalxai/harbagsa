# Probe volumes and spherical harmonics

**Question.** How are noise-free probe / irradiance-volume lighting systems built, and how does harbagsa's probe field compare?

**Date.** 2026-11-10

**Status.** Research complete for the sources listed. Read-only: no code, build, or
commit changes. DDGI and light field probes are analyzed as contrasts, not
recommendations; the baseline is the existing offline bake and the existing hard
ray-query shadows. Claims marked **analysis** are arithmetic or reasoning from
the cited source, not a measured result.

## Answer

1. **The canonical noise-free design is a spatial grid of directional irradiance
   samples.** Greger et al. store directional irradiance in bins at grid points
   and trilinearly interpolate the eight surrounding spatial samples [1]. Games
   replaced the bins with spherical harmonics (SH): Oat's GDC 2005 talk
   describes a "3D light map" of SH coefficients, seven lerps of the
   coefficients for trilinear interpolation, and gradients for adaptive grids
   [4]. Unity's classic Light Probes store L2 SH as 27 floats and interpolate
   tetrahedrally [12];
   Unreal's Volumetric Lightmap stores third-order SH in 4x4x4 bricks [17];
   Godot stores 9 SH coefficients per probe and tetrahedralizes the probe set
   [20-22]. Harbagsa is in the same family, with an 8x8 octahedral map instead
   of SH.

2. **Noise-free means deterministic quadrature with enough samples, not a
   denoiser.** Harbagsa bakes 1024 fixed Fibonacci rays per probe, with a
   per-probe hash rotation, once [26]. Dynamic diffuse global illumination
   (DDGI) is the contrast: 64 rays per probe per frame, stochastically rotated,
   with hysteresis 0.85-0.98 [9]. With fixed rays and a fixed scene, DDGI's
   probe update is also a deterministic weighted sum; the stochastic rotation
   and the per-frame undersampling are what the temporal filter hides. Harbagsa
   avoids the filter by spending 16x more rays per probe update, once per bake:
   8.19M primary rays versus DDGI's 0.52M per
   frame (analysis; 8000 x 1024 versus 32 x 8 x 32 x 64). DDGI repeats its update
   every frame; harbagsa repeats only on an explicit rebake.

3. **8x8 octa is a defensible angular resolution, but its storage format is
   the clear waste.** DDGI uses exactly 8x8 for irradiance [9], and the
   production extension was developed for use in RTXGI, Unity, and Unreal
   Engine 4 [10], so 8x8 is a production-used choice. Ramamoorthi and Hanrahan
   show that 9 SH coefficients approximate irradiance with under 1% average
   error and under 5% maximum error for their environments [5]; for a pure
   diffuse signal, 8x8 is
   more angular resolution than needed, and DDGI's own resolution study says
   probe count matters more than angular resolution [9]. Harbagsa's map is 8x8
   RGBA16F, 512 bytes per probe, while DDGI's is 8x8 R11G11B10, 256 bytes per
   probe. Fix the format first; the 8x8 resolution itself is defensible.

4. **SH9 is better on memory and linearity, not automatically on image
   quality.** SH9 (9 coefficients, L2) in f16 is 54 bytes per probe versus
   512 bytes for the current 8x8 RGBA16F irradiance map. Total probe memory
   falls from 776 to 318 bytes per probe (2.4x, not 9.5x, because depth moments
   dominate). But the 9-coefficient clamped-cosine reconstruction has a known
   spurious back lobe of 1/16 the peak [6]. A bright source in the probe's view
   can add false light on the opposite
   side of the probe, where the clamped cosine should be zero. The octa map is
   measured and local; it does not ring globally. The right test is an A/B bake
   against a high-ray reference, with windowing, on the dark side of a bright
   emitter and at a thin wall.

5. **The current octa field's biggest leaks are spatial and in the depth test,
   not in the directional basis.** The 1 m grid, tetrahedral interpolation, dilation
   radius 2, normal-only bias, f16 moments, and full-depth backface test can
   carry light across a thin wall. Production fixes are thicker walls or layer
   masks [15], normal-plus-view bias [10,15], backface depth shortening [10],
   probe relocation [10,16], and more probe density [9,15]. Harbagsa has the
   first-order fixes; the thin-wall case remains, and its 8x8 depth map has one
   quarter of DDGI's 16x16 depth texels.

6. **The gamma-5 encoding is DDGI-Production's, and the gamma-2 blend is
   intentional there.** DDGI-Production uses `irradianceGamma = 5.0`, decodes
   with 2.5 to leave a gamma-2 curve, weights the probes, then squares [10].
   Harbagsa's bake
   and shader use the same gamma-5 encode and 2.5 decode, with a 2x scale and
   four probe weights instead of DDGI's eight [26]. The internal review's
   arithmetic for a 50/50 lit/unlit pair (L/4 instead of L/2) is correct, but the
   primary source shows the order is a deliberate perceptual choice, not an
   accidental mismatch. For a static bake the temporal-convergence rationale is
   gone; decide whether the perceptual darkening is wanted.

7. **Dynamic lamps: the production legacy answer is direct-only.** Unreal
   Movable lights cast dynamic shadows and no baked indirect; Stationary lights
   bake indirect and keep dynamic direct [18,19]. Unity's Mixed/Realtime split is
   the same pattern [28]. Harbagsa's static-fixture/dynamic-lamp split is this
   pattern. A moving lamp that must bounce needs a dynamic-GI tier such as
   Enlighten [29] or a light-propagation volume; DDGI is the noisy one and the
   owner has excluded it.

8. **Recommendation.** Keep 1 m probe spacing; it is the dominant quality lever
   [9]. First try a format change for the octa irradiance: R11G11B10F halves the
   irradiance bytes and needs no algorithm change; test neutral grays because
   its blue channel has one fewer mantissa bit [9]. Then A/B a 4x4 octa and an
   SH9 variant against a high-ray reference, holding the 8x8 moment map fixed;
   test a 4x4 or 16x16 moment map separately. Use SH9 only with windowing and
   signed f16, and test the 1/16 back lobe. Do not reduce spatial density to save
   memory. Add a probe-noise capture and a thin-wall capture before changing the
   representation.

## Evidence

### 1. Irradiance volumes

#### 1.1 Greger, Shirley, Hubbard, Greenberg 1998

The paper defines a volumetric representation of irradiance at all points and
directions in space, not just on surfaces [1, abstract]. The implementation in
Greger's thesis stores, at each spatial sample, two 2D arrays of directional
irradiance, one per hemisphere:

> "Every sample is stored as two two-dimensional arrays. Each array represents
> the irradiance computed over a hemisphere, with each array element
> corresponding to a direction in (u, v) space. ... After the eight values are
> obtained, trilinear interpolation is used to get the irradiance at point x."
> [1, thesis §4.3]

Three details matter for the comparison:

- **Grid placement.** The base grid is uniform; a cell that contains geometry is
  subdivided into a second-level 3x3x3 grid. One example uses a 7^3 (343-sample)
  first-level grid plus 72 second-level 3x3x3 grids, 2287 spatial samples total;
  Greger calls the scheme a "bilevel grid" [1, thesis §4.1, §4.3, §5.1.1]. The adaptive
  step is around geometry, not a general octree.
- **Directional interpolation.** The original stores directional bins and
  returns the bin value; it does not interpolate between directions. Greger
  notes that smoother shading could be obtained by interpolating neighboring
  bins, but "performing these interpolations will reduce the performance of
  volume queries" [1, thesis §6.1.2]. The 8x8 bilinear octa map is already smoother than
  the original representation.
- **Known error.** "Most of the serious errors in spatial interpolation occur
  across visibility events." The bilevel grid reduces the size of the bad
  regions but "does not eliminate the problem" [1, thesis §6.1.1]. Greger also documents
  self-occlusion error for dynamic objects: the volume cannot represent the
  object's own occlusion, and suggests a precomputed visibility ratio as a
  mitigation [1, thesis §5.1.3, §5.10]. This is the same class of leak that later probe
  systems attack with depth tests and bias.

Historically, harbagsa's octa map is closer to Greger's directional bins than SH
is: it stores a dense directional table and interpolates it. SH is the compressed
descendant of the same idea, not the original representation.

The original has no SH, no normal bias, no Chebyshev moments, and no tetrahedral
interpolation. Those are later production additions. Do not attribute them to
1998.

#### 1.2 Christensen and Batali 2004: "An Irradiance Atlas"

This is the paper actually titled "An Irradiance Atlas for Global Illumination in
Complex Production Scenes" [2]. It is a tiled 3D MIP map, not a 2D lightmap atlas:

> "The data are organized in a sparse, adaptive octree. Each node ... has a
> pointer to a brick. A brick has N^3 voxels (we have chosen 8^3 in our
> implementation)." [2, §3.1]

The lookup builds a "lookup volume" from the query position and filter size,
walks the octree to the level whose voxels match that size, and weights the
overlapping voxels. To stop color leaking across edges and thin objects, it uses
the average normal per voxel:

> "If the voxels that overlap V_l have the 'incoherent normals' flag set, we
> reduce the size of the lookup volume and look deeper in the octree to resolve
> the normals. This resolves potential color leaking problems along edges and
> through thin objects." [2, §3.3]

> "... we determine which voxels overlap the lookup volume and have normals
> similar to the lookup normal (for example within 45 degrees)." [2, §3.3]

The production numbers show the scale: 237 million unique triangles, 52 million
photons, 29 minutes of photon tracing, 43 minutes to build the irradiance atlas,
and 3.8 hours to render on a 3.4 GHz CPU [2, §5]. A 10 MB brick cache is the
default [2, §3.4]. This is a film renderer's irradiance volume, but the failure
modes are the same ones a game probe volume has: interpolation across visibility
discontinuities, thin objects, and memory.

#### 1.3 Tabellion and Lamorlette 2004

The brief attributes "An Irradiance Atlas" to Tabellion and Lamorlette. That is a
mix-up: their 2004 SIGGRAPH paper is "An Approximate Global Illumination System
for Computer Generated Films" [3]. It is an irradiance **cache**, not a regular
irradiance volume:

> "Every irradiance sample is saved in a cache along with corresponding geometric
> information and irradiance gradient vectors. This information is used to
> smoothly extrapolate irradiance values for neighboring positions." [3, §4.5]

The cache uses a distance term and a normal term, with the normal tolerance
hard-coded to 10 degrees; the paper does not name a separate position-side
"behind" test [3, §4.5, Eq. 2-5]. The production shot contained 68,615
irradiance samples at film resolution; the average was 420 rays per sample, with
50 to 2000 depending on the shot, and the cache gave about 3x scalability from
video to film resolution [3, §6]. This is a useful production data point for
sparse sampling and gradient interpolation, but it is not a regular grid and it
is not the "irradiance atlas" paper.

#### 1.4 Oat, "Irradiance Volumes for Games," GDC 2005

This is the practical game treatment the question asks for. Oat describes the
volume as "a 3D light map: volume of diffuse lighting samples" and recommends SH
as the storage and evaluation basis [4, slides 5-17]. The specific numbers:

> "3rd order SH approximation for R, G and B: 27 floats
> 3rd order SH gradients for R, G, and B: 81 floats
> 108 floats / sample"
> [4, slide 50]

> "6th order SH approximation for R, G and B: 108 floats
> 6th order SH gradients for R, G, and B: 324 floats
> 432 floats / sample"
> [4, slide 50]

He reports about 2 MB for 3rd-order SH plus gradients and about 970 kB in a
smaller scene; 6th order is 8.2 MB and 3.8 MB [4, slide 51]. Interpolation is
explicitly trilinear in the SH coefficients:

> "Seven LERPs of the spherical harmonic coefficients. Works well for uniformly
> subdivided volumes. Adaptively subdivided volumes require slightly more care."
> [4, slide 41]

The talk also names the adaptive-grid problem: naive trilinear interpolation
between different octree levels produces popping, so neighboring samples must be
kept for interpolation [4, slides 42-43]; gradients and tricubic Hermite patches
are the higher-quality options [4, slides 44-45]. This is the same trade-off
harbagsa avoids by using one uniform 1 m grid.

#### 1.5 Practical engine use

| Engine | Representation | Spatial placement | Directional interpolation | Notes |
| -- | -- | -- | -- | -- |
| Unity classic Light Probes | L2 SH, 27 floats (9 per RGB) | Artist-placed Light Probe Group | Tetrahedral (Cupisz GDC 2012, cited by Unity) | Per-object by default |
| Unity Adaptive Probe Volumes (APV) | Light-probe data (the APV pages cited here do not state the basis or coefficient count) | Adaptive 4x4x4 bricks, 1/3/9/27 m default spacings | Eight-probe cage per pixel | Virtual Offset + Dilation; per-pixel sampling |
| Unreal Volumetric Lightmap | Third-order SH | Adaptive 4x4x4-cell bricks, denser near geometry | Per-pixel interpolation | Replaces the Indirect Lighting Cache; for dynamic objects |
| Godot LightmapGI probes | 9 SH coefficients per probe | Automatic subdivision or manual LightmapProbe nodes | Delaunay tetrahedralization + BSP | Dynamic objects only; direct light always real-time |

Sources: Unity [12,13,27]; Unreal [17]; Godot [20-22]. Unity's manual is explicit
that classic probes are L2 SH: "third order polynomials, also known as L2
Spherical Harmonics ... 27 floating point values, 9 for each color channel"
[12]. Unreal says each Volumetric Lightmap sample "uses a Third Order Spherical
Harmonic to store the incoming lighting in all directions" [17]. Godot's runtime
buffer is `sizeof(float) * 4 * 9 * probe_count`, and the bake writes nine
coefficients per probe before `Delaunay3D::tetrahedralize` [22].

The practical pattern is consistent: **low-order SH for the directional
function, a spatial grid or tetrahedralization for position, and a visibility or
validity mechanism for leaks.** Harbagsa keeps the spatial grid and visibility
mechanism but uses a dense octa map for the directional function.

### 2. Spherical harmonics

#### 2.1 Nine coefficients are the diffuse answer

Ramamoorthi and Hanrahan derive an analytic expression for irradiance in terms of
the SH coefficients of the lighting and show that only the lowest three bands
matter:

> "... one needs to compute and use only 9 coefficients, corresponding to the
> lowest-frequency modes of the illumination, in order to achieve average errors
> of only 1%. In other words, the irradiance is insensitive to high frequencies
> in the lighting, and is well approximated using only 9 parameters." [5,
> abstract]

The error statement is more precise in §3.1:

> "... the average error over all surface orientations can be shown to be under
> 3% for any physical input lighting distribution. For the environment maps used
> in our examples ... the average error is under 1%, and the maximum pixel error
> is under 5%." [5, §3.1]

Nine coefficients means l = 0, 1, 2, i.e. one constant, three linear, and five
quadratic basis functions. The reconstruction is a quadratic polynomial in the
normal, which is why it is cheap in a shader [5, §3.2, Eq. 11-13].

The often-quoted claim that "99% of the energy is in the first 9 coefficients"
was **not found** in the 2001 paper. The paper's claims are the 1%/5%/3% error
bounds above. Use those, not the 99% slogan.

#### 2.2 Ringing and windowing

Nine coefficients are enough on average, but the truncated basis is not exact,
and truncation produces ringing. Sloan's GDC 2008 companion paper gives the
cleanest statement of the problem for irradiance:

> "The Order 3 SH approximation over estimates by 1/16th at theta=0 (north pole)
> and has a spurious lobe at the south pole with magnitude of 1/16th. A
> directional light source that would reflect a value of 17 when a normal points
> at it would reflect a value of 1 pointing in the opposite direction (should be
> reflecting 0.)" [6, "Irradiance Environment Maps"]

That is a concrete, basis-level false lobe: a bright source can put about 6% of
its peak on the opposite side of the sphere. Sloan also notes that order 5 has a
negative lobe and can be worse for very bright HDR sources [6]. The standard
mitigation is windowing the coefficients with sigma factors (Hanning or
Lanczos):

> "Looking at all the graphs together ... you can see how windowing blurs the
> signal while eliminating the rings." [6, "Ringing"]

> "... the choice of windowing function is not as important as having
> flexibility to trade off between ringing and blurring." [6, "Ringing"]

For a hard-edged box arena with bright emissive panels and point lamps, this is
not a theoretical concern: the spurious lobe is a global leak that a depth test
cannot remove, because it lives in the probe's directional reconstruction, not
in the probe-to-surface visibility.

#### 2.3 SH9 versus an 8x8 octahedral map

| Property | SH9 (L2, 3 bands) | 8x8 octahedral irradiance |
| -- | -- | -- |
| Coefficients / texels | 9 per color channel | 64 texels, 3 channels used |
| Bytes per probe, RGB f16 / RGBA16F | 54 B | 512 B (RGBA16F) or 256 B (R11G11B10) |
| Directional degrees of freedom | 9 | 64 samples, bilinearly reconstructed |
| Diffuse fit | Matched to the l <= 2 clamped cosine | More resolution than the signal needs |
| Ringing | Yes; 1/16 back lobe for the 9-coefficient kernel [6] | No global ringing; local bilinear error |
| Seam | None | Octahedral seam; needs wrap or gutter |
| Signed values | Yes; needs f16 or a sign encoding | Non-negative; unsigned HDR formats work |
| Interpolation | Interpolate coefficients, then evaluate once | Interpolate per-probe direction lookups |
| Engine precedent | Unity classic probes, Unreal VLM, Godot | DDGI / RTXGI |

The DOF comparison is rough: 8x8 has 64 samples, about the sample count of SH
order 7, but bilinear reconstruction lowers the effective resolution. The point
is not the exact equivalence; it is that the cosine-convolved irradiance signal
has very little energy above l = 2, so most of those 64 samples are spent on
detail the signal does not contain.

#### 2.4 Engine specifics

- **Unity classic Light Probes.** L2 SH, 27 floats. The manual points to Robert
  Cupisz's GDC 2012 talk, "Light Probe Interpolation Using Tetrahedral
  Tessellations" [12]; the probe data is SH and the interpolation is tetrahedral,
  so the interpolated result is an SH probe rather than a directional texture.
- **Unity APV.** Adaptive 4x4x4 bricks; default probe spacings 1, 3, 9, and 27
  m; "Each pixel of a GameObject samples lighting data from the eight closest
  Light Probes around it" [13]. APV adds Virtual Offset and Dilation for invalid
  probes [14] and documents normal bias, view bias, leak reduction mode, and
  rendering layer masks as leak fixes [15].
- **Unreal Volumetric Lightmap.** 4x4x4-cell bricks, denser near static
  geometry, third-order SH, interpolated per pixel [17]. It replaces the older
  Indirect Lighting Cache and is specifically for dynamic objects; static
  objects use surface lightmaps [17].
- **Godot LightmapGI.** Dynamic objects receive indirect from light probes;
  probes can be generated automatically or placed as `LightmapProbe` nodes [20,
  21]. The bake writes nine SH coefficients per probe and Delaunay-tetrahedralizes
  the probe positions, with a BSP tree for locating the containing tetrahedron
  [22]. Direct light on dynamic objects is always real-time [20].
- **Harbagsa.** No SH. The directional function is an 8x8 octa map; spatial
  interpolation is tetrahedral over four probes [26].

### 3. Spherical Gaussians and other compact directional bases

Wang et al. 2009 define a spherical Gaussian as

> `G(v; p, lambda, mu) = mu * exp(lambda * (v . p - 1))`
> [7, §3, Eq. 2]

and use a mixture of a few lobes for all-frequency, spatially varying
reflectance. The properties that matter:

- SGs are compactly supported for a threshold epsilon; the support area shrinks
  as sharpness grows [7, §3, Eq. 3].
- A product of two SGs is another SG in closed form, and rotations rotate the
  lobe axis [7, §3, Eq. 5-7].
- The inner product of two SGs has a closed form [7, §3, Eq. 4].
- The basis is **not orthogonal**. The product of two n-term SG mixtures
  considers all pairs, so it is O(n^2); the paper uses SG mixtures only for
  sparse functions with small n [7, §3].

These properties make SGs a good fit for **high-frequency specular** and
all-frequency BRDF slices: a few lobes can represent a sharp highlight, and
products with lighting/visibility are analytic. They are a poor default for
**diffuse irradiance**:

- Diffuse irradiance is the low-frequency, cosine-convolved part of the light.
  SH9 is orthogonal and near-optimal for exactly that band-limited signal [5].
- An SG representation needs a fitting step, and the number of lobes needed for
  a given error is scene-dependent. Where the engine documentation states the
  basis, it is SH, not SG: Unity classic probes, Unreal's Volumetric Lightmap,
  and Godot's lightmap probes [12,17,22]. The APV pages cited here do not state
  the basis or coefficient count [13].
- The O(n^2) mixture product and non-orthogonality make the runtime and the
  tooling more complex than SH9 for no clear diffuse-quality gain.

Other compact bases occupy the same design space (analysis; the basis families
are surveyed in [6,7]): zonal harmonics are cheap for axially symmetric lights
but not general directional functions; wavelet bases are all-frequency but
non-local and expensive to rotate; a dense octa map is a local basis with no
ringing but more storage. For a flat, untextured, diffuse box arena, SH9 is the
natural compact basis and the octa map is the natural dense basis. SGs are the
right tool only if the probe field must also carry sharp, directional radiance,
which is a different feature.

### 4. Probe-based dynamic-object GI

#### 4.1 Light probes and tetrahedral interpolation

Unity's classic probes and Godot's lightmap probes both use tetrahedral
interpolation. Unity's manual explicitly cites Cupisz's GDC 2012 talk on
"Light Probe Interpolation Using Tetrahedral Tessellations" [12]. Godot's bake
runs `Delaunay3D::tetrahedralize` on the probe positions and stores the
resulting tetrahedra plus a BSP tree [22]. The tetrahedral approach:

- Uses four probes per query, not eight, so it is cheaper.
- Is piecewise linear and exact for a linear field inside each tetrahedron.
- Handles irregular probe placement naturally; Delaunay gives a well-shaped
  tetrahedralization, and the BSP locates the containing cell.
- Can still span a thin wall if the tetrahedralization crosses it; geometry
  visibility is a separate problem.

Trilinear interpolation uses the eight-probe cage of the containing grid cell.
Unity APV samples the eight closest probes per pixel [13]; DDGI computes weights
for the eight-probe cage and then applies a standard trilinear interpolation
[9, §5.2]. Trilinear is simple on a regular grid and all weights are
non-negative, but it includes the whole cage and can smooth across a diagonal.
On a regular grid, harbagsa's fixed six-tetrahedron decomposition gets the
four-probe cost without Delaunay slivers or a BSP; that is a good fit for its
uniform 1 m grid.

#### 4.2 Adaptive Probe Volumes

Unity's APV is the clearest production example of an adaptive probe volume:

- The volume is filled with 4x4x4-probe bricks; brick size varies with geometry
  density, with default probe spacings of 1, 3, 9, and 27 m [13].
- Each pixel samples the eight closest probes [13].
- Invalid probes are handled in two stages: Virtual Offset moves the capture
  point outside geometry, and Dilation copies data from nearby valid probes for
  probes that remain invalid [14].
- Leak controls include thicker walls, normal bias, view bias, leak reduction
  mode, rendering layer masks, a smaller dilation search radius, and higher probe
  density [15].

The important production lesson is that **placement and validity are separate
from the directional representation**. APV can change brick density, dilation,
and bias without changing the probe data. Harbagsa has a fixed uniform grid and
a single valid byte, so placement and validity are coupled to the bake.

#### 4.3 Unreal Volumetric Lightmap

Unreal's Volumetric Lightmap is the closest shipped analogue to harbagsa's
static probe field:

- Bricks of 4x4x4 cells, placed over the Lightmass Importance Volume and
  refined around static geometry [17].
- Each sample stores a third-order SH of incoming lighting [17].
- At runtime, the volume is interpolated to each pixel for dynamic objects [17].
- Static objects use surface lightmaps; the Volumetric Lightmap exists to give
  dynamic objects the baked indirect term [17].

That is exactly harbagsa's split: static boxes read the lightmap, dynamic boxes
read the probe field [26]. Unreal's dynamic objects do not occlude the baked
field either; the field is static, and dynamic occlusion is a separate problem.
Harbagsa's additional limitation is that dynamic crates do not occlude or
contribute to the field at all, which is the same class of limitation but more
visible in a crate-pushing game.

#### 4.4 Light field probes

McGuire et al. 2017 encode a full light field plus per-texel visibility:

> "Light field probes encode a scene's full light field and internal visibility.
> They extend current radiance and irradiance probe structures with per-texel
> visibility information similar to a G-buffer and variance shadow map." [8,
> abstract]

The scale is different from a diffuse probe field: a 4x4x4 probe grid of
1024x1024-texel probes, 8 bytes per octahedral texel, rendered at 4.7 ms [8,
Figure 1, §3]. The prefiltered irradiance path is explicitly "fast and
noise-free, but biased" [8, §1]. Per-texel visibility is what removes the
light/dark leaks that plain irradiance probes have [8, §5].

This is the high end of the design space: full radiance and visibility for
glossy and diffuse GI. It is far too heavy for harbagsa's 6 MB probe field and
its flat diffuse look, but it is the clearest evidence that **visibility per
direction** is the robust answer to probe leaks.

#### 4.5 Validity, dilation, and relocation

| Technique | Source | What it does | Failure mode |
| -- | -- | -- | -- |
| Virtual Offset | Unity APV [14,16] | Moves an invalid probe's capture point out of geometry | Can push through a nearby wall or into another room |
| Dilation | Unity APV [14,16] | Copies lighting from nearby valid probes | Larger search radius can copy across a lighting discontinuity |
| Probe position adjustment | DDGI-Production [10, §5] | Iteratively shifts probes through the closest backface, then away from close front-faces; 5 iterations | Can double-cover a surface; not applied to dynamic geometry |
| Normal + view bias | DDGI-Production [10, §4.1]; Unity APV [15] | Moves the visibility test point along a blend of normal and view | Too much bias leaks light around corners |
| Backface depth shortening | DDGI-Production [10, §4.1] | Backface rays record zero irradiance and shorten depth by 80% | Depth moments become conservative; can over-darken |
| Thicker walls / layer masks | Unity APV [15] | Separates probes by geometry or rendering layer | Content/tooling cost; layer masks are a coarse partition |

Harbagsa's equivalents:

- **Virtual offset:** `probe_sample` pushes a probe out through the nearest face
  by up to 0.5 m, with a 0.02 m margin; if it cannot get out, the probe is
  invalid [26, `src/bake/probe.odin:301-349`, `src/bake/bake.odin:126-127`].
- **Dilation:** after the bake, an invalid probe copies the nearest valid probe
  within a radius of 2 cells and adjusts the stored offset so the depth test is
  measured from the copied origin [26, `src/bake/probe_dilate.odin:8-85`].
- **Normal bias:** the shader samples at `world_position + normal * 0.1 * spacing`
  [26, `src/renderer/shaders/probe.glsl:176`]. There is no view-direction
  component.
- **Facing weight:** a probe behind the tangent plane is weighted by
  `max(dot(-direction, normal), 0)^2` [26, `src/renderer/shaders/probe.glsl:217-219`].
- **Depth moments:** the shader computes mean and variance from two f16 moments
  and applies a cubed Chebyshev weight with a 0.05 floor [26,
  `src/renderer/shaders/probe.glsl:224-236`].

The gaps relative to production are not exotic: no view bias, no backface depth
shortening, a dilation radius of 2 cells, and no layer-mask/portal separation.

#### 4.6 Leak fixes in one table

| Fix | What it targets | Cost |
| -- | -- | -- |
| More probe density | Interpolation error and small occluders | Cubic memory and bake time |
| Thicker walls / layer masks | Thin-wall and room-to-room leaks | Content rules, extra data |
| Normal + view bias | Self-shadow and grazing-angle leaks | Can leak around corners if too high |
| Facing/backface weight | Probes behind the surface | Over-darkens at grazing angles |
| Depth moments + Chebyshev | Probe-surface visibility | f16 variance precision; bimodal depth |
| Backface depth shortening | Probes seeing the far side of geometry | Conservative depth; over-darkening |
| Probe relocation | Probes inside geometry | Double coverage; not for dynamic geometry |
| Dilation | Invalid probes | Can copy across lighting discontinuities |
| Multiple volumes / portals | Distinct rooms | Authoring and runtime volume selection |

### 5. DDGI as the dynamic/noisy contrast

#### 5.1 Representation and update

DDGI encodes diffuse irradiance in an 8x8 octahedral map at R11G11B10F and
distance/distance-squared moments in a 16x16 RG16F map [9, §3]. The reference
configuration updates every probe every frame with 64 rays per probe at a
32x8x32 grid, about 0.52M rays per frame, and reports about 7 ms for its indirect
contributions on an RTX 2080 Ti at 1920x1080 [9, §6.2, Table 2]. Ray throughput
is 1.5-1.65 GRays/s [9, §6.2, Table 1].

The update is a cosine-weighted sum of ray radiance, with a hysteresis blend:

> `newIrradiance[texelDir] = lerp(oldIrradiance[texelDir], sum(max(0, texelDir . rayDir) * rayRadiance), hysteresis)`
> [9, §4.4, Eq. 1]

with `alpha` between 0.85 and 0.98 [9, §4.4]. The probe cage is trilinear, and
the interpolation adds a soft backface test, a low-irradiance perceptual weight,
mean/variance-biased Chebyshev visibility, and a normal-and-direction bias [9,
§5.2]. Those terms are the direct ancestors of harbagsa's facing weight, Chebyshev
test, and normal bias.

#### 5.2 Why temporal accumulation

The 2019 paper's per-frame budget is deliberately undersampled: 64 rays spread
over a sphere cannot resolve a sharp occlusion edge, and the next frame uses a
different rotation. The paper samples directions with a "stochastically-rotated
Fibonacci spiral" [9, §4.2] and blends over time. The temporal filter is not
hiding a mathematical necessity; it is amortizing a ray budget. The paper's own
limitations are a time lag in multiple bounces and error from the probe-density
assumption [9, §5.3, §7].

#### 5.3 What is deterministic when the rays are fixed

If the ray directions, ray count, scene, and lights are fixed, the DDGI update is
a deterministic quadrature: a weighted sum of the same radiance samples. The
hysteresis blend is a deterministic first-order IIR filter; with fixed input it
converges geometrically. The trilinear weights, backface test, Chebyshev test,
and bias are deterministic functions of position, normal, and probe data. The
only stochastic input in the reference is the per-frame rotation; adaptive probe
selection, which the paper disables in its performance runs, is a deterministic
heuristic [9, §4.2]. So "DDGI is noisy" is a statement about its
per-frame sampling budget and temporal filter, not about ray tracing being
inherently random. A fixed-ray DDGI is deterministic but biased and aliased; a
1024-ray offline bake is deterministic and much less aliased.

#### 5.4 Production extensions that matter

The 2021 production paper extends DDGI for RTXGI, Unity, and Unreal Engine 4
[10]. Four details are directly relevant:

1. **Gamma-5 perception encoding.** `irradianceGamma = 5.0`; encode
   `pow(sum, 1/5)`, decode `pow(stored, 2.5)` to leave a gamma-2 curve, weight
   the probes, then square [10, §4.2, Figure 4]. The paper says the exponent was
   chosen experimentally for perceptual convergence and firefly reduction [10,
   §4.2].
2. **Self-shadow bias.** A single vector
   `(n * 0.2 + view * 0.8) * (0.75 * D) * B`, with `B` defaulting to 0.3 and `D`
   the minimum axial probe distance [10, §4.1, Eq. 2]. It replaces three
   scene-tuned biases with one parameter.
3. **Backface handling.** Backface rays record zero irradiance and shorten their
   depth by 80%, so the probe sees the backface as shadowed [10, §4.1]. This is
   a direct leak fix that a plain depth moment does not provide.
4. **Probe position adjustment.** Five iterations move probes through the
   closest backface and away from close front-faces; the paper explicitly does
   not move probes around dynamic geometry because that would be unstable [10,
   §5].

Harbagsa has the gamma-5 encoding, a normal-only 0.1 m bias, and a one-shot
out-of-geometry offset. It does **not** have the view component, the backface
depth shortening, the iterative relocation, or the per-texel hysteresis (it does
not need the last one because it has no temporal update).

### 6. Storage and encoding

#### 6.1 Formats

Bit layouts are from the Vulkan and DXGI format specifications [23,24].

| Format | Bits per texel | Layout | Sign | Range / precision notes |
| -- | --: | -- | -- | -- |
| RGB9E5 | 32 | 5-bit shared exponent, 9-bit mantissa per channel | Unsigned | Unity's Enlighten irradiance uses it; range [0, 65408] [25]. One channel's magnitude sets the exponent for all three. |
| R11G11B10F | 32 | 5-bit exponent per channel, 6/6/5-bit mantissa | Unsigned | About 65k maximum; blue has one fewer mantissa bit; cannot represent exact grays, which DDGI observed as a green tint [9, §6.3] |
| RGBA16F | 64 | 5-bit exponent, 10-bit mantissa per channel | Signed | Max 65504; good general HDR; 2x the storage of the packed 32-bit formats |
| RGB16F | 48 | Same as f16, three channels | Signed | Good for signed SH coefficients; 3-channel formats can be less efficient on some hardware |
| SH9 RGB f16 | 54 B per probe | 9 coefficients x 3 channels x 2 B | Signed | The natural compact diffuse probe; no gamma decode, no octa seam |

The format choice follows from the sign and the range:

- **Octahedral irradiance is non-negative.** It can use RGB9E5 or R11G11B10F.
  Harbagsa uses RGBA16F, with the alpha channel written as 1.0 and never read
  [26, `src/bake/probe.odin:243-246`]. That is 25% waste in the irradiance map.
- **SH coefficients are signed.** RGB9E5 and R11G11B10F cannot store negative
  values, so SH9 needs f16 (or a sign-mask scheme). This is a hidden cost of the
  "SH9 is smaller" argument: it is smaller than RGBA16F, but it cannot use the
  cheapest unsigned HDR format.
- **Moments are non-negative but ill-conditioned.** Mean and mean-square are
  stored as f16 [26, `src/bake/probe.odin:248-249`]. The shader computes
  `variance = abs(mean * mean - moments.y)` [26,
  `src/renderer/shaders/probe.glsl:229`]. In f16, the subtraction loses
  precision when the variance is small relative to the mean squared; the `abs`
  hides the sign but not the cancellation. A thin wall that puts two depth
  populations in one texel also makes the mean/variance model wrong, not just
  imprecise.

#### 6.2 Gamma encodings

Harbagsa's bake stores `(irradiance / 2)^(1/5)` and the shader decodes with
`pow(encoded, 2.5)`, which leaves `sqrt(irradiance / 2)`; the final square and
2x restore irradiance [26, `src/bake/probe.odin:186-189`,
`src/renderer/shaders/probe.glsl:168-170, 241-248`]. This is the DDGI-Production
gamma-5 curve [10, §4.2, Figure 4], not an arbitrary "legacy" choice.

Three consequences:

1. **The four-probe blend is in square-root space, not linear irradiance.** For
   two equal weights with values L and 0, the result is L/4, not L/2. The
   internal review derived exactly this [26, `docs/research/lighting-system-review.md`].
   The primary source shows the order is deliberate in DDGI: the comment in the
   production shader says "leave a gamma = 2 curve to approximate sRGB blending
   for the trilinear" [10, Figure 4]. It is a perceptual approximation, not an
   accidental encode/decode mismatch. DDGI's comment is about its eight-probe
   trilinear blend; harbagsa applies the same curve to a four-probe tetrahedral
   blend, so the perceptual argument is inherited rather than re-derived for
   this sampler. Whether it is right for a static bake is a separate decision.
   The lightmap is linear RGBA16F and has no such decode, so this is a
   probe-path-specific bias [26, `docs/adr/0045-mixed-static-baked-indirect.md`].
2. **The intra-probe bilinear tap is also in encoded space.** The sampler
   filters the stored gamma-5 values before the shader decodes them [26,
   `src/renderer/shaders/probe.glsl:54-75`]. Hardware bilinear interpolation of
   a nonlinear encoding is not the same as interpolation of linear irradiance.
   The error is small where neighboring texels agree and larger at a sharp
   directional edge.
3. **The gamma curve spends precision at the low end and gives it up at the
   high end.** That is the point of a perceptual encoding, but it is not a
   storage necessity for f16, whose range is already 0-65504 [25]. If the goal
   is linear interpolation, decode each tap first and average in linear space;
   if the goal is DDGI's perceptual behavior, keep the curve and document it.

#### 6.3 Octahedral mapping details

Cigolle et al. call octahedral mapping "the best overall method: fast to encode
and decode, and a near-uniform mapping" [11, §4]. Light field probes report
about a factor of four space and bandwidth reduction compared with cube maps at
the same quality [8, §3]. The costs are a seam at the square boundary and
non-uniform area (more distortion near the corners).

DDGI uses a one-pixel gutter around each probe tile "to allow bilinear
interpolation without any boundary artifacts" [9, §3]. Harbagsa has no gutter:
`probe_atlas_uv` clamps the tile coordinate to the first and last texel center,
which prevents bleeding into the neighboring probe but does not wrap across the
octahedral seam [26, `src/renderer/shaders/probe.glsl:51-68`]. The result is a
one-texel plateau at the seam, not a leak. It is a small quality detail that a
gutter or a seam-aware tap would remove.

### 7. Comparison to harbagsa

#### 7.1 Facts

| Property | harbagsa | Source |
| -- | -- | -- |
| Probe volume | One axis-aligned grid, origin (-20, 0, -20), 40 x 5 x 40, 1 m spacing, 8000 probes | [26, `src/bake/bake.odin:135-147`] |
| Probe heights | Cell centers y = 0.5 ... 4.5; volume bounds y = 0 ... 5 | [26, `src/bake/bake.odin:140-146`] |
| Rays per probe | 1024 fixed Fibonacci rays, per-probe hash rotation | [26, `src/bake/bake.odin:33`; `src/bake/probe.odin:158`] |
| Irradiance | 8x8 octahedral, RGBA16F, gamma-5, 512 B/probe | [26, `src/bake/bake.odin:23-28,133`] |
| Depth | 8x8 octahedral, RG16F first/second moments, cos^50 directional lobe, 256 B/probe | [26, `src/bake/probe.odin:224-249`] |
| State | 8 B/probe: valid byte + three f16 offsets | [26, `src/renderer/shaders/probe.glsl:20-49`] |
| Spatial interpolation | Tetrahedral, four probes, six-tetrahedron cell decomposition | [26, `src/renderer/shaders/probe.glsl:92-165`] |
| Normal bias | `normal * 0.1 * spacing` | [26, `src/renderer/shaders/probe.glsl:176`] |
| Facing weight | `max(dot(-direction, normal), 0)^2` | [26, `src/renderer/shaders/probe.glsl:217-219`] |
| Visibility test | Chebyshev on two f16 moments, cubed, 0.05 floor | [26, `src/renderer/shaders/probe.glsl:224-236`] |
| Invalid probe handling | Out-of-geometry offset up to 0.5 m; otherwise dilation radius 2 | [26, `src/bake/probe.odin:301-349`; `src/bake/probe_dilate.odin:8-85`] |
| Bake cost | About 5.1 s total; probe stage about 1.9 s; artifact 14,608,480 B | [26, `docs/evidence/mixed-lighting.md`] |
| Runtime cost | Probe term below the 0.006 ms measurement noise; lightmap+probe about 0.028-0.033 ms | [26, `docs/evidence/mixed-lighting.md`] |
| Bake lifecycle | Keyed artifact; missing/stale/current/failed; explicit publish | [26, `docs/adr/0045-mixed-static-baked-indirect.md`] |
| Dynamic lamps | Direct only; no indirect | [26, `docs/adr/0045-mixed-static-baked-indirect.md`] |
| Lightmap | 1024^2 RGBA16F, 4 texels/m, 128 rays/texel, one separable 3x3 binomial per chart | [26, `docs/adr/0045-mixed-static-baked-indirect.md`; `docs/evidence/mixed-lighting.md`] |
| Static boxes | Lightmap only; never read probes | [26, `docs/adr/0045-mixed-static-baked-indirect.md`] |
| Dynamic boxes | Probe field only; do not occlude or contribute | [26, `docs/adr/0045-mixed-static-baked-indirect.md`] |
| Bounce | One diffuse bounce; static fixtures and static emissive boxes contribute | [26, `docs/adr/0045-mixed-static-baked-indirect.md`] |

#### 7.2 Is 8x8 octa overkill?

**For angular resolution: not relative to DDGI; yes relative to the diffuse
signal.** DDGI uses the same 8x8 irradiance resolution [9, §3]. Ramamoorthi and
Hanrahan say nine coefficients are enough for the diffuse field [5], and DDGI's
Figure 9 shows that low angular resolution can look close to the reference when
the probe grid is dense enough; the paper concludes that probe count is the
larger lever [9, §6.1]. Harbagsa's 1 m grid is already at the dense end of
DDGI's recommended 1-2 m [9, §4.1]. A 4x4 octa would likely be indistinguishable
in the open arena; the risk is at sharp occlusion edges, where the extra
direction samples help.

**For storage: yes, the format is overkill.** The 8x8 RGBA16F map is 512 B per
probe. DDGI's 8x8 R11G11B10 map is 256 B [9, §3]. Harbagsa stores a fourth
channel that is always 1.0 [26, `src/bake/probe.odin:243-246`]. A format change
is the cheapest win in the whole system.

**For depth: the field is under-resolved relative to DDGI.** DDGI uses 16x16
depth moments [9, §3]; harbagsa uses 8x8 [26, `src/bake/bake.odin:23-28`].
Harbagsa's depth uses a cos^50 lobe, whose half-angle is about 9.5 degrees
(analysis: `acos(0.5^(1/50))`), while an 8x8 map has about 11.25 degrees between
texel centers in the square parameterization. Each texel is therefore a narrow
cos^50 average, and bilinear interpolation fills between the centers; a thin
occluder can still fall between the sampled directions. If leaks are the
concern, spending the irradiance-format savings on a 16x16 depth map is a better
trade than adding more irradiance texels.

#### 7.3 Would SH9 be better?

**Better on memory, linearity, and engine precedent.** SH9 at f16 is 54 B per
probe; with the current 8x8 moments and state, 318 B per probe, 2.54 MB for 8000
probes. The current field is 776 B per probe, 6.21 MB. The irradiance part alone
shrinks 9.5x; the total shrinks 2.4x because the depth moments dominate. SH9 also
removes the gamma-5 decode, the octahedral seam, and the per-texel partition
noise, and it is what Unity, Unreal, and Godot use for diffuse probes
[12,17,22].

**Not automatically better on image quality.** The 9-coefficient clamped-cosine
approximation has a 1/16 spurious back lobe [6]. A bright emissive panel or lamp
in the probe's view can add false light on the opposite side of the probe, where
the clamped cosine should be zero, and a depth test cannot remove a lobe that
lives in the directional reconstruction. The octa map is local and measured: a
lamp behind a wall simply does not contribute to the directions that cannot see
it. For harbagsa's high-contrast, hard-edged arena, that local support is
valuable. SH9 also needs windowing (which blurs) and signed f16 storage (which
rules out the cheapest unsigned formats).

**Runtime is not the deciding factor.** The current probe term is below the
0.006 ms measurement noise [26, `docs/evidence/mixed-lighting.md`]. SH9 replaces
the four per-probe irradiance fetches and `pow` decodes with coefficient
interpolation and a nine-term polynomial; the depth-moment fetches stay. It may
be similar or slightly more ALU. The reasons to switch are memory and the
removal of the nonlinear decode, not frame time. Context: the full frame at 96
lights and 1080p is 1.50-1.52 ms GPU total (1.83-1.85 ms interval) against an
8 ms budget [26, `docs/evidence/mixed-lighting.md`], so the probe term is not
the frame-time constraint.

**Verdict.** SH9 is the better default for a pure diffuse probe field, provided
it is windowed and tested on the dark side of a bright emitter and at a thin
wall. It is not a guaranteed image-quality win over the current octa map, and
the internal review's "single best simplification" claim [26] is stronger than
the evidence supports for this specific scene. Test both against a high-ray
reference before rewriting the bake.

#### 7.4 What leaks remain

1. **Thin walls and sub-probe occluders.** The 1 m grid can place valid probes on
   both sides of a wall thinner than 1 m. Tetrahedral interpolation can select
   probes from both sides; the facing weight only suppresses probes behind the
   tangent plane, and the Chebyshev moment test can agree on distance through a
   thin wall. The historical DDGI ADR, whose probe field the bake inherited, says
   "a thin wall still has probes on both sides" and says "a very thin wall
   remains the case to watch" [26, `docs/adr/0042-single-volume-ddgi.md`].
   The sealed-cell evidence is a thick 4x4 m cell, not a thin wall [26,
   `docs/evidence/mixed-lighting.md`]. Production fixes are thicker walls, layer
   masks, backface depth shortening, and relocation [10,15].
2. **Dilation radius 2.** A radius of two cells (2 m at 1 m spacing) copies the
   nearest valid probe, which can be in a different lighting region. Unity warns
   that a larger search radius can cause exactly this [15,16]. Harbagsa copies a
   single nearest probe rather than blending several, so the result can also be a
   hard patch. A radius of 1 is worth testing.
3. **Normal-only bias.** The 0.1 m normal bias helps self-shadowing but does not
   move the sample toward the viewer at grazing angles. DDGI-Production's
   self-shadow bias is 80% view direction [10, §4.1]. A grazing view along a wall
   is the case where the normal-only bias is weakest.
4. **Full-depth backfaces.** Harbagsa zeroes backface radiance but stores the
   backface distance in the moments [26, `src/bake/probe.odin:211-227`].
   DDGI-Production shortens backface depth by 80% so the probe reads the surface
   as shadowed [10, §4.1]. A backface that is recorded at full distance can make
   the Chebyshev test permissive.
5. **Outside the volume.** `probe_indirect` returns zero outside the grid
   [26, `src/renderer/shaders/probe.glsl:177-181`]. The volume covers x/z in
   [-20, 20] and y in [0, 5]; the arena walls are 5.5 m and the ceiling is above
   that [26, `src/game/arena.odin:8-11`]. Anything above y = 5 or outside x/z
   ±20 gets direct light only. One volume is enough for one closed arena; a room
   transition needs a second volume or a portal.
6. **The static/dynamic seam.** Static boxes sample a 1024^2 lightmap at 4
   texels/m (25 cm per texel); dynamic boxes sample 1 m probes [26,
   `docs/research/lighting-system-review.md`]. A dynamic crate resting on a
   static floor can have a different indirect value from the floor it touches.
   The repository's seam evidence is static-to-static; it does not measure this
   contact [26, `docs/evidence/mixed-lighting.md`].
7. **The gamma-2 blend.** At a 50/50 lit/unlit probe pair the result is half the
   linear average; that is a dark bias at exactly the contact/corner regions
   where probe lighting is most visible. It is intentional in DDGI [10, §4.2],
   but its suitability for a static bake is unmeasured.
8. **The octahedral seam.** Clamping instead of wrapping produces a one-texel
   plateau at the seam [26, `src/renderer/shaders/probe.glsl:51-68`]. Minor, but
   a gutter or seam-aware tap would remove it.
9. **SH9, if adopted.** The 1/16 back lobe [6] is a new leak that the current
   octa map does not have. This is the main reason not to switch on memory
   grounds alone.

#### 7.5 What production does for dynamic objects and dynamic lamps

**Dynamic objects.** Every shipped engine in this survey uses a probe volume or
a lightmap-probe set for dynamic receivers: Unity APV or classic Light Probes
[12,13], Unreal Volumetric Lightmap [17], Godot LightmapGI probes [20-22], and
DDGI/RTXGI when the field itself must be dynamic [9,10]. The common elements are
per-pixel sampling, a low-order directional basis (SH) or an octa map, validity
handling (virtual offset, dilation, relocation), and a visibility term (depth
moments, facing weight, bias). A baked field does not change when a dynamic
object moves through it; that requires a dynamic-GI system or a separate AO
term. Harbagsa's dynamic crates receiving but not occluding the field is
therefore normal for a baked system, even if it is visible in a crate-pushing
game.

**Dynamic lamps.** The legacy production split is:

- **Unreal Static:** direct and indirect baked; cannot move [18].
- **Unreal Stationary:** indirect baked, direct dynamic, can change color and
  intensity but not position [18,19].
- **Unreal Movable:** fully dynamic direct and shadows; no baked indirect
  [18,19]. Lumen adds dynamic indirect, but that is a different, dynamic tier
  outside this note's noise-free scope [30].
- **Unity Mixed:** "direct real-time lighting and baked indirect lighting";
  **Realtime:** direct only by default [28]. Enlighten can update the indirect
  at runtime if the project pays for it [29].

Harbagsa's static fixture / dynamic lamp split is the Unreal Stationary/Movable
split. That is a legitimate production pattern, not a hack. The cost is that a
dynamic lamp cannot bounce; the benefit is no per-frame GI and no noise. A
production system that needs a moving lamp to bounce either rebakes, uses a
runtime radiosity system such as Enlighten [29], or accepts a dynamic-GI tier
such as a light-propagation volume. Given the owner's no-noise constraint,
Enlighten is the relevant shipped example; DDGI is the contrast, not the
recommendation.

**Static geometry edits.** Production lightmappers require a lighting build;
harbagsa's keyed artifact with explicit `stale`/`current` states is more honest
than a silent stale bind [26, `docs/adr/0045-mixed-static-baked-indirect.md`].
The research question is the probe field, but this lifecycle is a strength worth
keeping.

#### 7.6 Memory arithmetic and options

| Option | Irradiance B/probe | Depth B/probe | State B/probe | Total B/probe | 8000 probes | Change vs current |
| -- | --: | --: | --: | --: | --: | --: |
| Current: 8x8 RGBA16F + 8x8 RG16F moments | 512 | 256 | 8 | 776 | 6.21 MB | - |
| 8x8 R11G11B10 + 8x8 moments | 256 | 256 | 8 | 520 | 4.16 MB | -33% |
| 4x4 RGBA16F + 8x8 moments | 128 | 256 | 8 | 392 | 3.14 MB | -49% |
| 4x4 R11G11B10 + 8x8 moments | 64 | 256 | 8 | 328 | 2.62 MB | -58% |
| SH9 f16 + 8x8 moments | 54 | 256 | 8 | 318 | 2.54 MB | -59% |
| SH9 f16 + 4x4 moments | 54 | 64 | 8 | 126 | 1.01 MB | -84% |
| 8x8 R11G11B10 + 16x16 moments | 256 | 1024 | 8 | 1288 | 10.30 MB | +66% |

All numbers are arithmetic from the repository constants [26,
`src/bake/bake.odin:23-33`], not measurements. The 16x16 depth option matches
DDGI's depth resolution [9, §3] and is the most direct way to attack thin-wall
leaks without changing the irradiance basis.

For comparison, DDGI's per-probe storage is 8x8 R11G11B10 (256 B) plus 16x16
RG16F (1024 B), 1280 B/probe, before gutters [9, §3]. Harbagsa's current 776
B/probe is smaller overall, but it spends 2x DDGI's irradiance bytes and 1/4 of
its depth bytes. The allocation is backwards if leak handling is the priority.

### 8. Bottom line for harbagsa

- **Keep the 1 m grid.** It is at the dense end of DDGI's 1-2 m guidance [9,
  §4.1] and the paper's own study says probe count matters more than angular
  resolution [9, §6.1]. Reducing density to save memory would trade the dominant
  quality lever for the secondary one.
- **Change the irradiance format before changing the representation.**
  R11G11B10F halves the irradiance bytes and needs no bake or sampling algorithm
  change. Test neutral grays for the green tint DDGI observed [9, §6.3]. If the
  tint is unacceptable, RGB9E5 is the alternative, with the shared-exponent
  caveat [25].
- **If memory is still the problem, test 4x4 octa and SH9.** 4x4 R11G11B10 is
  about the same total memory as SH9 but keeps the local octa support and the
  existing decode. SH9 is smaller and more standard but introduces the 1/16 back
  lobe [6]; window it and test it on the dark side of a bright emitter.
- **Spend the saved bytes on depth if leaks show.** A 16x16 depth map is the
  configuration DDGI uses [9, §3] and directly addresses the thin-wall case. A
  4x4 depth map is the cheap option if memory is tight; test it before trusting
  it.
- **Decide what the gamma-2 blend is for.** DDGI uses it for perceptual temporal
  convergence and firefly reduction [10, §4.2]. A static bake has neither
  problem in the same form. If the darkening at lit/unlit boundaries is visible,
  decode each tap to linear before weighting; if the DDGI look is wanted, keep
  it and document it.
- **Add the missing evidence.** The repository has no probe-noise measurement,
  no thin-wall capture, and no static/dynamic contact measurement [26,
  `docs/research/lighting-system-review.md`]. These are cheap captures compared
  with a representation rewrite, and they decide whether SH9 or a depth-map
  change is worth doing.
- **Do not add DDGI, path tracing, or a temporal denoiser.** The owner excluded
  them. The existing offline bake plus hard ray-query shadows is the baseline;
  the research question is how to make the probe field better within that
  baseline.

## Conflicts

- **"Tabellion & Lamorlette 2004, An Irradiance Atlas..." is a misattribution.**
  The paper with that title is Christensen and Batali 2004 [2]. Tabellion and
  Lamorlette 2004 is "An Approximate Global Illumination System for Computer
  Generated Films" [3], an irradiance gradient cache. The brief's citation
  combines the title of one paper with the authors of another.
- **"Irradiance atlas" means two different things.** Christensen's atlas is a
  collection of sparse 3D brick maps (8^3 voxels, adaptive octree, 3D MIP)
  [2]. Harbagsa's lightmap atlas is a 2D chart atlas (one chart per box face,
  1024^2 RGBA16F). They are not the same data structure and should not be
  compared as if they were.
- **Gamma-5 is not merely "legacy."** The repository comment calls it legacy
  [26, `src/bake/probe.odin:186`], but DDGI-Production uses the same
  `irradianceGamma = 5.0` and the same `pow(encoded, 2.5)` decode to leave a
  gamma-2 curve [10, §4.2, Figure 4]. The internal review calls the resulting
  sqrt-space blend a bug [26, `docs/research/lighting-system-review.md`]. The
  arithmetic is right, but the primary source shows the order is intentional.
  The disagreement is about whether the perceptual choice is right for a static
  bake, not about what the code does.
- **"8x8 octa is overkill" is true only against the diffuse signal.** DDGI uses
  8x8 [9]; the claim is not "8x8 is too much for any probe system." It is "8x8
  is more angular resolution than a cosine-convolved diffuse field needs, and
  its RGBA16F format spends more bytes than it needs." The depth map is the
  under-resolved part relative to DDGI.
- **"SH9 is better" is not unconditional.** SH9 is better on memory, linearity,
  and engine precedent, but its 9-coefficient clamped-cosine approximation has
  a 1/16 spurious back lobe [6]. The octa map's local support is a real
  advantage in a hard-edged scene with bright emitters. The internal review's
  recommendation to switch to SH9 is a reasonable default, but it is not proven
  for this scene without an A/B capture.
- **"99% of the energy is in 9 SH coefficients" was not found in Ramamoorthi
  and Hanrahan 2001.** The paper reports average error under 1%, maximum under
  5%, and worst-case average under 3% [5, §3.1]. Do not cite the 99% figure
  without a source.
- **Normal bias and Chebyshev moments are not from Greger 1998.** Greger's
  original volume has directional bins and trilinear spatial interpolation; it
  has no normal bias, no depth moments, and no tetrahedral interpolation [1].
  Those are later production additions [9,10,14-16].
- **Probe relocation is not from DDGI 2019.** The 2019 paper uses trilinear
  interpolation plus visibility weights [9, §5.2]. The iterative probe position
  adjustment is in the 2021 production paper [10, §5]. Do not attribute it to
  the 2019 paper.
- **DDGI does not mathematically require temporal accumulation.** The 2019
  reference uses 64 rays/probe/frame plus hysteresis [9, §4.2, §4.4]. With fixed
  rays and a fixed scene, the update is deterministic; the temporal filter is a
  budget choice, not a requirement of ray tracing.
- **"Third order" can mean 9 coefficients, not 27.** Unity, Unreal, and Sloan
  use "third order" / "L2" for the 3-band, 9-coefficient basis [6,12,17]. Oat's
  slides use "3rd order SH" for 9 coefficients per channel, 27 floats for RGB
  [4]. Harbagsa's 8x8 map has 64 texels, not 27 coefficients; do not compare the
  numbers as if they were the same unit.

## Not found

- No public A/B comparison of SH9 versus an 8x8 octahedral irradiance map at
  1 m spacing and 1024 rays/probe in a hard-edged box arena. The conclusion in
  §7.3 is an inference from the SH error bounds [5], Sloan's back-lobe analysis
  [6], and DDGI's resolution study [9], not a measured result for harbagsa.
- No measurement of probe noise in harbagsa. The repository's noise evidence is
  lightmap-only; the probe term is below the 0.006 ms perf noise floor [26,
  `docs/evidence/mixed-lighting.md`, `docs/research/lighting-system-review.md`].
- No thin-wall leak measurement in harbagsa. The sealed-cell test uses a thick
  4x4 m cell; it does not test a wall thinner than the 1 m probe spacing [26,
  `docs/evidence/mixed-lighting.md`].
- No static/dynamic contact measurement: a dynamic crate on a static floor,
  comparing the crate's probe term with the floor's 25 cm lightmap term [26,
  `docs/research/lighting-system-review.md`].
- No official Unity APV per-probe coefficient count or byte size in the APV
  pages cited here. Those pages document the brick structure, sampling, and
  validity controls [13-16]; the 32 B/probe compressed-L2 figure comes from a
  Unity staff forum post, which is a secondary source and is not used as a
  primary claim here.
- No "99% energy" statement in Ramamoorthi and Hanrahan 2001 [5]. The paper's
  claims are the 1%/5%/3% error bounds.
- No exact Greger directional-bin counts. The PDF's superscripts are lost in
  text extraction; Figure 4.8 shows several directional resolutions, but the
  extracted text is ambiguous, so this note avoids a specific count [1].
- No Valve Source 2 irradiance-volume documentation. The Valve developer wiki
  returned an anti-bot challenge during this research; it is not used.
- No public measurement of 4x4 versus 8x8 octa at harbagsa's bake ray count.
  DDGI's Figure 9 is the closest evidence, and it is a different scene and a
  different renderer [9, §6.1].
- No head-to-head tetrahedral versus trilinear quality study found. Unity and
  Godot use tetrahedral for classic/lightmap probes [12,22]; DDGI and Unity APV
  use eight-probe interpolation [9,13]. The choice is practice-driven, not
  settled by a single benchmark in these sources.

## References

Peer-reviewed papers are [1]-[3], [5], [7]-[9], and [11]. Industry talks and
technical papers are [4] and [10]. Engine documentation is [12]-[25] and
[27]-[30]. Repository sources are [26]. Web sources were accessed 2026-11-10.

1. Gene Greger, Peter Shirley, Philip M. Hubbard, Donald P. Greenberg. "The
   Irradiance Volume." *IEEE Computer Graphics and Applications* 18(2):32-43,
   1998. DOI 10.1109/38.656788.
   https://dl.acm.org/doi/10.1109/38.656788
   Detailed implementation: Greger's thesis,
   https://www.gene.greger-weltin.org/professional/publications/thesis.pdf
2. Per H. Christensen, Dana Batali. "An Irradiance Atlas for Global Illumination
   in Complex Production Scenes." *Rendering Techniques 2004* (Eurographics
   Symposium on Rendering), pp. 133-141, 2004.
   https://research.pixar.com/docs/2004.Others.CB.pdf
3. Eric Tabellion, Arnauld Lamorlette. "An Approximate Global Illumination System
   for Computer Generated Films." *ACM SIGGRAPH 2004 Papers*, pp. 469-476, 2004.
   DOI 10.1145/1186562.1015748.
   https://www.tabellion.org/et/paper/siggraph_2004_gi_for_films.pdf
4. Chris Oat. "Irradiance Volumes for Games." GDC 2005, ATI Research. Slides
   1-54. https://chrisoat.com/papers/Oat_GDC2005_IrradianceVolumesForGames.pdf
   (Industry talk; not peer-reviewed.)
5. Ravi Ramamoorthi, Pat Hanrahan. "An Efficient Representation for Irradiance
   Environment Maps." *SIGGRAPH 2001*, pp. 497-500. DOI 10.1145/383259.383317.
   https://cseweb.ucsd.edu/~ravir/papers/envmap/envmap.pdf
6. Peter-Pike Sloan. "Stupid Spherical Harmonics (SH) Tricks." GDC 2008
   companion paper. https://www.ppsloan.org/publications/StupidSH36.pdf
7. Jiaping Wang, Peiran Ren, Minmin Gong, John Snyder, Baining Guo.
   "All-Frequency Rendering of Dynamic, Spatially-Varying Reflectance." *ACM
   Transactions on Graphics* 28(5), Article 133, 2009. DOI
   10.1145/1618452.1618479.
   https://cseweb.ucsd.edu/~ravir/291/2015/papers/a133-wang.pdf
8. Morgan McGuire, Mike Mara, Derek Nowrouzezahrai, David Luebke. "Real-Time
   Global Illumination using Precomputed Light Field Probes." *ACM SIGGRAPH
   Symposium on Interactive 3D Graphics and Games (I3D)*, pp. 1-11, 2017. DOI
   10.1145/3023368.3023378.
   https://casual-effects.com/research/McGuire2017LightField/McGuire2017LightField.pdf
9. Zander Majercik, Jean-Philippe Guertin, Derek Nowrouzezahrai, Morgan McGuire.
   "Dynamic Diffuse Global Illumination with Ray-Traced Irradiance Fields."
   *Journal of Computer Graphics Techniques* 8(2):1-30, 2019.
   https://jcgt.org/published/0008/02/01/
10. Zander Majercik, Adam Marrs, Josef Spjut, Morgan McGuire. "Scaling
    Probe-Based Real-Time Dynamic Global Illumination for Production."
    arXiv:2009.10796, 2021. https://arxiv.org/abs/2009.10796
    (Industry technical paper; not peer-reviewed.)
11. Zina H. Cigolle, Sam Donow, Daniel Evangelakos, Michael Mara, Morgan McGuire,
    Quirin Meyer. "A Survey of Efficient Representations for Independent Unit
    Vectors." *Journal of Computer Graphics Techniques* 3(2):1-30, 2014.
    https://jcgt.org/published/0003/02/01/
12. Unity. "Light Probes: Technical information." Unity 6.0 manual.
    https://docs.unity3d.com/6000.0/Documentation/Manual/LightProbes-TechnicalInformation.html
    (L2 SH, 27 floats, tetrahedral interpolation; cites Cupisz, GDC 2012.)
13. Unity. "Introduction to Adaptive Probe Volumes." Unity 6.0 manual.
    https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/concept
    (4x4x4 bricks, 1/3/9/27 m spacings, eight closest probes per pixel.)
14. Unity. "Light Probe validity in Adaptive Probe Volumes in URP." Unity 6.0
    manual.
    https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/fixissues/light-probe-validity
    (Virtual Offset and Dilation.)
15. Unity. "Troubleshooting light leaks in Adaptive Probe Volumes in URP." Unity
    6.0 manual.
    https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/fixissues/troubleshoot-light-leaks
    (Thicker walls, Normal Bias, View Bias, Leak Reduction Mode, rendering layer
    masks, dilation radius, probe density.)
16. Unity. "Adaptive Probe Volumes panel reference." Unity 6.0 manual.
    https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting/probevolumes/lighting-panel-reference
    (Dilation search radius, iterations, squared-distance weighting; Virtual
    Offset settings.)
17. Epic Games. "Volumetric Lightmaps in Unreal Engine." Unreal Engine 5.9
    documentation.
    https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine
    (4x4x4-cell bricks, third-order SH, adaptive density, per-pixel
    interpolation for dynamic objects.)
18. Epic Games. "Light Types and Their Mobility in Unreal Engine." Unreal Engine
    5.9 documentation.
    https://dev.epicgames.com/documentation/en-us/unreal-engine/light-types-and-their-mobility-in-unreal-engine
    (Static, Stationary, Movable definitions.)
19. Epic Games. "Stationary Light Mobility in Unreal Engine." Unreal Engine 5.9
    documentation.
    https://dev.epicgames.com/documentation/en-us/unreal-engine/stationary-light-mobility-in-unreal-engine
    (Indirect baked, direct dynamic; direct shadows in shadow maps.)
20. Godot Engine. "LightmapGI" class reference.
    https://docs.godotengine.org/en/stable/classes/class_lightmapgi.html
    (Dynamic objects via light probes, directional SH option, probe
    subdivision.)
21. Godot Engine. "LightmapProbe" class reference.
    https://docs.godotengine.org/en/stable/classes/class_lightmapprobe.html
    (Manual probes for dynamic object lighting.)
22. Godot Engine source, master branch, accessed 2026-11-10:
    `modules/lightmapper_rd/lightmapper_rd.cpp` (nine SH floats per probe;
    `light_probe_buffer = sizeof(float) * 4 * 9 * probe_positions.size()`),
    `scene/3d/lightmap_gi.cpp` (`Delaunay3D::tetrahedralize`, tetrahedra and BSP
    in the capture data),
    `doc/classes/LightmapGI.xml`.
    https://github.com/godotengine/godot/blob/master/modules/lightmapper_rd/lightmapper_rd.cpp
    https://github.com/godotengine/godot/blob/master/scene/3d/lightmap_gi.cpp
23. Khronos Group. "Vulkan Specification, Formats."
    https://docs.vulkan.org/spec/latest/chapters/formats.html
    (`VK_FORMAT_B10G11R11_UFLOAT_PACK32`: 10-bit B, 11-bit G, 11-bit R;
    `VK_FORMAT_E5B9G9R9_UFLOAT_PACK32`: 5-bit shared exponent, 9-bit mantissa
    per channel.)
24. Microsoft. "DXGI_FORMAT (dxgiformat.h)." Microsoft Learn.
    https://learn.microsoft.com/en-us/windows/win32/api/dxgiformat/ne-dxgiformat-dxgi_format
    (R11G11B10: 5-bit biased exponent per channel, 6/6/5-bit mantissa, no sign;
    R9G9B9E5: shared 5-bit exponent, 9-bit mantissa per channel, no sign.)
25. Unity. "Lightmaps: Technical information." Unity 6.0 manual.
    https://docs.unity3d.com/6000.0/Documentation/Manual/Lightmaps-TechnicalInformation.html
    (RGB9E5 range [0, 65408]; f16 lightmap range 0-65504.)
26. Harbagsa repository, current worktree, 2026-11-10:
    `src/bake/bake.odin`, `src/bake/probe.odin`,
    `src/bake/probe_dilate.odin`, `src/renderer/shaders/probe.glsl`,
    `src/renderer/shaders/terms.glsl`,
    `docs/adr/0042-single-volume-ddgi.md`,
    `docs/adr/0045-mixed-static-baked-indirect.md`,
    `docs/evidence/mixed-lighting.md`,
    `docs/research/lighting-system-review.md`.
27. Unity. "SphericalHarmonicsL2" scripting API.
    https://docs.unity3d.com/ScriptReference/Rendering.SphericalHarmonicsL2.html
    (L2 SH, 9 coefficients per color channel; used for Light Probes and
    environment lighting.)
28. Unity. "Light Modes" and "Light Mode: Mixed." Unity 6.0 manual.
    https://docs.unity3d.com/6000.0/Documentation/Manual/LightModes-introduction.html
    https://docs.unity3d.com/6000.0/Documentation/Manual/LightMode-Mixed.html
    (Realtime lights contribute direct lighting by default; Mixed lights combine
    direct real-time and baked indirect lighting.)
29. Unity. "Realtime Global Illumination using Enlighten." Unity 6.0 manual.
    https://docs.unity3d.com/6000.0/Documentation/Manual/realtime-gi-using-enlighten.html
    (Realtime lights contribute indirect lighting when Enlighten Realtime GI is
    enabled; the update is split across several frames.)
30. Epic Games. "Movable Light Mobility in Unreal Engine." Unreal Engine 5.9
    documentation.
    https://dev.epicgames.com/documentation/en-us/unreal-engine/movable-light-mobility-in-unreal-engine
    (Movable lights support dynamic indirect lighting with Lumen.)
