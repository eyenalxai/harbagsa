# Font provenance

The two fonts in this directory are subsets of **Roboto Condensed** and
**Roboto Mono**, both licensed under the SIL Open Font License 1.1. `OFL.txt`
holds the licence text from the Roboto Condensed distribution.

Upstream:

- repository: <https://github.com/google/fonts>
- files: `ofl/robotocondensed/RobotoCondensed[wght].ttf`,
  `ofl/robotomono/RobotoMono[wght].ttf`
- fetched: 2026-10-24 from `main`
- axes: Roboto Condensed `wght` 100..900, Roboto Mono `wght` 100..700
- named instances: Thin 100, ExtraLight 200, Light 300, Regular 400, Medium 500,
  SemiBold 600, Bold 700, ExtraBold 800, Black 900. Mono stops at Bold 700.

Subset: Unicode `U+0020-007E` plus `U+00B7` (`·`) and `U+00D7` (`×`), which the
HUD and the menu use as separators, and `U+2026` (`…`), which the type guide
requires. Without it HarfBuzz maps the ellipsis to `.notdef`, the shaper drops
`.notdef`, and the text measures zero. The variable tables (`fvar`, `avar`,
`gvar`, `HVAR`, `STAT`) and `GSUB` are kept in both faces; `GPOS` and `GDEF` are
kept in Roboto Condensed and are absent from Roboto Mono upstream. FreeType can
instance any weight in both faces, and HarfBuzz can apply kerning in Roboto
Condensed. Hinting is dropped and CFF subroutines are flattened.

```sh
pyftsubset RobotoCondensed[wght].ttf \
  --unicodes=U+0020-007E,U+00B7,U+00D7,U+2026 \
  --output-file=src/renderer/fonts/RobotoCondensed-Variable.ttf \
  --no-hinting --desubroutinize
pyftsubset RobotoMono[wght].ttf \
  --unicodes=U+0020-007E,U+00B7,U+00D7,U+2026 \
  --output-file=src/renderer/fonts/RobotoMono-Variable.ttf \
  --no-hinting --desubroutinize
```

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `RobotoCondensed-Variable.ttf` | 48556 | `ffca461e77a8ac4bcfd299ffb14e99505389942bc1086369f64a5f83abdd76a5` |
| `RobotoMono-Variable.ttf` | 27772 | `72e7c8f4fde82851e53f4330ee45f9e8025c1f9b0e5a224db18693441eb0ac7a` |

Table check: `fontTools.ttLib.TTFont` reports the same table set in the files
before and after this subset, for both faces. Condensed keeps `fvar` (`wght`
100-900, nine named instances), `avar` (9 segments), `gvar` (124 entries),
`HVAR` (4 regions), `STAT` (`wdth`, `wght`, `ital`), `GPOS` (4 lookups),
`GDEF`, and `GSUB` (8 lookups). Mono keeps `fvar` (`wght` 100-700, seven named
instances), `avar` (5 segments), `gvar` (99 entries), `HVAR` (0 regions, as
upstream), `STAT` (`wght`, `ital`), and `GSUB`. Mono has no `GPOS` or `GDEF` in
the upstream file either, so the subset neither kept nor lost them. Both faces
keep `gasp`. Neither keeps `cvt `, `fpgm`, or `prep`, because hinting is
dropped.

FreeType check: `FT_Get_MM_Var` reports `wght` 100-900 with nine named
instances for Condensed and `wght` 100-700 with seven for Mono.
`FT_Set_Var_Design_Coordinates` and a 15 px render of `U+2026` both succeed on
each face.

Source files:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `RobotoCondensed[wght].ttf` | 371616 | `dace262afcee68a5276f200d8026c57221735c0118ab5fda8c2c0d3dc409a8d0` |
| `RobotoMono[wght].ttf` | 183700 | `66a80e79d17e4c7cabd162e2916578a4cc08fd19eef6e2a643305eae9c567b2b` |

A future re-subset must re-check that `fvar`, `gvar`, `HVAR`, `avar`, `STAT`, and
`GSUB` survive in both faces, that `GPOS` and `GDEF` survive in Roboto Condensed,
and that FreeType still exposes the `wght` axis.
