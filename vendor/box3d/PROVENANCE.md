# Box3D vendored copy

Source: the Odin vendor collection at `/usr/lib/odin/vendor/box3d`.

| Item | Value |
| --- | --- |
| Odin version | `dev-2026-10:84bc3fc21` |
| Snapshot date | 2026-10-07 |
| Upstream | Box3D 0.1.0 by Erin Catto |
| License | MIT, see `LICENSE` |

The Odin bindings (`*.odin`) and the C source (`src/`) come from the same
snapshot. Do not update one without the other. A newer C library linked to
older bindings corrupts the stack, because the struct layouts differ.

The build script from the Odin installation is not copied, because it writes
into the root-owned Odin installation. `make` builds the archive from
`src/src/*.c` into `lib/linux-amd64/libbox3d.a`.

The archive is a build artifact. Git ignores it.

To update:

1. Copy the bindings and `src/` from a newer Odin installation as one unit.
2. Record the new date and Odin version here.
3. Run `make test`. The smoke test catches struct layout drift.
