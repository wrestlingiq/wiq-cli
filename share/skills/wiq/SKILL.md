---
name: wiq
description: Use this skill when the user asks about their WrestlingIQ data — rosters, attendance, check-ins, paid sessions and registrations, the prospects/leads pipeline, financial metrics, reports, USAW/AAU memberships, fundraising, online store orders, or per-location/site breakdowns for multi-gym clubs. The `wiq` CLI provides read-only access to /api/v1 via personal access tokens. Recognize phrasings like "how is our pipeline?", "who came to practice this week?", "show me the roster", "what's our MRR?", "which kids need USAW renewal?", "how is the Eastside gym doing?", or anything that maps to a wrestling club's admin workflows.
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

## Rate-limit etiquette

WIQ enforces **100 requests per 3 seconds per source IP** (≈ 33 req/sec).
It's a per-IP throttle, not per-PAT — multi-club aliases on the same
workstation share the budget.

In practice the CLI rarely hits it because:

- Pagination (`--all`) walks pages sequentially, naturally rate-limited
  by request latency (100–500ms round-trip = 2–10 req/sec, well under).
- Report polling backs off exponentially (2s → 30s cap).
- Transient 429s are auto-retried by the Faraday middleware (3 attempts,
  exponential backoff, `Retry-After` honored).

**Agent guidance:** invoke `wiq` commands **sequentially** from scripts.
Don't parallelize a fan-out (e.g. running three `wiq metrics show`
calls at once) — the per-IP budget is shared across every concurrent
process. If you see `code: "rate_limited"` after the auto-retries
exhaust, treat it as backpressure: wait ~3 seconds, then continue
sequentially. It's not a bug; you're just moving faster than the
server wants you to.

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
  The default (row/CSV) shape carries the **"Added to roster at"** column
  (`roster_memberships.created_at` — when a wrestler landed on that roster,
  NOT their registration date). Requires a specific `--roster <id>` (id > 0);
  it's blank for `--roster 0`. `--v1` returns fuller per-wrestler objects but
  drops that column.
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

**Result shape — vrow default (`--v1` escape hatch).** The CLI requests
the row/CSV shape (`version: "vrow"`) by default: `result.rows.objects`
with the first row being the header — identical to the web "Download"
buttons, and a uniform shape across every report type. Most reports emit
only this shape and ignore the version. Only `RosterReport`, `UsawReport`,
and `PaidSessionAccountingReport` also support a legacy v1 shape
(structured JSON objects) via `--v1`, which returns fuller per-wrestler
data but drops RosterReport's **"Added to roster at"** column. If a user
asks when a wrestler joined a roster (e.g. roster-join → first-practice
latency), `wiq reports run RosterReport --roster <id>` is the answer — the
join date is in the default output.

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
- **Legacy free-text `Event.location` vs structured locations.** Old
  events carry a free-text `location` string; the serialized `location`
  field is the display form (structured Location name/address when
  `location_id` is set, else the legacy text). `--location` filters only
  match the structured `location_id` — events, rosters, and paid sessions
  with NO location set are excluded from filtered listings, so an empty
  filtered result doesn't mean "nothing happened", it may mean "nothing
  is stamped with that location yet."
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

## Integer-backed enums (Ransack gotcha for future write paths)

Some WIQ models back enums with integers (Rails default). Ransack 4.x
does NOT translate enum strings to integers on those columns — sending
`q[status_eq]=failed` against an integer column silently drops the
predicate and returns every row, not zero rows.

The CLI translates internally for the surfaces it exposes
(`wiq charges list --status`, `wiq check_ins event --status`). If you
construct ad-hoc `q[...]` filters via `curl` or a future surface, watch
for this. Known integer-enum columns the CLI touches today:

| Model | Field | Values |
| --- | --- | --- |
| Charge | status | successful (0), failed (1) |
| CheckIn | status | unknown (0), present (1), absent (2), excused (3), unexcused (4), late (5), injured (6), other (7) |
| WrestlerProfile | gender | male (0), female (1), other (2) |
| PaidSession | usaw_override / aau_override | disabled (0), optional (1), require_id_and_expires (2), require_all (3) |

String columns (Prospect.stage, WrestlerProfile.profile_type / academic_class)
do NOT have this issue — Ransack matches the string directly.

## Payment debugging

For "did Johnny pay X?" / "what's failing right now?" / "is this family's
subscription healthy?" — use the charges surface (admin coach PAT only):

```bash
wiq charges list --status failed --since 2026-04-01
wiq charges list --billing-profile <id> --since 2026-04-01 --all
wiq billing_profiles show <parent_profile_id> --profile-type ParentProfile
```

**Critical: a failed charge alone is NEVER actionable.** Stripe/Justifi
retry subscriptions automatically and customers re-enter cards after
declines, so most failures resolve themselves silently. Before
flagging anything as needing follow-up, cross-check that no successful
charge for the same `(billing_profile_id, chargeable_id,
chargeable_type)` tuple exists AFTER the failure's `created_at`. The
canonical pattern is in `wiq workflows show failed-payments-recent`.

To go from a wrestler name to a billing_profile_id:

```bash
wiq wrestlers list --query "Johnny Smith"               # find wrestler_id
wiq wrestlers show <wrestler_id>                        # find parent_profile_id
wiq billing_profiles show <parent_id> --profile-type ParentProfile  # billing_profile_id
wiq charges list --billing-profile <bp_id>              # their payment history
```

