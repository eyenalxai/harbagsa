# Mixed-lighting evidence

Measured on 2026-10-29 on `AMD Radeon RX 9060 XT (RADV GFX1200)`, Vulkan loader
1.4.363. Build `6cf23ef`; `setup.dirty` is false in every quoted report. The
quality captures are 640x360 with TAA off. The performance runs are 1920x1080.
All runs are under `runs/`; no image is committed.

The decision and the data contract are in
[ADR 0045](../adr/0045-mixed-lighting.md) and
[ADR 0044](../adr/0044-bake-data-contract.md). The commands and quality checks
are in [docs/agents/harness.md](../agents/harness.md).

## Bake

`bin/harbagsa-bake` at 16 threads. The 1 m run is also `make bake`:

| Quantity | Default 1 m | 2 m fallback |
| --- | --- | --- |
| Key | `6920149317377461357` | `16308736185393186116` |
| SHA-256 | `96bc7e58…f291` | `e775d313…f760` |
| Bake time | 4909 ms | 3349 ms |
| Probes | 8000 (40 x 5 x 40) | 1200 (20 x 3 x 20) |
| Invalid / dilated / skipped | 88 / 88 / 0 | 4 / 4 / 0 |
| Atlas | 1024² RGBA16F, 8,388,608 bytes | same |
| Probe payload | 6,208,000 bytes | 931,200 bytes |
| Artifact | 14,608,480 bytes | 9,331,680 bytes |
| GPU lighting data | 14,608,096 bytes | 9,331,296 bytes |

The artifact stores `bake_ms = 0`, so two runs with the same input are
byte-identical. The tool prints the measured time; a runtime publish reports it
as `state.bake.build_ms`. The 1 m tool output is in `runs/387-bake/` when it is
run with the other evidence; the 2 m output is `runs/387-bake/tool-2m.txt`.

## Quality captures

`scenarios/mixed-lighting.json` produces the bounce, crate, wall, and seam
captures in `runs/387-mixed`. `scenarios/bake-lifecycle.json` produces the lamp
and bake-state captures in `runs/387-lifecycle`. `scenarios/crate-pair.json`
produces the moving-crate pair in `runs/387-crate-pair-left` and
`runs/387-crate-pair-right`; `runs/387-crate-diff.txt` holds the `diff` table.

| State | Capture / run | Result |
| --- | --- | --- |
| Static bounce on/off | `bounce-on` / `bounce-off`, `runs/387-mixed` | mean R 48.82 -> 42.17; zero fraction 0.034 -> 0.357. Indirect lifts the static floor and walls; dynamic crates stay dark. |
| Moving crate, probes on/off | `crate-on` / `crate-off`, `runs/387-mixed` | mean R 40.55 -> 37.28; zero fraction 0.029 -> 0.147. The crate picks up static bounce and loses it with `probes=false`. |
| Moving crate, two positions | `runs/387-crate-pair-left`, `runs/387-crate-pair-right`, `runs/387-crate-diff.txt` | mean R 41.85 and 42.30; `diff` mean 15.012, max 236, 65,284 pixels different. The crate and its hard direct shadow move together; the bake key stays `6920149317377461357`. |
| Moving dynamic lamp | `lamp-center` / `lamp-left`, `runs/387-lifecycle` | mean R 98.61 -> 81.26; key stays `6920149317377461357` and status stays `current`. No probe or lightmap change. |
| Static fixture added | `fixture-stale` / `fixture-current`, `runs/387-lifecycle` | stale 101.23 at key `17021468173752322421` against artifact `6920149317377461357`; publish makes it current at the same key, mean 111.27. The new fixture's bounce is missing while stale. |
| Static fixture removed | `fixture-removed-stale` / `-current`, `runs/387-lifecycle` | stale 73.93 at key `6920149317377461357` against artifact `17021468173752322421`; publish makes it current, mean 55.62. The 18.31 gap is the removed fixture's old bounce. |
| Near-wall crate, probes on/off | `wall-on` / `wall-off`, `runs/387-mixed` | mean R 6.90 -> 6.45; zero fraction 0.004 -> 0.093. No bright band on the wall; the dilated probes add a dim value to the crate. |
| Lit wall/floor seam | `seam-on` / `seam-off`, `runs/387-mixed` | mean R 238.44 -> 225.89 with `lightmap=false`; zero fraction 0.000 -> 0.016. The capture shows no line at the chart border. The seam publishes a new static wall lamp at key `18280171283310484885`. |
| All lights off, current bake | `empty`, `runs/387-lifecycle` | key `14958416254372390669`, `current`; stats max `1/255`, mean R `0.17/255`, zero fraction `0.835`. The image is black; the spider's emissive eyes are the only lit pixels in a normal camera. |
| 2 m artifact | `runs/387-2m-load` | `current`, key `16308736185393186116`, 1200 probes, spacing 2, 4 invalid, 4 dilated. |
| Missing / failed artifact | `runs/387-missing`, `runs/387-failed` | `missing` with zero probes; `failed` with the loader error. Neither adds indirect. |

The `fixture-stale` and `fixture-removed-stale` captures are allowed to report
`stale`; every other capture above reports `current`.

## Performance at 1920x1080

GPU pass means and p50 over the quoted runs. The 3-light runs use
`scenarios/perf.json` with 120 measured frames and 60 warmup frames, TAA off.
The 96-light runs use `scenarios/perf-96.json` with 20 measured frames and 10
warmup frames, TAA on. The offscreen frame interval is dominated by the harness
readback (p50 384 ms at 3 lights and 336 ms at 96 lights) and is not a frame
budget; the GPU pass sum is the frame-budget evidence.

