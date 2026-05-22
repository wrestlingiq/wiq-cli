require_relative "lib/wiq/version"

Gem::Specification.new do |spec|
  spec.name = "wiq-cli"
  spec.version = Wiq::VERSION
  spec.authors = ["WrestlingIQ"]
  spec.email = ["support@wrestlingiq.com"]

  spec.summary = "Command-line interface for the WrestlingIQ API"
  spec.description = "Agent-native CLI for reading WrestlingIQ data via /api/v1 personal access tokens."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.homepage = "https://github.com/wrestlingiq/wiq-cli"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/wrestlingiq/wiq-cli",
    "bug_tracker_uri" => "https://github.com/wrestlingiq/wiq-cli/issues",
    "documentation_uri" => "https://github.com/wrestlingiq/wiq-cli#readme",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "bin/wiq",
    "docs/**/*.md",
    "share/**/*.md",
    "README.md",
    "LICENSE",
    "LICENSE.txt"
  ].select { |f| File.file?(f) }
  spec.bindir = "bin"
  spec.executables = ["wiq"]
  spec.require_paths = ["lib"]

  spec.add_dependency "thor", "~> 1.3"
  spec.add_dependency "faraday", "~> 2.9"
  spec.add_dependency "faraday-retry", "~> 2.2"

  spec.add_development_dependency "rspec", "~> 3.13"
end
