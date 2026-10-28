# Per-run image analysis

> Status: removed. The analysis engine, `analysis.json`, and the `--no-analysis`
> option were deleted. This page records the old decision.

A run with captures writes `analysis.json` beside `report.json`. `report.json`
links it in `analysis`. The pair and pixel analysis uses color PNG captures; a
run with only intermediate captures writes an empty window and summary. The
analysis is on by default and can be disabled with `"analysis": false` or
`--no-analysis`. A scenario selects a capture window and the optional maps.

## Why

The TAA investigation compared captures with an external Python script. The
numbers were already in the run; the script only repeated arithmetic. Pair
deltas, variance, the dominant period, and the worst pixels belong in the run
report so two investigations compare the same numbers.

## Decisions

- The analysis pairs read the color PNG captures only. An intermediate target is
  not comparable with a color frame, and the captures already hold the deltas.
  The file is still written for any run with captures, with an empty window when
  no color frame exists.
- `analysis.json` holds the window, the frames, the pairs, the summary, the
  worst pixels, and the map paths. `report.json` holds the path.
- The dominant period is the smallest lag within 10% of the strongest
  autocorrelation of the per-pair mean series. A periodic series correlates at
  every multiple of its period, so the argmax alone can name a multiple.
- The worst pixels are the eight with the highest variance over the window.
  Each keeps its mean channel value per frame, so a ripple can be read as a
  series rather than guessed from a variance map.
- The maps are optional because they cost two PNG decodes per frame and two
  files. The diff map is the first-to-last frame difference; the variance map
  is the square-rooted, scaled variance.
- The check window is `{"start": S, "count": N}` over the captures. `warmup`
  stays the shorthand for the first N captures. Both are rejected together.
- The session keeps a live summary from the capture results, so a check can
  read the period during the run. The file adds the pixel-level detail after
  the commands finish.

## Considered Options

- **External Python**: no harness code, but every investigation repeats the
  arithmetic and can disagree on the period.
- **Analyze every capture target**: the deltas already exist for color, and a
  depth or velocity image has different units. Color only keeps the numbers
  comparable.
- **Keep every frame in memory**: the maps and series need one accumulation
  pass, not every frame. Decoding twice is cheaper than holding 60 frames.
- **Check the analysis only after the run**: a scenario check could not gate on
  the period. The live summary closes that gap without a second process.

## Consequences

- A run with no captures writes no `analysis.json`, and an analysis check
  reports that analysis is unavailable. A run with only intermediate captures
  writes an empty summary, not an unavailable analysis.
- The analysis decodes each frame twice when maps or worst pixels exist. At
  1280x720 and 60 captures this is a few seconds, which is acceptable for a
  diagnostic run.
- The live summary and the file share the same summary procedure, so a check
  cannot disagree with the report.
- The period threshold is a heuristic. The correlation is reported with it, so
  a weak period is visible rather than hidden.
