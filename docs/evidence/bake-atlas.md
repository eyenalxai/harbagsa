# Bake atlas layout and static slot keys

The lightmap atlas now uses a 1-texel gutter and a 4-texel minimum chart, the
shelf packer sorts charts by allocation height, the bake report carries
allocated texels and occupancy, and a static box slot key includes the box
transform. The 2x linear arena fits the 1024² atlas. A moved static box reports
stale and falls back to direct light instead of sampling its old chart.

## What changed

- `GUTTER_TEXELS` is 1 and `MIN_CHART_TEXELS` is 4. The atlases in
  `runs/before/arena.hbake` (tool 3) and `runs/after/arena.hbake` (tool 4) are
  the same size; only the chart allocation changes.
- The packer builds every chart plan first and sorts by allocation height, then
  allocation width, then box and face. A tall face no longer sets a mostly
  empty shelf row.
- `allocated_texels` is the sum of the chart rectangles plus 2 x gutter on each
  axis. `occupancy` is that sum divided by `atlas_width * atlas_height`. It is
  not `valid_texels` and not the baked count.
- `TOOL_VERSION` is 4. The loader rejects the previous 4-texel gutter and
  8-texel minimum chart as an unsupported quality block, so a tool 3 artifact
  must be rebuilt with tool 4.
- A slot key hashes `(source, id, transform)`. The frame recomputes it. A moved
  static box misses the artifact's slot and `bake_box_slot` returns no tile.
  The texel seed still follows `(source, id, face, x, y)`, so the transform does
  not re-roll the noise field after a rebuild.

## Default arena, before and after

`./bin/harbagsa-bake --out runs/before/arena.hbake --threads 16` (tool 3) and
`./bin/harbagsa-bake --out runs/after/arena.hbake --threads 16` (tool 4). The
tool 3 binary did not print allocation; its value below is read from the same
artifact with the same definition (chart rectangle plus gutter).

| Measure | before (tool 3, 4/8) | after (tool 4, 1/4) | Change |
| --- | --: | --: | --: |
| Atlas | 1024² (1,048,576) | 1024² (1,048,576) | 0 |
| Charts | 330 | 330 | 0 |
| Valid texels | 165,334 | 149,448 | −16,114 |
| Invalid texels | 21,322 | 15,548 | −5,774 |
| Dilated texels | 121,270 | 28,134 | −93,136 |
| Allocated texels | 301,504 | 187,052 | −114,452 (−38.0%) |
| Occupancy | 28.75% | 17.84% | −10.91 points |
| Artifact bytes | 12,560,480 | 12,560,480 | 0 |
| Bake time | 5,690 ms | 5,835 ms | +145 ms |

The occupancy drop is the smaller chart allocation, not a packing regression.
The packer's effect is isolated in the 2x sorted-versus-unsorted run below. The
artifact size is fixed by the 1024² atlas and the probe field. The bake time
difference is inside the ±100 ms stage spread measured in
`docs/evidence/mixed-lighting.md`; the lightmap stage is 3,377 ms before and
3,077 ms after.

The tool 4 runtime rejects the tool 3 artifact because its quality block names
the previous 4-texel gutter and 8-texel minimum chart. The status is `failed`,
not `stale`; rebuild with `make bake`. The same scenario against the tool 4
artifact reports `status: current`, `tool_version: 4`,
`artifact_key == key: 651230722116722838`, `allocated_texels: 187,052`, and
`occupancy: 0.17838669`.

## 2x linear arena

`./bin/harbagsa-bake --out runs/after/arena-2x.hbake --threads 16 --scale 2`
scales every static box centre and half extent and every static light position
by 2; the scenario form is `scenarios/bake-atlas-2x.json` with
`{"cmd":"bake","scale":2.0}`. The 4x surface area fits:

| Measure | 2x value |
| --- | --: |
| Atlas | 1024² (1,048,576) |
| Allocated texels | 670,000 |
| Occupancy | 63.90% |
| Headroom | 378,576 texels |
| Valid texels | 576,940 |
| Invalid texels | 52,300 |
| Dilated texels | 64,728 |
| Bake time | 14,173 ms |
| Artifact bytes | 12,560,480 |

