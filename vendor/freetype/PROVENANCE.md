# FreeType provenance

Vendored from <https://github.com/freetype/freetype> at tag `VER-2-15-0`,
commit `37515cf56ba3349656049edbed89ffc6f6466f2d`. The tree is unmodified.

Build: `vendor/freetype-config/ftoption.h` and `ftmodule.h` override the stock
configuration. The module set is TrueType-only:

```
ftsystem ftinit ftdebug ftbase ftbbox ftglyph ftbitmap ftmm
truetype sfnt psnames smooth
```

The bytecode interpreter, subpixel hinting, the autohinter, CFF, Type 1, zlib,
png, and bzip2 are not built. `make` compiles the sources with
`-DFT2_BUILD_LIBRARY` and archives them with `ar crsD`.

The `sfnt` module still references `FT_Gzip_Uncompress` for WOFF and SVGZ even
with zlib disabled. `vendor/freetype-config/ftgzip_stub.c` provides that symbol
and returns `FT_Err_Unimplemented_Feature`; this build only loads plain TTF.

Licences: `LICENSE.TXT`, `docs/FTL.TXT`, `docs/GPLv2.TXT`. The FreeType credit
line is in the repository `README.md`.
