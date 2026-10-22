# harbagsa

## Engineering routes

Follow these routes. Do not invent a procedure.

- **Multi-session feature**: grill the design (the `grilling` skill) → write a spec as a GitHub issue → cut tickets as sub-issues → implement → code review (the `code-review` skill) → push → tell the owner when it is done.
- **Raw report (bug, request)**: investigate → cut tickets → fix → close. No spec. Grill only when a decision is open.

## Working rules

- Use subagents as much as possible, including for exploration and review. Run independent subagents in parallel.
- Give each parallel subagent its own Rift workspace, created with the Rift tools. Each subagent creates a new branch from `main` in its workspace and pushes that branch when the work is done. Subagents never commit to `main`. The main orchestrator stays on `main`, pulls the branches, and merges them.
- Find the facts yourself before you propose anything. Read the repository under change: files, root cause, existing patterns, `GLOSSARY.md`, and relevant `docs/adr/`. Explore as much as possible. Time is not a constraint. Take your time.
- Make technical decisions yourself. Do not ask the owner to choose technical options. The owner does not know the code. Backwards compatibility does not matter. Replace or rewrite code as needed. You may change any code. Focus on long-term maintenance. If only the owner can act (a credential, a dashboard, an approval), stop and state the blocker in plain words.
- Write plain English (ASD-STE100). Use the project's domain terms. Do not invent jargon.
- Do not write process documents. These routes and rules are the process. The tracker conventions live in `docs/agents/`.
- Do not start the game or kill running instances. Tell the owner instead. They will do it.

## Engine source

The Bevy source is at `~/Projects/rust/bevy`. Use it to check engine APIs and behavior. The checkout is `0.20.0-dev`; the exact version in `Cargo.lock` decides the behavior.

## Issue tracker

Issues and specs live as GitHub issues in `eyenalxai/harbagsa`. Use the `gh` CLI for all operations. See `docs/agents/issue-tracker.md`.

## Triage labels

The five canonical triage roles use their default label strings. See `docs/agents/triage-labels.md`.

## Domain docs

Single-context: one `GLOSSARY.md` and one `docs/adr/` at the repo root. See `docs/agents/domain.md`.

## Done

When the work is done:

1. Run `cargo fmt`.
2. Run `cargo clippy --no-deps --all-targets`.
3. Run `cargo test`.
4. Run `cargo build`.
5. Commit and push your branch. The orchestrator merges subagent branches into `main` and pushes `main`.
6. Tell the owner to start the game and check the change.
