# frozen_string_literal: true

RSpec.describe Wiq::Workflows do
  let(:all_workflows) { described_class::ALL }

  describe "schema invariants" do
    it "keys the hash by the same string as the workflow's :name field" do
      all_workflows.each do |key, workflow|
        expect(workflow[:name]).to eq(key),
                                  "Workflow at key #{key.inspect} has name=#{workflow[:name].inspect}"
      end
    end

    it "uses kebab-case slugs (lowercase letters + digits + hyphens only)" do
      all_workflows.each_key do |key|
        expect(key).to match(/\A[a-z0-9]+(-[a-z0-9]+)*\z/),
                       "Workflow name #{key.inspect} is not kebab-case"
      end
    end

    it "assigns every workflow a valid category" do
      all_workflows.each_value do |workflow|
        expect(described_class::CATEGORIES).to include(workflow[:category]),
                                               "Workflow #{workflow[:name]} has invalid category #{workflow[:category].inspect}"
      end
    end

    it "carries the required top-level fields on every workflow" do
      all_workflows.each_value do |workflow|
        %i[name category question parameters recipe].each do |key|
          expect(workflow).to have_key(key),
                              "Workflow #{workflow[:name]} missing :#{key}"
        end
      end
    end

    it "always lists at least one recipe step starting with `wiq `" do
      all_workflows.each_value do |workflow|
        expect(workflow[:recipe]).not_to be_empty,
                                         "Workflow #{workflow[:name]} has an empty recipe"
        workflow[:recipe].each do |cmd|
          expect(cmd).to start_with("wiq "),
                         "Workflow #{workflow[:name]} has non-`wiq` recipe step: #{cmd.inspect}"
        end
      end
    end
  end

  describe "placeholder ↔ parameter cross-reference" do
    # Catches drift between the structured `parameters:` list and the visible
    # `<placeholder>` substitutions in the recipe strings. If a parameter is
    # declared but never used (or vice versa), the workflow is broken.
    it "ensures every declared parameter appears as <name> somewhere in the recipe" do
      all_workflows.each_value do |workflow|
        recipe_text = workflow[:recipe].join("\n")
        workflow[:parameters].each do |param|
          marker = "<#{param[:name]}>"
          expect(recipe_text).to include(marker),
                                 "Workflow #{workflow[:name]} declares parameter " \
                                 "#{param[:name].inspect} but the recipe never references " \
                                 "it as #{marker.inspect}."
        end
      end
    end

    it "ensures every <placeholder> in the recipe maps to a declared parameter" do
      all_workflows.each_value do |workflow|
        recipe_text = workflow[:recipe].join("\n")
        placeholders = recipe_text.scan(/<([a-z][a-z0-9_]*)>/i).flatten.uniq
        declared = workflow[:parameters].map { |p| p[:name] }
        placeholders.each do |placeholder|
          expect(declared).to include(placeholder),
                              "Workflow #{workflow[:name]} uses <#{placeholder}> in its " \
                              "recipe but doesn't declare it under :parameters."
        end
      end
    end
  end

  describe "admin_only consistency" do
    # The 9 reports listed in Reports::TYPES with admin_only: true require an
    # admin coach PAT. Any workflow whose recipe submits one of those reports
    # MUST itself carry admin_only: true. Otherwise an agent will hit a
    # surprise 403.
    let(:admin_only_reports) do
      Wiq::Commands::Reports::TYPES.select { |_, info| info[:admin_only] }.keys
    end

    it "propagates admin_only from the underlying report" do
      all_workflows.each_value do |workflow|
        triggers_admin = workflow[:recipe].any? do |cmd|
          admin_only_reports.any? { |report_type| cmd.include?(report_type) }
        end
        next unless triggers_admin

        expect(workflow[:admin_only]).to be(true),
                                         "Workflow #{workflow[:name]} runs an admin_only report " \
                                         "but isn't marked admin_only itself."
      end
    end
  end

  describe Wiq::Commands::Workflows do
    it "rejects unknown workflow names with a structured error" do
      expect { described_class.new.show("does-not-exist") }
        .to raise_error(Wiq::Error) { |e| expect(e.code).to eq("workflow_not_found") }
    end
  end
end
