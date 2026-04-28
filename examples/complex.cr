require "../src/argy"

# Complex: two-level nested subcommands (db > migrate/seed/rollback,
#          cache > clear/warm) with persistent flags, all four flag types,
#          a hook lifecycle, and flag.changed.
#
# With OptionParser and two-level nesting, you nest parser.on("db",...) blocks
# inside which you nest further parser.on("migrate",...) blocks, tracking command
# state across two levels of closures and calling your logic manually at the end.
#
# With argy, each command is an independent object that can be built in any order
# and composed via add_command. The tree structure is declared explicitly, and
# each command can be exercised in isolation.

# ------------------------------------------------------------------
# Root
# ------------------------------------------------------------------

root = Argy::Command.new(
  use: "infra",
  short: "Infrastructure management CLI",
  long: <<-LONG
infra manages database and cache infrastructure across environments.

  infra db migrate --env production --verbose
  infra cache warm --concurrency 8 --ttl 600
LONG
)

# Persistent flags cascade to every descendant automatically.
# With OptionParser, there is no built-in inheritance mechanism; the common
# approaches are closing over shared variables or re-registering the same
# flags at each parser level.
root.persistent_flags.string("env", 'e', "development", "target environment")
root.persistent_flags.bool("verbose", 'v', false, "verbose output")
root.persistent_flags.float("timeout", nil, 30.0, "operation timeout in seconds")

# on_persistent_pre_run fires root → leaf on every invocation path, before
# on_pre_run and on_run. OptionParser has no built-in hook lifecycle; setup
# that must run on every path is typically a manual function call at the
# start of each command branch.
root.on_persistent_pre_run do |cmd, _args|
  if cmd.bool_flag("verbose")
    env = cmd.string_flag("env")
    timeout = cmd.float_flag("timeout") # Float64 — with OptionParser the value would be a String
    puts "[infra] env=#{env}  timeout=#{timeout}s"
  end
end

# ------------------------------------------------------------------
# db command group
# ------------------------------------------------------------------

db = Argy::Command.new(
  use: "db",
  short: "Database commands",
  long: "Manage database migrations, seeds, and rollbacks."
)

# on_pre_run fires only on this command and its leaves — after persistent_pre_run.
db.on_pre_run do |cmd, _args|
  puts "[db] connecting to #{cmd.string_flag("env")} database..." if cmd.bool_flag("verbose")
end

# db migrate -------------------------------------------------------

db_migrate = Argy::Command.new(
  use: "migrate [flags]",
  short: "Run pending migrations"
)
db_migrate.flags.int("steps", 'n', 0, "max number of migrations to apply (0 = all)")
db_migrate.flags.bool("dry-run", nil, false, "print SQL without executing")

db_migrate.on_run do |cmd, _args|
  dry = cmd.bool_flag("dry-run")

  # flag.changed is true only when the user explicitly passed --steps,
  # making it possible to distinguish "--steps 0" (explicit) from the default 0.
  # With OptionParser, flag defaults live as plain Crystal variables outside the
  # parser; the parser itself has no record of whether a flag was explicitly set.
  steps_flag = cmd.flags.lookup("steps")
  steps_label = (steps_flag && steps_flag.changed) ? cmd.int_flag("steps").to_s : "all"

  if dry
    puts "[dry-run] would apply #{steps_label} migration(s) on #{cmd.string_flag("env")}"
  else
    puts "Applying #{steps_label} migration(s) on #{cmd.string_flag("env")}"
  end
end

# db seed ----------------------------------------------------------

db_seed = Argy::Command.new(
  use: "seed [flags]",
  short: "Seed the database"
)
db_seed.flags.string("file", 'f', "db/seeds.sql", "path to seed file")
db_seed.flags.bool("truncate", nil, false, "truncate tables before seeding")

db_seed.on_run do |cmd, _args|
  prefix = cmd.bool_flag("truncate") ? "[truncate] " : ""
  puts "#{prefix}Seeding #{cmd.string_flag("env")} from #{cmd.string_flag("file")}"
end

# db rollback ------------------------------------------------------

db_rollback = Argy::Command.new(
  use: "rollback [flags]",
  short: "Roll back applied migrations"
)
db_rollback.flags.int("steps", 'n', 1, "number of migrations to roll back")

db_rollback.on_run do |cmd, _args|
  puts "Rolling back #{cmd.int_flag("steps")} migration(s) on #{cmd.string_flag("env")}"
end

db.add_command(db_migrate, db_seed, db_rollback)

# ------------------------------------------------------------------
# cache command group
# ------------------------------------------------------------------

cache = Argy::Command.new(
  use: "cache",
  short: "Cache commands",
  long: "Manage cache warming and clearing."
)

# cache clear ------------------------------------------------------

cache_clear = Argy::Command.new(
  use: "clear [flags]",
  short: "Delete cached entries"
)
cache_clear.flags.string("pattern", 'p', "*", "key glob pattern (default: all keys)")
cache_clear.flags.bool("dry-run", nil, false, "list matching keys without deleting")

cache_clear.on_run do |cmd, _args|
  pattern = cmd.string_flag("pattern")
  if cmd.bool_flag("dry-run")
    puts "[dry-run] would clear keys matching '#{pattern}' on #{cmd.string_flag("env")}"
  else
    puts "Clearing keys matching '#{pattern}' on #{cmd.string_flag("env")}"
  end
end

# cache warm -------------------------------------------------------

cache_warm = Argy::Command.new(
  use: "warm [flags]",
  short: "Pre-warm the cache"
)
# All four flag types are used across this file: string, bool, int, float64.
# With OptionParser, all flag values arrive as String regardless of the intended
# type; conversion and validation are left to the caller.
cache_warm.flags.int("concurrency", 'c', 4, "number of parallel warmers")
cache_warm.flags.float("ttl", nil, 300.0, "TTL for warmed entries in seconds")

cache_warm.on_run do |cmd, _args|
  concurrency = cmd.int_flag("concurrency") # Int32
  ttl = cmd.float_flag("ttl")               # Float64 — with OptionParser this would be a String
  puts "Warming cache on #{cmd.string_flag("env")} " \
       "(concurrency=#{concurrency}, ttl=#{ttl}s)"
end

cache.add_command(cache_clear, cache_warm)

# ------------------------------------------------------------------
# Wire up and run
# ------------------------------------------------------------------

root.add_command(db, cache)
root.execute
