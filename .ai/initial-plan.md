# WIQ CLI + Personal Access Tokens

**Date:** 2026-05-11
**Status:** Part 1 shipped in PR #2310; Part 2 (CLI) pending in a new repo.
**Driver:** Customer ask for API access to build automated reports (roster by zip, attendance trends, growth across seasons, calendar views, recurring practice creation). Decision after research: expose `api/v1` to external callers via per-user Personal Access Tokens, and ship a Ruby CLI that is explicitly designed to be driven by AI agents (Claude Code, Cursor, cron) as well as humans.

Out of scope for this doc (tracked separately): cleanup of `Team.api_key` / `api/team/v1` namespace.

---

## Part 1 — Personal Access Tokens — SHIPPED (PR #2310)

Per-user `wiq_pat_<32 hex>` tokens that authenticate against `/api/v1`, with SHA256-digest storage, an async last-used debounce job, and a Vue settings page at **`/settings/personal_access_tokens`** to mint/list/revoke. Token inherits the user's full permission set (no scopes); no new rate limiting (existing `api/ip` rule covers it).

See PR #2310 for the implementation. Refer to commits there if you need exact file layout — duplicating those details here would just rot.

### Prerequisite audit — done

The planned half-day audit of `api/v1` for `skip_authorization` / missing-Pundit gaps was completed after PATs shipped. Findings:

- **Two real cross-team gaps**, both flagged in the source with `# todo fixup with a real policy` comments:
  - `Api::V1::WrestlerGuardiansController#index` — loaded `WrestlerProfile.find(params[:wrestler_id])` with no authorize call. A coach's PAT could fetch parent contact info (phone, email, address) for any wrestler ID, cross-team.
  - `Api::V1::MatchScoringEventsController#index` — loaded `Match.find(params[:match_id])` with no authorize. PAT could enumerate match IDs and pull scoring events across teams.
  - Both fixed in this branch by adding `authorize <resource>, :show?` (the existing `WrestlerProfilePolicy#show?` and `MatchPolicy#show?` already enforce team membership). Cross-team specs added.
- **No other gaps.** Every other `skip_after_action :verify_authorized` / `verify_policy_scoped` in `api/v1` is legitimate: form-object pattern (calls `.authorize` on the form), public reference data (login, scoring rulesets), or custom scoping that filters by `current_profile.team` (search, accounts index). No webhooks or system endpoints hiding under v1.
- **No ship-blocking issues** for the CLI launch.

---

## Part 2 — CLI Architecture

### The SDK-vs-CLI question

**Decision: single Ruby gem (`wiq-cli`). No separately published SDK gem.**

Justification:

- Basecamp ships an SDK in 6 languages because they're an established platform with thousands of integrators. Generating from a Smithy IDL pays off at their scale. We have one customer asking.
- A Ruby SDK against our own Rails app is awkward — internal callers should be hitting models, not HTTP. The audience for a Ruby SDK is essentially the audience for the CLI (Ruby scripters), and they can just `require 'wiq/cli/client'` from the gem if they want.
- For non-Ruby users (Python, Node), the right artifact is our **OpenAPI spec**, which we already generate with `rspec-openapi`. They use `openapi-generator` and get a client in any language. That's strictly more flexible than maintaining a hand-rolled SDK per language.
- The internal HTTP client lives in `lib/wiq/client.rb` inside the CLI gem. Factor it cleanly. If demand for a standalone gem appears later, lifting it out is mechanical (move file, change requires, version bump). Don't pre-extract.

**Two contracts we maintain:**
1. **HTTP API + OpenAPI spec** — the canonical interface. Anyone in any language can hit this.
2. **The CLI gem** — opinionated Ruby wrapper, agent-native, our "first-party" experience.

### Repo + distribution

