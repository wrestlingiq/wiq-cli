# WIQ API Notes for the CLI

Reference for what the CLI can assume about `/api/v1`. The WIQ Rails app uses
**jbuilder partials** as the source of truth for response shapes; the
committed OpenAPI spec at `wrestling/doc/openapi.yaml` is out of date (last
regen ~1 year ago, partial coverage). Don't trust the YAML — read jbuilders
or rerun `OPENAPI=1 bundle exec rspec` against current specs before relying
on a shape.

Citations below point at the WIQ PAT worktree
(`/Users/msencenb/conductor/wrestling/.conductor/beirut`,
branch `msencenb/wiq-agent-cli-research`, commits `00d1dbf08` PAT,
`f4006b7dd` audit fixes). PAT support is in that branch and not yet in
`develop`.

## Host + alias configuration (no hard-coded URLs)

The CLI is going to be public source code. It must **not** ship a default
that points at WIQ infrastructure URLs in committed code.

The credentials store at `~/.config/wiq/credentials.json` (mode 0600) is a
two-level map: `host → alias → entry`. This is what makes the multi-club
case work — a single user with PATs for several clubs on the same host
stores each PAT under a different alias.

```json
{
  "https://www.wrestlingiq.com": {
    "default":  { "token": "...", "profile": { "team_name": "Springfield" } },
    "westside": { "token": "...", "profile": { "team_name": "Westside" } }
  }
}
```

**Host resolution order:**
1. `--host <url>` CLI flag.
2. `WIQ_HOST` env var.
3. `host` key in `.wiq/config.json` (walked from cwd upward).
4. Sole host in the credentials store (if exactly one).
5. **Production default** (`https://www.wrestlingiq.com`, hardcoded as
   `Wiq::Config::PRODUCTION_HOST`). The 99% case is production; testing
   against staging requires an explicit override via flag/env/config.

**Alias resolution order** (only consulted once the host is known):
1. `--as <alias>` CLI flag.
2. `WIQ_ALIAS` env var.
3. `alias` key in `.wiq/config.json`.
4. Sole alias for this host in the credentials store.
5. Literal `"default"` alias if it exists.
6. Otherwise unresolved → commands needing a token fail with
   `code: "ambiguous_alias"` and a hint listing what's stored.

**Token resolution:**
1. `WIQ_TOKEN` env var (highest priority — direct bypass of the store).
2. `Credentials[host][alias].token`.

Auth surface:

- `wiq auth login [--as <alias>] [--force]` — stores into the slot. If
  `--as` is omitted: uses `"default"` if free, otherwise refuses with
  `code: "alias_required"` and points at `--as`.
- `wiq auth status [--as <alias>]` — resolves the chain and shows which
  source won, plus the bound profile (display_name @ team_name (type)).
  The live `/api/v1/personal_access_tokens` probe is best-effort; failures
  are reported in `live_error` rather than aborting the command.
- `wiq auth logout [--as <alias>]` — removes one slot.
- `wiq auth list` — dumps every stored credential (token_prefix only, no
  raw tokens) across all hosts and aliases.

Multi-club mechanics in practice:

```
# First club — stored under "default" automatically.
wiq auth login --host https://www.wrestlingiq.com --token wiq_pat_aaa...

# Second club — explicit alias required because "default" is taken.
wiq auth login --as westside --token wiq_pat_bbb...

# Run a command against the non-default club.
wiq --as westside rosters list
WIQ_ALIAS=westside wiq rosters list
echo '{"alias":"westside"}' > .wiq/config.json   # pins the cwd to westside
```

Routes are constrained `format: "json"` (`config/routes.rb` ll. 92, 153) —
send `Accept: application/json` and append `.json` to be safe.

## Authentication

PATs are the only auth mode the CLI uses.

- Header: `Authorization: Bearer wiq_pat_<32 lowercase hex chars>` (token
  length 40; the `wiq_pat_` prefix is literal and case-sensitive).
- The `Bearer` scheme is matched case-insensitively server-side
  (RFC 7235 conformance), with `\s+` between scheme and token. Send
  `Bearer wiq_pat_…` with a single space and you're fine.
