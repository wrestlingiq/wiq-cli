# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "wiq"
require "tmpdir"
require "fileutils"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  # Each example gets a clean credentials path + env. Anything a test sets
  # via ENV[...] = should be reverted; the around hook below snapshots and
  # restores the env vars our config cares about.
  config.around(:each) do |example|
    Dir.mktmpdir do |dir|
      original_env = {}
      %w[WIQ_HOST WIQ_TOKEN WIQ_ALIAS WIQ_CREDENTIALS_PATH].each do |key|
        original_env[key] = ENV[key]
        ENV.delete(key)
      end
      ENV["WIQ_CREDENTIALS_PATH"] = File.join(dir, "credentials.json")

      example.run
    ensure
      original_env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
  end
end