- New public repo: `wrestlingiq/wiq-cli` (separate from the main app repo — customers/agents shouldn't browse our app source).
- Gem name: `wiq-cli`. Binary: `wiq`.
- Distribution:
  - `gem install wiq-cli` — primary.
  - `brew install wrestlingiq/tap/wiq-cli` — for Mac users who don't want to think about Ruby. Homebrew tap formula installs via Ruby in `/opt/homebrew`.
  - `curl -fsSL https://wrestlingiq.com/install-cli | bash` — for the "agent setting up its environment" path. Detects ruby, installs gem.
- Require Ruby ≥ 3.1 on the user's machine. Our audience is technical enough; bundling Ruby into a single static binary (ruby-packer) is more work than it's worth for v1.

### Framework

- **Thor** for command tree. Standard, well-supported, plays nicely with subcommands.
- **HTTP:** `faraday` + `faraday-retry`. Adds the resilience patterns Basecamp's SDK has (exponential backoff, Retry-After respect).
- **Keychain storage:** `keyring` gem on macOS, fall back to `~/.config/wiq/credentials.json` (mode 0600) on Linux/Windows.
- **Per-repo config:** `.wiq/config.json` for project-level defaults (so an agent working in a customer's reports repo doesn't pass `--team`/identity on every call). Note: today we have one team per user/token, so this is mostly future-proofing. Useful immediately for setting default date ranges, output format, etc.

### Command surface for v1

Scoped tightly to the customer's five use cases plus the meta-commands every CLI needs.

**Auth + meta:**

```
wiq auth login              # prompt for PAT, store in keychain, verify against /api/v1/me
wiq auth status             # who am i, when does the token last get used
wiq auth logout             # delete from keychain
wiq doctor                  # diagnose env, network, token validity
wiq url parse <url>         # extract team/roster/event IDs from a WIQ URL
wiq commands --json         # dump full command catalog (for agent discovery)
wiq --help --agent          # structured JSON help (any command)
```

**Domain:**

```
wiq rosters list [--season <year>] [--expand memberships,profiles]
wiq rosters show <id>
wiq rosters members <id>

wiq events list [--since <date>] [--until <date>] [--roster <id>]
wiq events show <id>
wiq events create --name "..." --start <ts> --end <ts> [--repeat mon,wed,fri --until <date>] [--roster <id>]

wiq reports run <type> [args...]    # types: practice_attendance, roster_stats, last_practice_attended, ...
wiq reports list                    # async; returns IDs
wiq reports show <id>               # poll status, download when ready
wiq reports types                   # list supported report types
```

Roughly 15 commands. Cover the customer's stated needs.

**Explicit non-goals for v1:**
1. 1:1 coverage of all 152 controllers. We're shipping a sharp, opinionated tool, not a bindings library. Coverage grows on demand.
2. **No `wiq raw` / HTTP passthrough command.** Tempting as an escape hatch, but the cost outweighs the benefit:
   - Any endpoint a customer invokes via `raw` becomes de facto supported — we'd ship a stability promise without ever making one. Six months in we can't change `/api/v1/foo` because three customers have `wiq raw GET /api/v1/foo` in cron.
   - Agents will prefer `raw` because it's simpler, so the SKILL.md would have to spend paragraphs telling agents *not* to use a command we shipped.
   - `raw` returns naked JSON — no breadcrumbs, no `agent_notes`, no structured errors. Including it lowers the floor of the CLI's UX.
   - Customers with truly off-blessed-path needs can use `curl` + their PAT against the published OpenAPI spec. That friction is a feature: it tells them they're outside the supported integration path and may want to ask us to bless it.
   - Basecamp ships zero raw passthrough. They have 100% endpoint coverage instead. We won't hit 100% but the principle holds: every command in the CLI is something we support.

### Output / agent envelope

Steal directly from Basecamp. Every command supports:

- `--json` — envelope:
  ```json
  {
    "ok": true,
    "data": { ... },
    "summary": "Listed 14 rosters",
    "breadcrumbs": [
      { "action": "view members", "cmd": "wiq rosters members <id>", "description": "..." },
      { "action": "filter by season", "cmd": "wiq rosters list --season 2026", "description": "..." }
    ],
    "meta": { "page": 1, "total": 14, "request_id": "..." }
  }
  ```
- `--agent` — same data, no envelope, no prompts, no colors. Raw for headless scripts.
- `--md` — GitHub-flavored Markdown, for agents to surface inline in chat.
- TTY autodetect: pretty ANSI on a terminal, JSON when piped.

Implement in `lib/wiq/output.rb`. One module, four formatters.

Error envelope on failure:

```json
{ "ok": false, "error": "Roster not found", "code": "ROSTER_NOT_FOUND", "hint": "Run `wiq rosters list` to see available rosters." }
```

### Per-command `agent_notes`

Each Thor command carries a `class_option :agent_note` or (cleaner) a method-level annotation:

```ruby
agent_note <<~MD
  Recurring events: pass --repeat as comma-separated days (mon,wed,fri).
  --until is required when --repeat is set — open-ended recurrence is not supported.
  Each repeat creates a separate event row; use the returned batch_id to track them.
MD
desc "create ...", "Create a new event"
def create(...); end
```

`wiq <cmd> --help --agent` returns the description, options, and `agent_notes` as JSON.

### SKILL.md + Claude Code plugin

Bundled in the gem at `share/skills/wiq/SKILL.md`. Sections:

1. **Invariants** — "always check `wiq auth status` first if commands fail with 401"; "PATs inherit user permissions, so list operations may return empty if the user doesn't have access"; "reports are async — `wiq reports run` returns an ID, `wiq reports show` polls."
2. **Output mode decision matrix** — when to use `--json` vs `--agent` vs `--md`.
3. **Common workflows** — "monthly attendance report by program," "create a recurring practice block," "find rosters by zip code."
4. **ID resolution** — always prefer `wiq url parse` over guessing IDs.
5. **Pagination** — use `--all` for full pulls, default is page 1.

Two hundred lines, not nine hundred. Grow it as we see how agents actually use the CLI.

`wiq setup claude` — installs a `.claude-plugin/plugin.json` pointing at the bundled SKILL.md. Mirror Basecamp's approach.

### Drift protection

`.surface` files at the repo root snapshot the command tree (output of `wiq commands --json`). CI fails if the snapshot drifts without an explicit update. Same trick Basecamp uses to keep `SKILL.md` honest.

### Estimate

- HTTP client + Thor scaffolding + auth flow + keychain: 4 days
- 15 commands + output envelope + agent notes: 5 days
- SKILL.md + Claude plugin + drift CI: 2 days
- Distribution (RubyGems publish, Homebrew tap, install script): 2 days
- Docs + README: 1 day

Roughly 2–3 weeks of focused work for a v1.

---

## Part 3 — Which APIs to expose

**Decision: HTTP is open (a PAT can hit any `/api/v1` endpoint); CLI surface is the blessed subset, ~15 commands in v1.**

Reasoning:

- A PAT authenticates as a user. Whatever that user can do in the web app, they can do via `api/v1`. We don't need a separate allowlist — Pundit policies are the access control surface, and they already exist.
- The CLI commands are an opinionated *subset* selected for ergonomics. Customers who need uncovered endpoints use `curl` against `/api/v1` with their PAT and the published OpenAPI spec; **not** via a `wiq raw` passthrough (see Part 2 non-goals for why).
- The CLI's surface = the integration surface we explicitly support. New endpoints get blessed when there's repeated, real demand — not implicitly by being reachable.
- Important: this means **we should audit `api/v1` for endpoints we don't want to expose externally before announcing the CLI / OpenAPI publicly.** Most should be fine — it's the same surface our own SPA uses. Likely flags:
  - Any endpoint that returns data the user shouldn't see via the UI but happens to via the API (Pundit gaps).
  - Endpoints that perform expensive operations without rate limits (mass exports, full team data dumps).
  - Internal/debug endpoints, if any leaked into `api/v1`.

**Status:** audit done (see Part 1 prerequisite note). Two real cross-team gaps found and fixed in the same branch as the PAT work.

### What about the OpenAPI spec?

Currently ~14 endpoints documented. Before publishing to customers we should:

1. Run `OPENAPI=1 bundle exec rspec` across the full suite to expand coverage.
2. Audit the resulting spec for missing endpoints; backfill specs where needed.
3. Publish to `https://api.wrestlingiq.com/openapi.yaml` (or similar).
4. Link prominently from the CLI README and SKILL.md.

This is the contract for non-Ruby integrators and the foundation for any future official SDK.

---

## Sequencing

1. ~~**PAT model + auth concern integration + specs**~~ — **shipped in PR #2310**.
2. ~~**PAT settings UI**~~ — **shipped in PR #2310**.
3. ~~**`api/v1` audit for missing-Pundit gaps**~~ — **done.** Two cross-team gaps found and fixed in the PAT branch (`WrestlerGuardiansController#index`, `MatchScoringEventsController#index`).
4. **OpenAPI spec full run + publish** (1 day). Independent of CLI; useful on its own.
5. **CLI v0** (1 week). Auth + 5 commands + JSON envelope. Internal use against staging.
6. **CLI v1** (1 week). Full 15 commands + agent envelope + SKILL.md + Claude plugin.
7. **Distribution** (2 days). RubyGems, Homebrew tap, install script.
8. **Customer beta** (the original asker). Iterate on SKILL.md and `agent_notes` based on what their agents actually trip over.

A customer can hit `api/v1` directly with a PAT today, ahead of CLI v0. Step 3 must complete before we publicly announce or market the CLI / OpenAPI surface to external customers.

---

## Decisions

1. **PAT scopes — none.** PAT inherits the full permission set of its user. A parent's PAT can only see their kid's stuff; a coach's PAT acts as that coach. No `read`/`full` split. Easy to add later if a customer requests it.
2. **Token expiry — indefinite, with a revoke button.** No automatic expiration. UI surfaces `last_used_at` so customers can spot stale tokens; revoke is a one-click action in settings.
3. **Who can mint — any user.** Parents, wrestlers, and coaches can all create PATs under their own account. The blast radius is bounded by the user's own permissions, so a wrestler's leaked PAT can only see what that wrestler could see in the web app. No team-level gating in v1.
4. **Rate limiting — reuse existing `api/ip` (100 req / 3 sec).** No new per-PAT throttle. Revisit if shared-IP unfairness shows up in practice.
5. **CLI repo visibility — public.** Trade-off acknowledged: a public CLI makes "export all team data with one command" trivially discoverable, which is a legitimate competitive-defection vector. Mitigations: (a) PATs are per-user and individually revocable, so an exfiltrating coach leaves a clear audit trail in `last_used_at`; (b) we should add basic outbound-volume telemetry (count of records returned per PAT per day) so unusual exports are visible; (c) if a defector wants to export their team's data they can already do it through the UI's CSV exports, so the CLI changes the *speed* of exfiltration, not the possibility. The agent-discovery upside (Claude/Cursor browsing source + SKILL.md when an agent first authenticates) outweighs the marginal defection risk.

### Follow-up worth tracking separately

- Outbound volume telemetry per PAT (records returned, endpoints hit) — feeds an admin dashboard so head coaches can see what their org's tokens are doing.
- A "suspicious activity" alert if a PAT pulls more than N records in a day, emailed to the team owner.

