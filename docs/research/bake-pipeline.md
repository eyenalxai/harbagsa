# Deterministic bake tool and runtime data path

Status: research for #374. No renderer code changes. This note assumes the mixed-lighting model from `docs/research/mixed-lighting.md`, the lightmap atlas from `docs/research/lightmap-boxes.md`, and the baked probe layer from `docs/research/baked-probes.md`.

## Bottom line

Use a **CPU box-only ray caster** in a standalone Odin tool, write one versioned raw binary, and embed it at build time:

- `make bake` runs `cmd/harbagsa-bake`, which imports the same `src:game` arena/props/starting-lamp data and a pure `src:bake` package. It writes `build/bake/arena.hbake` atomically.
- `make build` and `make check` depend on that artifact. `src/renderer/bake_data.odin` embeds it with `#load("../../build/bake/arena.hbake")`; there is no runtime file open, so there is no hidden failed load. A missing artifact is a compile error.
- The bake is one bounce, indirect only, from static fixtures and static emissive boxes. Dynamic lamps, dynamic crates, the spider, and the camera never enter the bake. Direct light and hard shadows stay in the frame path (`src/renderer/shaders/box.frag:96-154`); the bake never writes them.
- CPU is chosen for determinism, headless operation, build-time cost, and implementation size. The arena is 52 static boxes today (6 shell + 46 props, `src/game/arena.odin:16`, `arena_props.odin:87`), so an analytic OBB caster with a small BVH is enough. GPU ray tracing is not worth a second device path.
- Recommended quality: **1024 x 1024** RGBA16F atlas at 4 texels/m, **1 m** probe grid, **128 rays per lightmap texel**, **1024 rays per probe**. Estimated artifact: about 8.4 MB atlas + 6.2 MB probes = **14.6 MB**, embedded.
- Static edits after startup are a **runtime rebake** of the same pure `src:bake` package, not a second baker. The old bake stays visible with a `stale`/`failed` status until the new one is published; never silently substitute black, a fill light, or an old bake presented as current.

## CPU ray tracing versus GPU compute

