# UI evidence

The 2D layer is drawn by the overlay pass: a status panel, a capture hint, a
crosshair, and the settings panel. The captures come from `bin/harbagsa-agent` at
1280x720. Run the scenario into a run directory and read the PNGs from `frames/`.
Screenshots stay out of the repository; point at the run directory instead.

## Settings panel

```sh
./bin/harbagsa-agent run scenarios/settings-menu.json --out runs/ui/menu
```

What changed:

- Text is Roboto Condensed and Roboto Mono, drawn from a coverage atlas
  rasterized by FreeType at the device pixel size. A texel is the fraction of its
  pixel the glyph covers. The earlier distance field could not draw a one-pixel
  stem; ADR 0007 has the measurement.
- HarfBuzz shapes every string, so advances and pair kerning match the variable
  font at the displayed weight. The old 97x97 kerning table is gone.
- A type size still means an em in device pixels. Each layer of the atlas now
  carries the face, the weight, and the pixel size, so a weight change never
  silently reuses the regular outlines.
- `Type weight` is a two-line slider row after Resolution. It runs from Thin 100
  to Black 900, marks the nine named instances, and accepts a drag or ten-unit
  arrow steps. The number is the only text value.
- Values sit on one column at the panel's inner edge. The old layout padded with
  `%-12s`, which spread the value column over a 16 px range because the font is
  proportional.
- The selected row lifts to a lighter surface and carries a 2 px amber bar. The
  old selection filled the row with a blue that measured 4.2:1 against white
  text, under the 4.5:1 floor.
- `Controls` is a section header in tracked capitals, not a row that looks
  selectable.
- The control list is a key legend: keys are set against their action in three
  measured columns instead of runs of four spaces.
- `1920×1080` uses the multiplication sign.

## Type weight

```sh
./bin/harbagsa-agent run scenarios/type-weight.json --out runs/ui/weight
```

The scenario captures the menu at 400, 900, and 100. The same frames show the
slider at the three positions, the `Settings` title at the role weight, and the
numeric `400`, `900`, and `100` values in Roboto Mono. Above 700 the mono face
clamps at Bold, so the numbers stop gaining weight before the prose does.

## Status panel

```sh
./bin/harbagsa-agent run scenarios/hud.json --out runs/ui/hud
```

What changed:

- One heading carries the stance and the gait. Speed and movement state are
  body rows. Grounded and position are caption rows. The old panel drew six
  lines at one size and one colour.
- Every number that changes during play is formatted into a fixed field and drawn
  in Roboto Mono, so the row width never changes and the panel never resizes as
  the player walks. A test holds this.
- A numeric Detail row now draws at 14 px. It used to fall back to the 15 px mono
  layer.
- The position names its axes.
- The capture hint sits below the crosshair. The old hint was centre-anchored
  and the crosshair drew straight through the text.

## Debug readout

```sh
./bin/harbagsa-agent run scenarios/hud-debug.json --out runs/ui/hud-debug
```

The debug mode readout uses the same row renderer: a heading, two metrics, a
divider, and two caption rows.
