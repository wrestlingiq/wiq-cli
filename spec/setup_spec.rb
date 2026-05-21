# frozen_string_literal: true

RSpec.describe Wiq::Commands::Setup do
  let(:tmp_home) { Dir.mktmpdir }
  let(:project_dir) { Dir.mktmpdir }

  before do
    allow(Dir).to receive(:home).and_return(tmp_home)
  end

  after do
    FileUtils.rm_rf(tmp_home)
    FileUtils.rm_rf(project_dir)
  end

  def run_claude(args)
    described_class.start(["claude", *args])
  end

  describe "bundled skill" do
    it "ships SKILL.md inside the gem at share/skills/wiq/" do
      expect(File.exist?(described_class::BUNDLED_SKILL_PATH)).to be true
    end

    it "has the YAML frontmatter Claude Code expects" do
      content = File.read(described_class::BUNDLED_SKILL_PATH)
      expect(content).to start_with("---\n")
      expect(content).to match(/^name: wiq$/)
      expect(content).to match(/^description: /)
    end

    it "is under the 1536-character description limit Claude Code enforces" do
      content = File.read(described_class::BUNDLED_SKILL_PATH)
      frontmatter = content.split("---\n")[1] || ""
      description_match = frontmatter.match(/^description: (.+?)(?=\n[a-z_]+:|\z)/m)
      expect(description_match).not_to be_nil
      description_text = description_match[1].strip
      expect(description_text.length).to be <= 1536
    end
  end

  describe "--print" do
    it "writes SKILL.md to stdout without touching the filesystem" do
      output = capture_stdout { run_claude(["--print"]) }
      expect(output).to include("# WrestlingIQ CLI Skill")
      expect(File.exist?(File.join(tmp_home, ".claude/skills/wiq/SKILL.md"))).to be false
    end
  end

  describe "user-global install" do
    it "writes to ~/.claude/skills/wiq/SKILL.md" do
      capture_stdout { run_claude([]) }
      target = File.join(tmp_home, ".claude/skills/wiq/SKILL.md")
      expect(File.exist?(target)).to be true
      expect(File.read(target)).to start_with("---\n")
    end

    it "creates intermediate directories" do
      expect(File.directory?(File.join(tmp_home, ".claude"))).to be false
      capture_stdout { run_claude([]) }
      expect(File.directory?(File.join(tmp_home, ".claude/skills/wiq"))).to be true
    end
  end

  describe "--project install" do
    it "writes to ./.claude/skills/wiq/SKILL.md relative to cwd" do
      Dir.chdir(project_dir) do
        capture_stdout { run_claude(["--project"]) }
        target = File.join(project_dir, ".claude/skills/wiq/SKILL.md")
        expect(File.exist?(target)).to be true
      end
    end

    it "does NOT touch the user-global path when --project is set" do
      Dir.chdir(project_dir) do
        capture_stdout { run_claude(["--project"]) }
      end
      expect(File.exist?(File.join(tmp_home, ".claude/skills/wiq/SKILL.md"))).to be false
    end
  end

  describe "existing-target safety" do
    let(:target) { File.join(tmp_home, ".claude/skills/wiq/SKILL.md") }

    before do
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, "preserve me")
    end

    it "raises skill_exists when the target is already present and --force is not set" do
      expect { run_claude([]) }.to raise_error(Wiq::Error) { |e|
        expect(e.code).to eq("skill_exists")
        expect(e.hint).to match(/--force/)
      }
      expect(File.read(target)).to eq("preserve me")
    end

    it "overwrites when --force is passed" do
      capture_stdout { run_claude(["--force"]) }
      expect(File.read(target)).to start_with("---\n")
      expect(File.read(target)).not_to eq("preserve me")
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
