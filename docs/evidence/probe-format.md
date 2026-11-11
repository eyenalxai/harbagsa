# Probe format and directional-basis A/B

The probe field now stores octahedral irradiance in `R11G11B10F` with no alpha
channel. SH9 irradiance and 16 x 16 depth moments are selectable bake options.
The default stays octa with `R11G11B10F` and 8 x 8 moments.

## What changed

- `VK_FORMAT_B10G11R11_UFLOAT_PACK32` replaces `RGBA16F` for the octa map. One
  texel is four bytes instead of eight, and the unused alpha is gone.
- The gamma-5 storage and gamma-2 blend are unchanged on the default path. A
  `probe_linear` diagnostic view decodes every tap with `2 * pow(encoded, 5)`
  before weighting, so one capture writes the gamma-2 and linear pair from one
  frame.
- `probe_basis` selects `octa` or `sh9`. SH9 stores nine signed `RGBA16F`
  coefficients per probe; the fourth channel is padding because this device
  does not sample `RGB16F`. The projection is scaled by the clamped-cosine band
  factors and a Lanczos window.
- `probe_moments` selects an 8 x 8 or 16 x 16 first/second moment block. The
  moment atlas keeps its own shelf extents, so the irradiance basis and the
  moment resolution vary independently.

## Method

The thin-wall scene places a 0.5 m static wall between a static fixture and a
dynamic crate. The crate reads the probe field on the unlit side. The
bright-emitter scene places the fixture behind a dynamic crate and looks at the
crate face that points away from it; direct light there is zero, so the probe
term shows a basis back lobe.

Each variant is one run of the same scenario with only the bake quality
changed:

```sh
./bin/harbagsa-agent run scenarios/probe-thin-wall.json \
  --param basis=octa --param moments=8 --out runs/probe-thin-wall-octa-8
./bin/harbagsa-agent run scenarios/probe-bright-emitter.json \
  --param basis=sh9 --param moments=16 --out runs/probe-bright-emitter-sh9-16
```

All runs use the same camera, 1280 x 720, TAA off, jitter off, and ten settle
frames. The direct view is identical in every variant, so the camera and frame
pairing holds.

## Results

Probe-term image deltas against the octa 8 x 8 baseline:

| Scene | Variant | Artifact bytes | Probe mean | Delta mean | Delta max | Changed pixels |
| --- | --- | --: | --: | --: | --: | --: |
| Thin wall | octa 8 x 8 | 12,560,896 | 65.1051 | 0 | 0 | 0% |
| Thin wall | octa 16 x 16 | 18,704,896 | 65.1051 | 0 | 0 | 0% |
| Thin wall | SH9 8 x 8 | 11,088,896 | 65.1895 | 0.1385 | 14 | 5.7% |
| Thin wall | SH9 16 x 16 | 17,232,896 | 65.1895 | 0.1385 | 14 | 5.7% |
| Bright emitter | octa 8 x 8 | 12,560,688 | 70.7498 | 0 | 0 | 0% |
| Bright emitter | octa 16 x 16 | 18,704,688 | 70.7498 | 0 | 1 | <0.1% |
| Bright emitter | SH9 8 x 8 | 11,088,688 | 71.2086 | 0.4883 | 11 | 8.6% |
| Bright emitter | SH9 16 x 16 | 17,232,688 | 71.2086 | 0.4883 | 11 | 8.6% |

The picked away-side crate face in the bright-emitter scene:

| Variant | Probe term (R, G, B) |
| --- | --- |
| octa 8 x 8 | 0.067237, 0.129294, 0.047151 |
| octa 16 x 16 | 0.067237, 0.129294, 0.047151 |
| SH9 8 x 8 | 0.077361, 0.146884, 0.052787 |
| SH9 16 x 16 | 0.077361, 0.146884, 0.052787 |

SH9 raises the face that points away from the bright emitter by 15.1% red,
13.6% green, and 11.9% blue. That is the SH9 back-lobe failure mode the research
note warns about, and it is the one direction a depth test cannot remove.

The thin-wall crate's picked face moves by less than 0.0003 per channel across
all four variants; the wall does not produce a measurable probe leak in this
scene. The 16 x 16 moment variants are image-identical within one 8-bit step to
their 8 x 8 counterparts.

Gamma-2 versus linear, same camera and same frame
(`runs/probe-bright-emitter-octa-8/frames/gamma-linear-probe.png` and
`gamma-linear-probe_linear.png`):

| Pair | Mean | Delta mean | Delta max | Changed pixels |
| --- | --: | --: | --: | --: |
| `probe` vs `probe_linear` | 70.7498 / 70.7565 | 0.006709 | 1 | 0.7% |

The linear reconstruction is within one 8-bit step in this scene, so the
gamma-5 storage and gamma-2 blend stay the default. The pair is available as a
diagnostic view for any future scene.

## Decision

Keep the default at octa irradiance with `R11G11B10F`, 8 x 8 depth moments, and
the gamma-5 storage / gamma-2 blend:

- **16 x 16 moments** double the moment bytes and raise the default-arena
  artifact from about 12 MiB to about 18 MiB, with no image change beyond one
  8-bit step on either scene. It does not win.
- **SH9** adds false light on the side facing away from a bright emitter and
  does not reduce the thin-wall case. Its memory win is real, but the ticket
  asked for the basis that wins the captures, and SH9 does not. It stays an
  option, not the default.
- The gamma-2 pair shows no visible difference, so the existing default path is
  left alone.

Worst-case artifact size is 18,704,896 bytes (17.8 MiB), under the 32 MiB
budget.

## Determinism

The same static input and quality produce byte-identical artifacts at one and
sixteen threads.

| Variant | SHA-256 |
| --- | --- |
| thin-wall octa 8 x 8, 1 and 16 threads | `e7aa197066be5441bb45846a2ac6d13447ef3cbde51a620fd650ee9f3414373f` |
| default-arena SH9 16 x 16, 1 and 16 threads | `db8c68b40c1a4cc33f7dc1b53a7e44d38b349ff2777ed6d280f9e59a6cbd53a9` |

The captured PNGs are byte-identical across the two thread counts as well. The
measured wall time lives in the `.time` sidecar, not in the artifact.

## Reproduce

```sh
make build
make bake
./bin/harbagsa-agent run scenarios/probe-thin-wall.json --param basis=octa --param moments=8
./bin/harbagsa-agent run scenarios/probe-thin-wall.json --param basis=sh9 --param moments=16
./bin/harbagsa-agent run scenarios/probe-bright-emitter.json --param basis=octa --param moments=8
./bin/harbagsa-agent run scenarios/probe-bright-emitter.json --param basis=sh9 --param moments=16
```

The run directories are `runs/probe-thin-wall-*` and
`runs/probe-bright-emitter-*`. The PNGs, artifacts, and `.time` sidecars stay
out of the repository.