| Criterion | CPU box caster | GPU compute / ray query |
| --- | --- | --- |
| Accuracy for this scene | Exact analytic OBB intersection; same box model as the renderer | Triangle ray query against the cube BLAS; watertightness is a "should", not a "must" ([Vulkan ray traversal](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#ray-traversal-watertight)) |
| Speed | Seconds to a minute for the arena, depending on samples and threads | Sub-second to seconds; much faster on paper |
| Determinism | Same binary and CPU can reproduce byte-for-byte with fixed loops, fixed seeds, and f64 accumulators | Shader floating point defaults allow contraction, reassociation, reciprocal, and transform; without explicit `NoContraction`/`SignedZeroInfNanPreserve`, results are not specified to be bit-stable ([Vulkan SPIR-V precision](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#spirvenv-precision-operation)); ray candidate order is not guaranteed ([Vulkan ray traversal](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#ray-traversal-watertight)) |
| Device requirement | None; runs in `make`, in CI, and in a headless harness with `--no-render` | Needs a Vulkan 1.3 device with ray query and a static TLAS; `make build` would need a GPU |
| Implementation cost | One package, one BVH, one OBB test, one atlas packer | Static TLAS, descriptor set, compute pipelines, storage image or readback, device lifetime, queue synchronization, fallback |
| Denoising | More samples or a simple spatial filter in the baker | Unreal GPU Lightmass relies on Intel Open Image Denoise; Unity's GPU lightmapper needs up to four times more indirect samples than the CPU branched path tracer ([GPU Lightmass](https://dev.epicgames.com/documentation/en-us/unreal-engine/gpu-lightmass-global-illumination-in-unreal-engine), [Unity GPU](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/gpuprogressive-lightmapper)) |
| Build integration | Natural fit for `make bake`; no device, no window | Requires a device at bake time; a checked-in artifact or a startup bake becomes tempting, both worse |
| Reuse of existing renderer | Shares geometry and lighting formulas, not Vulkan state | Could reuse the BLAS, but needs a separate static TLAS and a bake descriptor set |
| Verdict | **Chosen** | Rejected for the first version |

The GPU path is not wrong in principle; it is a poor fit for a 40 m room with 52 boxes and a build-time artifact. Unreal's GPU Lightmass is Windows/DX12/DXR and still beta, and its multi-GPU mode explicitly does not support the Volumetric Lightmap and warns that the irradiance cache differs between GPUs ([GPU Lightmass](https://dev.epicgames.com/documentation/en-us/unreal-engine/gpu-lightmass-global-illumination-in-unreal-engine)). That is exactly the reproducibility problem this project does not need.

## Traversal: box-only caster, not the frame TLAS

The bake must see **static geometry only**, so the frame TLAS is the wrong structure: it is rebuilt from every box each frame, includes dynamic crates and the spider, and is a GPU object (`src/renderer/acceleration.odin:120-160`). A bake that reused it would either include moving crates or need a second static TLAS.

The recommended structure is:

- A flat list of static `geometry.Box` values: arena boxes first, then static placed objects sorted by stable object id.
- A deterministic BVH over the boxes' world-space AABBs. Build with a median split on the largest axis; break ties by stable index. A 52-box arena is already fast; the BVH keeps a debug scene with hundreds of static props usable.
- An analytic OBB ray test: transform the ray into box local space with the inverse rotation, divide by `2 * half_extents`, then slab-test. This is exact for boxes, has no triangle-edge watertightness question, and is deterministic.
- A miss returns zero. A hit returns the box index, `t`, the face normal, and the box color/emissive. The renderer's cube faces already have unique normals (`src/renderer/mesh.odin:6-39`); the box hit normal is the face normal, not a smoothed vertex normal.

Alternatives rejected: Box3D world ray casts (dynamic bodies and physics broadphase in the bake, and a dependency on simulation state); the frame TLAS (dynamic, per-frame, GPU); a GPU static TLAS (a second acceleration structure and device dependency for no quality gain at this scale); brute force over every static placed object (still fine at 52 boxes, but a BVH is cheap and keeps the editor usable).

## Sample budget

Monte Carlo error falls as `O(1/sqrt(N))` ([PBRT](https://pbr-book.org/3ed-2018/Monte_Carlo_Integration/The_Monte_Carlo_Estimator)), so sample counts should be chosen from the visible noise floor, not from a round number:

| Output | Baseline | Quality option | Draft / preview | Why |
| --- | --- | --- | --- | --- |
| Lightmap texel | 128 rays | 256-512 rays | 32 rays | Indirect is low frequency; 128 gives about 8.8% relative error before bilinear and chart averaging; the scene has three lights and one bounce |
| Lightmap edge texel | 2 x 2 supersample | 4 x 4 | 1 | Unity's default anti-aliasing is 4 samples (2 x 2) for lightmaps ([Lightmap Parameters](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-reference/class-lightmap-parameters)); only chart edges need it here |
| Probe | 1024 rays | 2048 rays | 256-512 rays | 8 x 8 octa means 16 rays per texel at 1024; 4 x 4 at 512 is the same per-texel budget |
| Bounces | 1 | 1 | 1 | One diffuse bounce is the look and the current field; more bounces add cost and a long tail |
| Static lights | 3 fixtures | 3+ | 3 | Every hit evaluates the bake light list; range-cull per hit; do not inherit the 96-light frame budget |

The current probe set is a fixed spherical Fibonacci sequence with the same directions for every probe (`src/renderer/shaders/probe.glsl:44-53`). For a bake, rotate the set per output with a hash-derived offset (Cranley-Patterson) so probes do not share structured banding, and keep the number of samples fixed. The lightmap texel loop should use a low-discrepancy sequence (Hammersley/Sobol) with a per-texel hash rotation; per-output seeds avoid a global random stream and make parallel work order-independent.

## File format

Use a single raw little-endian file with a versioned header and a section table. KTX2 is a good container for GPU textures, but this artifact is a texture plus probe buffers plus face rects plus a bake key; adding a KTX2 parser or `libktx` would buy mips, layers, and supercompression that the first version does not use ([KTX2 spec](https://github.khronos.org/KTX-Specification/ktxspec.v2.html)). Keep the format field so a later version can switch the atlas section to KTX2 or BC6H.

```text
Bake_Header {
  magic: [4]u8 = "HBAK"
  format_version: u16 = 1
  header_bytes: u16
  tool_version: u32
  flags: u32
  bake_key: u64
  artifact_hash: u64       // FNV-1a over the payload
  atlas_width: u32
  atlas_height: u32
  atlas_format: u32        // 1 = RGBA16F
  probe_min: [3]f32
  probe_spacing: f32
  probe_counts: [3]u32
  probe_texels: u32        // 64 for 8 x 8
  face_count: u32
  section_count: u32
}
Bake_Section { kind: u32; offset: u64; size: u64; stride: u32; count: u32 }
Bake_Face { uv_rect: [4]f32; slot: u32; face: u32 }
Bake_Stats { bake_ms: u32; lightmap_rays: u64; probe_rays: u64; atlas_texels: u32; probe_count: u32 }
```

- Sections: lightmap atlas bytes, face rects, probe irradiance, probe moments, probe valid/offset, stats, and an optional preview image. Section offsets are 16-byte aligned; payloads are tightly packed; no struct padding is written.
- The atlas is linear `VK_FORMAT_R16G16B16A16_SFLOAT`, one mip, one layer. The format is mandatory in the Vulkan 16-bit table and supports sampled linear filtering ([Vulkan formats](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#formats-mandatory-features-16bit)); still check `SAMPLED_IMAGE_FILTER_LINEAR_BIT` at device creation rather than assume a feature.
- Probe texels are RGBA16F irradiance (gamma 5) and RG16F moments; the layout matches `docs/research/baked-probes.md`.
- `bake_key` is the canonical hash of the bake inputs and quality. `artifact_hash` is the hash of the payload, not of the header. Both are printed by the tool and exposed in the renderer state.
- The artifact is one file. Do not split the lightmap and probes into two files with two versions; they are published together and must not disagree.

### Atlas dimensions

The arena's shell has about 8,700 m² of box surface including buried faces, and the 46 props add roughly 1,000 m². At 4 texels/m that is about 155k texels before padding; a 1024² atlas has 1.05M texels, about 6.7x headroom. At 8 texels/m it is about 620k texels, and 1024² is tight; use 2048² if 8/m is chosen. Recommendation: **1024² at 4 texels/m**, with 2048² as the measured upgrade. The atlas is 8.4 MB at 1024² and 33.6 MB at 2048²; the smaller size matters because the artifact is embedded in both `bin/harbagsa` and `bin/harbagsa-agent`.

## Build and runtime data flow

```text
make bake
  cmd/harbagsa-bake
    src:game arena_static_boxes() + static fixture list
    src:bake Bake_Input -> BVH -> lightmap + probes -> Bake_Output
    write build/bake/arena.hbake.tmp -> rename

make build
  bin/harbagsa, bin/harbagsa-agent
    src/renderer/bake_data.odin
      BAKE_BYTES :: #load("../../build/bake/arena.hbake")
    renderer init
      parse header -> validate magic/version/size/key/hash
      upload atlas image + probe buffers
      bake_version = header.bake_key; bake_status = current
    frame
      static box: direct + atlas indirect
      dynamic box: direct + probe indirect
      no probe pass, no gi switch
```

- **Build target:** `build/bake/arena.hbake` depends on the arena/props/prefabs/lights/geometry sources and `src:bake`; Make only reruns the bake when an input is newer. `make build` and `make check` depend on it, exactly as they already depend on `shaders` (`Makefile:27-36, 152-174`). `make clean` removes `build/bake`.
- **Standalone tool:** `cmd/harbagsa-bake` is a second executable like `cmd/harbagsa-agent`; it imports `src:game` for the arena and `src:bake` for the math. It links the vendored Box3D because `src:game` does, even though the baker itself does not need physics.
- **Pure package boundary:** `src:bake` must not import `src:renderer` or `src:game`. It takes a `Bake_Input` value and returns a `Bake_Output`; the tool and the runtime rebake are two adapters. This prevents the renderer from depending on the game and prevents the tool from depending on Vulkan.
- **Embedding:** the `#load` lives in `src/renderer/bake_data.odin`, not in `src:bake`. If `src:bake` embedded the artifact, the tool that builds `src:bake` would need the artifact before it could run. `#load` is compile-time file embedding ([Odin directives](https://odin-lang.org/docs/directives/#loadstring-path-or-loadstring-path-type)); the repo already uses it for shaders (`src/renderer/probe.odin:68-69`). Keep the path next to the source file that owns the embed.
- **No `or_else`:** a missing bake is a compile error, not a runtime fallback. The renderer must never load a black atlas or skip indirect because the artifact failed to parse.
- **Startup validation:** parse the header, check `magic`, `format_version`, section bounds, section sizes, and `bake_key` against the current compile-time static input. A mismatch is an init error (`.Create_Bake`), not a warning and not a silent old bake. The compile-time key is cheap to recompute from `arena_static_boxes()` and the static fixture list.
- **Runtime rebake:** when the editor adds, moves, removes, or recolors a static box or static fixture, recompute `bake_key`. If it differs, set `bake_status = stale`, keep the old atlas/probes bound, and run `src:bake` on a worker. On success, wait for the old frame in flight or retire the old image after `MAX_FRAMES_IN_FLIGHT`, swap descriptors, bump `bake_version`, reset TAA history, and clear stale. On failure, keep the old bake and set `bake_status = failed` with the error; never claim current.
- **Static placed objects:** the build-time artifact only contains the compile-time arena. A runtime-placed static object is not in it; the runtime key changes and triggers a rebake. Until the rebake publishes, the new object has no lightmap tile and must use the visible stale/failed state, not black.
- **Runtime sampling:** static boxes read the atlas; dynamic boxes read probes. A static box with no current tile falls back to probe indirect and reports `bake_missing`; it never silently renders black. Dynamic boxes always read probes.
- **Harness:** add a `bake` command (`wait`, `force`, `status`) and a `state.bake` block with `status`, `key`, `version`, `ms`, `atlas`, `probes`, `stale`, `error`. A capture taken while stale is allowed but carries the status; the harness compare should include it. This is evidence, not a gate.

## Determinism and reproducibility

Define three different things so they are not confused:

- **Input identity:** `bake_key`, computed from canonical static boxes, static fixtures, quality, and `tool_version`. Two runs with the same key are the same bake request.
- **Artifact identity:** `artifact_hash`, computed from the payload bytes. It answers "is this the same output on this toolchain?"
- **Visual identity:** harness captures and `compare --delta`; the render digest must include `bake_version`/`bake_key` so two different bakes cannot compare as the same image.

Rules:

- **Canonical order:** arena boxes in array order, then static placed objects by stable id, then static fixtures by object id. Never hash a hash map iteration or a pointer address. Hash fields explicitly; never hash struct padding.
- **Canonical floats:** normalize `-0.0` to `0.0`; reject NaN/Inf in bake inputs; write floats as their IEEE-754 bit pattern (the repo already hashes `f32` with `transmute(u32)` in `src/digest/digest.odin:39-41`).
- **Per-output seed:** `seed = hash(bake_key, kind, index)` using a fixed 64-bit mix (PCG or splitmix64). Each texel/probe owns its stream; there is no global RNG and no order dependency ([PCG](https://www.pcg-random.org/pdf/hmc-cs-2014-0905.pdf)).
- **Sample sequence:** a fixed low-discrepancy set per output, rotated by a hash offset. Do not vary the count with frame time or thread count. Hash-based Owen scrambling is the quality option if banding appears ([Burley](https://jcgt.org/published/0009/04/01/paper.pdf)).
- **Parallelism:** one thread writes one texel or one probe; the BVH and box list are read-only; no atomics and no reduction across threads. The result is independent of thread scheduling and thread count.
- **Floating point:** use `f64` accumulators for radiance and moments, store `f32`/`f16` at the end; keep a fixed sample order; avoid `sin`/`cos` in the inner loop by precomputing the direction table once per bake. Do not enable fast-math; do not rely on FMA contraction for reproducibility.
- **Cross-machine rule:** byte identity is promised only for the same binary, CPU, and sample counts. Across machines, `bake_key` must match and `artifact_hash` may differ in the last bits. Compare with a per-channel max/mean tolerance, not with a byte-equality gate.
- **Bake compare:** a `hbake compare A B` subcommand prints key match, hash match, per-channel max/mean/percentile difference for the atlas and probes, and the stats block. The visual check is the harness `compare` on the same scenario; never commit images.

## Rebake rules

A full rebake is required when any of these changes:

- a static box is added, removed, moved, rotated, scaled, recolored, changes emissive, or flips static/dynamic;
- a static fixture is added, removed, moved, recolored, changes intensity/range, or changes its emissive body;
- a lamp flips between static fixture and dynamic lamp;
- atlas size, texel density, probe spacing, probe texel size, ray counts, bounces, seed policy, or `tool_version` changes.

No rebake is required when a dynamic crate moves, a dynamic lamp moves or changes color/intensity/range, the spider moves, the camera moves, TAA changes, or the HUD changes. That is the main cost win of the static/dynamic split.

Do not do incremental per-tile invalidation in the first version. A moved fixture changes its bounce across the whole room and changes the fixture body's occlusion; a visibility map would be more machinery than a full small-scene rebake. Rebuild the whole atlas and the whole probe field, then publish atomically.

## Memory and bake-time estimates

These are estimates from the arena size and the sample counts, not measurements. The ticket explicitly prefers design over a prototype.

| Item | 1024² atlas, 1 m probes | 2048² atlas, 1 m probes |
| --- | --- | --- |
| Atlas RGBA16F | 8.4 MB | 33.6 MB |
| Probes 8 x 8 + moments | 6.2 MB | 6.2 MB |
| Face rects + stats + header | < 0.1 MB | < 0.1 MB |
| Embedded artifact | **~14.6 MB** | **~39.8 MB** |
| Lightmap texels at 4/m | ~155k | ~155k |
| Lightmap rays at 128 | ~19.8M | ~19.8M |
| Probe rays at 1024 | ~8.2M | ~8.2M |
| Shadow candidates at 3 lights | up to ~84M | up to ~84M |

At 8 texels/m the atlas texel count is about 620k and the lightmap rays are about 79M; that is the case for 2048². With a BVH, 52 boxes, and 8 threads, the whole bake should be seconds to tens of seconds on a desktop CPU; single-threaded is slower. A runtime rebake of the full 1 m field is a visible hitch, so a draft (512 rays/probe, 32 rays/texel) for interactive edits and a final bake on commit is the recommended policy. The bake must report its own `bake_ms`, `lightmap_rays`, and `probe_rays`; do not hide it inside the frame interval.

Frame cost moves in the other direction: the current probe pass and gather cost about 0.76 ms and 0.58 ms at 96 lights and 1080p (`docs/adr/0042-single-volume-ddgi.md`). Removing both and adding one atlas fetch for static boxes or four probe fetches for dynamic boxes should be cheaper; the direct shadow term remains the budget. Measure with `scenarios/perf.json` and `scenarios/perf-arena.json` and report the pass means, not a single frame.

## Known artifacts

| Artifact | Cause | Control |
| --- | --- | --- |
| Stale bake after a source edit | A static source changed without a new `make bake` | Make dependency on every static source; startup `bake_key` check; `stale` in state |
| Missing bake | A clean build without the artifact | `#load` compile error; no `or_else`; no black fallback |
| Atlas seam or dilation ring | Wrong padding, UV rect, or dilation | #372's center-to-center rects, 4-texel gutter, deterministic packer |
| Probe/lightmap mismatch at a crate contact | Two representations of the same bounce | Same bake, same source list, same `indirect_scale`; normal bias; capture the contact |
| Noise or splotches | Too few rays for the light/geometry contrast | 128/1024 baseline; raise counts; only then a simple filter |
| Baker/renderer divergence | A different falloff, lamp mask, or shadow bias | Share the point-light and box helpers; compare the same scenario |
| Oversized artifact | 2048² or 8 texels/m chosen | 1024²/4 texels/m default; measure before adopting the larger budget |

## Risks

| Risk | Consequence | Control |
| --- | --- | --- |
| CPU bake is slower than expected on a low-end machine | Build or edit latency | BVH; threads; draft/final counts; measure `bake_ms` and publish the number |
| OBB caster diverges from the renderer | Baked light does not match real-time direct/shadows | Share the point-light falloff, shadow bias, lamp mask, and box transform helpers; compare captures of the same scenario |
| Static/dynamic classification drifts | A crate leaks into the bake or a static object misses it | One `Bake_Input` builder used by the tool and the runtime; fail if an object has no stable key |
| Static lamps are still forced dynamic | The bake has no static fixture list | #371/#377 must land the lamp kind first; the baker must not guess from `Light_Settings.active` |
| Floating-point drift across machines | Artifact hash differs | Key-based identity; tolerance compare; fixed loops and f64 accumulators |
| Embedded artifact size | Binary grows by about 15-40 MB | 1024² and 1 m default; measure 2048²/8 texels/m before adopting; compression later |
| `make check` now needs a bake | Slow first check; a new bootstrap dependency | Make dependencies cover the bake inputs; the artifact is generated once and reused until an input changes |
| Missing or stale artifact | Black room or old lighting presented as current | `#load` compile error; startup key check; visible `stale`/`failed`; no silent fallback |
| Atlas packing overflows | A static face has no tile | Deterministic shelf packer; grow the atlas or fail the bake loudly; never wrap UVs |
| No denoiser | Visible noise if samples are too low | 128/1024 baseline; raise counts; simple spatial filter in the baker only if captures show noise |
| Runtime rebake hitch | Editor stall while dragging a static fixture | Draft bake; debounce edits; async worker; keep the old bake visible |
| `f16` moments lose precision | Depth test misfires at 40 m | Start with RG16F; if captures show leaks, store RG32F in a format version bump |
| KTX2/compression added later | Format incompatibility | Versioned header and `atlas_format`; keep the raw path as the baseline |
| Headless harness has no Vulkan | A GPU bake cannot run in `--no-render` | CPU baker has no device dependency; this is a reason to choose it |

## Rejected alternatives

| Alternative | Why rejected |
| --- | --- |
| GPU compute bake | Device dependency at build time, non-bit-stable shader math and ray order, denoiser/VRAM machinery, and no quality gain at 52 boxes. |
| External engine (Unity/Unreal) bake | Adds a second engine, asset pipeline, and licensing; the project is a small Odin/Vulkan renderer with one box mesh. |
| Startup bake | Moves a multi-second cost into every run and every harness capture; needs a device or a CPU stall; stale/failed states become startup failures. |
| Checked-in bake artifact | Binary blob in git, stale after every geometry edit, merge conflicts, and no reviewable diff. Generate it in `build/`. |
| KTX2 now | A container and loader for one texture with no mips and no compression; the artifact also carries probes and face rects. Keep the format field for later. |
| Per-frame bake | Guaranteed hitch and the opposite of a static bake. |
| Incremental per-tile rebake | A fixture change reaches the whole room and changes the fixture body's occlusion; more machinery than a full small-scene rebake. |
| Denoiser dependency | OIDN and OptiX add a third-party binary and platform constraints; raise samples first for this scene. |
| Multiple bounces | One bounce is the target look and the current field; more bounces add cost and a long settling tail. |
| Path tracing the frame | Dynamic GI, out of scope. |
| Bake What You See / view-dependent bake | The arena is small and the camera moves; a view-dependent bake would leave holes. |

## Open decisions for the owner

1. **CPU versus GPU.** Recommendation: CPU box caster; revisit GPU only if the bake budget is missed with a BVH and threads.
2. **Build-time versus startup versus runtime.** Recommendation: build-time base artifact plus runtime rebake for static edits; no startup bake.
3. **Atlas size.** Recommendation: 1024² at 4 texels/m; 2048² only if 8/m or more static props are chosen. The sibling quality note budgets 32 MiB for a 2048² atlas; this note's 1024² default is 8.4 MB. Pick one before #378 freezes the budget.
4. **Probe spacing.** Recommendation: 1 m, 40 x 5 x 40; 2 m is the fallback. The quality note assumes 1200 probes; if the probe cap is 4 MiB, use 2 m or 1 m/4 x 4.
5. **Sample counts.** Recommendation: 128/texel and 1024/probe; 256/2048 is the quality option; 32/512 is the draft.
6. **Raw versus KTX2.** Recommendation: raw `.hbake` first; KTX2 only for an exported atlas preview or a later compressed path.
7. **Embed versus external file.** Recommendation: embed with `#load`; external files add a hidden load failure and a working-directory dependency.
8. **`make check` and the bake.** Recommendation: `make check` depends on the artifact, like `shaders`; keep the dependency list complete and the artifact cached.
9. **Runtime rebake policy.** Recommendation: async worker, draft quality while editing, final on commit, old bake visible with `stale`; block only at startup if the key mismatches.
10. **Static edit scope.** Recommendation: any static edit invalidates the whole bake; dynamic edits never do.
11. **Compression.** Recommendation: none first; BC6H only after the float path and captures are clean.
12. **Format version.** Recommendation: one version field and one `tool_version`; bump both when the sample or shading math changes.
13. **Bake stats.** Recommendation: include `bake_ms`, ray counts, atlas texels, and probe count in the artifact and in `state.bake`.
14. **Visual-only boxes.** Recommendation: include them as occluders but not as lightmap receivers if they are thin markers; decide with captures of the slide markers.
15. **Debug export.** Recommendation: an optional atlas PNG/float dump and a probe validity dump outside the repo; useful for seams and leaks, never committed.

## Primary sources

- Unity baking: [Progressive CPU/GPU requirements](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/configure/progressive-lightmapper), [GPU lightmapper, 4x samples, tiling](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/gpuprogressive-lightmapper), [lightmapping settings, samples, bounces, filtering](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/direct-and-indirect-lighting/lightmapping/baking-before-runtime/lightmaps-reference), [Lightmap Parameters: AA, backface tolerance, pushoff](https://docs.unity.com/en-us/engine/6000.0/manual/lighting-overview/lighting-reference/class-lightmap-parameters).
- Unreal baking: [CPU Lightmass: bounces, quality, smoothness](https://dev.epicgames.com/documentation/en-us/unreal-engine/cpu-lightmass-global-illumination-in-unreal-engine), [GPU Lightmass: beta, DX12/DXR, denoiser, multi-GPU limits](https://dev.epicgames.com/documentation/en-us/unreal-engine/gpu-lightmass-global-illumination-in-unreal-engine), [Volumetric Lightmaps](https://dev.epicgames.com/documentation/en-us/unreal-engine/volumetric-lightmaps-in-unreal-engine).
- Vulkan: [mandatory 16-bit format support](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#formats-mandatory-features-16bit), [SPIR-V precision and contraction](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#spirvenv-precision-operation), [ray traversal watertightness and ordering](https://registry.khronos.org/vulkan/specs/latest/html/vkspec.html#ray-traversal-watertight).
- KTX2: [Khronos KTX 2.0 specification](https://github.khronos.org/KTX-Specification/ktxspec.v2.html).
- Odin: [`#load` compile-time embedding](https://odin-lang.org/docs/directives/#loadstring-path-or-loadstring-path-type).
- Sampling: [PBRT Monte Carlo error O(sqrt(N))](https://pbr-book.org/3ed-2018/Monte_Carlo_Integration/The_Monte_Carlo_Estimator), [PCG](https://www.pcg-random.org/pdf/hmc-cs-2014-0905.pdf), [hash-based Owen scrambling](https://jcgt.org/published/0009/04/01/paper.pdf).
- Repository: `Makefile`, `src/game/arena.odin`, `src/game/arena_props.odin`, `src/game/prefabs.odin`, `src/game/lights.odin`, `src/renderer/acceleration.odin`, `src/renderer/shaders/box.frag`, `src/renderer/render_digest.odin`, `src/renderer/state.odin`, `src/perf/perf.odin`, `src/harness/`, `docs/agents/harness.md`, `docs/adr/0008-performance-instrumentation.md`, `docs/research/mixed-lighting.md`, `docs/research/lightmap-boxes.md`, `docs/research/baked-probes.md`.
