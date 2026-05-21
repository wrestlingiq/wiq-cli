# frozen_string_literal: true

require "thor"

module Wiq
  class CLI < Thor
    package_name "wiq"

    def self.exit_on_failure?
      true
    end

    desc "version", "Print the CLI version"
    def version
      puts Wiq::VERSION
    end
    map %w[--version -v] => :version

    desc "commands", "Dump the full command tree as JSON for agent discovery"
    long_desc <<~DESC
      Walks the Thor command registry and emits the entire CLI surface as
      structured JSON. Schema:

        { name, version, global_options[], top_level_commands[],
          groups: [ { name, description, commands: [
            { name, description, long_description, usage,
              options: [ { name, type, required, default?, enum?, description } ]
            }
          ] } ] }

      Recommended first call for any agent: pipe to a file, cache it, then
      pick a command and invoke it directly. No HTTP, no auth required.

      `global_options` lists --host, --as, --json, --agent — these apply
      uniformly to every command and aren't repeated per-command.
    DESC
    def commands
      puts JSON.pretty_generate(Wiq::Introspection.dump_tree)
    end

    desc "doctor", "Diagnose env, network, token, and config sources"
    subcommand "doctor", Wiq::Commands::Doctor

    desc "auth SUBCOMMAND", "Manage authentication (login, status, logout, list)"
    subcommand "auth", Wiq::Commands::Auth

    desc "check_ins SUBCOMMAND", "Attendance + check-ins (event, wrestler, summary)"
    subcommand "check_ins", Wiq::Commands::CheckIns

    desc "reports SUBCOMMAND", "Reports (run, show, types)"
    subcommand "reports", Wiq::Commands::Reports

    desc "paid_sessions SUBCOMMAND", "Paid sessions / registration data (list, show)"
    subcommand "paid_sessions", Wiq::Commands::PaidSessions

    desc "registrations SUBCOMMAND", "Registration questions + answers"
    subcommand "registrations", Wiq::Commands::Registrations

    desc "metrics SUBCOMMAND", "Dashboard metrics (list, show)"
    subcommand "metrics", Wiq::Commands::Metrics

    desc "events SUBCOMMAND", "Calendar events (list, show)"
    subcommand "events", Wiq::Commands::Events

    desc "rosters SUBCOMMAND", "Rosters (list, show)"
    subcommand "rosters", Wiq::Commands::Rosters

    desc "prospects SUBCOMMAND", "Prospect pipeline — individual kids (list, show, summary)"
    subcommand "prospects", Wiq::Commands::Prospects

    desc "prospect_families SUBCOMMAND", "Prospect pipeline — households (list, show, notes)"
    subcommand "prospect_families", Wiq::Commands::ProspectFamilies
  end
end
