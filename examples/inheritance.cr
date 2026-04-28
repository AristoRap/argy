require "../src/argy"

# Inheritance-style commands are defined as subclasses
# instead of being assembled entirely with Argy::Command.new.

class DevtoolCommand < Argy::Command
  def initialize
    super(
      use: "devtool",
      short: "Developer utility with subclassed commands",
      long: <<-LONG
            devtool demonstrates an object-oriented argy CLI.

            Each command is its own Crystal class, with flags, hooks, and behaviour
            defined where the command lives.
          LONG
    )

    persistent_flags.bool("verbose", 'v', false, "enable verbose logging")
    persistent_flags.string("config", 'c', "./devtool.yml", "path to config file")

    on_persistent_pre_run do |cmd, _args|
      next unless cmd.bool_flag("verbose")
      puts "[verbose] using config #{cmd.string_flag("config")}"
    end

    add_command(ServeCommand.new, DbCommand.new, DeployCommand.new)
  end
end

class ServeCommand < Argy::Command
  def initialize
    super(
      use: "serve [paths...]",
      short: "Start the local web server",
      long: "Start a local server and optionally mount one or more paths."
    )

    flags.string("host", nil, "127.0.0.1", "host interface to bind")
    flags.int("port", 'p', 8080, "port to listen on")
    flags.bool("tls", nil, false, "enable TLS")

    on_pre_run do |cmd, _args|
      puts "Preparing listener on #{cmd.string_flag("host")}:#{cmd.int_flag("port")}" if cmd.bool_flag("verbose")
    end

    on_run do |cmd, args|
      host = cmd.string_flag("host")
      port = cmd.int_flag("port")
      tls = cmd.bool_flag("tls")

      puts "Serving #{args.empty? ? "current directory" : args.join(", ")}"
      puts "Endpoint: #{tls ? "https" : "http"}://#{host}:#{port}"
    end
  end

  def print_help(io : IO = STDOUT) : Nil
    super
    io.puts
    io.puts "Examples:"
    io.puts "  devtool serve"
    io.puts "  devtool serve public assets --port 9000 --tls"
  end
end

class DbCommand < Argy::Command
  def initialize
    super(
      use: "db",
      short: "Database operations",
      long: "db groups commands that act on the application database."
    )

    persistent_flags.string("env", 'e', "development", "database environment")

    add_command(MigrateCommand.new, SeedCommand.new)
  end
end

class MigrateCommand < Argy::Command
  def initialize
    super(
      use: "migrate",
      short: "Run schema migrations"
    )

    flags.int("steps", 's', 0, "limit how many migrations to apply (0 = all)")
    flags.bool("dry-run", 'd', false, "print what would happen without applying changes")

    on_run do |cmd, _args|
      env = cmd.string_flag("env")
      steps = cmd.int_flag("steps")
      dry_run = cmd.bool_flag("dry-run")

      puts "Migrating #{env} database"
      puts steps.zero? ? "Applying all pending migrations" : "Applying #{steps} migration(s)"
      puts "Mode: #{dry_run ? "dry-run" : "live"}"
    end
  end
end

class SeedCommand < Argy::Command
  def initialize
    super(
      use: "seed [dataset]",
      short: "Load seed data"
    )

    flags.bool("truncate", nil, false, "clear tables before seeding")

    on_run do |cmd, args|
      dataset = args.first? || "default"
      env = cmd.string_flag("env")
      truncate = cmd.bool_flag("truncate")

      puts "Seeding #{env} database with #{dataset.inspect} dataset#{truncate ? " after truncation" : ""}"
    end
  end
end

class DeployCommand < Argy::Command
  def initialize
    super(
      use: "deploy <target>",
      short: "Deploy an application build"
    )

    flags.float("timeout", 't', 15.0, "deployment timeout in seconds")
    flags.bool("force", 'f', false, "skip confirmation checks")

    on_run do |cmd, args|
      target = args.first? || abort("deploy: missing <target>")
      timeout = cmd.float_flag("timeout")
      force = cmd.bool_flag("force")
      verbose = cmd.bool_flag("verbose")

      puts "Deploying to #{target}"
      puts "Timeout: #{timeout} seconds"
      puts "Checks: #{force ? "skipped" : "enabled"}"
      puts "Verbose mode is on" if verbose
    end
  end
end

DevtoolCommand.new.execute
