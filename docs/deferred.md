# Deferred work

Everything we've explicitly chosen NOT to ship in v1. Each item carries a
one-line "why we punted" so future-us doesn't have to re-derive the
decision. Re-order as priorities shift; the headings are descriptive, not
priority-ordered.

Last updated: 2026-05-12 (after L1 ships).

## Agent-discovery surface

- ~~**L2 — `wiq workflows` command.**~~ SHIPPED. 14 curated workflows
  across 7 categories (attendance, leads, roster, finance, memberships,
  fundraising, store) in `lib/wiq/workflows.rb`. Each carries a
  `question`, structured `parameters` (with types + enums + required
  flags), an ordered `recipe` (with `<placeholder>` and `[--flag <name>]`
  syntax), and `admin_only` flag propagated from underlying reports.
  Spec invariants enforce parameter↔placeholder consistency and
  admin_only drift detection across `Workflows::ALL` and
  `Reports::TYPES`.
- ~~**L3 — SKILL.md + Claude Code installer.**~~ SHIPPED.
  `share/skills/wiq/SKILL.md` (lean — 10.8 KB) bundled in the gem,
  installed via `wiq setup claude` (default `~/.claude/skills/wiq/`,
  `--project` for per-project, `--force` to overwrite, `--print` to
  inspect). Uses Claude Code's canonical skill format (no plugin
  wrapper — confirmed via current docs). Sections cover bootstrap,
  three core surfaces (commands/workflows/reports), auth model,
  multi-club aliases, output modes, error codes table, pagination,
  report decision matrix, common gotchas, what's NOT available.
- ~~**Per-command `agent_notes` annotations.**~~ SHIPPED via Thor
  `long_desc` blocks on every command across all 11 groups. Surfaces in
  `wiq <group> help <cmd>` today; Phase 2's `wiq <cmd> --help --agent`
  will project it to structured JSON.
- ~~**Recommendation pass on the other report types.**~~ SHIPPED — 20
  REC, 1 DEP, 15 NEU, 9 admin_only across the 36 entries in
  `Reports::TYPES`. User-curated.
- ~~**`wiq commands` JSON tree dump.**~~ SHIPPED. Walks Thor's
  registry, emits stable nested JSON: `{name, version, global_options,
  top_level_commands, groups: [{name, description, commands:
  [{name, description, long_description, usage, options}]}]}`. Filters
  Thor internals (`help`, `tree`), surfaces `enum` constraints,
  reverses Thor's `map` so display names match what users type
  (`run` not `run_report`, `check` not `check_all`).
- **Per-command `--help --agent` JSON mode.** Deferred per the
  Phase 2 scoping discussion — `wiq commands` covers the discovery
  case in one call (~30 KB total). Add later only if a real agent
  flow needs per-command JSON narrowly (filter the same introspection
  output to one entry; very low cost).
- **`.surface` drift CI.** Snapshot of the command tree at repo root; CI
  fails on drift without an explicit update. Worth it once the command
  surface stabilizes (i.e., after L2 lands).

## Commands not yet exposed

- ~~**`wiq events types`**~~ SHIPPED. Six canonical strings from
  `app/models/event.rb` (practice, dual_meet, tournament, scramble,
  private_lesson, other) surfaced via static command.
- **`wiq events create`** — recurring practice/event creation
  (`POST /api/v1/events` with `repeat:` block). Write surface; deferred
  until v1.1.
- **`wiq check_ins record`** — mark attendance via CLI
  (`POST/PUT /api/v1/events/:id/check_ins`). Write surface; deferred.
- **`wiq invoice_payments list`** — receipts/payment-instance granularity
  for tracing money on a specific subscription. Endpoint exists
  (`GET /api/v1/billing_subscriptions/:id/invoice_payments`). Hold
  until a real use case beats `wiq charges list` for clarity.
- ~~**`wiq wrestlers list`**~~ SHIPPED narrow. Default per_page=20, no
  --all flag, base payload kept tight. Filters translate to Ransack
  (--first-name, --last-name, --weight-class, --academic-class, --age,
  --roster, --profile-type) + legacy free-text --query. --expand opts
  into rosters / registration_answers / notification_preferences
  (coach-only, Aug 2026 — see wiq_api_notes.md) per row. Multi-roster
  intersection deferred (API supports it; CLI surface didn't justify
  the complexity for v1). `wiq wrestlers show <id>` paired.
