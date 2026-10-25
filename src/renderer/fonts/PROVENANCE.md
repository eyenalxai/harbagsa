# Font provenance

The two fonts in this directory are subsets of **Geist** and **Geist Mono**,
both licensed under the SIL Open Font License 1.1. `OFL.txt` holds the licence
text from the Geist distribution.

Upstream:

- repository: <https://github.com/vercel/geist-font>
- release: `v1.8.2`
- files: `Geist/variable/Geist[wght].ttf`,
  `GeistMono/variable/GeistMono[wght].ttf`
- fetched: 2026-10-25
- axes: both faces `wght` 100..900
- named instances: Thin 100, ExtraLight 200, Light 300, Regular 400, Medium 500,
  SemiBold 600, Bold 700, ExtraBold 800, Black 900

Subset: Unicode `U+0020-007E` plus `U+00B7` (`·`) and `U+00D7` (`×`), which the
HUD and the menu use as separators, and `U+2026` (`…`), which the type guide
requires. Without it HarfBuzz maps the ellipsis to `.notdef`, the shaper drops
`.notdef`, and the text measures zero. The variable tables (`fvar`, `gvar`,
`HVAR`, `MVAR`, `STAT`) and `GSUB` are kept in both faces; `GPOS` and `GDEF` are
kept in both. FreeType can instance any weight in both faces, and HarfBuzz can
apply kerning in Geist. Hinting is dropped. The `meta` table is not subset by
fontTools and is also dropped.

```sh
pyftsubset "Geist[wght].ttf" \
  --unicodes=U+0020-007E,U+00B7,U+00D7,U+2026 \
  --output-file=src/renderer/fonts/Geist-Variable.ttf \
  --no-hinting --desubroutinize
pyftsubset "GeistMono[wght].ttf" \
  --unicodes=U+0020-007E,U+00B7,U+00D7,U+2026 \
  --output-file=src/renderer/fonts/GeistMono-Variable.ttf \
  --no-hinting --desubroutinize
```

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `Geist-Variable.ttf` | 39552 | `dd44696176f481fea6d44cf8587d8997231e1f664c1019e1608c6e95fa043742` |
| `GeistMono-Variable.ttf` | 23780 | `e4593169938019c013140080dca3a7ac17b91d49ec974ca51ea5ed3962a6ff26` |

Table check: `fontTools.ttLib.TTFont` reports the same table set in the files
before and after this subset, except for `prep` and `meta`. Geist keeps `fvar`
(`wght` 100-900, nine named instances), `gvar` (147 entries), `HVAR` (4
regions), `MVAR`, `STAT`, `GPOS` (2 lookups), `GDEF`, and `GSUB` (12 lookups).
Geist Mono keeps `fvar` (`wght` 100-900, nine named instances), `gvar` (133
entries), `HVAR` (0 regions, as upstream), `MVAR`, `STAT`, `GPOS` (0 lookups, as
upstream), `GDEF`, and `GSUB` (7 lookups). Both faces keep `gasp`. Neither keeps
`prep`, because hinting is dropped. Neither upstream file has `avar`.

FreeType check: `FT_Get_MM_Var` reports `wght` 100-900 with nine named instances
for both faces. `FT_Set_Var_Design_Coordinates` and a 15 px render of `U+2026`
both succeed on each face.

Source files:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `Geist[wght].ttf` | 169056 | `98c7f53f48cb74b8b89e012e3902f0c11d12ae361c67db8da35d5969cfaa610d` |
| `GeistMono[wght].ttf` | 171200 | `4d2bad39b04d4e994500de6d2a70d2a74beb61de24cd127394294258f55e8c7f` |

A future re-subset must re-check that `fvar`, `gvar`, `HVAR`, `MVAR`, `STAT`,
`GSUB`, `GPOS`, and `GDEF` survive in both faces, and that FreeType still
exposes the `wght` axis.
