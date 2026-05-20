# Deferred work

Everything we've explicitly chosen NOT to ship in v1. Each item carries a
one-line "why we punted" so future-us doesn't have to re-derive the
decision. Re-order as priorities shift; the headings are descriptive, not
priority-ordered.

Last updated: 2026-05-12 (after L1 ships).

## Agent-discovery surface

- **L2 — `wiq workflows` command.** Static catalog of named recipes
  ("attendance-report-last-month" → exact command sequence). Lives in
  `lib/wiq/workflows.rb` as a Ruby hash. Aim for 5–8 named workflows.
  Hold until initial testing surfaces which multi-step recipes agents
  actually run.
- **L3 — SKILL.md + Claude plugin.** Bundled at `share/skills/wiq/SKILL.md`,
  installed via `wiq setup claude`. Sections: invariants, output-mode
  matrix, ID resolution, pagination, common workflows. Hold until we have
  real agent-usage telemetry — written cold it's guesswork.
- **Per-command `agent_notes` annotations.** Method-level prose blocks
  that render in `wiq <cmd> --help --agent` as JSON. Useful for commands
  with non-obvious behavior (recurring-event fan-out, season resolution).
  Adopt incrementally as commands earn it.
- **Recommendation pass on the other report types.** L1 only marked
  CheckInSummary/Feed (recommended) and PracticeAttendance (deprecated).
  The other 19 types in `Reports::TYPES` are neutral. Needs a pass from
  the WIQ team to identify recommended picks per use case
  (finance, roster ops, USAW/AAW, fundraising, …).
- **`wiq commands --json` / `wiq --help --agent`.** Full command tree
  dump + structured JSON help on any command. Initial-plan items, useful
  for agent discovery without scraping help text.
- **`.surface` drift CI.** Snapshot of the command tree at repo root; CI
  fails on drift without an explicit update. Worth it once the command
  surface stabilizes (i.e., after L2 lands).

## Commands not yet exposed

- **`wiq events types`** — list the team's allowed event_type strings
  (practice, competition, dual_meet, private_lesson, …). ~30 minutes;
  hardcoded allowlist in the CLI. Add when an agent trips on guessing.
- **`wiq events create`** — recurring practice/event creation
  (`POST /api/v1/events` with `repeat:` block). Write surface; deferred
  until v1.1.
- **`wiq check_ins record`** — mark attendance via CLI
  (`POST/PUT /api/v1/events/:id/check_ins`). Write surface; deferred.
- **`wiq wrestlers list`** — endpoint works but `expand_registration_answers`
  produces wide payloads. Wait for a real use case to scope the right
  default expansion.
- **`wiq url parse <url>`** — extract team/roster/event IDs from WIQ web
  URLs. Initial-plan item; useful for agents pasted URLs by humans.
- **`wiq paid_sessions create/update`**, **`wiq rosters create/update`**,
  etc. — every write path on every resource. v1 is reads-only except
  report submission. Cherry-pick as customers ask.
- **Prospect write commands.** API supports `POST /prospect_families`,
  `PATCH /prospect_families/:id` (incl. assigned_coach), `DELETE`,
  `POST /prospect_families/:id/prospects`, `PATCH /prospects/:id`
  (incl. stage transitions via `advance_to!`), and
  `POST /prospect_families/:id/notes` (with `clear_follow_up_for[]` /
  `add_follow_up_for[]` side-effect params). Reads-only in v1 — most
  pipeline edits happen in the drawer UI today, and exposing
  stage-transition writes without first watching agents use them is
  asking for trouble.

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
- **README.md / CHANGELOG.md.** None exist today. Add when the gem is
  ready for external publish.
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

- **`days_threshold` permit fix on `Api::V1::ReportsController`** — IN
  FLIGHT (matt is handling). The Vue form sends it for `ChurnRiskReport`
  but the controller's StrongParams allowlist doesn't include it, so it
  gets silently dropped and the model falls back to its 30-day default.
  CLI already exposes `--days-threshold` and sends the value; once the
  permit fix lands, the CLI works as-documented without further changes.
- **Echo `request_id`** in the response body or `X-Request-ID` header,
  for support correlation. Today the CLI can't give a customer a request
  ID to ship to support.
- **Real location/site filter on events.** `Event.location` is free-text
  and not in `ransackable_attributes`. WIQ team has flagged a structured
  location concept as roadmap. Until then the CLI deliberately exposes
  no `--site` flag.
- **Subdomain discovery flow for `wiq auth login`.** PAT settings URL
  lives at `<team-subdomain>.wrestlingiq.com/settings/personal_access_tokens`.
  If a customer doesn't know their subdomain, the CLI can't deep-link
  them. Either document a discovery flow on the marketing site or accept
  the host URL interactively (current plan).
