---
name: wiq
description: Use this skill when the user asks about their WrestlingIQ data — rosters, attendance, check-ins, paid sessions and registrations, the prospects/leads pipeline, financial metrics, reports, USAW/AAU memberships, fundraising, or online store orders. The `wiq` CLI provides read-only access to /api/v1 via personal access tokens. Recognize phrasings like "how is our pipeline?", "who came to practice this week?", "show me the roster", "what's our MRR?", "which kids need USAW renewal?", or anything that maps to a wrestling club's admin workflows.
---

# WrestlingIQ CLI Skill

`wiq` is a read-only Ruby CLI for WrestlingIQ data, designed to be driven
by both humans and AI agents. It hits `/api/v1` using per-user personal
access tokens (PATs). This skill orients you to its shape; the CLI itself
is the source of truth for what's available right now.

## Bootstrap (always do this first)

Three calls give you the entire usable surface:

```bash
wiq doctor               # Confirms reach, identity, and which team you're scoped to
wiq commands             # JSON dump of every command, option, enum (42 KB; cache this)
wiq workflows list       # 14 curated multi-step recipes by category
```

Run these BEFORE inventing commands. The `wiq commands` output is
authoritative — if it doesn't appear there, it doesn't exist in this
build of the CLI.

## Three core surfaces

**`wiq commands`** — flat machine-readable JSON tree of the CLI. Use this
when you need to know what commands exist, what options they take, what
enums are valid. Cache the output in your context; it doesn't change
within a session.

**`wiq workflows`** — named recipes for common questions. Each workflow
has a structured `parameters` list, a `recipe` of command strings with
`<placeholder>` and `[--flag <name>]` substitutions, an `admin_only`
flag, and notes. Map the user's natural-language question to a workflow
when one fits; fall back to composing commands otherwise.

**`wiq reports types`** — curated allowlist of WIQ's 36 report types with
`recommended:` / `admin_only:` / `prefer:` / `notes:` / `example:`
metadata. When a user asks for "an attendance report" or "a finance
report", check this list first — the WIQ team has marked the right pick
per situation.

## Auth model (load-bearing)

- **PATs are bound to a single profile at mint time.** A user with
  CoachProfile + ParentProfile on different teams mints a separate token
  per role. The CLI does not switch profiles at runtime.
- **Everything is gated by the bound profile's permissions.** Parent or
  wrestler PATs cannot run reports (`enforce_pat_restrictions` returns 403
  with body `"Personal access tokens are read-only..."` — reports is the
  one write currently on the PAT allowlist).
- **The 9 finance reports require `admin?`.** They're flagged
  `admin_only: true` in `wiq reports types`. Workflows that submit them
  carry the same flag. Non-admin coach PATs 403 on these.
- **`elite` and `payments_enabled` are NOT API gates.** They're team
  attributes that affect UI tab rendering only. Ignore them when
  reasoning about API access.

## Multi-club (alias mechanic)

A single user may have PATs for multiple clubs on the same host
(`www.wrestlingiq.com`). The CLI stores them by `host → alias` in
`~/.config/wiq/credentials.json`:

```bash
wiq auth list                          # See all stored credentials
wiq auth status                        # Resolved alias + bound profile
wiq --as westside rosters list         # Use a specific alias
WIQ_ALIAS=westside wiq events list     # Same via env var
```

Resolution chain: `--as` flag → `WIQ_ALIAS` env → `.wiq/config.json` →
sole alias for host → literal `"default"`. Ambiguous-alias errors
include a list of available aliases in the `hint:` field.

## Output modes

| Mode | When it kicks in |
| --- | --- |
| `--json` | Full envelope: `{ok, data, summary, breadcrumbs, meta}`. Best for agents needing context. |
| `--agent` | Bare `data` as JSON, no envelope, no prompts. Best for headless piping. |
| (default) | Pretty JSON when stdout is a TTY; otherwise bare JSON (same as `--agent`). |

The envelope's `breadcrumbs` array suggests obvious next-step commands —
read it when deciding what to do after a response.

## Error model

All errors come back as a stable JSON envelope on stderr with a
non-zero exit code:

```json
{ "ok": false, "error": "...", "code": "...", "hint": "...", "details": ... }
```

Common codes and the right response:

| `code` | Meaning | What to do |
| --- | --- | --- |
| `host_unset` | No host configured (unusual; production is the default) | `wiq auth login` |
| `not_authenticated` | No PAT stored for the resolved host | `wiq auth login` |
| `ambiguous_alias` | Multiple aliases stored, none "default" | Pass `--as <alias>` (hint lists choices) |
| `alias_not_found` | `--as` named a slot that doesn't exist | Check `wiq auth list` |
| `unauthorized` (401) | Token rejected by server | Re-login; could be revoked |
| `forbidden` (403) | Pundit denial (often admin gate on a finance report) | Check the report's `admin_only:` flag in `wiq reports types` |
| `not_found` (404) | Resource doesn't exist for this profile | Confirm the id; cross-team enumeration returns 404 to avoid leaking existence |
| `validation_failed` (422) | Server-side input rejection | Read `details` for per-field messages |
| `rate_limited` (429) | 100 req / 3 sec per IP exceeded | Back off |
| `season_not_found` | `--season <year>` matched zero paid sessions | `wiq paid_sessions list` to see configured periods |
| `report_failed` | The report ran but errored server-side | Inspect `details` (the report's result jsonb) |
| `report_timeout` | Polling exceeded `--timeout` | Re-run with longer `--timeout` or check later with `wiq reports show <id>` |

## Pagination

Index endpoints (`wiq rosters list`, `wiq events list`, etc.) page at 30
per page by default. The CLI surfaces this in two ways:

- Without `--all`: returns page 1 only. The envelope `meta` block carries
  `total` (server-side total record count).
- With `--all`: follows `Link: rel=next` until exhausted. Required when
  doing CLI-side filtering (`--season`, `--site` if it ever lands) since
  filters apply *after* the fetch.

The server's `TotalCount` header is non-standard capitalization (not
`X-Total-Count`); the CLI handles this internally.