- Server logic (`app/controllers/concerns/token_authenticable.rb`):
  - Parses the header with `/\ABearer\s+(.+)\z/i` and strips whitespace.
  - If the token starts with `wiq_pat_`, looks up its SHA-256 digest in
    `personal_access_tokens` (scoped `revoked_at IS NULL`). On hit,
    stashes `pat.profile` on the request and returns `pat.user`. On
    miss, returns `nil` → 401 `{"errors":["Unauthorized"]}`.
  - Otherwise falls through to a legacy `User.find_by(auth_token: …)`
    lookup (mobile webview only — the CLI never sees this path).
  - `last_used_at` is debounced via a Sidekiq job (5-minute window). Don't
    use it for sub-minute liveness signals.
- PATs inherit the full permission set of their bound profile. No scopes.

### PATs are profile-bound (this matters)

A WIQ user can carry multiple profiles — `CoachProfile`, `ParentProfile`,
`WrestlerProfile` — sometimes on different teams. Authorization is keyed on
`current_profile`, not `current_user`. **Each PAT is bound to one specific
profile at creation time**, and that binding is immutable. The token *is*
the profile context.

Implications for the CLI:

- **Do not send `X-WIQ-Profile-Id` / `X-WIQ-Profile-Type` headers.** They
  are ignored on PAT-authenticated requests (`@authenticated_pat_profile`
  short-circuits the header path in `token_authenticable.rb`).
- No `--profile` flag, no profile-switching command, no stored profile
  state on the CLI side. The customer mints one PAT per role.
- If a customer switches profiles in the web UI, their cron behavior is
  unaffected.

### Identity via `GET /api/v1/personal_access_tokens`

This endpoint doubles as the "who am I" probe. Response is wrapped:

```json
{
  "personal_access_tokens": [
    {
      "id": 42,
      "name": "Monthly reporting cron",
      "token_prefix": "wiq_pat_a1",
      "created_at": "2026-05-11T12:00:00Z",
      "updated_at": "2026-05-11T12:00:00Z",
      "last_used_at": "2026-05-11T14:30:00Z",
      "revoked_at": null,
      "profile": {
        "id": 17,
        "type": "CoachProfile",
        "display_name": "Matt Sencenbaugh",
        "team_name": "Springfield Wrestling"
      }
    }
  ]
}
```

The calling PAT is always present in this list (the row whose
`token_prefix` matches the first 12 chars of the local plaintext). The
embedded `profile` object gives the CLI enough identity info that **no
separate `/api/v1/me` endpoint is needed.** What was a follow-up
in the previous draft of this doc is closed.

CLI behavior for `wiq auth login` and `wiq auth status`:

1. `GET /api/v1/personal_access_tokens` — confirms 200 (auth probe) and
   provides identity in the same call.
2. Find the row whose `token_prefix` matches the local token's prefix.
3. Store `{host, token, token_prefix, name, profile}` in
   `~/.config/wiq/credentials.json` (mode 0600).
4. `wiq auth status` displays
   `<display_name> @ <team_name> (<profile_type>)`.

## Index responses are wrapped (not bare arrays)

Every `/api/v1` index endpoint wraps its records under the resource name:

```json
{ "rosters":               [ { "id": 1, "name": "Varsity" }, ... ] }
{ "events":                [ ... ] }
{ "paid_sessions":         [ ... ] }
{ "reports":               [ ... ] }
{ "check_ins":             [ ... ] }
{ "personal_access_tokens":[ ... ] }
{ "registration_questions":[ ... ] }
{ "registration_answers":  [ ... ] }
```

Confirmed from the jbuilders (e.g. `app/views/api/v1/rosters/index.json.jbuilder`
does `json.rosters @rosters do |r| ... end`). **Show**, **create**, and
**update** responses are NOT wrapped — they return the resource object at
the top level. Metrics endpoints follow a third shape
(`{ metrics: {...}, charts: [...] }`); see the dashboard section.

The CLI's HTTP client takes the resource-name key as an argument to
`paginate` / `collect_all` and unwraps before yielding records — index
callers must specify it explicitly.

## Pagination contract

`app/controllers/concerns/pageable.rb`.

