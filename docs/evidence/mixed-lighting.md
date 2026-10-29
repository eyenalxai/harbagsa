# Mixed-lighting evidence

Measured on 2026-10-29 on `AMD Radeon RX 9060 XT (RADV GFX1200)`, Vulkan
1.4.363. Build `d577189`. The offscreen target was 1920x1080 for the performance
runs and 640x360 for the quality captures. All runs are under `runs/`; no image
is committed.

The decision and the data contract are in
[ADR 0045](../adr/0045-mixed-lighting.md) and
[ADR 0044](../adr/0044-bake-data-contract.md). The commands and quality checks
are in [docs/agents/harness.md](../agents/harness.md).

## Bake

`bin/harbagsa-bake --out build/bake/arena.hbake` at 16 threads:

| Quantity | Default 1 m | 2 m fallback |
| --- | --- | --- |
| Key | `6920149317377461357` | `16308736185393186116` |
| SHA-256 | `96bc7e58…f291` | `—` |
| Bake time | 4873 ms | 3356 ms |
| Probes | 8000 (40 x 5 x 40) | 1200 (20 x 3 x 20) |
| Invalid probes | 88 | 4 |
| Dilated / skipped | 88 / 0 | 4 / 0 |
| Atlas | 1024² RGBA16F, 8,388,608 bytes | same |
| Probe payload | 6,208,000 bytes | 931,200 bytes |
| Artifact | 14,608,480 bytes | 9,331,680 bytes |
| GPU lighting data | 14,608,096 bytes | 9,331,296 bytes |

The artifact stores `bake_ms = 0`, so two runs with the same input are
byte-identical. The tool prints the measured time; a runtime publish reports it
as `state.bake.build_ms`.

## Quality captures

Every capture below was taken with TAA off and both `lightmap` and `probes`
enabled unless the row says otherwise. `mean` is the 8-bit colour mean.

| State | Run directory | Result |
| --- | --- | --- |
| Static bounce on/off | `runs/387-ev-bounce` | mean 48.82 -> 42.17; zero fraction 0.034 -> 0.357. Indirect lifts the static floor and walls; dynamic crates stay dark. |
| Moving crate, probes on/off | `runs/387-ev-crate-probe` | mean 40.55 -> 37.28; zero fraction 0.029 -> 0.147. The crate picks up static bounce and loses it with `probes=false`. |
| Moving crate, two positions | `runs/387-crate-left`, `runs/387-crate-right` | means 41.85 and 42.30; `diff` mean 15.0, max 236. The crate and its hard direct shadow move together; the bake key stays `6920149317377461357`. |
| Moving dynamic lamp | `runs/387-ev-dynamic-lamp` | lamp center mean 98.61, left mean 81.26; key stays `6920149317377461357` and status stays `current`. No probe or lightmap change. |
| Static fixture removed | `runs/387-ev-lamp-removed` | before 48.85 (current), stale 39.46 (key `16461673560160267698` against artifact `6920149317377461357`), after publish 38.27 (current). The 1.19 stale gap is the removed fixture's old bounce. |
| Static fixture added | `runs/387-fixture` | stale 38.57 against artifact `6920149317377461357`; publish makes it current at key `9691824680332138508`, mean 44.58. |
| Near-wall crate, probes on/off | `runs/387-ev-wall` | mean 6.90 -> 6.45; zero fraction 0.004 -> 0.093. No bright band on the wall; the dilated probes add a dim value to the crate, not a leak through the shell. |
| Lit wall/floor seam | `runs/387-ev-seam-lit` | mean 243.61 -> 232.33 with `lightmap=false`; zero fraction 0.000 -> 0.007. No line at the chart border in the capture. |
| All lights off, current bake | `runs/387-empty` | key `14958416254372390669`, `current`; wall-corner stats max `1/255`, mean `0.16/255`, zero fraction `0.836`. The image is black; the spider's emissive eyes are the only lit pixels in a normal camera. |
| 2 m artifact | `runs/387-2m` | `current`, key `16308736185393186116`, 1200 probes, spacing 2, 4 invalid, 4 dilated. |
| Missing / failed artifact | `runs/386-missing`, `runs/386-failed` | `missing` with zero probes; `failed` with the loader error. Neither adds indirect. |

