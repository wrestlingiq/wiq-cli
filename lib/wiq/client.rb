# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "json"
require "uri"

module Wiq
  # Thin wrapper around Faraday that:
  #   - Adds Authorization: Bearer <pat>
  #   - Parses JSON requests and responses
  #   - Retries on 429 and 5xx (Retry-After honored) — GET/HEAD only, so a
  #     write is never replayed
  #   - Translates non-2xx responses into Wiq::APIError
  #   - Exposes paginate(path, params) that walks the Link: rel=next chain
  class Client
    USER_AGENT = "wiq-cli/#{Wiq::VERSION}"

    attr_reader :host

    def initialize(config)
      @config = config
      config.require_host!
      @host = config.host
      @token = config.token
    end

    def get(path, params = {})
      request(:get, path, params: params)
    end

    def post(path, body = {})
      request(:post, path, body: body)
    end

    def put(path, body = {})
      request(:put, path, body: body)
    end

    def patch(path, body = {})
      request(:patch, path, body: body)
    end

    def delete(path, params = {})
      request(:delete, path, params: params)
    end

    # Yields each page's records until rel=next runs out.
    # All /api/v1 index endpoints wrap their array under the resource name
    # (e.g. `{"rosters": [...]}`) — callers must pass `key:` so we can unwrap.
    # Yields (records_array, response, total_count).
    def paginate(path, params = {}, key:)
      url = absolute(path)
      first = true
      loop do
        resp = first ? request(:get, path, params: params, raw: true)
                     : request(:get, url, raw: true)
        first = false
        records = extract_records(resp.body, key)
        total = Pagination.total_count(resp.headers)
        yield records, resp, total
        url = Pagination.next_url(resp.headers["Link"] || resp.headers["link"])
        break unless url
      end
    end

    # Collects every page of an index into a single array.
    def collect_all(path, params = {}, key:)
      all = []
      total = nil
      paginate(path, params, key: key) do |records, _resp, t|
        total ||= t
        all.concat(records)
      end
      [all, total]
    end

    private

    def extract_records(body, key)
      return Array(body) if body.is_a?(Array)
      return [] if body.nil?
      raise Error.new("Expected wrapped index response with key #{key.inspect}, got #{body.class}",
                      code: "unexpected_response") unless body.is_a?(Hash)

      Array(body[key.to_s] || body[key.to_sym])
    end

    def request(method, path_or_url, params: {}, body: nil, raw: false)
      url = path_or_url.start_with?("http") ? path_or_url : absolute(path_or_url)

      response = connection.public_send(method) do |req|
        req.url(url)
        req.params.update(params) if params && !params.empty?
        req.body = body if body
      end

      if response.status >= 400
        raise APIError.new(
          status: response.status,
          body: response.body,
          request_id: response.headers["X-Request-Id"]
        )
      end

      raw ? response : response.body
    end

    def absolute(path)
      base = @host.sub(%r{/+\z}, "")
      path = path.start_with?("/") ? path : "/#{path}"
      "#{base}#{path}"
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.request :json
        f.request :retry,
                  max: 3,
                  interval: 0.5,
                  backoff_factor: 2,
                  retry_statuses: [429, 500, 502, 503, 504],
                  methods: %i[get head]
        f.response :json, content_type: /\bjson\z/
        f.headers["Accept"] = "application/json"
        f.headers["User-Agent"] = USER_AGENT
        f.headers["Authorization"] = "Bearer #{@token}" if @token
        f.adapter Faraday.default_adapter
      end
    end
  end
end
