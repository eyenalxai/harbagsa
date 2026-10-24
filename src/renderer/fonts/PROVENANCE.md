# Font provenance

The three fonts in this directory are subsets of **Noto Sans** and **Noto Sans
Mono**, both licensed under the SIL Open Font License 1.1. `OFL.txt` holds the
licence text, copied unchanged from the distribution package.

Upstream:

- package: `noto-fonts 1:2026.10.01-1`
- files: `/usr/share/fonts/noto/NotoSans-Regular.ttf`,
  `NotoSans-Medium.ttf`, `NotoSansMono-Regular.ttf`

Subset: Unicode `U+0020-007E` plus `U+00B7` (`·`) and `U+00D7` (`×`), which the
HUD and the menu use as separators. Hinting is dropped and CFF subroutines are
flattened; the atlas rasterizes glyphs at 48 px so hinting cannot apply.

```sh
pyftsubset <source>.ttf \
  --unicodes=U+0020-007E,U+00B7,U+00D7 \
  --output-file=src/renderer/fonts/<name>.ttf \
  --no-hinting --desubroutinize
```

| File | Bytes | SHA-256 |
| --- | --- | --- |
| `NotoSans-Regular.ttf` | 13120 | `73d795c40e86e22cc0dce732728e02a5bb9d6f5f27afa5b1201c4f1420685996` |
| `NotoSans-Medium.ttf` | 13092 | `1defe466995a6adc36eaa8181a836d48af7592d12594df5a3d8ee10c1af78e0f` |
| `NotoSansMono-Regular.ttf` | 10904 | `1fb093c57afaad63d2416d3e968d574acac9d848ed297f6dce97df8dcbef07c6` |

The subset keeps the legacy `kern` table, which `stb_truetype` reads; `A/V`
returns the same -40 font units before and after subsetting. A future re-subset
must re-check that.
