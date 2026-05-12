# frozen_string_literal: true

require "uri"

module Wiq
  # Parses the WIQ pagination headers:
  #   Link: <https://host/api/v1/foo?page=2>; rel="next", <...>; rel="last"
  #   TotalCount: 123
  module Pagination
    module_function

    # Returns { "next" => "...url...", "prev" => "...", "first" => "...", "last" => "..." }.
    def parse_link(header)
      return {} if header.nil? || header.empty?

      header.split(",").each_with_object({}) do |part, acc|
        url_part, *params = part.split(";").map(&:strip)
        next unless url_part&.start_with?("<") && url_part.end_with?(">")

        url = url_part[1..-2]
        rel = params.find { |p| p.start_with?("rel=") }
        next unless rel

        rel_value = rel.sub(/\Arel="?/, "").sub(/"?\z/, "")
        acc[rel_value] = url
      end
    end

    def next_url(link_header)
      parse_link(link_header)["next"]
    end

    def total_count(headers)
      # Header is literally `TotalCount` (case-insensitive via Faraday).
      v = headers["TotalCount"] || headers["totalcount"] || headers["Totalcount"]
      v && Integer(v)
    rescue ArgumentError
      nil
    end
  end
end
