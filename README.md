# gh-pr-monitor

A GitHub CLI extension that polls a single PR and reports every actionable event, enabling automated fix/review loops to react to changes in real time.

Unlike `gh pr checks --watch`, which only tracks CI checks, `gh pr-monitor` detects all significant PR changes: CI check pass/fail, new/updated/deleted PR reviews (approve/changes-requested/comment), new/updated/deleted comments (top-level and inline/diff), reviewer/team requests added, PR description edits, and mergeable-state changes (conflicts, out-of-date branch).

## Install

```bash
gh extension install aanojima/gh-pr-monitor
```

Requires: `gh` CLI (authenticated via `gh auth login`) and `jq` (JSON processor).

## Usage

```bash
# Watch the current branch's PR (must be in a Git repo with a tracking branch)
gh pr-monitor

# Watch a specific PR number in the current repo
gh pr-monitor 42

# Watch a PR in another repo
gh pr-monitor 42 --repo owner/repo

# Watch via PR URL or branch name
gh pr-monitor https://github.com/owner/repo/pull/42
gh pr-monitor main

# Single status snapshot (no polling loop)
gh pr-monitor --once

# Poll every 30 seconds instead of default 15
gh pr-monitor --interval 30

# Output machine-readable JSON (one object per line) for agent consumption
gh pr-monitor --json | jq .

# Stop polling once PR is ready to merge
gh pr-monitor --until-mergeable

# Combine options
gh pr-monitor 42 --repo owner/repo --json --until-mergeable
```

## Event Types

Each poll reports changes as one of these event types:

- **comment** — new or edited top-level PR comment
- **comment_deleted** — top-level PR comment removed
- **review** — new or updated PR review (APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED, PENDING)
- **review_deleted** — review removed (rare — GitHub only allows deleting a PENDING review directly, but a review can also disappear as a side effect of deleting its last remaining comment)
- **review_request** — reviewer or team added to review queue
- **inline_comment** — new or edited diff/review comment on a specific file and line
- **inline_comment_deleted** — diff/review comment removed
- **check** — status check or CI job changed state (e.g., PENDING → COMPLETED, conclusion updated)
- **mergeable** — PR mergeable state or merge status changed (conflicts, out-of-date branch, etc.)
- **description** — the PR's description (body) was edited

## Output Formats

### Human-readable (default)

```
watching PR #42 (https://github.com/owner/repo/pull/42), polling every 15s ...
[14:23:45] review by @alice: APPROVED
[14:23:46] check "build": SUCCESS
[14:24:01] comment by @bob: Looks good to me!
```

### JSON (--json)

One compact JSON object per event, suitable for piping to agents or log parsers:

```json
{"type":"review","time":"2025-09-05T14:23:45Z","data":{"id":"123","author":{"login":"alice"},"state":"APPROVED"}}
{"type":"check","time":"2025-09-05T14:23:46Z","data":{"name":"build","conclusion":"SUCCESS"}}
```

## Behavior Notes

- **Baseline poll**: The first poll establishes a baseline. Events are only emitted when changes are detected on subsequent polls.
- **--once mode**: Prints a one-line summary of current PR state without entering a polling loop.
- **--until-mergeable**: Exits (status 0) once the PR is approved, all checks pass, and no merge conflicts exist. Combined with `--once`, it instead reports readiness via exit code (0 = ready, 1 = not yet) without polling — useful as `gh pr-monitor --once --until-mergeable && gh pr merge`.
- **Closed/merged PRs**: The watch loop exits on its own once a PR leaves the `OPEN` state — there's nothing further to report.
- **Rate limits**: Very short `--interval` values may hit GitHub API rate limits. Default 15s is recommended.
- **Authentication**: Requires `gh auth login` to have been run; this extension uses your authenticated `gh` session.

## Known Limitations

- **`--until-mergeable` on repos without required reviews**: GitHub only sets `reviewDecision` to `APPROVED` when the base branch has a review-requirement rule. On a repo without one, an approving review never flips `reviewDecision`, so `--until-mergeable` will wait on review approval indefinitely even after someone approves. Everything else (CI status, merge conflicts, closed/merged detection) still works correctly in that case.
- **Very large comment bodies**: prev/curr snapshots are passed to `jq` over stdin (not argv) specifically to avoid OS argument-size limits, but pathological cases (many megabytes of comments in a single PR) could still be slow to diff every poll.

## License

MIT
