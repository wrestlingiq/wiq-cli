# frozen_string_literal: true

require "json"

module Wiq
  # Walks Thor's command registry and produces a stable JSON shape for agents
  # to introspect the CLI surface in one call.
  #
  # Schema (nested):
  #   {
  #     "name": "wiq",
  #     "version": "0.1.0",
  #     "global_options": [ ... ],
  #     "top_level_commands": [ ... ],
  #     "groups": [ { "name": "...", "description": "...", "commands": [ ... ] } ]
  #   }
  module Introspection
    # Thor auto-generates these on every Thor::Group subclass; they're not
    # useful for agents and would just bloat the dump.
    INTERNAL_COMMANDS = %w[help tree].freeze

    module_function

    def dump_tree(root: Wiq::CLI)
      {
        "name" => "wiq",
        "version" => Wiq::VERSION,
        "global_options" => dump_options(Wiq::Commands::Base.class_options),
        "top_level_commands" => dump_commands(root.commands, klass: root),
        "groups" => root.subcommand_classes.sort.map do |name, klass|
          dump_group(name, klass, root)
        end
      }
    end

    def dump_group(name, klass, root)
      {
        "name" => name,
        "description" => root.commands[name]&.description,
        "commands" => dump_commands(klass.commands, klass: klass)
      }
    end

    def dump_commands(commands, klass:)
      aliases = method_to_alias(klass)
      commands
        .reject { |k, _| INTERNAL_COMMANDS.include?(k) || subcommand_name?(klass, k) }
        .map { |k, cmd| dump_command(cmd, display_name: aliases[k] || k) }
        .sort_by { |row| row["name"] }
    end

    def dump_command(cmd, display_name:)
      {
        "name" => display_name,
        "description" => cmd.description,
        "long_description" => cmd.long_description,
        "usage" => cmd.usage,
        "options" => dump_options(cmd.options)
      }
    end

    # Thor's `map` declares user-facing command aliases. `map "run" => :run_report`
    # means when a user types `wiq reports run`, Thor dispatches to method
    # :run_report. Internally Thor stores the command under "run_report" — the
    # method name — but agents need to see "run" (the name they type).
    # Build a reverse map: method_name (String) => alias_name (String).
    #
    # Flag-style aliases (--version, -v) are also registered via `map` for
    # convenience but they're not command names — skip them.
    def method_to_alias(klass)
      return {} unless klass.respond_to?(:map)

      klass.map.each_with_object({}) do |(alias_name, method_name), h|
        alias_str = alias_name.to_s
        next if alias_str.start_with?("-")

        h[method_name.to_s] = alias_str
      end
    end

    def dump_options(options)
      options.sort.map do |name, opt|
        row = {
          "name" => name.to_s,
          "type" => opt.type.to_s,
          "required" => opt.required?,
          "description" => opt.description
        }
        row["default"] = opt.default unless opt.default.nil?
        row["enum"] = opt.enum if opt.enum
        row
      end
    end

    # When a class registers a `subcommand "foo", FooClass`, Thor also adds
    # a placeholder command named "foo" to the parent's commands hash. Skip
    # those when listing the parent's own commands — they're rendered as
    # groups, not commands.
    def subcommand_name?(klass, command_name)
      return false unless klass.respond_to?(:subcommand_classes)

      klass.subcommand_classes.key?(command_name)
    end
  end
end