- Query: `?page=<n>&per_page=<m>`. Defaults `page=1`, `per_page=30`. No
  documented `per_page` ceiling; treat 100 as safe.
- Response headers:
  - `Link` — RFC 5988-ish, comma-separated, e.g.
    `<https://host/api/v1/rosters?page=2>; rel="next", <...>; rel="last"`.
    Only `rel=first|last|next|prev` are emitted; `prev`/`first` omitted on
    page 1, `next`/`last` on the last. Single-page responses emit no rels.
  - `TotalCount` — bare integer total record count for the filtered query.
    **Note the unusual capitalized name (not `X-Total-Count`).** Faraday's
    case-insensitive access handles it; remember when writing `--all` logic.
- Filters via `filter_and_page`:
  - `?query=<string>` — legacy substring search via per-model `.search`
    scope (mostly name-based).
  - `?q[<attr>_<predicate>]=<val>` — Ransack. Each model has a
    `ransackable_attributes` allowlist; an unlisted attribute is silently
    ignored by Ransack. `q[s]=<attr>+<direction>` sets sort
    (default `id desc`).

Implementation note: implement `--all` by following `rel=next` until
absent. Do not divide `TotalCount / per_page` and parallelize — several
endpoints distinct-join and the page count can drift.

## Error response shapes

`app/controllers/concerns/json_api.rb`. All errors come back as
`{"errors": <payload>}`.

