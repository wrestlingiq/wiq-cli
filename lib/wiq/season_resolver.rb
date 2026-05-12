# frozen_string_literal: true

module Wiq
  # Translates `--season <year>` into a set of PaidSession ids. No first-class
  # Season exists in WIQ; we approximate by finding paid sessions whose
  # [start_at, end_at] window overlaps the calendar year.
  class SeasonResolver
    def initialize(client)
      @client = client
    end

    # Returns the array of paid_session hashes that overlap `year`.
    def paid_sessions_for(year)
      year = Integer(year)
      start_of_year = "#{year}-01-01"
      end_of_year = "#{year}-12-31"

      sessions, = @client.collect_all(
        "/api/v1/paid_sessions",
        {
          "q[start_at_lteq]" => end_of_year,
          "q[end_at_gteq]" => start_of_year,
          "per_page" => 100
        },
        key: "paid_sessions"
      )
      sessions
    end

    def paid_session_ids_for(year)
      paid_sessions_for(year).map { |ps| ps["id"] }
    end

    # Filter an array of rosters (as returned by /api/v1/rosters) to those
    # whose roster_syncers point at any paid session id in `ids`.
    def filter_rosters_by_ids(rosters, ids)
      id_set = ids.to_set
      rosters.select do |roster|
        syncers = roster["roster_syncers"] || []
        syncers.any? { |rs| id_set.include?(rs["paid_session_id"]) }
      end
    end
  end
end

require "set"
