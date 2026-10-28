# The scenario declares what the run needs and varies

A scenario owns its gated commands and its knobs. `requires` enables a gated
command for that run, and `parameters` declares a value that commands use as
`${name}`. The runner no longer needs an external flag for a known requirement,
and one file can produce a sweep instead of a directory of near-copies.

## Why

- The lamp-wall capture needed `--debug-renderer`. The scenario already declared
  the override block; the runner required a second declaration from the command
  line.
- Finding the lamp threshold took ten scenario files that differed in one
  number. `--param lamp_x=20,19.999,19.99` is the same experiment in one file.
- A name is stable when a capture is inserted; an index is not. The same change
  adds `capture.named.<name>.*`.

## Decisions

- **`requires` is a scenario-level gate.** `requires.renderer_debug` sets the
  same session flag as `--debug-renderer`. A scenario without the declaration
  still needs the flag or the build define. The setup block records the gate.
- **`parameters` is the only source of `${name}`.** A placeholder is a JSON
  string, so `["${x}", 0, 0]` puts a numeric parameter in an array. The declared
  value sets the type: a string stays text, a boolean must parse as `true` or
  `false`, and a number accepts both `20` and `19.999`.
- **An override must be used.** `--param` fails when no `${name}` outside the
  `parameters` block names it, so a typo cannot silently do nothing.
- **The sweep is a CLI loop, not a command.** `--param NAME=V1,V2` runs one
  scenario per value into its own directory, and the parent gets `sweep.json`.
  A single value is a plain run. Repeated flags take the cartesian product,
  last parameter fastest.
- **The effective parameters are part of the scenario.** `report.scenario`
  lists them sorted by name, and they join the scenario hash. Two values of one
  file are two distinct scenarios in the report.

## Consequences

- `lamp-threshold.json` is the worked sweep.
- `capture.named.<name>.*` reuses the `capture.N` resolver; a missing name is a
  field error.
- A sweep that hits a command failure still runs every combination. The process
  exit code is the highest of the runs.
- The report and `sweep.json` are the evidence; no extra capture or log format
  was added.
