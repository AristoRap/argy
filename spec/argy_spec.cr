require "./spec_helper"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

private def make_root
  Argy::Command.new(use: "root", short: "root command")
end

class SilentHelpCommand < Argy::Command
  def print_help(io : IO = STDOUT) : Nil
  end
end

class TrackingHelpCommand < Argy::Command
  getter help_calls : Int32 = 0

  def print_help(io : IO = STDOUT) : Nil
    @help_calls += 1
  end
end

class Argy::Command
  def __execute_without_rescue_for_spec(argv : Array(String)) : Nil
    argv = argv[1..] if argv.first? == name
    root = root_command
    root.reset_tree_state!
    root.validate_tree_flag_collisions!
    _execute(argv)
  end
end

# ---------------------------------------------------------------------------
# FlagSet parsing
# ---------------------------------------------------------------------------

describe Argy::FlagSet do
  describe "#parse" do
    it "parses a long string flag" do
      fs = Argy::FlagSet.new
      fs.string("name", nil, "", "your name")
      remaining = [] of String
      fs.parse(["--name", "Alice"], remaining)
      fs.lookup("name").as(Argy::StringFlag).value.should eq "Alice"
      remaining.should be_empty
    end

    it "parses --key=value syntax" do
      fs = Argy::FlagSet.new
      fs.string("output", 'o', "", "output file")
      remaining = [] of String
      fs.parse(["--output=/tmp/result.txt"], remaining)
      fs.lookup("output").as(Argy::StringFlag).value.should eq "/tmp/result.txt"
    end

    it "parses a shorthand flag" do
      fs = Argy::FlagSet.new
      fs.int("port", 'p', 3000, "port")
      remaining = [] of String
      fs.parse(["-p", "9000"], remaining)
      fs.lookup("port").as(Argy::IntFlag).value.should eq 9000
    end

    it "parses -Xvalue shorthand style" do
      fs = Argy::FlagSet.new
      fs.string("format", 'f', "json", "output format")
      remaining = [] of String
      fs.parse(["-fyaml"], remaining)
      fs.lookup("format").as(Argy::StringFlag).value.should eq "yaml"
    end

    it "parses a bool flag implicitly (no value)" do
      fs = Argy::FlagSet.new
      fs.bool("verbose", 'v', false, "verbose output")
      remaining = [] of String
      fs.parse(["--verbose"], remaining)
      fs.lookup("verbose").as(Argy::BoolFlag).value.should be_true
    end

    it "parses a bool flag with explicit value" do
      fs = Argy::FlagSet.new
      fs.bool("quiet", nil, true, "suppress output")
      remaining = [] of String
      fs.parse(["--quiet=false"], remaining)
      fs.lookup("quiet").as(Argy::BoolFlag).value.should be_false
    end

    it "parses a bool flag with explicit separate value" do
      fs = Argy::FlagSet.new
      fs.bool("verbose", 'v', true, "verbose output")
      remaining = [] of String
      fs.parse(["--verbose", "false"], remaining)
      fs.lookup("verbose").as(Argy::BoolFlag).value.should be_false
      remaining.should be_empty
    end

    it "parses shorthand bool with explicit separate value" do
      fs = Argy::FlagSet.new
      fs.bool("verbose", 'v', true, "verbose output")
      remaining = [] of String
      fs.parse(["-v", "false"], remaining)
      fs.lookup("verbose").as(Argy::BoolFlag).value.should be_false
      remaining.should be_empty
    end

    it "parses shorthand bool with equals syntax" do
      fs = Argy::FlagSet.new
      fs.bool("verbose", 'v', true, "verbose output")
      remaining = [] of String
      fs.parse(["-v=false"], remaining)
      fs.lookup("verbose").as(Argy::BoolFlag).value.should be_false
    end

    it "collects positional arguments" do
      fs = Argy::FlagSet.new
      fs.bool("dry-run", nil, false, "dry run")
      remaining = [] of String
      fs.parse(["file1.txt", "--dry-run", "file2.txt"], remaining)
      remaining.should eq ["file1.txt", "file2.txt"]
    end

    it "stops parsing at bare --" do
      fs = Argy::FlagSet.new
      fs.string("name", nil, "", "name")
      remaining = [] of String
      fs.parse(["--name", "Bob", "--", "--not-a-flag"], remaining)
      fs.lookup("name").as(Argy::StringFlag).value.should eq "Bob"
      remaining.should eq ["--not-a-flag"]
    end

    it "raises UnknownFlagError for unknown flags" do
      fs = Argy::FlagSet.new
      remaining = [] of String
      expect_raises(Argy::UnknownFlagError) do
        fs.parse(["--bogus"], remaining)
      end
    end

    it "raises UnknownFlagError for unknown shorthand flags" do
      fs = Argy::FlagSet.new
      remaining = [] of String
      expect_raises(Argy::UnknownFlagError) do
        fs.parse(["-x"], remaining)
      end
    end

    it "raises InvalidFlagValueError for bad int value" do
      fs = Argy::FlagSet.new
      fs.int("count", nil, 0, "count")
      remaining = [] of String
      expect_raises(Argy::InvalidFlagValueError) do
        fs.parse(["--count=abc"], remaining)
      end
    end

    it "marks a flag as changed after parsing" do
      fs = Argy::FlagSet.new
      flag = fs.string("env", 'e', "dev", "environment")
      remaining = [] of String
      flag.changed.should be_false
      fs.parse(["--env", "prod"], remaining)
      flag.changed.should be_true
    end

    it "raises MissingFlagValueError for long flag without value" do
      fs = Argy::FlagSet.new
      fs.string("name", nil, "", "name")
      remaining = [] of String
      expect_raises(Argy::MissingFlagValueError) do
        fs.parse(["--name"], remaining)
      end
    end

    it "raises MissingFlagValueError for shorthand flag without value" do
      fs = Argy::FlagSet.new
      fs.int("port", 'p', 3000, "port")
      remaining = [] of String
      expect_raises(Argy::MissingFlagValueError) do
        fs.parse(["-p"], remaining)
      end
    end

    it "does not consume another flag token as a value" do
      fs = Argy::FlagSet.new
      fs.string("name", nil, "", "name")
      fs.bool("other", nil, false, "other")
      remaining = [] of String
      expect_raises(Argy::MissingFlagValueError) do
        fs.parse(["--name", "--other"], remaining)
      end
    end

    it "parses shorthand with equals syntax" do
      fs = Argy::FlagSet.new
      fs.int("port", 'p', 3000, "port")
      remaining = [] of String
      fs.parse(["-p=8080"], remaining)
      fs.lookup("port").as(Argy::IntFlag).value.should eq 8080
    end

    it "parses negative int values from separate tokens" do
      fs = Argy::FlagSet.new
      fs.int("count", nil, 0, "count")
      remaining = [] of String
      fs.parse(["--count", "-5"], remaining)
      fs.lookup("count").as(Argy::IntFlag).value.should eq -5
      remaining.should be_empty
    end

    it "parses negative int values from inline syntax" do
      fs = Argy::FlagSet.new
      fs.int("count", nil, 0, "count")
      remaining = [] of String
      fs.parse(["--count=-5"], remaining)
      fs.lookup("count").as(Argy::IntFlag).value.should eq -5
      remaining.should be_empty
    end

    it "parses negative float values from separate tokens" do
      fs = Argy::FlagSet.new
      fs.float("ratio", nil, 0.0, "ratio")
      remaining = [] of String
      fs.parse(["--ratio", "-3.14"], remaining)
      fs.lookup("ratio").as(Argy::Float64Flag).value.should eq -3.14
      remaining.should be_empty
    end

    it "ignores unknown flags when ignore_unknown=true" do
      fs = Argy::FlagSet.new
      fs.bool("verbose", 'v', false, "verbose")
      remaining = [] of String
      fs.parse(["--bogus", "-v", "-x", "-xfoo", "file.txt"], remaining, ignore_unknown: true)
      fs.lookup("verbose").as(Argy::BoolFlag).value.should be_true
      remaining.should eq ["--bogus", "-x", "-xfoo", "file.txt"]
    end

    it "handles mixed parsing without leaking consumed values" do
      fs = Argy::FlagSet.new
      fs.int("count", nil, 0, "count")
      fs.bool("verbose", 'v', true, "verbose")
      remaining = [] of String
      fs.parse(["--count", "-5", "-v", "false", "file.txt"], remaining)
      fs.lookup("count").as(Argy::IntFlag).value.should eq -5
      fs.lookup("verbose").as(Argy::BoolFlag).value.should be_false
      remaining.should eq ["file.txt"]
    end

    it "preserves positional args while parsing flags" do
      fs = Argy::FlagSet.new
      fs.bool("flag", nil, false, "flag")
      remaining = [] of String
      fs.parse(["file1", "--flag", "file2"], remaining)
      fs.lookup("flag").as(Argy::BoolFlag).value.should be_true
      remaining.should eq ["file1", "file2"]
    end

    it "uses the last value when a flag is repeated" do
      fs = Argy::FlagSet.new
      fs.string("name", nil, "", "name")
      remaining = [] of String
      fs.parse(["--name", "Alice", "--name", "Bob"], remaining)
      fs.lookup("name").as(Argy::StringFlag).value.should eq "Bob"
    end

    it "parses true and false bool literals across supported aliases" do
      fs = Argy::FlagSet.new
      fs.bool("flag", nil, false, "flag")

      ["true", "1", "yes", "on"].each do |token|
        fs.reset!
        remaining = [] of String
        fs.parse(["--flag", token], remaining)
        fs.lookup("flag").as(Argy::BoolFlag).value.should be_true
      end

      ["false", "0", "no", "off"].each do |token|
        fs.reset!
        remaining = [] of String
        fs.parse(["--flag", token], remaining)
        fs.lookup("flag").as(Argy::BoolFlag).value.should be_false
      end
    end
  end

  describe "registration" do
    it "raises DuplicateFlagError on duplicate long name" do
      fs = Argy::FlagSet.new
      fs.string("name", nil, "", "name")

      expect_raises(Argy::DuplicateFlagError) do
        fs.string("name", 'n', "", "name again")
      end
    end

    it "raises DuplicateFlagError on duplicate shorthand" do
      fs = Argy::FlagSet.new
      fs.string("name", 'n', "", "name")

      expect_raises(Argy::DuplicateFlagError) do
        fs.string("nickname", 'n', "", "nickname")
      end
    end
  end