WrestlerProfile cannot have billing profiles directly — always walk
through a parent.

## ID discovery

### Disambiguating "who is X?"

WIQ tracks people in three states. When the user asks about a person by
name (e.g., "show me Johnny"), decide which scope to search FIRST,
based on context:

| If recent context is about… | Search this |
| --- | --- |
| Leads / pipeline / trials / "potential new kid" | `wiq prospect_families list --query <name>` |
| Active club members / attendance / rosters / subscriptions | `wiq wrestlers list --query <name>` |
| Former members / graduates | `wiq wrestlers list --query <name> --profile-type alumnus` |
| Truly ambiguous, no prior context | **Ask the user.** Don't fan out across both. |

Don't default to wrestlers because it's listed first alphabetically —
that wastes a call when the user is clearly asking about a lead.

### How `--query` actually matches

- **`wiq wrestlers list --query`** — name search (first/last) against
  active WrestlerProfile rows on the team.
- **`wiq prospect_families list --query`** — searches BOTH family
  contact (name, email, phone — digits stripped for phone match) AND
  child first/last names via a subquery. A "Johnny" search matches a
  parent named Johnny OR a child named Johnny; check
  `child_first_name` on the embedded prospects array to tell which.
- **`wiq prospects list --query`** — same scope as families above, but
  currently returns HTTP 500 due to a server-side ambiguous-column bug
  (tracked in `docs/deferred.md`). Use `prospect_families list --query`
  instead until the WIQ-app fix ships.

### Wrestlers-specific filters

```bash
wiq wrestlers list --query "Jane Smith"
wiq wrestlers list --last-name Smith
wiq wrestlers list --roster 42 --weight-class 132
```

Narrow surface on purpose: default page size 20, no `--all` flag.
For exhaustive exports go through `wiq reports run RosterReport`
(with `--append-properties` for custom columns) or
`wiq reports run FullExportWrestlerReport`. The list defaults to
`profile_type=teammate` (matching the WIQ web UI default); pass
`--profile-type alumnus|guest|all` to widen.

For "can this family be reached, and how?" questions, add
`--expand notification_preferences` to `wrestlers list|show` or
`parents list|show`. Each row gains `wiq_app_installed` plus a
`notification_preferences` object (`email`, `sms`, `push`,
`push_user_pref`; `null` means no explicit preference recorded). Coach
PATs only — with a parent/wrestler token the server returns 200 with
the fields silently absent, so a missing field means "check the
token's profile type", not "API bug".

### Parents

`wiq parents list [--query <name>] [--first-name X] [--last-name Y]`
and `wiq parents show <id>` — slim payload (id, user_id, names) over
the team's teammate parents. There are no wrestler refs on a parent
row; to walk a family, start from the wrestler side
(`wiq wrestlers show <id>` embeds parent refs). Main uses: parent-first
ID discovery for `wiq billing_profiles show <id> --profile-type
ParentProfile`, and the notification-reachability expand above.

## Locations (multi-site clubs)

WIQ has a structured Location model (name + street address, per team).
Multi-gym clubs stamp rosters, events, and paid sessions with a
location; single-site clubs usually have none, and every `--location`
flag is simply irrelevant for them.

Discover ids first — this is the anchor for everything below:

```bash
wiq locations list                     # id, name, address, archived
wiq locations list --include-archived
```

Then scope any of these surfaces:

| Command | Flag | Semantics |
| --- | --- | --- |
| `wiq rosters list` | `--location <id>` | Rosters stamped with that location (`q[location_id_eq]`) |
| `wiq events list` | `--location <id> [<id>...]` | Events at those locations (repeatable; unset-location events excluded) |
| `wiq paid_sessions list` | `--location <id>` | Sessions stamped with that location |
| `wiq wrestlers list` | `--location <id>` | Wrestlers on ANY roster at that location; composes with other filters |
| `wiq metrics show <name>` | `--location <id>` | Per-location finance metrics (the payment-dashboard filter) |
| `wiq reports run <Type>` | `--location <id>` | Scopes the wrestler set for the 13 location-aware report types |

Three gotchas an agent must know:

1. **Reports precedence:** a specific `--roster <id>` (> 0) WINS over
   `--location` in report args. Pass `--location` alone (or with
   `--roster 0`) to get location scoping. A wrestler on multiple rosters
   at the location collapses to one row; RosterReport's "Added to roster
   at" becomes their EARLIEST membership across that location's rosters.
   `CheckInSummaryReport` / `CheckInFeedReport` ignore both args
   entirely (always team-wide) — use `CheckInReport --location <id>` for
   location-scoped attendance.
2. **Metrics fail silent, not loud:** an unknown or foreign `--location`
   id on `wiq metrics show` silently falls back to ALL locations —
   team-wide numbers, no error. Verify the id against
   `wiq locations list` before quoting per-site revenue to the user.
3. **Nothing is auto-stamped retroactively.** Filters only match records
   whose `location_id` is set. Empty filtered results on a club that
   just adopted locations usually mean unstamped data, not zero
   activity. Rosters/events/paid_sessions embed their `location` object
   (or null) in list payloads, so you can check coverage cheaply.

## What's NOT available (yet)

The CLI is read-only by design except for report submission. You
cannot via this CLI:

- Create/edit prospects, families, notes, check-ins, events, paid
  sessions, rosters, locations, or any other resource
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
