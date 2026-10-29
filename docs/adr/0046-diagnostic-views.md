# Diagnostic views capture one frame per term

A capture can name up to eight views: `beauty`, `direct`, `lightmap`, `probe`,
`emissive`, `shadow`, `lightmap_grid`, and `probe_cell`. One simulation frame
yields one capture entry per view, each with its own PNG and a `view` field. The
frame is drawn once, the depth prepass is shared, and each term view is one extra
lit pass at the same camera and jitter. The term views share the TAA history with
the beauty frame instead of resetting it.

## Why

- A lighting question is "which term is this pixel?". Toggling renderer debug
  flags, re-rendering, and diffing images answers it slowly and loses the frame
  the question was about.
- Term measurements need the same camera, jitter, and history as the beauty
  frame. A debug override resets TAA history, so a term capture taken that way
  cannot be compared with the composed pixel it explains.
- `lightmap_grid` and `probe_cell` read data the beauty image hides: atlas texel
  addresses and the probe cell a dynamic surface samples. No image diff can
  recover them.

## Decisions

- **One simulation frame.** `views` is an array on a `capture` output. The
  command expands into one capture entry per view, named `<name>-<view>`. The
  outputs of one `views` list share a frame, a camera, and a jitter index, and
  the renderer report names that one frame for every entry.
- **One extra lit pass per view.** The depth prepass is shared. Each term view
  re-runs the lit pass with a `view` push constant and resolves into its own
  image. The scene target, the velocity, and the history are untouched by the
  term passes.
- **Every view is a colour image.** A term view resolves through the same gamma
  and dither path as beauty, with history read and write disabled. The resolve
  pipeline has one colour attachment, so it cannot write history. `float` and
  `raw` views are command errors; use `scene_color` for linear analysis.
- **Beauty is untouched.** A capture without `views` renders, resolves, and
  writes exactly as before. The composed pixel is the original expression in the
  original shader, and a beauty capture in a `views` list is the same image as a
  plain color capture of that frame.
- **The term include is the seam.** `terms.glsl` owns the direct, shadow,
  lightmap, probe, and emissive evaluation. The term-view fragment shader reads
  it today and the pick shader reads it next. The beauty shader includes it for
  the shared terms but keeps its composed expression and its own dispatch-free
  entry point: a shader that also carries the term branch recompiles the
  composed pixel, which perturbs the last dither bit. `scene.glsl` holds the
  shared bindings so the two fragment shaders and the pick shader declare the
  same interface once.
- **The shadow view is a ratio.** It redraws with shadow rays off and divides the
  shadowed direct luma by the open direct luma. One `trace_shadows` flag on the
  direct term selects the walk; the beauty call passes true, and the compiler
  folds it, so the composed pixel keeps its instructions.
- **Grid views paint data, not light.** `lightmap_grid` is a checker from atlas
  texel coordinates plus a red line at each chart edge, and magenta for a box
  with no tile. `probe_cell` is a hashed cell-id hue, red when a cell probe is
  invalid, and magenta outside the volume.
- **Everything else is a normal capture.** Per-view output options apply to
  every view: `format`, `png`, `region`, `rect`, `profile`, `crop`, `histogram`,
  `steps`, `color_key`, and `coverage`. `compare`, `storyboard`, and `evidence`
  treat a view like any other capture entry.

## Considered options

- **A renderer debug toggle per term.** Rejected. It resets history, it changes
  the next beauty frame, and the toggle state outlives the capture.
- **One draw per term into the scene target, copying after each.** Rejected. It
  would need one readback per view anyway, and it destroys the scene color that
  a `scene_color` capture in the same group asked for.
- **A second frame per view.** Rejected. The simulation advances, TAA advances,
  and the entries would not describe one frame.
- **A separate scene draw including its own depth prepass.** Rejected. The depth
  buffer is the same geometry at the same jitter, and the shared prepass is what
  makes "one extra draw" true.
- **Put the term dispatch in the beauty shader.** Rejected. Measured: the
  composed pixel moved by one dither level on a few pixels. The acceptance rule
  is byte identity, so the dispatch lives in `box_view.frag`.
- **Write a float term image.** Rejected. A term is a colour image; linear
  analysis reads `scene_color`, which is already float and already a capture
  target.

## Consequences

- A capture with N views costs one extra lit pass and one readback slot per
  view. The beauty path, the game loop, and a capture without `views` are
  unchanged.
- View images are allocated on the first term-view capture and reused until the
  target extent changes. The game binary that never captures owns none.
- A term view is a single sample, so a noisy bake looks noisy in the term image
  while the beauty image is still converged. That is the point: the term image
  shows the raw term.
- `render_digest` is unchanged by the view list. A view is a capture input, not
  a frame input, and the beauty digest must stay comparable with earlier runs.
