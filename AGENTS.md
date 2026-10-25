# harbagsa

An Odin project. Build, check, and test commands live in `README.md`.

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
- Never weaken or delete a test to make a run pass.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues in `eyenalxai/harbagsa`, driven by the `gh` CLI. See `docs/agents/issue-tracker.md`.

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

Use `bin/harbagsa-agent` to drive the simulation, run checks, and take
screenshots. It is separate from the game and needs no window or compositor.
See `docs/agents/harness.md` for the scenario format, commands, run layout, and
determinism rules. For performance work, read its **Performance** section and
`docs/adr/0008-performance-instrumentation.md`.

When you add or change a feature, update the harness and its docs in the same
change. The harness is part of the feature, not an afterthought.
