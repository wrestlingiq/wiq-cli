# frozen_string_literal: true

require "json"
require "fileutils"
require "time"

module Wiq
  # File-backed credential store. ~/.config/wiq/credentials.json, mode 0600.
  # Shape:
  #   {
  #     "<host>": {
  #       "<alias>": { "token": "...", "token_prefix": "...", "name": "...",
  #                    "profile": {...}, "scopes": ["prospects:write"],
  #                    "stored_at": "..." },
  #       "<alias>": { ... }
  #     }
  #   }
  module Credentials
    DEFAULT_PATH = File.join(Dir.home, ".config", "wiq", "credentials.json")
    DEFAULT_ALIAS = "default"

    module_function

    def path
      ENV["WIQ_CREDENTIALS_PATH"] || DEFAULT_PATH
    end

    def load_all
      return {} unless File.exist?(path)

      JSON.parse(File.read(path))
    rescue JSON::ParserError
      {}
    end

    def for_host(host, alias_name)
      load_all.dig(host, alias_name)
    end

    def aliases_for(host)
      Array((load_all[host] || {}).keys)
    end

    def hosts
      load_all.keys
    end

    # Flat list across hosts × aliases. Useful for `wiq auth list`. Excludes the
    # raw token; callers should never log tokens.
    def all_entries
      load_all.flat_map do |host, by_alias|
        by_alias.map do |alias_name, entry|
          {
            "host" => host,
            "alias" => alias_name,
            "token_prefix" => entry["token_prefix"],
            "name" => entry["name"],
            "profile" => entry["profile"],
            "scopes" => entry["scopes"],
            "stored_at" => entry["stored_at"]
          }
        end
      end
    end

    def store(host:, alias_name:, token:, token_prefix: nil, name: nil, profile: nil, scopes: nil)
      data = load_all
      data[host] ||= {}
      data[host][alias_name] = {
        "token" => token,
        "token_prefix" => token_prefix,
        "name" => name,
        "profile" => profile,
        "scopes" => scopes,
        "stored_at" => Time.now.utc.iso8601
      }.compact
      write(data)
    end

    def remove(host, alias_name)
      data = load_all
      bucket = data[host]
      return false unless bucket
      return false unless bucket.delete(alias_name)

      data.delete(host) if bucket.empty?
      write(data)
      true
    end

    def write(data)
      FileUtils.mkdir_p(File.dirname(path))
      File.open(path, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |f|
        f.write(JSON.pretty_generate(data))
      end
    end
  end
end
