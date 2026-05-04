# argy

Argy is a typed CLI framework for Crystal, inspired by [Cobra](https://cobra.dev/).
It helps you build command trees with typed flags, inherited global flags, and auto-generated help output.

## Project Meta

- Status: beta (API may evolve before 1.0)
- Crystal compatibility: `>= 1.20.0`
- Focus: typed flags, explicit command-tree composition, deterministic lifecycle hooks
- Runtime guarantees:
  - Per-execution flag reset (`value` and `changed`)
  - Strict unknown-subcommand errors
  - Duplicate visible-flag detection across local, persistent, and inherited scopes

## Features

- Nested commands and subcommands
- **Command aliases** — route multiple tokens to the same command (e.g. `build` and `b`)
- Typed flags: `string`, `bool`, `int`, `float`
- Local flags (`flags`) and inherited global flags (`persistent_flags`)
- Command lifecycle hooks with `on_pre_run` and `on_persistent_pre_run`
- Built-in help (`--help`, `-h`) and usage rendering
- Flexible flag parsing styles:
  - `--port 8080`
  - `--port=8080`
  - `-p 8080`
  - `-p8080`
  - `-p=8080`
  - `--verbose` (boolean implicit true)
  - `--verbose false` / `-v false` / `-v=false` (boolean explicit value)
  - `--count -5` (negative numeric values)

## Installation

Add this dependency to your `shard.yml`:

```yaml
dependencies:
  argy:
    github: AristoRap/argy
```

Then install dependencies:

```bash
shards install
```

## Quick Start

```crystal
require "argy"

root = Argy::Command.new(
  use: "hello",
  short: "A tiny greeter"
)

root.on_run do |cmd, _args|
  name = cmd.string_flag("name")
  puts "Hello, #{name}!"
end

root.flags.string("name", 'n', "world", "name to greet")
root.execute
```

Run it:

```bash
crystal run app.cr -- --name Crystal
```

## Building Command Trees

Create commands and compose them with `add_command`:

```crystal
root = Argy::Command.new(use: "devtool", short: "Developer tool")
serve = Argy::Command.new(use: "serve", short: "Start server")

root.add_command(serve)
root.execute
```

## Command Aliases

Pass `aliases` to give a command one or more alternative names. Every alias is registered alongside the canonical name, so `argy b` dispatches to exactly the same handler as `argy build`:

```crystal
build = Argy::Command.new(
  use: "build",
  short: "Compile the project",
  aliases: ["b", "bld"]
)

build.on_run do |_cmd, _args|
  puts "Building..."
end

root.add_command(build)
```

All three invocations below are equivalent:

```bash
mytool build
mytool b
mytool bld
```

Aliases also work at every level of a nested command tree:

```crystal
db = Argy::Command.new(use: "database", short: "Database commands", aliases: ["db"])
migrate = Argy::Command.new(use: "migrate", short: "Run migrations", aliases: ["m"])

db.add_command(migrate)
root.add_command(db)

# All equivalent:
# mytool database migrate
# mytool db migrate
# mytool db m
# mytool database m
```

Help output lists aliases inline next to the canonical name:

```
Available Commands:
  build, b, bld   Compile the project
```

## Defining and Reading Flags

Define local flags on `flags`:

```crystal
serve.flags.int(name: "port", shorthand: 'p', default: 8080, usage: "port to listen on")
serve.flags.string("host", nil, "127.0.0.1", "host")
serve.flags.bool("tls", nil, false, "enable tls")
serve.flags.float("timeout", nil, 5.0, "request timeout")
```

Define global inherited flags on `persistent_flags`:

```crystal
root.persistent_flags.string("config", 'c', "~/.mytool.yml", "config path")
root.persistent_flags.bool("verbose", 'v', false, "verbose output")
```

Read typed values inside `on_run`/`on_pre_run` callbacks:

```crystal
serve.on_run do |cmd, _args|
  puts cmd.int_flag("port")
  puts cmd.string_flag("host")
  puts cmd.bool_flag("tls")
  puts cmd.float_flag("timeout")
end
```

Use `args` when you want positional (non-flag) input:

```crystal
serve = Argy::Command.new(use: "serve [flags] [paths...]", short: "Start server")
serve.flags.int("port", 'p', 8080, "port to listen on")

serve.on_run do |cmd, args|
  puts "Port: #{cmd.int_flag("port")}"
  puts "Paths: #{args.join(", ")}" unless args.empty?
end
```

Example invocation:

```bash
devtool serve --port 9000 public assets
```

In that call, `port` is parsed from the flag, and `args` is `["public", "assets"]`.

## Execution Lifecycle

When `root.execute` is called (or `root.execute(argv)` in tests), argy follows these steps in order:

### 1. Routing

The first non-flag token in `argv` is checked against the current command's subcommands. If a match is found, dispatch recurses into that subcommand with the remaining tokens. This continues until no further subcommand matches or the remaining argv starts with a flag.

```
infra db migrate --env production
      ^^                           → routed to `db`
         ^^^^^^^                   → routed to `db migrate`
                 ^^^^^^^^^^^^^^^^  → parsed as flags on `db migrate`
```

### 2. Flag parsing

Once the target command is identified, all flags are parsed together in a single pass:

- **Local flags** (`cmd.flags`) — defined on and only visible to this command
- **Own persistent flags** (`cmd.persistent_flags`) — defined on this command, inherited by all descendants
- **Inherited persistent flags** — the `persistent_flags` of every ancestor, from parent up to root

Remaining tokens (non-flag words) are collected into `args` and passed to the hooks and `on_run`.

### 3. Help short-circuit

If `--help` or `-h` was passed, help is printed and execution stops. No hooks fire.

### 4. `on_persistent_pre_run` — root → leaf

Every command in the ancestry chain that has an `on_persistent_pre_run` block registered fires in order from root to the matched leaf. This runs on every execution path, making it ideal for setup that must happen regardless of which subcommand was invoked (loading config, setting up logging, etc.).

Because this fires _after_ flag parsing, flags are fully resolved and readable inside the callback.

```crystal
root.on_persistent_pre_run do |cmd, args|
  # cmd is the command the hook was registered on (root here),
  # not necessarily the matched leaf.
  # Flags are already parsed and accessible.
  setup_logger(cmd.bool_flag("verbose"))
end
```

### 5. `on_pre_run` — matched command only

Fires for the matched command only, after all `on_persistent_pre_run` hooks. Use this for per-command setup that shouldn't cascade to siblings.

```crystal
db.on_pre_run do |cmd, _args|
  connect_database(cmd.string_flag("env"))
end
```

### 6. `on_run` — matched command only

The command body. If no `on_run` is registered, argy prints that command's help page instead (useful for group commands like `db` that exist only to hold subcommands).

```crystal
db_migrate.on_run do |cmd, args|
  # flags fully parsed, all hooks already fired
  puts "Migrating #{cmd.string_flag("env")}"
end
```

### Full lifecycle summary

```
root.execute(argv)
  │
  ├─ route to matching leaf command
  │
  ├─ parse flags (local + own persistent + inherited persistent)
  │
  ├─ --help? → print_help, stop
  │
  ├─ on_persistent_pre_run  root → ... → matched command
  │
  ├─ on_pre_run             matched command
  │
  └─ on_run                 matched command  (or print_help if absent)
```

### Flag resolution inside callbacks

Inside any hook or `on_run`, typed accessors search in this order:

1. The command's local `flags`
2. The command's own `persistent_flags`
3. Ancestor `persistent_flags`, nearest ancestor first

```crystal
cmd.string_flag("env")     # String
cmd.bool_flag("verbose")   # Bool
cmd.int_flag("workers")    # Int32
cmd.float_flag("timeout")  # Float64
```

### Detecting whether a flag was explicitly set

`flag.changed` is `true` only when the user actually passed that flag. This lets you distinguish an explicit `--steps 0` from the default value of `0`:

```crystal
steps_flag = cmd.flags.lookup("steps")
label = (steps_flag && steps_flag.changed) ? cmd.int_flag("steps").to_s : "all"
```

### Built-in help

Every command automatically gets `--help` / `-h`. If `on_run` is not registered on a command, argy prints that command's help page when it is invoked directly.

### Repeated execution semantics

Calling `execute` multiple times on the same command tree is supported. Before each run, argy resets all flag values to their declared defaults and clears each flag's `changed` marker.

## Error Handling

Argy raises typed errors such as:

- `Argy::UnknownFlagError` — unknown flag or shorthand passed at runtime
- `Argy::UnknownCommandError` — unknown subcommand token encountered during routing
- `Argy::MissingFlagValueError` — flag that requires a value was given none
- `Argy::InvalidFlagValueError` — flag value could not be coerced to the expected type
- `Argy::DuplicateFlagError` — duplicate visible flag name or shorthand detected at runtime (local, persistent, or inherited)

`Command#execute` catches `Argy::Error`, prints an error message plus usage hint, and exits with code `1`.

## Examples

Runnable examples are in the `examples` directory:

- `examples/simple.cr` — single command with typed flags
- `examples/moderate.cr` — multiple subcommands and `flag.changed` usage
- `examples/complex.cr` — nested command tree, persistent flags, and lifecycle hooks

Run them with:

```bash
crystal run examples/simple.cr -- --help
crystal run examples/moderate.cr -- info file.txt --format json
crystal run examples/complex.cr -- db migrate --env production --verbose
```

## Development

Run specs:

```bash
crystal spec
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add or update specs
4. Open a pull request

## License

MIT