| Status | Trigger | Payload shape |
| --- | --- | --- |
| 400 | `Client version expired` (mobile-only; CLI won't trip it) | `{"errors": ["Client version expired"]}` |
| 401 | Missing/invalid/revoked PAT | `{"errors": ["Unauthorized"]}` |
| 403 | Pundit denial | `{"errors": ["Not Authorized To View Content"]}` |
| 404 | `ActiveRecord::RecordNotFound` or explicit | `{"errors": ["Not Found"]}` |
| 422 | `validation_error(@model.errors)` | `{"errors": { "<field>": ["msg", ...], ... }}` — **ActiveModel::Errors hash** |
| 422 | `validation_error(["msg"])` (rare; e.g. roster delete restriction) | `{"errors": ["msg", ...]}` |
| 500 | Fallback | `{"errors": [...]}` |

The CLI error mapper must handle both 422 variants — same key (`errors`)
but value is **either an array of strings or a hash of field→messages**.
Normalize to a flat list (with field prefix when present) for agent output.

There is no `request_id` echoed by the server today; another follow-up to
file with the WIQ team.

## Report polling contract

`app/controllers/api/v1/reports_controller.rb`, `app/models/report.rb`,
`app/models/concerns/queueable.rb`.

- `POST /api/v1/reports`
  - Body: `{ "report": { "type": "<ReportClass>", "version": "v1"|"vrow", "name": "...", "start_at": "YYYY-MM-DD", "end_at": "YYYY-MM-DD", "args": { ... } } }`
  - Permitted `args` keys: `paid_session_id, roster_id, fundraiser_id, online_store_id, event_id, include_archived_roster_tags, append_property_ids[]`.
  - Response: `201 Created` with the full report jbuilder
    (`id, created_at, updated_at, type, processed_at, start_at, end_at, name,
    version, status, result, args`). `status` is `"requested"` momentarily;
    `after_save_commit` flips it to `"queued"` and enqueues `ReportJob`,
    so a follow-up GET will usually see `queued` or later.
- `GET /api/v1/reports/:id` — same payload. Poll this.
- Status state machine (`Queueable`):
  - `requested` → `queued` → `processing` → `ready` (terminal success) or
    `failed` (terminal error). `potential` exists but is unused for reports.
- Completion: `status == "ready"`. `processed_at` and populated `result`
  are corollaries.
- `result` is jsonb, type-specific. Treat as opaque JSON in the CLI;
  pretty-print or write to file.
- `GET /api/v1/reports` — paginated index of completed/known reports for
  the team, policy-scoped.
- CLI polling: start at 2s, exponential backoff to 30s cap, default
  timeout 5 min (`--timeout` override). On `failed`, surface `result`
  (most subclasses stash an error there) and exit non-zero
  (`code: "report_failed"`).

### Report `type` values

All STI subclasses of `Report` in `app/models/`. Club-admin-relevant ones
bolded; the rest exist but aren't on a club-admin's daily path:

`AauExpiredReport, AauExportReport, AauReport, CancelledSubscriptionsReport,
CheckInFeedReport, **CheckInReport**, **CheckInSummaryReport**,
ChurnRiskReport, CurrentlyPausedSubscriptionsReport,
DiscountedSubscriptionsReport, **DonationTransactionReport**,
**EventStatsReport**, ExpiringSubscriptionsReport,
**FullExportWrestlerReport**, **FundraiserAccountingReport**,
**FundraiserSummaryReport**, InProgressRegistrationReport, InviteStatusReport,
**LastPracticeAttendedReport**, **MembershipSummaryReport**,
**OnlineStoreDetailReport**, **OnlineStoreSummaryReport**,
**OverdueRegistrationReport**, **PaidSessionAccountingReport**,
PaidSessionAddOnDetailReport, PaidSessionAddOnSummaryReport,
**PracticeAttendanceReport**, **RecurringDonorReport**, RegistrationAnswerReport,
**RegistrationFinanceSummaryReport**, **RosterReport**, **RosterStatsReport**,
**ScholarshipAuditReport**, SessionRegistrationAnswerReport,
TeamRegistrationRosterReport, UsawExpiredReport, UsawExportReport, UsawReport,
**WinLossReport**, **WrestlersWithoutSubscriptionsReport**`

`wiq reports types` should print descriptions + required args for the
bolded set; users can still pass any type string, but help only documents
the curated list.

## Dashboard / metrics endpoints

`app/controllers/api/v1/metrics_controller.rb`.

All metrics endpoints `authorize :finances, :show?` — only users with the
`finances#show` Pundit grant (typically full-access coaches) can call
them. PATs minted by parents/wrestlers will 403 here.

- Routes (all GET): `/api/v1/metrics/<name>` where `<name>` ∈
  `active_subscribers, category_breakdown_net, charge_avg, charge_count,
  gross_volume, mrr, net_volume, new_subscriptions (alias: new_subscribers),
  cancelled_subscriptions, renewed_subscriptions, revenue_per_subscriber`.
- Query params (uniform across all metrics):
  - `range` — one of `today, 7d, 4w, 3m, 12m, "year to date", custom`. Default `7d`. (Note the literal space in `"year to date"` — URL-encode as `year%20to%20date`.) Unknown values fall back to `7d` silently.
  - `interval_group` — one of `hourly, daily, weekly, monthly`. Default `daily`. Invalid values fall back to `daily` silently.
  - `start_date`, `end_date` (YYYY-MM-DD) — required when `range=custom`. If invalid or missing, server silently downgrades to `range=7d`. CLI should validate before sending.
- Response shape (uniform):
  ```json
  {
    "metrics": {
      "primary_series": [{ "interval": "...", "metric": <number>, ... }],
      "primary_total": <number>,
      "comparison_series": [...],
      "comparison_total": <number>
    },
    "charts": [ /* Highcharts-shaped, ignore in CLI */ ]
  }
  ```
- **All currency values are in integer cents.** Divide by 100 for dollars.
  Applies to `gross_volume, net_volume, charge_avg, mrr, revenue_per_subscriber, category_breakdown_net`.
- `comparison_series` is empty when `range=custom`. For all other ranges,
  it's the prior period of the same length (e.g. `7d` → previous 7 days).
- The `charts[]` blob is server-rendered HTML/Highcharts config; the CLI
  should ignore it entirely and project `metrics.primary_series` /
  `primary_total` for agent output.
- `category_breakdown_net` has a different `metrics.primary_series` row
  shape (`category`, `subcategory`, `detail_category`, `total_net_amount`)
  — special-case it in the formatter.

## Check-ins (attendance)

Two index endpoints + create/update on the event-scoped path.

- `GET /api/v1/events/:event_id/check_ins` —
  `event.check_ins` paginated, sorted `id desc`. Ransackable on
  `created_at, status` (`CheckIn.ransackable_attributes`). Includes
  `registration_answers, event, wrestler_profile`.
- `GET /api/v1/wrestlers/:wrestler_id/check_ins` —
  the wrestler's check-ins across all events; paginated.
- `POST /api/v1/events/:event_id/check_ins` —
  body `{ check_in: { wrestler_profile_id, status, notes } }`. Status is a
  free-text string column (no enum); current UI values are `"checked_in"`,
  `"absent"`, etc. — confirm with the team before exposing creation.
- `PUT /api/v1/events/:event_id/check_ins/:id` — same body.

Check-in jbuilder (`app/views/api/v1/shared/_check_in.json.jbuilder`):
`id, created_at, updated_at, event_id, event_name, notes, status, rosters,
wrestler_profile_id, profile, registration_answers, class_pass_id,
class_pass`.

For attendance analytics, `PracticeAttendanceReport` (date range +
optional `roster_id`) is the right primitive — it aggregates server-side
and is cheaper than paginating raw check-ins. Use the raw endpoints when
the client needs the individual rows (e.g., late-arrival lookups).

## Paid sessions (registration data)

`app/controllers/api/v1/paid_sessions_controller.rb`.

- `GET /api/v1/paid_sessions[?type=...]` — heavy preset-scope filter.
  Recognized `type` values:
  `registerable, guest_registerable, ends_in_future, recurring_registerable,
  recurring, not_recurring, not_recurring_with_archived, not_archived,
  dropin, trial, trial_or_dropin`. Without `type`, returns all team
  paid_sessions.
- Plus Ransack on `name, start_at, end_at, slug, session_type`
  (`PaidSession.ransackable_attributes`).
- `GET /api/v1/paid_sessions/:id` — full payload.
- `POST` / `PUT` — supported (params include `roster_syncers_attributes`,
  `team_registration_divisions_attributes` for nested updates).

Jbuilder embeds `stats` inline:
`good_standing_registrations_count, not_canceled_registrations_count,
overdue_registrations_count, registrations_count,
good_standing_membership_count`. These are server-counted aggregates — a
CLI `paid-sessions list --stats` doesn't need extra calls.

Roster ↔ paid-session linkage runs through `roster_syncers` (joined
in the response). A `RosterSyncer` row carries `paid_session_id` and
`roster_id`; this is how to walk "what rosters does this season feed?"
without a separate query.

Other registration surface:

- `GET /api/v1/registration_questions` — team's question definitions
  (`prompt, type, for_type, required, is_public, coach_visibility, …`).
  `RegAddressQuestion` is the type used to collect address+zip.
- `GET /api/v1/registration_answers?profile_id=X&profile_type=WrestlerProfile`
  — answers for a specific profile, optionally scoped to a session via
  `session_id`. Visibility filterable with `visibility=public|private`.
- `POST /api/v1/memberships` + `POST /api/v1/memberships/preview` — create
  a paid-session signup. Out of CLI v1 scope (write path, more involved
  payment validation).

## Calendar / events

`app/controllers/api/v1/events_controller.rb` +
`app/controllers/concerns/calendar_event_helpers.rb`.

- `GET /api/v1/events?start=YYYY-MM-DD&end=YYYY-MM-DD[&roster_ids[]=...&event_type=practice]`
  — date range params parsed in the team's `default_time_zone` and
  converted to UTC server-side. Use ISO dates, let the server handle TZ.
- Additional filters in the helper: `private_lesson_filter, invited,
  invite_status, event_booking_status_in, coach_ids`.
- `expand=event_invites,event_bookings,private_lessons` — comma-separated
  CSV; pulls in nested data on the events index/show.
- `Event.ransackable_attributes` allows
  `id, name, start_at, end_at, event_type, paid_session_id`. **`location`
  is not ransackable today.** A real location filter is on the WIQ
  backend roadmap (it will replace the free-text `location` column with a
  structured concept); until that ships the CLI doesn't expose a
  location/site flag. Users who need it can fetch the date range, write
  the results to a file, and post-process — that's not the CLI's problem
  to solve in v1.
- Soft deletes: events use `acts_as_paranoid`; the index calls
  `.without_deleted`. No "include deleted" param exposed.
- `POST /api/v1/events` — recurring practice creation:
  ```json
  {"event": {
     "name": "...", "event_type": "practice",
     "start_at": "2026-09-01T17:00:00Z", "end_at": "2026-09-01T18:30:00Z",
     "repeat": {"mon": true, "wed": true, "fri": true, "until": "2027-05-31"},
     "roster_events_attributes": [{"roster_id": 42}]
  }}
  ```
  Each day in `repeat` fans out into separate event rows server-side. The
  response only returns the first event — there's no `batch_id`. To
  delete a whole series later: `DELETE /api/v1/events/:id?delete_recurring=true`.
- `POST /api/v1/events/:id/notify` — pushes change notifications. CLI
  should never call this implicitly; gate behind an explicit `--notify`
  flag on event edits.

## How `--season <year>` resolves

No first-class `Season` model exists. The CLI treats "season" as a
client-side projection over `PaidSession`:

1. `GET /api/v1/paid_sessions?q[start_at_lteq]=<year>-12-31&q[end_at_gteq]=<year>-01-01`
   to find paid sessions overlapping the calendar year. (Both `start_at`
   and `end_at` are in the Ransack allowlist.) Paid sessions per team are
   usually <50, so a full pull and client-side filter is also fine.
2. For roster-scoped commands: `GET /api/v1/rosters` (full list is
   cheap; the jbuilder already embeds `roster_syncers`), then filter
   rosters whose `roster_syncers[].paid_session_id` is in the matched set.
3. Some teams tag rosters with strings like `2025-26`. The roster
   jbuilder exposes `taggings[].tag`; offer `--season-tag <tag>` as a
   secondary path for teams that use that convention. Don't default to
   tag-based resolution — hygiene varies.

Documented behavior:

- `wiq rosters list --season 2026` → resolve to paid_session_ids, filter
  the rosters response client-side.
- `wiq reports run … --season 2026` → if the report type accepts
  `paid_session_id` in `args`, pass each matching id (or error if the
  type wants exactly one). Otherwise error with
  `code: "season_unsupported_for_type"`.
- Zero paid sessions match → exit with `code: "season_not_found"`, hint
  pointing at `wiq paid-sessions list`.

Long-term: push for a first-class `Season` resource on the backend if the
PaidSession-overlap convention proves load-bearing for many customers.

## Other things worth knowing

- **CORS:** Allowlist is `localhost:{3000,5002}`, the ngrok dev host, prod,
  qa (`config/application.rb:100`). Irrelevant for the CLI (no browser
  origin) but explains the absence of CORS pain.
- **Rate limit:** existing `api/ip` rule, 100 req / 3 sec per source IP.
  No per-PAT throttle yet.
- **`include`s by default:** controllers pre-include heavily; the CLI
  doesn't need to think about N+1s.
- **Side-effect endpoints to gate behind explicit flags:** roster sync
  (`POST /api/v1/rosters/:id/sync`), event-change notifications
  (`POST /api/v1/events/:id/notify`), message-group read
  (`POST /api/v1/message_groups/:id/read`). These work, but they kick
  off jobs / send pushes / move read state. v1 either doesn't expose
  them or wraps them in `--confirm`.

## Open questions to file back with the WIQ app team

1. The committed `doc/openapi.yaml` is ~1 year stale. Either (a) wire
   `OPENAPI=1 bundle exec rspec` into CI so it regenerates on PRs that
   touch `api/v1`, or (b) drop the committed copy and regenerate on
   demand. Until then, jbuilders are the source of truth.
2. `request_id` echoed in response body and/or `X-Request-ID` header for
   support correlation.
3. Real location/site filter on `GET /api/v1/events` (when the backend
   gets a structured location concept). Until then the CLI doesn't expose
   a flag.
4. Subdomain discovery for `wiq auth login`. The PAT settings URL lives at
   `<team-subdomain>.wrestlingiq.com/settings/personal_access_tokens`; if
   the customer doesn't know their subdomain, the CLI can't deep-link
   them. Either accept the host URL interactively (current plan), or
   document a discovery flow on the marketing site.
