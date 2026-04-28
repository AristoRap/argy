require "../src/argy"

# Moderate: a root command with three subcommands (copy, move, info).
#
# With OptionParser, subcommands are typically implemented as string triggers:
#   parser.on("copy", "...") { copy = true }
# Dispatch then happens via if/elsif at the end of the parse block, and each
# subcommand's flags are registered inside its handler, all sharing one parser.
#
# With argy, each Command is an independent object with its own flag set.
# add_command wires the tree and routing happens automatically.

root = Argy::Command.new(
  use: "fileutil",
  short: "Simple file manipulation utility",
  long: "fileutil copies, moves, and inspects files on the local filesystem."
)

# ------------------------------------------------------------------
# copy
# ------------------------------------------------------------------

copy_cmd = Argy::Command.new(
  use: "copy <src> <dst>",
  short: "Copy a file to a new location"
)
copy_cmd.flags.bool("force", 'f', false, "overwrite destination without prompting")
copy_cmd.flags.bool("dry-run", 'd', false, "print what would happen without doing it")

copy_cmd.on_run do |cmd, args|
  src = args[0]? || abort("copy: missing <src>")
  dst = args[1]? || abort("copy: missing <dst>")

  if cmd.bool_flag("dry-run")
    puts "[dry-run] would copy #{src} -> #{dst}"
  else
    puts "Copying #{src} -> #{dst}#{cmd.bool_flag("force") ? " (force)" : ""}"
  end
end

# ------------------------------------------------------------------
# move
# ------------------------------------------------------------------

move_cmd = Argy::Command.new(
  use: "move <src> <dst>",
  short: "Move a file to a new location"
)
move_cmd.flags.bool("force", 'f', false, "overwrite destination without prompting")
move_cmd.flags.bool("dry-run", 'd', false, "print what would happen without doing it")

move_cmd.on_run do |cmd, args|
  src = args[0]? || abort("move: missing <src>")
  dst = args[1]? || abort("move: missing <dst>")

  if cmd.bool_flag("dry-run")
    puts "[dry-run] would move #{src} -> #{dst}"
  else
    puts "Moving #{src} -> #{dst}#{cmd.bool_flag("force") ? " (force)" : ""}"
  end
end

# ------------------------------------------------------------------
# info
# ------------------------------------------------------------------

info_cmd = Argy::Command.new(
  use: "info <path>",
  short: "Print metadata about a file"
)
info_cmd.flags.string("format", 'F', "text", "output format: text or json")
info_cmd.flags.bool("checksum", nil, false, "include SHA-256 checksum in output")

info_cmd.on_run do |cmd, args|
  path = args[0]? || abort("info: missing <path>")

  # flag.changed is true only if the user explicitly passed --format on this
  # invocation. With OptionParser, flag defaults live as plain Crystal variables
  # outside the parser; the parser itself has no record of whether a value was
  # explicitly provided or simply left at its default.
  unless cmd.flags.lookup("format").try(&.changed)
    puts "(tip: use --format json for machine-readable output)"
  end

  checksum = cmd.bool_flag("checksum")

  case cmd.string_flag("format")
  when "json"
    puts %({"path":"#{path}","checksum":#{checksum ? %("abc123") : "null"}})
  else
    puts "path:     #{path}"
    puts "checksum: #{checksum ? "abc123" : "n/a"}"
  end
end

# ------------------------------------------------------------------
# Wire up and run
# ------------------------------------------------------------------

root.add_command(copy_cmd, move_cmd, info_cmd)
root.execute
