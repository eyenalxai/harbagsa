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
HUD and the menu use as separators. The variable tables (`fvar`, `avar`, `gvar`,
`HVAR`, `STAT`), `GPOS`, `GDEF`, and `GSUB` are kept, so FreeType can instance
any weight and HarfBuzz can apply kerning. Hinting is dropped and CFF
subroutines are flattened.

```sh
pyftsubset RobotoCondensed[wght].ttf \
  --unicodes=U+0020-007E,U+00B7,U+00D7 \
  --output-file=src/renderer/fonts/RobotoCondensed-Variable.ttf \
  --no-hinting --desubroutinize
pyftsubset RobotoMono[wght].ttf \
  --unicodes=U+0020-007E,U+00B7,U+00D7 \
  --output-file=src/renderer/fonts/RobotoMono-Variable.ttf \
  --no-hinting --desubroutinize
```

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `RobotoCondensed-Variable.ttf` | 48392 | `cff66d04820ac9330f4bd0401d21a8162a6ad5cb1aab2f61d93c68996c9df257` |
| `RobotoMono-Variable.ttf` | 27696 | `3cc489ac1bd5be3a697ccfaf05b8110141fe640b5477979e226b3a093f8ff07a` |

Source files:

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `RobotoCondensed[wght].ttf` | 371616 | `dace262afcee68a5276f200d8026c57221735c0118ab5fda8c2c0d3dc409a8d0` |
| `RobotoMono[wght].ttf` | 183700 | `66a80e79d17e4c7cabd162e2916578a4cc08fd19eef6e2a643305eae9c567b2b` |

A future re-subset must re-check that `fvar`, `gvar`, `HVAR`, `avar`, and `GPOS`
survive, and that FreeType still exposes the `wght` axis.
