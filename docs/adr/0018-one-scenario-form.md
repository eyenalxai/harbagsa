# One scenario form

A scenario has one body form: `commands`. It runs verbatim. Only a `capture`
command captures. The `steps` form and the top-level `capture` key are gone.

## Why

- Two forms with different capture rules made the same file mean different
  things after an edit. `steps` captured the final frame by default and also
  appended the total to an explicit capture list, so a list of three frames
  silently became four.
- `record` already writes `commands`. Keeping `steps` meant every recorded
  scenario used a form that hand-written scenarios did not.
- The glossary already described a scenario as "a JSON document that compiles to
  one command list". The `steps` compiler was the exception, not the rule.
- A capture is now visible where it happens. There is no hidden final frame and
  no `"capture": []` opt-out to remember.

## Considered Options

- **`steps` with a `capture: false` flag**: keeps the terse movement form, but
  leaves two body forms and a second capture control.
- **One command list with a default final capture**: keeps simple scenarios
  short, but adds a hidden rule that `replay` must not apply and a flag to turn
  it off.
- **Keep both and document the difference**: no behaviour change. The difference
  is the bug.
- **One command list with explicit captures**: every capture is a command, and
  the same rule covers a batch run and a replay.

## Consequences

- Every scenario uses `commands`; `scenarios/smoke.json` and the TAA scenarios
  list their captures explicitly.
- `record` and `replay` produce and consume the same form by construction.
- A scenario with no `capture` and no perf run does not create a renderer unless
  `--present` asks for the window.
- The scenario compiler no longer validates a total frame count; each `step`
  command keeps its own bounded frame count.