## Reports — choosing the right type

Use `wiq reports types` as the decision matrix. Three guidelines:

1. **`recommended: true` entries are the WIQ-blessed picks.** When a
   user's question matches multiple reports, prefer recommended ones
   unless they specifically asked for a non-recommended variant.
2. **`recommended: false` with `prefer:` lists alternatives.** Example:
   `PracticeAttendanceReport` is deprecated → use `CheckInSummaryReport`
   or `CheckInFeedReport` instead.
3. **`admin_only: true` reports require `admin?` permission.** If the
   PAT isn't admin, the submit returns 403. Check the bound profile's
   permission level before suggesting an admin report.

Key reports an agent should know by heart:

- **`CheckInSummaryReport`** — "How many practices did each wrestler
  attend?" (one row per wrestler, totals).
- **`CheckInFeedReport`** — "Who came today?" (one row per check-in).
- **`ChurnRiskReport`** — Active subscribers who haven't checked in
  within N days (7, 14, 30, 60, 90). Requires `--days-threshold`.
- **`RosterReport`** — Roster snapshot with optional custom columns via
  `--append-properties <q_ids>`. Discover ids via `wiq registrations questions`.
- **`LastPracticeAttendedReport`** — "Who hasn't been to practice in a
  while?"
- **`PaidSessionAccountingReport`** (admin_only) — Line-item charges for
  a paid session.

For anything else, `wiq reports types` is faster than guessing.

## Reports — polling

Submit + poll is the API's canonical async pattern:

```bash
wiq reports run <Type> --start <date> --end <date> [args]
# Submits, then polls every 2s (backoff to 30s cap) until ready.
# Default timeout 5 min; --timeout overrides.
```

`--no-wait` returns immediately after submit; poll later with
`wiq reports show <id> --wait`. Status values: `requested → queued →
processing → ready` (terminal) | `failed` (terminal). `result` is the
type-specific jsonb payload.

## Common gotchas

- **`roster_id=0` = "all rosters"** in report args. UI convention; if
  you want all rosters, pass `--roster 0` explicitly. Reports always
  accept it.
- **`paid_session_id=0` = "all sessions"** is accepted by ONE report
  only: `UsawExportReport`. Anywhere else, `0` causes a 404 on
  `PaidSession.find(0)`.
- **`--season <year>` is CLI-side filtering, not a server param.** It
  resolves to paid_session ids whose date range overlaps the calendar
  year, then filters client-side. There's no first-class Season entity
  in WIQ.
- **`Event.location` is free-text and not filterable.** No `--site` or
  `--location` flag exists yet. A structured location concept is on the
  WIQ roadmap.
- **Index responses are wrapped.** Every `/api/v1` index returns
  `{"<resource>": [...]}` — the CLI unwraps internally, but if you ever
  hit the API directly remember to unwrap.
- **Custom registration columns are `RosterReport`-only.** The
  `--append-properties` flag is accepted by other reports but only
  RosterReport's model code reads it.
- **`days_threshold` for `ChurnRiskReport`** accepts only `7, 14, 30,
  60, 90`. Any other value silently falls back to 30 server-side.
- **`wrestler_id` vs `wrestler_profile_id`.** The API uses both
  interchangeably in different endpoints — the CLI normalizes, but if
  you're constructing URLs yourself, expect the inconsistency.

## What's NOT available (yet)

The CLI is read-only by design except for report submission. You
cannot via this CLI:

- Create/edit prospects, families, notes, check-ins, events, paid
  sessions, rosters, or any other resource
- Mint, list, or revoke PATs (use the web UI at
  `<host>/settings/personal_access_tokens`)
- Mark attendance, advance prospect stages, log contact notes
- Trigger event-change notifications or roster re-sync jobs

If the user asks for a write operation, tell them it's not yet exposed
and point them at the WIQ web UI for now.

## When to compose vs run a workflow

- **Run a workflow** when the user's question matches one closely. They
  encode WIQ's recommended patterns and reduce drift risk.
- **Compose ad-hoc** when the user wants something workflow-shaped but
  with twists (date range, roster scope, additional filtering).
  Reference the workflow's recipe as a template, then adapt.
- **Never** compose finance commands without first checking
  `wiq auth status` to confirm `admin?` permission — saves the agent
  from running into avoidable 403s mid-sequence.
