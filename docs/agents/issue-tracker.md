# Issue tracker: Linear

Issues and specs for this repo live as Linear issues in the `HARB` team
(workspace `utbetdix`). Use the `rata` CLI for issue operations. Pull requests
still live on GitHub and use the `gh` CLI.

The repository was migrated from GitHub issues. Old GitHub numbers are not the
current identifiers; use the Linear reference (`HARB-123`). The migration note
in each Linear issue names its old GitHub source.

## Vocabulary

Use the `GLOSSARY.md` term in the spec, tickets, and code. If a ticket uses a
synonym, fix the ticket before implementation.

## Conventions

- **Read an issue**: `rata issue show HARB-123 --comments`.
- **Read the raw document**: `rata issue show HARB-123 --json --no-comments`.
- **Create an issue**: `rata issue create --title "..." --body "..."` or
  `--body-file -` for a heredoc. Add `--parent HARB-123` for a sub-issue.
- **List issues**: `rata issue list --state Todo --limit 100` with `--team`,
  `--parent`, `--label`, `--assignee`, or `--unblocked` filters.
- **Comment on an issue**: `rata issue comment HARB-123 --body "..."`.
- **Apply / remove labels**: `rata issue label add HARB-123 ready-for-agent` /
  `rata issue label remove HARB-123 ready-for-agent`.
- **Move state**: `rata issue update HARB-123 --state "In Progress"` or
  `rata issue close HARB-123`.
- **Assign**: `rata issue assign HARB-123 me`.
- **Blocking**: `rata issue link HARB-124 --blocked-by HARB-123`. The blocked
  issue is unblocked when every blocker is completed. Use `--blocks` for the
  inverse edge and `--related` for a non-blocking link.
- **Frontier**: `rata issue list --parent HARB-123 --unblocked --unassigned
  --sort priority`; first in map order wins.
- **Claim**: `rata issue assign HARB-123 me`, the session's first write.
- **Resolve**: `rata issue comment HARB-123 --body "<answer>"`, then
  `rata issue close HARB-123`, then append a context pointer to the map.

`rata status` prints the repository, workspace, team, and viewer that `rata`
uses. Run it from inside the clone.

## Pull requests as a triage surface

**PRs as a request surface: no.**

Issues describe the work; PRs deliver it. A PR body names its Linear issue with
`Closes HARB-123` or `Part of HARB-123`.

When a T3 Code thread creates or picks up a PR, it registers the PR on the thread
with `link_pull_request` and the full PR URL. For a stack, register every layer.
PRs created through `gh`, `gh stack`, or another CLI still need that registration
call. A delegated child task returns the PR URL, head SHA, and check state to its
parent instead of watching the PR itself.

## When a skill says "publish to the issue tracker"

Create a Linear issue.

## When a skill says "fetch the relevant ticket"

Read it as in **Read an issue** above.

## Wayfinding operations

Used by `/wayfinder`. The **map** is one Linear issue with **child** issues as
tickets.

- **Map**: one issue labelled `wayfinder:map`, holding the Notes /
  Decisions-so-far / Fog body.
- **Child ticket**: an issue with `--parent <map>`. Labels:
  `wayfinder:<type>` (`research`/`prototype`/`grilling`/`task`). Once claimed,
  the ticket is assigned to the driving dev.
- **Blocking**: Linear issue relations, the canonical, UI-visible
  representation. Add an edge with `rata issue link <child> --blocked-by
  <blocker>`. A ticket is unblocked when every blocker is completed.
- **Frontier query**: `rata issue list --parent <map> --unblocked --unassigned --sort priority`;
  first in map order wins.
- **Claim**: `rata issue assign <child> me`, the session's first write.
- **Resolve**: `rata issue comment <child> --body "<answer>"`, then
  `rata issue close <child>`, then append a context pointer (gist + link) to the
  map's Decisions-so-far.