## Performance at 1920x1080

GPU pass means over 30 measured frames (10 warmup) for the default scene, and
over 20 measured frames (10 warmup) for the 96-light synthetic scene. Each row
is the mean of three runs for 3 lights and two runs for 96 lights. TAA was off
for the 3-light rows and on for the 96-light rows. The offscreen frame interval
is dominated by the harness readback; the GPU pass means are the frame-budget
evidence.

| Scene | `lightmap` | `probes` | Scene pass | Total GPU |
| --- | --- | --- | --- | --- |
| 3 lights | on | on | 0.440 ms | 1.268 ms |
| 3 lights | off | off | 0.295 ms | 0.878 ms |
| 3 lights | off | on | 0.377 ms | — |
| 3 lights | on | off | 0.450 ms | — |
| 96 lights | on | on | 3.083 ms | 3.921 ms |
| 96 lights | off | off | 2.830 ms | 3.637 ms |

The 96-light total is the sum of TLAS, cluster, depth, scene, TAA, and overlay.
At 3 lights the probe difference is inside the run-to-run noise floor (the
`probes=off` mean was slightly higher than the `probes=on` mean); the lightmap
difference is 0.063 ms. At 96 lights the mixed added cost is 0.25 ms in the
scene pass and 0.28 ms in the GPU total, well inside the 1.0 ms budget.

## Budgets

| Target | Result | Status |
| --- | --- | --- |
| Lightmap fetch <= 0.25 ms | ~0.063 ms at 3 lights/1080p | Met |
| Probe gather <= 0.60 ms | Below the ~0.05 ms noise floor at 3 lights; not separable at 96 lights | Met by upper bound |
| Mixed lighting added <= 1.0 ms | 0.14 ms at 3 lights; 0.25 ms at 96 lights | Met |
| Full frame <= 8.0 ms at 96 lights/1080p | 3.92 ms GPU total | Met |
| GPU lighting data <= 32 MiB | 13.93 MiB | Met |
| Default bake <= 2 s | 4.87 s at 16 threads | **Not met** |
| High-quality bake <= 8 s | No separate quality preset; 4.87 s is the only preset | Not measured |
| Artifact <= 32 MiB | 13.93 MiB | Met |

## Accepted limitations

- A dynamic object does not occlude static indirect. A crate does not darken
  the floor's baked value; its real-time direct shadow supplies the contact.
- A dynamic lamp contributes no indirect. A corner lit only by a dynamic lamp
  stays dark until a static fixture is added and baked.
- A static edit is stale until an explicit publish. The harness publish blocks
  for the bake duration (about 5 s at 16 threads); there is no in-game bake UI.
- The default 128 rays per lightmap texel leaves low-frequency noise on
  near-black walls. The noise is static, not temporal; raise `lightmap_rays`
  if it matters for a specific shot.
- The bake is not under the 2 s target. The 1 m grid is 4.87 s at 16 threads and
  about 37 s at one thread. The 2 m fallback is 3.36 s at 16 threads. Lowering
  the sample counts would need a quality decision.
- The bisected lightmap/probe costs at 96 lights are below run-to-run variance
  because the 96 direct lights and their shadow rays dominate the scene pass.
- TAA history resets on a publish or reload; the next few frames reconverge.
- The empty-bake capture still contains the spider's emissive eyes. The room
  itself is black.

## Reproduction

```sh
make bake
./bin/harbagsa-agent run scenarios/perf.json --size 1920x1080 --out runs/perf
./bin/harbagsa-agent run scenarios/perf-arena.json --size 1920x1080 --out runs/perf-arena
```

The paired quality captures use temporary scenarios with a fixed camera and
`renderer_debug` toggles; the run directories above name the output of each
pair. The 96-light runs set `synthetic_lights` to 96 and compare `lightmap` and
`probes` on with both off. Keep `state.bake.status == "current"` and
`state.bake.key == state.bake.artifact_key` for every accepted capture.
