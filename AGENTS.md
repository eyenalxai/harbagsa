# harbagsa

An Odin project. Build, check, and test commands live in `README.md`.

## Code changes

Backwards compatibility does not matter. Rip and tear if needed. Refactor anything you need; you have free rein over the code. Focus on long-term maintenance. Do not write duplicated code. Re-use existing code when possible.

Keep each first-party `.odin` file under 300 lines. `make check` enforces it. Vendored bindings are exempt.

All new commits must be written in conventional commit style.

## Comments

Write a comment only when it answers a hard "Why this way?" question. Do not narrate what the code does, restate a name, or explain how it works. If the signature and the names already say it, delete the comment.

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues in `eyenalxai/harbagsa`, driven by the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles use their default label strings. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### References

External API and language references: see `docs/agents/references.md`.
