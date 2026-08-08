# frozen_string_literal: true

module Wiq
  module Commands
    class Parents < Base
      DEFAULT_PER_PAGE = 20

      desc "list", "Search parents — narrow ID-discovery surface"
      long_desc <<~DESC
        Narrow listing over the team's parent profiles (teammates only —
        guest parents from camp signups are excluded server-side). Rows
        are slim: id, user_id, type, first_name, last_name, full_name.
        Sorted by first name. Default page size is 20; there's no --all
        flag.

        Filters:
          --query        free-text name search (legacy `?query=`)
          --first-name   q[first_name_cont]
          --last-name    q[last_name_cont]

        --expand opts into a wider payload:
          notification_preferences  Adds wiq_app_installed + a
                                    notification_preferences object
                                    (email, sms, push, push_user_pref)
                                    per parent — "which parents can we
                                    reach, and how?". Coach PATs only;
                                    the server silently omits it for
                                    parent/wrestler tokens.

        The parent → wrestler linkage is NOT in this payload. To see a
        family's kids, go the other direction: `wiq wrestlers show <id>`
        embeds parent refs, or `wiq wrestlers list --query <last name>`.
      DESC
      method_option :query, type: :string, desc: "Free-text name search"
      method_option :first_name, type: :string, desc: "First name (contains)"
      method_option :last_name, type: :string, desc: "Last name (contains)"
      method_option :expand, type: :string,
                             desc: "CSV: notification_preferences"
      method_option :per_page, type: :numeric, default: DEFAULT_PER_PAGE,
                               desc: "Page size (default 20; narrow surface)"
      def list
        params = build_list_params

        records, total = fetch_index("/api/v1/parents", params, key: "parent_profiles")
        render_index(
          records, total: total,
          summary: "Listed #{records.size} parents#{summary_filters_suffix}.",
          breadcrumbs: [
            { "cmd" => "wiq parents show <id>", "description" => "Drill into one parent" },
            { "cmd" => "wiq billing_profiles show <id> --profile-type ParentProfile",
              "description" => "Billing profile for a parent (admin only)" },
            { "cmd" => "wiq wrestlers list --last-name <name>",
              "description" => "Find the family's wrestlers (parent refs embedded)" }
          ]
        )
      end

      desc "show ID", "Fetch a single parent profile"
      long_desc <<~DESC
        Single-parent drill-down. Same slim payload as the index (id,
        user_id, type, names); soft-deleted parents still resolve here.

        Pass --expand for additional sections:
          notification_preferences  wiq_app_installed + notification_preferences
                                    (email, sms, push, push_user_pref) —
                                    "can this parent be reached, and how?"
                                    Coach PATs only; silently omitted for
                                    parent/wrestler tokens.
      DESC
      method_option :expand, type: :string,
                             desc: "CSV: notification_preferences"
      def show(id)
        params = {}
        params["expand_notification_preferences"] = true if expand_includes?("notification_preferences")
        parent = client.get("/api/v1/parents/#{id}", params)
        render(parent,
               summary: "Parent #{parent["id"]} — #{parent["full_name"]}",
               breadcrumbs: [
                 { "cmd" => "wiq billing_profiles show #{parent["id"]} --profile-type ParentProfile",
                   "description" => "Billing profile for this parent (admin only)" },
                 { "cmd" => "wiq wrestlers list --last-name #{parent["last_name"]}",
                   "description" => "Likely wrestlers for this family" }
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
          params["expand_notification_preferences"] = true if expand_includes?("notification_preferences")
          params
        end

        def expand_includes?(part)
          return false unless options[:expand]

          options[:expand].split(",").map(&:strip).include?(part)
        end

        def summary_filters_suffix
          bits = []
          bits << "matching #{options[:query].inspect}" if options[:query]
          bits << "first name ~ #{options[:first_name].inspect}" if options[:first_name]
          bits << "last name ~ #{options[:last_name].inspect}" if options[:last_name]
          bits.empty? ? "" : " (#{bits.join(", ")})"
        end
      end
    end
  end
end
