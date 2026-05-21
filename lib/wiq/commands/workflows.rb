# frozen_string_literal: true

module Wiq
  module Commands
    class Workflows < Base
      desc "list", "List all documented workflows"
      long_desc <<~DESC
        Workflows are named recipes that map a human question to a CLI
        command sequence. Use them to bootstrap agent flows for common
        club-admin tasks.

        Each workflow carries:
          name         kebab-case slug (the lookup key)
          category     attendance | leads | roster | finance |
                       memberships | fundraising | store
          question     natural-language framing — match against this
          parameters   structured list of {name, type, required, ...}
          recipe       ordered command strings with <placeholder> and
                       [optional] brackets
          admin_only   true means non-admin coach PATs will 403
          notes        when present, agent-facing guidance

        Placeholder syntax in recipes:
          <name>          required substitution (must match a parameter)
          [--flag <name>] optional bracket — drop the whole thing when
                          the parameter isn't provided

        Run `wiq workflows show <name>` for a single workflow's full detail.
      DESC
      def list
        rows = Wiq::Workflows::ALL.values.map { |w| summary_row(w) }
        render_index(
          rows,
          summary: "#{rows.size} documented workflows across #{Wiq::Workflows::CATEGORIES.size} categories.",
          breadcrumbs: [
            { "cmd" => "wiq workflows show <name>", "description" => "Detail for one workflow" },
            { "cmd" => "wiq commands", "description" => "Full command tree (for ad-hoc composition)" }
          ]
        )
      end

      desc "show NAME", "Show a single workflow's full detail"
      long_desc <<~DESC
        Returns the complete workflow definition: question, parameters
        (with types and required/default), the recipe (ordered command
        list), admin_only flag, and notes.

        Use this after `wiq workflows list` narrows you to a candidate.
      DESC
      def show(name)
        workflow = Wiq::Workflows::ALL[name]
        unless workflow
          available = Wiq::Workflows::ALL.keys.sort.join(", ")
          raise Wiq::Error.new(
            "Unknown workflow #{name.inspect}.",
            code: "workflow_not_found",
            hint: "Available: #{available}"
          )
        end

        render(workflow,
               summary: "#{workflow[:name]} — #{workflow[:question]}",
               breadcrumbs: workflow[:recipe].map do |cmd|
                 { "cmd" => cmd, "description" => "Run this step" }
               end)
      end

      default_task :list

      no_commands do
        def summary_row(workflow)
          {
            "name" => workflow[:name],
            "category" => workflow[:category],
            "question" => workflow[:question],
            "admin_only" => workflow[:admin_only] == true,
            "step_count" => workflow[:recipe].size,
            "parameter_count" => workflow[:parameters].size
          }
        end
      end
    end
  end
end
