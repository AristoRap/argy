require "../src/argy"

# The simplest possible argy CLI: a single command with no subcommands.
#
# With Crystal's built-in OptionParser, flags are declared via string callbacks
# and values arrive as String regardless of type, so callers convert manually
# (e.g. value.to_i). Help output is also registered by hand:
#   parser.on("-h", "--help", "Show help") { puts parser; exit }
#
# With argy, flags carry their type at declaration time and typed accessors
# return the correct Crystal type. --help / -h is registered automatically
# on every command.

root = Argy::Command.new(
  use: "greet [name]",
  short: "Print a personalised greeting",
  long: <<-LONG
greet prints a greeting for the given name.

  greet Alice
  greet Alice --count 3 --upper
LONG
)

# OptionParser: parser.on("-n COUNT", "--count=COUNT", "...") { |v| count = v.to_i }
# argy:         root.flags.int("count", 'n', 1, "...")  → int_flag returns Int32
root.flags.int(name: "count", shorthand: 'n', default: 1, usage: "number of times to print the greeting")
root.flags.bool("upper", 'u', false, "uppercase the output")

root.on_run do |cmd, args|
  name = args.first? || "World"
  count = cmd.int_flag("count")  # Int32 — no .to_i, no ArgumentError to rescue
  upper = cmd.bool_flag("upper") # Bool — no string coercion

  count.times do
    greeting = "Hello, #{name}!"
    puts upper ? greeting.upcase : greeting
  end
end

# With OptionParser, help requires a manual parser.on("-h", "--help", ...) { puts parser; exit }.
# argy registers --help / -h automatically on every command.
root.execute
