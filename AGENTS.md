# harbagsa

An Odin project. Build and check commands live in `README.md`.

## Documentation

Documentation is a lead, not the source of truth. It is malleable: it records a
moment and goes stale. A doc speaks only to its subject: a note about world motion
says nothing about UI motion. Check a doc claim against the code, the harness, or
a run before you rely on it. When they disagree, follow the code and correct or
delete the doc in the same change. Justify a decision with code, not with a doc
line.

## When to stop

Stop only when the owner must act: a decision only the owner can make, a
credential or approval only the owner holds, or a PR ready to review or merge.
A failed build, a layout that will not size, a missing API, or any other
technical blocker is work for the agent. Report it in the run log and keep
going. Never end a turn with a next step the agent could perform itself.

## Code changes

Backwards compatibility does not matter. Rip and tear if needed. Refactor anything you need; you have free rein over the code. Focus on long-term maintenance. Do not write duplicated code. Re-use existing code when possible.

Keep each first-party `.odin` file under 400 lines. `make check` enforces it. Vendored bindings are exempt.

All new commits must be written in conventional commit style.

## Git identity and signing

- Keep the repository identity. Never pass `-c user.name`, `-c user.email`, `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME`, or `GIT_COMMITTER_EMAIL`. A made-up identity breaks GitHub attribution: the commit shows an unknown author and `Unverified`.
- Sign every commit. Never pass `--no-gpg-sign` and never set `commit.gpgsign` to false.
- Do not use GitHub's "Rebase and merge". GitHub rewrites the commits without their signatures, so the published commits become `Unverified`. Use a merge commit, or rebase locally and sign the rewritten commits.

## Repository hygiene

Never commit images. Screenshots, captures, and other binary evidence stay out of the repository; point at a run directory or an external link instead.

## Comments

Write a comment only when it answers a hard "Why this way?" question. Do not narrate what the code does, restate a name, or explain how it works. If the signature and the names already say it, delete the comment.

## Code hygiene

- Do not hide a failed call behind a default. An `or_else` value that keeps the program running is a bug unless the degraded state is visible.
- Do not add a helper that only forwards its arguments. Inline it.
- Search for an existing helper before you add one.
- Do not name a thing `V2`, `New`, or `Enhanced`. Replace the old one and take its name.

## Tests

Never add tests. Do not create test files, test targets, test suites, or
assertion scenarios. Do not add a test gate. There is no test command.

## CI

CI checks and CI tests are not needed. Do not add a CI workflow, and do not
wait for CI to merge a pull request. There is no test gate.

## Agent skills

### Issue tracker

Issues and specs live as Linear issues in the `HARB` team, driven by the `rata` CLI. Pull requests still live on GitHub and use the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles use their default label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### References

External API and language references: see `docs/agents/references.md`.

### Design

The visual direction has its own guide: `docs/design/`. Read
`docs/design/README.md` before a visual change, then the topic file for the job:
`world.md`, `motion.md`, or `review.md`.

### UI

The 2D layer has its own guide: `docs/ui/`. Read `docs/ui/README.md` before
drawing anything in the overlay, then the topic file for the job: type, colour,
spacing, or components.

### Automation

Use `bin/harbagsa-agent` to drive the simulation and take screenshots. It is
separate from the game and needs no window or compositor. See
`docs/agents/harness.md` for the scenario format, commands, run layout, and
determinism rules. For performance work, read its **Performance** section and
`docs/adr/0008-performance-instrumentation.md`.

When a feature changes how the harness drives the simulation or captures a
frame, update the harness and its docs in the same change. The harness is part
of the feature, not an afterthought.