end

# ---------------------------------------------------------------------------
# Command routing
# ---------------------------------------------------------------------------

describe Argy::Command do
  describe "subcommand routing" do
    it "routes to a matching subcommand" do
      called_on = nil
      root = make_root

      child = Argy::Command.new(
        use: "child",
        short: "child command"
      )
      child.on_run { |cmd, _args| called_on = cmd.name }
      root.add_command(child)

      # capture stdout to suppress help
      root.execute(["child"])
      called_on.should eq "child"
    end

    it "routes to a nested subcommand two levels deep" do
      depth = 0
      root = make_root

      mid = Argy::Command.new(use: "mid", short: "mid")
      leaf = Argy::Command.new(
        use: "leaf",
        short: "leaf"
      )
      leaf.on_run { |_cmd, _args| depth = 2 }
      mid.add_command(leaf)
      root.add_command(mid)

      root.execute(["mid", "leaf"])
      depth.should eq 2
    end

    it "passes remaining args to the runner" do
      received_args = [] of String
      root = Argy::Command.new(use: "root")
      root.on_run { |_cmd, args| received_args = args }
      root.execute(["alpha", "beta"])
      received_args.should eq ["alpha", "beta"]
    end

    it "routes to a nested subcommand three levels deep" do
      called = false
      root = make_root

      db = Argy::Command.new(use: "db", short: "db")
      migrate = Argy::Command.new(use: "migrate", short: "migrate")
      up = Argy::Command.new(use: "up", short: "up")
      up.on_run { |_cmd, _args| called = true }

      migrate.add_command(up)
      db.add_command(migrate)
      root.add_command(db)

      root.execute(["db", "migrate", "up"])
      called.should be_true
    end

    it "raises UnknownCommandError for unknown subcommands" do
      root = make_root
      child = Argy::Command.new(use: "known", short: "known")
      child.on_run { |_cmd, _args| }
      root.add_command(child)

      expect_raises(Argy::UnknownCommandError) do
        root.__execute_without_rescue_for_spec(["unknown"])
      end
    end
  end

  describe "persistent flags" do
    it "makes persistent flags accessible to child commands" do
      root = make_root
      root.persistent_flags.bool("verbose", 'v', false, "verbose")

      child_verbose = false
      child = Argy::Command.new(
        use: "child"
      )
      child.on_run { |cmd, _args| child_verbose = cmd.bool_flag("verbose") }
      root.add_command(child)
      root.execute(["child", "--verbose"])
      child_verbose.should be_true
    end

    it "inherits persistent flags from all ancestors" do
      root = make_root
      root.persistent_flags.string("env", 'e', "dev", "env")

      db = Argy::Command.new(use: "db")
      db.persistent_flags.bool("verbose", 'v', false, "verbose")

      migrate = Argy::Command.new(use: "migrate")
      observed_env = ""
      observed_verbose = false
      migrate.on_run do |cmd, _args|
        observed_env = cmd.string_flag("env")
        observed_verbose = cmd.bool_flag("verbose")
      end

      db.add_command(migrate)
      root.add_command(db)
      root.execute(["db", "migrate", "--env", "production", "--verbose"])

      observed_env.should eq "production"
      observed_verbose.should be_true
    end

    it "raises DuplicateFlagError when ancestor persistent long names collide" do
      root = make_root
      root.persistent_flags.string("env", nil, "root", "env")

      db = Argy::Command.new(use: "db")
      db.persistent_flags.string("env", nil, "db", "env")

      leaf = Argy::Command.new(use: "leaf")
      leaf.on_run { |_cmd, _args| }

      db.add_command(leaf)
      root.add_command(db)

      expect_raises(Argy::DuplicateFlagError) do
        root.__execute_without_rescue_for_spec(["db", "leaf"])
      end
    end
  end

  describe "lifecycle hooks" do
    it "runs hooks in order: persistent_pre root->leaf, then pre_run, then run" do
      order = [] of String
      root = make_root

      db = Argy::Command.new(use: "db")
      leaf = Argy::Command.new(use: "migrate")

      root.on_persistent_pre_run { |_cmd, _args| order << "root.persistent_pre" }
      db.on_persistent_pre_run { |_cmd, _args| order << "db.persistent_pre" }
      leaf.on_pre_run { |_cmd, _args| order << "leaf.pre_run" }
      leaf.on_run { |_cmd, _args| order << "leaf.run" }

      db.add_command(leaf)
      root.add_command(db)
      root.execute(["db", "migrate"])

      order.should eq [
        "root.persistent_pre",
        "db.persistent_pre",
        "leaf.pre_run",
        "leaf.run",
      ]
    end

    it "short-circuits hooks and run handlers when --help is present" do
      order = [] of String
      cmd = SilentHelpCommand.new(use: "cmd")
      cmd.on_persistent_pre_run { |_c, _a| order << "persistent_pre" }
      cmd.on_pre_run { |_c, _a| order << "pre_run" }
      cmd.on_run { |_c, _a| order << "run" }

      cmd.execute(["--help"])
      order.should be_empty
    end

    it "short-circuits hooks across nested routing when --help is present" do
      order = [] of String

      root = Argy::Command.new(use: "root")
      db = Argy::Command.new(use: "db")
      leaf = SilentHelpCommand.new(use: "migrate")

      root.on_persistent_pre_run { |_c, _a| order << "root.persistent_pre" }
      db.on_persistent_pre_run { |_c, _a| order << "db.persistent_pre" }
      leaf.on_pre_run { |_c, _a| order << "leaf.pre_run" }
      leaf.on_run { |_c, _a| order << "leaf.run" }

      db.add_command(leaf)
      root.add_command(db)

      root.execute(["db", "migrate", "--help"])
      order.should be_empty
    end

    it "prints help when a matched command has no run handler" do
      root = Argy::Command.new(use: "root")
      group = TrackingHelpCommand.new(use: "group")
      root.add_command(group)

      root.execute(["group"])
      group.help_calls.should eq 1
    end
  end

  describe "help rendering" do
    it "prints root help when argv is empty and subcommands exist" do
      root = TrackingHelpCommand.new(use: "root")
      child_called = false

      child = Argy::Command.new(use: "child")
      child.on_run { |_cmd, _args| child_called = true }
      root.add_command(child)

      root.execute([] of String)

      root.help_calls.should eq 1
      child_called.should be_false
    end

    it "prints help sections in expected order" do
      root = Argy::Command.new(use: "root", short: "root")
      root.persistent_flags.string("env", 'e', "dev", "env")

      child = Argy::Command.new(use: "child", short: "child")
      leaf = Argy::Command.new(use: "leaf", short: "leaf")

      child.flags.bool("dry-run", 'd', false, "dry run")
      child.persistent_flags.bool("verbose", 'v', false, "verbose")

      child.add_command(leaf)
      root.add_command(child)

      output = IO::Memory.new
      child.print_help(output)
      text = output.to_s

      usage_i = text.index("Usage:").not_nil!
      available_i = text.index("Available Commands:").not_nil!
      flags_i = text.index("Flags:").not_nil!
      global_i = text.index("Global Flags:").not_nil!
      persistent_i = text.index("Persistent Flags:").not_nil!

      (usage_i < available_i).should be_true
      (available_i < flags_i).should be_true
      (flags_i < global_i).should be_true
      (global_i < persistent_i).should be_true
    end
  end

  describe "state reset across executions" do
    it "resets flag values to defaults on each execute" do
      cmd = Argy::Command.new(use: "cmd")
      cmd.flags.bool("verbose", 'v', false, "verbose")

      seen = [] of Bool
      cmd.on_run { |c, _args| seen << c.bool_flag("verbose") }

      cmd.execute(["--verbose"])
      cmd.execute([] of String)

      seen.should eq [true, false]
    end

    it "resets changed markers on each execute" do
      cmd = Argy::Command.new(use: "cmd")
      cmd.flags.string("env", 'e', "dev", "env")

      changed_states = [] of Bool
      cmd.on_run do |c, _args|
        changed_states << c.flags.lookup("env").not_nil!.changed
      end

      cmd.execute(["--env", "prod"])
      cmd.execute([] of String)

      changed_states.should eq [true, false]
    end
  end

  describe "flag collision safety" do
    it "raises DuplicateFlagError when local and inherited persistent long names collide" do
      root = make_root
      root.persistent_flags.string("env", nil, "dev", "env")

      child = Argy::Command.new(use: "child")
      child.flags.string("env", 'e', "child", "env override")
      child.on_run { |_cmd, _args| }

      root.add_command(child)

      expect_raises(Argy::DuplicateFlagError) do
        root.__execute_without_rescue_for_spec(["child"])
      end
    end

    it "raises DuplicateFlagError when local and inherited persistent shorthands collide" do
      root = make_root
      root.persistent_flags.bool("verbose", 'v', false, "verbose")

      child = Argy::Command.new(use: "child")
      child.flags.bool("version", 'v', false, "version")
      child.on_run { |_cmd, _args| }

      root.add_command(child)

      expect_raises(Argy::DuplicateFlagError) do
        root.__execute_without_rescue_for_spec(["child"])
      end
    end
  end

  describe "typed accessors" do
    it "returns the correct string flag value" do
      received = ""
      cmd = Argy::Command.new(use: "cmd")
      cmd.on_run { |c, _args| received = c.string_flag("env") }
      cmd.flags.string("env", 'e', "dev", "environment")
      cmd.execute(["--env", "production"])
      received.should eq "production"
    end

    it "returns the correct int flag value" do
      received = 0
      cmd = Argy::Command.new(use: "cmd")
      cmd.on_run { |c, _args| received = c.int_flag("workers") }
      cmd.flags.int("workers", 'w', 1, "worker count")
      cmd.execute(["-w", "4"])
      received.should eq 4
    end
  end

  describe "#name" do
    it "extracts the name from the use line" do
      cmd = Argy::Command.new(use: "serve [flags]", short: "serve")
      cmd.name.should eq "serve"
    end
  end
end
