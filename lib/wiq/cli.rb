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
  end
end
