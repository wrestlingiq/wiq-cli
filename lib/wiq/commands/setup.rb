# frozen_string_literal: true

require "fileutils"

module Wiq
  module Commands
    class Setup < Base
      SKILL_FILENAME = "SKILL.md"
      BUNDLED_SKILL_PATH = File.expand_path("../../../../share/skills/wiq/#{SKILL_FILENAME}", __FILE__)

      desc "claude", "Install the wiq Claude Code skill"
      long_desc <<~DESC
        Copies the bundled SKILL.md into the right location for Claude Code
        to auto-detect.

        Default install (user-global):
          ~/.claude/skills/wiq/SKILL.md

        Per-project install (--project):
          ./.claude/skills/wiq/SKILL.md

        Claude Code watches both locations live during a session — no
        restart needed. Re-run with --force to overwrite an existing
        install (useful when upgrading the gem).

        The skill is read-only on the WIQ side: it teaches Claude how to
        drive `wiq`, but doesn't touch any WIQ data.
      DESC
      method_option :project, type: :boolean, default: false,
                              desc: "Install per-project (./.claude/skills/) instead of user-global"
      method_option :force, type: :boolean, default: false,
                            desc: "Overwrite an existing SKILL.md at the target path"
      method_option :print, type: :boolean, default: false,
                            desc: "Print SKILL.md to stdout instead of installing"
      def claude
        unless File.exist?(BUNDLED_SKILL_PATH)
          raise Wiq::Error.new(
            "Bundled SKILL.md not found at #{BUNDLED_SKILL_PATH}.",
            code: "skill_missing",
            hint: "Reinstall wiq-cli — the gem package may be incomplete."
          )
        end

        if options[:print]
          puts File.read(BUNDLED_SKILL_PATH)
          return
        end

        target_dir = options[:project] ? File.join(Dir.pwd, ".claude", "skills", "wiq")
                                       : File.join(Dir.home, ".claude", "skills", "wiq")
        target_path = File.join(target_dir, SKILL_FILENAME)

        if File.exist?(target_path) && !options[:force]
          raise Wiq::Error.new(
            "#{target_path} already exists.",
            code: "skill_exists",
            hint: "Pass --force to overwrite, or --print to inspect the bundled version first."
          )
        end

        FileUtils.mkdir_p(target_dir)
        FileUtils.cp(BUNDLED_SKILL_PATH, target_path)

        render(
          {
            "scope" => options[:project] ? "project" : "user-global",
            "target_path" => target_path,
            "size_bytes" => File.size(target_path),
            "claude_will_auto_detect" => true
          },
          summary: "Installed Claude Code skill to #{target_path}.",
          breadcrumbs: [
            { "cmd" => "wiq setup claude --print",
              "description" => "Inspect the bundled skill content" },
            { "cmd" => "wiq setup claude --force",
              "description" => "Re-install (e.g. after upgrading wiq-cli)" }
          ]
        )
      end
    end
  end
end