| Scene | `lightmap` | `probes` | Runs | Scene p50 | Scene mean | Total p50 | Total mean |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 3 lights | on | on | `runs/387-3-on-{1,2,3}` | 0.375 ms | 0.396 ms | 0.909 ms | 1.107 ms |
| 3 lights | off | off | `runs/387-3-off-{1,2,3}` | 0.299 ms | 0.297 ms | 0.825 ms | 0.865 ms |
| 3 lights | off | on | `runs/387-3-lightmap-off-{1,2}` | 0.338 ms | 0.328 ms | 0.866 ms | 0.884 ms |
| 3 lights | on | off | `runs/387-3-probes-off-{1,2}` | 0.337 ms | 0.352 ms | 0.911 ms | 1.023 ms |
| 96 lights | on | on | `runs/387-96-on-{1,2}` | 3.016 ms | 2.945 ms | 3.994 ms | 3.903 ms |
| 96 lights | off | off | `runs/387-96-off-{1,2}` | 2.724 ms | 2.697 ms | 3.656 ms | 3.565 ms |

The 96-light totals are the sum of TLAS, cluster, depth, scene, TAA, and
overlay. The 96-light scene is dominated by the 96 direct lights and their
shadow rays; the lightmap/probe split is measured at 3 lights instead. The
96-light off run has one high outlier (scene p50 2.466 ms) beside 2.982 ms; the
mean is quoted.

## Budgets

| Target | Result | Status |
| --- | --- | --- |
| Lightmap fetch <= 0.25 ms | 0.068 ms scene mean (3 lights, TAA off) | Met |
| Probe gather <= 0.60 ms | 0.044 ms scene mean (3 lights, TAA off), inside the 0.03-0.05 ms run spread | Met |
| Mixed lighting added <= 1.0 ms | 0.10 ms scene / 0.24 ms total at 3 lights; 0.25 ms scene / 0.34 ms total at 96 lights | Met |
| Full frame <= 8.0 ms at 96 lights/1080p | GPU total mean 3.90 ms, p50 3.99 ms | Met on the GPU pass sum; the offscreen interval is readback-bound |
| GPU lighting data <= 32 MiB | 13.93 MiB | Met |
| Default bake <= 2 s | 4.91 s at 16 threads | **Not met** |
| High-quality bake <= 8 s | No separate high-quality preset exists; the only preset is the 1 m default at 4.91 s | Not measured |
| Artifact <= 32 MiB | 13.93 MiB | Met |

## Accepted limitations

- A dynamic object does not occlude static indirect. A crate does not darken
  the floor's baked value; its real-time direct shadow supplies the contact.
- A dynamic lamp contributes no indirect. A corner lit only by a dynamic lamp
  stays dark until a static fixture is added and baked.
- A static edit is stale until an explicit publish. The harness publish blocks
  for the bake duration (about 5 s at 16 threads); there is no in-game bake UI.
- The 3-light probe delta is inside the run-to-run spread; the 96-light direct
  path is too dominant to separate the probe cost, so the probe budget is an
  upper bound.
- The default 128 rays per lightmap texel leaves low-frequency noise on
  near-black walls. The noise is static, not temporal; raise `lightmap_rays`
  if it matters for a specific shot.
- The bake is not under the 2 s target. The 1 m grid is 4.91 s at 16 threads and
  about 37 s at one thread. The 2 m fallback is 3.35 s at 16 threads. Lowering
  the sample counts would need a quality decision.
- TAA history resets on a publish or reload; the next few frames reconverge.
- The empty-bake capture still contains the spider's emissive eyes. The room
  itself is black.

## Reproduction

```sh
make build
make bake
./bin/harbagsa-agent run scenarios/mixed-lighting.json --out runs/mixed-lighting
./bin/harbagsa-agent run scenarios/bake-lifecycle.json --out runs/bake-lifecycle
./bin/harbagsa-agent run scenarios/crate-pair.json --param crate_x=-3 --out runs/crate-left
./bin/harbagsa-agent run scenarios/crate-pair.json --param crate_x=3 --out runs/crate-right
./bin/harbagsa-agent diff runs/crate-left runs/crate-right

./bin/harbagsa-agent run scenarios/perf.json --size 1920x1080 \
  --debug-renderer --renderer-debug taa=false --out runs/perf-3-on
./bin/harbagsa-agent run scenarios/perf.json --size 1920x1080 \
  --debug-renderer --renderer-debug taa=false \
  --renderer-debug lightmap=false --renderer-debug probes=false --out runs/perf-3-off
./bin/harbagsa-agent run scenarios/perf.json --size 1920x1080 \
  --debug-renderer --renderer-debug taa=false \
  --renderer-debug lightmap=false --out runs/perf-3-lightmap-off
./bin/harbagsa-agent run scenarios/perf.json --size 1920x1080 \
  --debug-renderer --renderer-debug taa=false \
  --renderer-debug probes=false --out runs/perf-3-probes-off
./bin/harbagsa-agent run scenarios/perf-96.json --out runs/perf-96-on
./bin/harbagsa-agent run scenarios/perf-96.json --debug-renderer \
  --renderer-debug lightmap=false --renderer-debug probes=false --out runs/perf-96-off

bin/harbagsa-bake --probe-spacing 2 --out /tmp/arena-2m.hbake
./bin/harbagsa-agent run scenarios/perf.json --size 640x360 \
  --bake /tmp/arena-2m.hbake --out runs/2m-load
```

Keep `state.bake.status == "current"` and
`state.bake.key == state.bake.artifact_key` for every accepted capture, except
the two deliberately stale captures. The run reports carry `setup.revision` and
`setup.dirty`; a quoted claim should name both.