- ~~**`wiq parents list/show`**~~ SHIPPED narrow (Aug 2026, alongside
  the `expand_notification_preferences` param from wrestling PR #2460).
  Filters: --query (legacy name search), --first-name / --last-name
  (Ransack). --expand notification_preferences (coach-only). Slim
  payload by design (id, user_id, type, names); no wrestler refs —
  family linkage stays on the wrestlers side.
- **`wiq url parse <url>`** — extract team/roster/event IDs from WIQ web
  URLs. Initial-plan item; useful for agents pasted URLs by humans.
- **`wiq paid_sessions create/update`**, **`wiq rosters create/update`**,
  etc. — every other write path. Each needs a server-side capability in
  `ApiCapability::REGISTRY` first (writes fail closed without one), then
  a CLI command. Cherry-pick as customers ask.
- **Prospect deletes.** Shipped in v0.6.0: `prospect_families
  create/update/note` and `prospects create/update/advance` behind the
  `prospects:write` scope. `DELETE /prospect_families/:id` and
  `DELETE /prospects/:id` remain out of reach — destroy actions are in
  no API capability server-side, by design.

## Packaging / distribution

- **macOS Keychain integration.** Currently file-based at
  `~/.config/wiq/credentials.json` mode 0600. Keychain via the `keyring`
  gem was in the original plan; the gem has compilation quirks and the
  file store is fine for v1. Add once we have at least one customer
  using the CLI.
- **Homebrew tap (`brew install wrestlingiq/tap/wiq-cli`).** Initial-plan
  distribution channel for Mac users. Gem-only install for v1.
- **`curl …/install-cli | bash` script.** Agent-friendly env-setup
  installer. Gem-only install for v1.
- ~~**README.md**~~ SHIPPED (lean — install, bootstrap, common
  commands, multi-club, Claude integration, output modes, pointers
  to docs/). **CHANGELOG.md** still deferred — wait for v0.2.
- **Integration / command-level tests.** Smoke layer landed
  (`spec/{pagination,credentials,errors,config,output,client,season_resolver}_spec.rb`,
  57 examples covering config resolution, error mapper, pagination,
  output formatters, client wrap-unwrap, season filter). Still missing:
  full Thor-invocation tests that exercise the command modules end-to-end
  (`wiq rosters list --as westside` against a stubbed API). Add once a
  command module starts carrying real logic beyond passing params through.

## Output

- **`--md` Markdown output mode.** Three modes (pretty/json/agent) cover
  v1. Add when an agent actually needs Markdown inline in a chat surface.

## Verification gaps (driven by user, not me)

- **End-to-end smoke against real staging.** Auth flow + at least one
  paginated index + one report poll. User is driving this.
- **Confirm `PracticeAttendanceReport.result` / `CheckInSummaryReport.result`
  shapes are agent-friendly.** Both land in `report.result` as opaque
  jsonb; verify the structure is parseable without an HTML-strip step.
- **OpenAPI regeneration.** `wrestling/doc/openapi.yaml` is ~1 year
  stale. Run `OPENAPI=1 bundle exec rspec` and inspect the diff before
  the CLI / spec is published externally. WIQ-app side, not CLI side.

## Backend asks (push back to WIQ app team)

- ~~**`GET /api/v1/prospects?query=<str>` 500s on ambiguous ORDER BY.**~~ —
  SHIPPED (WIQ-app commit 7ac9d90a5, 2026-05-21, qualifies the ORDER BY
  as `prospects.created_at`). `wiq prospects list --query` works; the
  KNOWN BUG note was removed from its long_desc in v0.6.0.


- ~~**`days_threshold` permit fix on `Api::V1::ReportsController`**~~ —
  SHIPPED. The CLI's `--days-threshold` flag now lands on the model
  unchanged; no further CLI work needed.
- **Echo `request_id`** in the response body or `X-Request-ID` header,
  for support correlation. Today the CLI can't give a customer a request
  ID to ship to support.
- ~~**Real location/site filter on events.**~~ — SHIPPED (June 2026,
  wre-506). The backend grew a structured Location model. The CLI now
  exposes `wiq locations list|show` plus `--location` flags on
  `events list` (repeatable → `location_ids[]`), `rosters list`
  (`q[location_id_eq]`), `paid_sessions list`, `wrestlers list`,
  `metrics show`, and `reports run` (args.location_id, honored by 13
  report types). The legacy free-text `Event.location` remains for old
  rows; serialized `location` is the display form.
- **Subdomain discovery flow for `wiq auth login`.** PAT settings URL
  lives at `<team-subdomain>.wrestlingiq.com/settings/personal_access_tokens`.
  If a customer doesn't know their subdomain, the CLI can't deep-link
  them. Either document a discovery flow on the marketing site or accept
  the host URL interactively (current plan).
