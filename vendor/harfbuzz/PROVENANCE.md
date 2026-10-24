# HarfBuzz provenance

Vendored from <https://github.com/harfbuzz/harfbuzz> at tag `15.0.0`, commit
`35f656a1a2bab548ea7f54a6dd3fba2b09680d14`. The tree is unmodified.

Build: `src/harfbuzz.cc` is the upstream amalgamation, compiled once as C++11
with `-fno-exceptions -fno-rtti -fno-threadsafe-statics -DNDEBUG` and
`-DHB_NO_MT`. Glib, ICU, Cairo, Graphite, and the FreeType integration are not
built. `HB_NO_VAR` is deliberately absent, because it removes variable-font
support.

Licences: `COPYING` (Old MIT) and `src/ms-use/COPYING` (Unicode).
