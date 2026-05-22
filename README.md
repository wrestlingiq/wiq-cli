# wiq-cli

> [!WARNING]
> **Research preview — v0.1.0.** This is an exploratory tool. The command
> surface, output shapes, and behavior are subject to change quickly and
> without backwards compatibility guarantees between releases. Not yet
> recommended for production-critical automation. Pin your gem version
> if you build anything load-bearing on top of it.

Read-only command-line interface for [WrestlingIQ](https://www.wrestlingiq.com).
Designed to be driven by both humans and AI agents (Claude Code, Cursor,
etc.) via per-user personal access tokens (PATs).

## Getting started

Four steps. Roughly five minutes end-to-end.

### 1. Install

```bash
gem install wiq-cli
```

Requires Ruby 3.1+. On macOS, the system Ruby is too old —
`brew install ruby` (or use rbenv / asdf) before running the gem install.

### 2. Get a personal access token

Sign into WrestlingIQ in your browser, then visit:

**https://www.wrestlingiq.com/settings/personal_access_tokens**

Click "New token", give it a name (e.g., `wiq-cli on my laptop`),
and copy the token value. **You'll only see it once** — paste it
somewhere safe for the next step.

The token inherits your WrestlingIQ permissions. If you're an admin
coach, your CLI will be able to run admin reports; if you're not, it
won't. Either way, the token can be revoked anytime from the same
page.

### 3. Log in

```bash
wiq auth login
```

The CLI prompts for the host (defaults to production — just press
Enter) and the token (paste the value from step 2). It verifies
against the API and stores the token at
`~/.config/wiq/credentials.json` (mode 0600, never logged).

Sanity-check:

```bash
wiq doctor
```

All checks should pass and "Bound profile" should show your name + team.

### 4. Install the Claude Code skill (optional but recommended)

```bash
wiq setup claude
```

This drops a small `SKILL.md` into `~/.claude/skills/wiq/` that
teaches Claude how to drive the CLI. Claude Code auto-detects it
within the current session — no restart needed.

Now you can ask Claude things like:

- "How is our prospect pipeline doing?"
- "Show me everyone who hasn't been to practice in 2 weeks"
- "Which families have failed payments that weren't retried successfully?"

…and Claude will translate them into the right CLI commands.

## Try it without Claude

```bash
wiq rosters list                                            # Browse rosters
wiq prospects summary                                       # Pipeline dashboard
wiq events list --start 2026-05-01 --end 2026-05-31         # Calendar
wiq workflows list                                          # Curated multi-step recipes
wiq reports types                                           # 36 report types w/ recommendations
wiq commands                                                # Full JSON command tree (for agents)
```

Pass `--help` to any command for the full option list. Pass
`--json` for the structured envelope, `--agent` for bare JSON, or
just let the default pretty output flow.

## Multiple clubs / multiple roles

If you have PATs for different WIQ accounts (different clubs, or
both a coach + parent role), store each under its own alias:

```bash
wiq auth login                          # First login → slot "default"
wiq auth login --as westside            # Second account → slot "westside"
wiq --as westside rosters list          # Run against the second slot
WIQ_ALIAS=westside wiq events list      # Same, via env var
```

Full mechanic + resolution chain documented in `docs/wiq_api_notes.md`.

## If something doesn't work

```bash
wiq doctor                              # Diagnostic checks (host, token, reachability, profile)
wiq auth status                         # Shows the resolved credential
wiq auth list                           # All stored credentials
```

If `wiq doctor` reports a failure or you see an unexpected error code,
the error envelope includes a `hint` field pointing at the next thing
to try. If you get stuck, email
[support@wrestlingiq.com](mailto:support@wrestlingiq.com) with the
output (the CLI never logs your token — paste the full JSON safely).

## Output modes

| Flag | Output |
| --- | --- |
| (default) | Pretty JSON to a TTY, bare JSON when piped |
| `--json` | Full envelope: `{ok, data, summary, breadcrumbs, meta}` |
| `--agent` | Bare `data` as JSON — best for headless agents |

## Where things live

- [`docs/wiq_api_notes.md`](docs/wiq_api_notes.md) — auth model, response shapes, gotchas, what the CLI maps to in `/api/v1`
- [`docs/deferred.md`](docs/deferred.md) — work explicitly out of scope for v1 + the rationale
- [`share/skills/wiq/SKILL.md`](share/skills/wiq/SKILL.md) — the bundled Claude Code skill content

## Status

v0.1.0 — 29 commands across 16 groups, 117 RSpec smoke examples.
Reads-only except for report submission (the API's canonical async
pattern). Write commands deferred — see `docs/deferred.md`.

## License

MIT.
