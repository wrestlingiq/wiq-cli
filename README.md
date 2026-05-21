# wiq-cli

Read-only command-line interface for [WrestlingIQ](https://www.wrestlingiq.com).
Designed to be driven by both humans and AI agents (Claude Code, Cursor,
etc.) via per-user personal access tokens (PATs).

## Install

```bash
gem install wiq-cli
```

Requires Ruby 3.1+.

## Bootstrap

```bash
wiq auth login            # Paste a PAT minted at <host>/settings/personal_access_tokens
wiq doctor                # Verify host, alias, token, and bound profile
wiq commands              # Print the full command tree as JSON
```

Production (`https://www.wrestlingiq.com`) is the default host — for
staging/testing use `--host` or `WIQ_HOST`.

## Common things

```bash
wiq rosters list                                            # Browse rosters
wiq prospects summary                                       # Pipeline dashboard
wiq events list --start 2026-05-01 --end 2026-05-31         # Calendar
wiq reports run CheckInSummaryReport --start … --end …      # Attendance
wiq workflows list                                          # Curated multi-step recipes
wiq reports types                                           # 36 report types w/ recommendations
```

## Multiple clubs

Tokens for different WIQ accounts on the same host live in separate
aliased slots:

```bash
wiq auth login                          # First login → slot "default"
wiq auth login --as westside            # Second account → slot "westside"
wiq --as westside rosters list          # Run a command against the second slot
```

Full mechanic + resolution chain documented in `docs/wiq_api_notes.md`.

## Claude Code integration

```bash
wiq setup claude                        # Installs the wiq skill to ~/.claude/skills/wiq/
wiq setup claude --project              # Per-project install (./.claude/skills/wiq/)
wiq setup claude --print                # Inspect the bundled SKILL.md
```

Claude Code auto-detects the skill within the current session — no
restart needed. The skill teaches Claude how to orient itself in the
CLI surface; pair it with a PAT and Claude can answer most club-admin
questions directly.

## Where things live

- [`docs/wiq_api_notes.md`](docs/wiq_api_notes.md) — auth model, response shapes, gotchas, what the CLI maps to in `/api/v1`
- [`docs/deferred.md`](docs/deferred.md) — work explicitly out of scope for v1 + the rationale
- [`share/skills/wiq/SKILL.md`](share/skills/wiq/SKILL.md) — the bundled Claude Code skill content

## Output modes

| Flag | Output |
| --- | --- |
| (default) | Pretty JSON to a TTY, bare JSON when piped |
| `--json` | Full envelope: `{ok, data, summary, breadcrumbs, meta}` |
| `--agent` | Bare `data` as JSON — best for headless agents |

## Status

v1. 27 commands across 12 groups, ~90 RSpec smoke examples. Reads-only
except for report submission (the API's canonical async pattern).
Write commands deferred — see `docs/deferred.md`.

## License

MIT.
