# UI evidence

The 2D layer is drawn by the overlay pass: a status panel, a capture hint, a
and the settings panel. The captures come from `bin/harbagsa-agent` at
1280x720. Evidence is a run directory plus a scenario. Run the scenario into
`runs/<scenario-stem>/` and read the frames from `frames/`. Screenshots stay out
of the repository.

## Geist typeface

The overlay moved from Roboto Condensed and Roboto Mono to Geist and Geist Mono.
Run the two surfaces into before and after directories, then compare them:

```sh
make shot SCENARIO=hud OUT=runs/ui/hud-before
make shot SCENARIO=hud OUT=runs/ui/hud-after
make shot SCENARIO=scenarios/settings-menu.json OUT=runs/ui/menu-before
make shot SCENARIO=scenarios/settings-menu.json OUT=runs/ui/menu-after
./bin/harbagsa-agent diff runs/ui/hud-before runs/ui/hud-after
./bin/harbagsa-agent diff runs/ui/menu-before runs/ui/menu-after
```

The diff covers the text region only:

- `hud-walk`: 8622 pixels differ, max delta 224 of 255, mean 0.780, over-16
  7595.
- `settings-menu`: 62984 pixels differ, max delta 246 of 255, mean 5.410,
  over-16 59456.

The status panel and the settings panel grow with the wider face. Both still fit
1280x720.

## Settings panel

```sh
./bin/harbagsa-agent run scenarios/settings-menu.json --out runs/ui/menu
```

What changed:

- Text is Geist and Geist Mono, drawn from a coverage atlas rasterized by
  FreeType at the device pixel size. A texel is the fraction of its pixel the
  glyph covers. The earlier distance field could not draw a one-pixel stem; ADR
  0007 has the measurement.
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
numeric `400`, `900`, and `100` values in Geist Mono. Both faces run to Black
900, so the numbers keep pace with the prose.

## Blocked note

```sh
./bin/harbagsa-agent run scenarios/blocked-note.json --out runs/ui/blocked-note
```

The Type weight is at 900, so the press is blocked. `blocked-note.png` shows the
reason on the frame after the press. The next command sets the weight to 400,
and `note-cleared.png` shows the default note. A new blocked press restarts the
two-second hold.

## Neutral ramp

The six neutral tokens were re-pinned to OKLCH hue 253. `scenarios/ui.json` was
captured before and after the change, and `bin/harbagsa-agent diff` measured the
result:

- `menu-number`: 229,907 pixels differ, max delta 1 of 255, mean 0.249,
  over-16 0.
- `menu-action`: 228,863 pixels differ, max delta 1 of 255, mean 0.248,
  over-16 0.

The 8-bit change is one step in one channel on three tokens. The measured hue
spread of the six neutrals is 7.8 degrees.

## Status panel

```sh
./bin/harbagsa-agent run scenarios/hud.json --out runs/ui/hud
```

What changed:

- One heading carries the spider and the gait. Speed and the planted foot count are
  body rows. Grounded and position are caption rows. The old panel drew six
  lines at one size and one colour.
- Every number that changes during play is formatted into a fixed field and drawn
  in Geist Mono, so the row width never changes and the panel never resizes as
  the player walks. A test holds this.
- A numeric Detail row now draws at 14 px. It used to fall back to the 15 px mono
  layer.
- The position names its axes.
- The capture hint sits on the bottom margin. The old hint was centre-anchored
  and covered the third-person body.

## Debug readout

```sh
./bin/harbagsa-agent run scenarios/hud-debug.json --out runs/ui/hud-debug
```

The debug mode readout uses the same row renderer: a heading, two metrics, a
divider, and two caption rows.
