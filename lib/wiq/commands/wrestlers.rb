# frozen_string_literal: true

module Wiq
  module Commands
    class Wrestlers < Base
      # Match WrestlerProfile constants in app/models/wrestler_profile.rb.
      PROFILE_TYPES = %w[teammate alumnus guest all].freeze
      DEFAULT_PER_PAGE = 20

      desc "list", "Search wrestlers — narrow ID-discovery surface"
      long_desc <<~DESC
        Narrow listing + filtering, primarily for ID discovery before
        running another command (e.g. `wiq check_ins wrestler <id>`).
        Default page size is 20; there's no --all flag. For exhaustive
        exports use `wiq reports run RosterReport [--append-properties …]`
        or `wiq reports run FullExportWrestlerReport`.

        Filters translate to Ransack params server-side:
          --query              free-text name search (legacy `?query=`)
          --first-name         q[first_name_cont]
          --last-name          q[last_name_cont]
          --roster <id>        q[rosters_id_eq] — filter to one roster
          --location <id>      location_id (dedicated param, not Ransack) —
                               wrestlers on ANY roster at that location.
                               Composes with the other filters. Discover
                               ids via `wiq locations list`.
          --weight-class       q[weight_class_numeric_eq] — exact numeric
          --academic-class     q[academic_class_eq] (senior, junior, …)
          --age                q[age_eq]
          --profile-type       teammate (default) | alumnus | guest | all

        Multi-roster intersection ("kids on both A AND B") is supported
        by the API but not yet exposed in the CLI — use the web UI for
        now or compose two `--roster <id>` calls and intersect
        client-side.

        --expand opts into a wider payload:
          rosters                Adds full roster details per wrestler
          registration_answers   Adds intake-form answers per wrestler

        Base payload is already wider than most index endpoints (parents,
        coach_guardians, profile_photos, basic roster refs all render by
        default). For agents on a tight context window, prefer
        `wiq wrestlers show <id>` once you've narrowed to a candidate.
      DESC
      method_option :query, type: :string, desc: "Free-text name search"
      method_option :first_name, type: :string, desc: "First name (contains)"
      method_option :last_name, type: :string, desc: "Last name (contains)"
      method_option :roster, type: :numeric, desc: "Filter to a single roster id"
      method_option :location, type: :numeric,
                               desc: "Filter to wrestlers on any roster at this location id"
      method_option :weight_class, type: :string,
                                   desc: "Weight class (exact numeric, e.g. 132)"
      method_option :academic_class, type: :string,
                                     desc: "senior, junior, sophomore, freshman, …"
      method_option :age, type: :numeric, desc: "Age in years (exact)"
      method_option :profile_type, type: :string, enum: PROFILE_TYPES, default: "teammate",
                                   desc: "Default 'teammate' matches the WIQ web UI default; " \
                                         "'all' removes the filter entirely"
      method_option :expand, type: :string,
                             desc: "CSV: rosters, registration_answers"
      method_option :per_page, type: :numeric, default: DEFAULT_PER_PAGE,
                               desc: "Page size (default 20; narrow surface)"
      def list
        params = build_list_params

        records, total = fetch_index("/api/v1/wrestlers", params, key: "wrestlers")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} wrestlers#{summary_filters_suffix}.",
          breadcrumbs: [
            { "cmd" => "wiq wrestlers show <id>", "description" => "Drill into one wrestler" },
            { "cmd" => "wiq check_ins wrestler <id>", "description" => "See a wrestler's check-in history" },
            { "cmd" => "wiq reports run RosterReport --roster 0 --append-properties <q_ids>",
              "description" => "For exhaustive exports, use a report instead" }
          ]
        )
      end

      desc "show ID", "Fetch a single wrestler profile"
      long_desc <<~DESC
        Single-wrestler drill-down. Returns the full base payload
        (basic profile, parents, coach_guardians, profile_photos,
        rosters refs).

        Pass --expand for additional sections:
          rosters                Full roster details with tags
          registration_answers   Intake-form answers
      DESC
      method_option :expand, type: :string,
                             desc: "CSV: rosters, registration_answers"
      def show(id)
        params = {}
        params["expand_rosters"] = true if expand_includes?("rosters")
        params["expand_registration_answers"] = true if expand_includes?("registration_answers")
        wrestler = client.get("/api/v1/wrestlers/#{id}", params)
        render(wrestler,
               summary: "Wrestler #{wrestler["id"]} — #{wrestler["full_name"] || wrestler["display_name"]}",
               breadcrumbs: [
                 { "cmd" => "wiq check_ins wrestler #{wrestler["id"]}",
                   "description" => "Check-in history for this wrestler" },
                 { "cmd" => "wiq registrations answers --profile #{wrestler["id"]} --profile-type WrestlerProfile",
                   "description" => "Registration answers (subject to visibility gating)" }
               ])
      end

      no_commands do
        # Extracted so the spec can verify the option → query-param mapping
        # without round-tripping a real Faraday connection.
        def build_list_params
          params = { "per_page" => options[:per_page] || DEFAULT_PER_PAGE }
          params["query"] = options[:query] if options[:query]
          params["q[first_name_cont]"] = options[:first_name] if options[:first_name]
          params["q[last_name_cont]"] = options[:last_name] if options[:last_name]
          params["q[rosters_id_eq]"] = options[:roster] if options[:roster]
          params["location_id"] = options[:location] if options[:location]
          params["q[weight_class_numeric_eq]"] = options[:weight_class] if options[:weight_class]
          params["q[academic_class_eq]"] = options[:academic_class] if options[:academic_class]
          params["q[age_eq]"] = options[:age] if options[:age]
          params["q[profile_type_eq]"] = options[:profile_type] if profile_type_filter?
          params["expand_rosters"] = true if expand_includes?("rosters")
          params["expand_registration_answers"] = true if expand_includes?("registration_answers")
          params
        end

        def profile_type_filter?
          options[:profile_type] && options[:profile_type] != "all"
        end

        def expand_includes?(part)
          return false unless options[:expand]

          options[:expand].split(",").map(&:strip).include?(part)
        end

        def summary_filters_suffix
          bits = []
          bits << "matching #{options[:query].inspect}" if options[:query]
          bits << "in roster #{options[:roster]}" if options[:roster]
          bits << "at location #{options[:location]}" if options[:location]
          bits << "weight class #{options[:weight_class]}" if options[:weight_class]
          bits << "profile_type=#{options[:profile_type]}" if profile_type_filter? && options[:profile_type] != "teammate"
          bits.empty? ? "" : " (#{bits.join(", ")})"
        end
      end
    end
  end
end