The exact atlas limit is 1,048,576 texels. The 2x build is 670,000 allocated
texels, so it fits without lowering the 4-texels/m density. The same build with
the height sort removed fails with `the lightmap atlas is full`
(`runs/after/bake-2x-unsorted.txt`); the packer is what puts it under the limit.

## Moved static box

`scenarios/bake-static-move.json` places a static crate at `[0, 0.5, 9.5]`,
bakes, picks the top face, moves the crate to `[2, 0.5, 9.5]`, and picks the
same face again. The camera keeps the same relative view.

| | baked | after the move |
| --- | --- | --- |
| `state.bake.status` | current | stale |
| `state.bake.key` | 17145427004284724291 | 12683803151893692035 |
| `state.bake.artifact_key` | 17145427004284724291 | 17145427004284724291 |
| pick `lightmap.rect` | 0.171387, 0.239746, 0.174316, 0.242676 | 0, 0, 0, 0 |
| pick `lightmap.texel` | 178, 246 | −1, −1 |
| pick `terms.lightmap` | 0.006515, 0.019307, 0.013562 | 0, 0, 0 |

The before capture reports `current`; the after capture reports `stale` with
the same artifact key. The moved box keeps its direct term and loses its
lightmap term. The captures are `baked-beauty.png`, `baked-lightmap.png`,
`moved-beauty.png`, and `moved-lightmap.png` under
`runs/after/bake-static-move/frames/`.

## Seam and leak comparison

Before and after runs use the same scenarios, cameras, settle counts, and
capture regions. `direct` is pixel-identical (0 different pixels), so the
simulation and frame pairing hold; the differences are in the lightmap term.

| Scenario | Capture | Different pixels | max delta | mean delta | over 16 |
| --- | --- | --: | --: | --: | --: |
| lighting-quality | `bounce` | 42,278 (4.59%) | 8 | 0.0760 | 0 |
| lighting-quality | `bounce-shadow` region | 0 | 0 | 0 | 0 |
| lighting-quality | `direct` | 0 | 0 | 0 | 0 |
| lighting-seam | `seam-stairs` | 62,566 (6.79%) | 8 | 0.0939 | 0 |
| lighting-seam | `seam-junction` | 12,251 (1.33%) | 7 | 0.0205 | 0 |
| lighting-wall | `wall-inside` | 63,292 (6.87%) | 10 | 0.0830 | 0 |
| lighting-wall | `wall-away` | 70,170 (7.61%) | 10 | 0.1022 | 0 |

The region statistics are the seam and leak checks. The stair band gradient is
0.712390 before and 0.710550 after; the junction band gradient is 0.578125
before and 0.576575 after. The sealed cell's outer face is unchanged:
`wall-inside-face` mean 16.710991 before and 16.710970 after (delta −0.000021),
stddev 3.067077 → 3.067023, gradient 0.503742 → 0.503712. The same face inside
and after the fixture moves is identical within each run, so the cell still
does not leak. The crate region mean is 157.058 → 157.096, a 0.038 code-value
move from the new chart sampling, with no outlier step.

## Determinism and check

Two default builds with 16 and 1 thread produce identical bytes:
sha256 `780f0437aa2e82ee3d095f7dceafa96bf495bbdbb488c3ca5cff520849ad65bc`,
key `0909a2e43296a096`, payload `3a680665ebcdd171`. The `.time` sidecar carries
the different wall times, not the artifact.

`make check` passes with the 400-line limit, shader validation, and every
`odin check` target.

## Runs

- `runs/before/arena.hbake`, `runs/before/bake-report.txt`, and
  `runs/before/atlas.txt` (baseline artifact and allocation read).
- `runs/after/arena.hbake`, `runs/after/bake-report.txt`,
  `runs/after/arena-2x.hbake`, `runs/after/bake-2x-report.txt`,
  `runs/after/arena-repro.hbake`.
- `runs/before/lighting-quality`, `runs/before/lighting-seam`,
  `runs/before/lighting-wall` and the matching `runs/after/` directories.
- `runs/after/bake-static-move`, `runs/after/bake-atlas-2x` (and its
  `runs/bake-atlas-2x/arena-2x.hbake`), `runs/after/old-artifact`,
  `runs/after/new-artifact`, and `runs/after/compare-*.json`.

Images stay in the run directories; none are committed.
