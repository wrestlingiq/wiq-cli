# frozen_string_literal: true

require "json"

module Wiq
  # Resolves host + alias + token from the documented precedence chain.
  #
  # Host:
  #   --host > WIQ_HOST > .wiq/config.json:host > sole stored host
  #         > PRODUCTION_HOST
  #
  # Alias (only meaningful once host is known):
  #   --as > WIQ_ALIAS > .wiq/config.json:alias > sole alias for host > "default"
  #
  # Token:
  #   WIQ_TOKEN (direct override) > credentials store (host, alias)
  class Config
    PRODUCTION_HOST = "https://www.wrestlingiq.com"

    attr_reader :host, :alias_name, :token, :sources

    def self.load(options = {})
      new(options).tap(&:resolve!)
    end

    def initialize(options = {})
      @options = options || {}
      @sources = {}
    end

    def resolve!
      @host = resolve_host
      @alias_name = resolve_alias if @host
      @token = resolve_token
      self
    end

    def require_host!
      raise HostUnsetError unless @host
    end

    def require_token!
      require_host!
      return if @token

      # No env override, no usable alias-keyed entry — decide which error to raise.
      aliases = Credentials.aliases_for(@host)
      if aliases.empty?
        raise NotAuthenticatedError
      elsif @alias_name && !Credentials.for_host(@host, @alias_name)
        raise AliasNotFoundError.new(@host, @alias_name, aliases)
      elsif @alias_name.nil?
        raise AmbiguousAliasError.new(@host, aliases)
      else
        raise NotAuthenticatedError
      end
    end

    def trace
      {
        host: @host,
        host_source: @sources[:host],
        alias: @alias_name,
        alias_source: @sources[:alias],
        token_present: !@token.nil?,
        token_source: @sources[:token],
        credentials_path: Credentials.path,
        repo_config_path: repo_config_path
      }
    end

    private

    def resolve_host
      if (val = @options[:host])
        @sources[:host] = "--host flag"
        return val
      end
      if (val = ENV["WIQ_HOST"])
        @sources[:host] = "WIQ_HOST env"
        return val
      end
      if (val = repo_config["host"])
        @sources[:host] = "repo config (#{repo_config_path})"
        return val
      end
      hosts = Credentials.hosts
      if hosts.size == 1
        @sources[:host] = "credentials store (sole host)"
        return hosts.first
      end
      @sources[:host] = "production default"
      PRODUCTION_HOST
    end

    def resolve_alias
      if (val = @options[:as])
        @sources[:alias] = "--as flag"
        return val
      end
      if (val = ENV["WIQ_ALIAS"])
        @sources[:alias] = "WIQ_ALIAS env"
        return val
      end
      if (val = repo_config["alias"])
        @sources[:alias] = "repo config (#{repo_config_path})"
        return val
      end
      aliases = Credentials.aliases_for(@host)
      if aliases.size == 1
        @sources[:alias] = "credentials store (sole alias)"
        return aliases.first
      end
      if aliases.include?(Credentials::DEFAULT_ALIAS)
        @sources[:alias] = "credentials store (default)"
        return Credentials::DEFAULT_ALIAS
      end
      @sources[:alias] = aliases.empty? ? "no credentials stored" : "ambiguous (#{aliases.join(", ")})"
      nil
    end

    def resolve_token
      return nil unless @host

      if (val = ENV["WIQ_TOKEN"])
        @sources[:token] = "WIQ_TOKEN env"
        return val
      end
      return nil unless @alias_name

      entry = Credentials.for_host(@host, @alias_name)
      return nil unless entry && entry["token"]

      @sources[:token] = "credentials store (alias=#{@alias_name})"
      entry["token"]
    end

    def repo_config
      @repo_config ||= load_repo_config
    end

    def repo_config_path
      @repo_config_path
    end

    def load_repo_config
      dir = Dir.pwd
      while dir != "/" && !dir.empty?
        candidate = File.join(dir, ".wiq", "config.json")
        if File.exist?(candidate)
          @repo_config_path = candidate
          begin
            return JSON.parse(File.read(candidate))
          rescue JSON::ParserError
            return {}
          end
        end
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      {}
    end
  end
end
