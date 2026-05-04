module Argy
  # A Command represents a single verb in the CLI hierarchy.
  #
  # Example:
  #
  #   root = Argy::Command.new(
  #     use:   "mytool",
  #     short: "A fictional dev tool",
  #     long:  "mytool is a fictional dev tool used to illustrate argy."
  #   )
  #
  #   serve = Argy::Command.new(
  #     use:   "serve [flags]",
  #     short: "Start the HTTP server"
  #   )
  #   serve.on_run do |cmd, _args|
  #     port = cmd.int_flag("port")
  #     puts "Serving on port #{port}"
  #   end
  #   serve.flags.int("port", 'p', 8080, "port to listen on")
  #
  #   root.add_command(serve)
  #   root.execute
  #
  class Command
    # The usage line – first word is treated as the command name.
    # e.g. "serve [flags]" or just "serve"
    getter use : String

    # One-line description shown in parent's help listing
    property short : String

    # Long description shown at the top of this command's help page
    property long : String

    # Alternative names that route to this command
    getter aliases : Array(String)

    # ------------------------------------------------------------------
    # Construction
    # ------------------------------------------------------------------

    def initialize(
      @use : String,
      @short : String = "",
      @long : String = "",
      aliases : Array(String) = [] of String,
    )
      @aliases = aliases
      # Register built-in --help / -h
      @flags.bool("help", 'h', false, "Show help for this command")
    end

    # Register the command body callback.
    def on_run(&block : Command, Array(String) ->) : self
      @on_run = block
      self
    end

    # Register a callback run before this command's body.
    def on_pre_run(&block : Command, Array(String) ->) : self
      @on_pre_run = block
      self
    end

    # Register a callback run from root to current command on every path.
    def on_persistent_pre_run(&block : Command, Array(String) ->) : self
      @on_persistent_pre_run = block
      self
    end

    # The first word of *use* — the canonical command name used for routing
    def name : String
      @use.split(' ', 2).first
    end

    # ------------------------------------------------------------------
    # Flag sets
    # ------------------------------------------------------------------

    # Local flags — only available to *this* command
    def flags : FlagSet
      @flags
    end

    # Persistent flags — inherited by all subcommands
    def persistent_flags : FlagSet
      @persistent_flags
    end

    # ------------------------------------------------------------------
    # Subcommand management
    # ------------------------------------------------------------------

    def add_command(*cmds : Command) : Nil
      cmds.each do |cmd|
        cmd.set_parent(self)
        @subcommands[cmd.name] = cmd
        cmd.aliases.each { |a| @subcommands[a] = cmd }
      end
    end

    def subcommands : Hash(String, Command)
      @subcommands
    end

    # ------------------------------------------------------------------
    # Typed flag accessors (search local → persistent chain)
    # ------------------------------------------------------------------

    def string_flag(name : String) : String
      flag = find_flag(name)
      raise Error.new("flag --#{name} is not a StringFlag") unless flag.is_a?(StringFlag)
      flag.value
    end

    def bool_flag(name : String) : Bool
      flag = find_flag(name)
      raise Error.new("flag --#{name} is not a BoolFlag") unless flag.is_a?(BoolFlag)
      flag.value
    end

    def int_flag(name : String) : Int32
      flag = find_flag(name)
      raise Error.new("flag --#{name} is not an IntFlag") unless flag.is_a?(IntFlag)
      flag.value
    end

    def float_flag(name : String) : Float64
      flag = find_flag(name)
      raise Error.new("flag --#{name} is not a Float64Flag") unless flag.is_a?(Float64Flag)
      flag.value
    end

    # ------------------------------------------------------------------
    # Entry point
    # ------------------------------------------------------------------

    # Call this on the root command to parse ARGV and dispatch.
    # If the first token equals this command's own name (e.g. the user passed
    # the program name explicitly), it is stripped before routing so that
    # `myapp myapp subcommand` and `myapp subcommand` behave identically.
    def execute(argv : Array(String) = ARGV.to_a) : Nil
      argv = argv[1..] if argv.first? == name
      root = root_command
      root.reset_tree_state!
      root.validate_tree_flag_collisions!
      _execute(argv)
    rescue e : Error
      STDERR.puts "Error: #{e.message}"
      STDERR.puts "Run '#{full_command_path} --help' for usage."
      exit(1)
    end

    # ------------------------------------------------------------------
    # Help rendering
    # ------------------------------------------------------------------

    def print_help(io : IO = STDOUT) : Nil
      # Description
      if !long.empty?
        io.puts long
      elsif !short.empty?
        io.puts short
      end
      io.puts

      # Usage line
      io.puts "Usage:"
      io.puts "  #{full_use_line}"
      io.puts

      # Subcommands
      unless @subcommands.empty?
        io.puts "Available Commands:"
        seen = Set(Command).new
        unique_cmds = @subcommands.each_value.select { |cmd| seen.add?(cmd) }.to_a
        labels = unique_cmds.map { |cmd| ([cmd.name] + cmd.aliases).join(", ") }
        max_len = labels.max_of(&.size)
        unique_cmds.each_with_index do |cmd, i|
          io.printf "  %-#{max_len + 2}s %s\n", labels[i], cmd.short
        end
        io.puts
      end

      # Local flags
      local_flags = [] of Flag
      @flags.each { |f| local_flags << f }

      unless local_flags.empty?
        io.puts "Flags:"
        local_flags.each { |f| print_flag(f, io) }
        io.puts
      end

      # Inherited persistent flags
      inherited = collect_persistent_flags_from_parents
      unless inherited.empty?
        io.puts "Global Flags:"
        inherited.each { |f| print_flag(f, io) }
        io.puts
      end

      # Persistent flags defined on *this* command (visible to children)
      pf_list = [] of Flag
      @persistent_flags.each { |f| pf_list << f }
      unless pf_list.empty?
        io.puts "Persistent Flags:"
        pf_list.each { |f| print_flag(f, io) }
        io.puts
      end

      unless @subcommands.empty?
        io.puts "Use \"#{root_command.name} [command] --help\" for more information about a command."
      end
    end

    # ------------------------------------------------------------------
    # Protected / internal dispatch (called recursively)
    # ------------------------------------------------------------------

    protected def _execute(argv : Array(String)) : Nil
      # Try to route to a subcommand before touching flags
      if !argv.empty? && !argv[0].starts_with?("-")
        if sub = @subcommands[argv[0]]?
          sub._execute(argv[1..])
          return
        elsif !@subcommands.empty?
          raise UnknownCommandError.new("unknown command: #{argv[0]}")
        end
      end

      # Parse flags (local + own persistent + all inherited persistent)
      remaining = [] of String
      extra = collect_persistent_flags_from_ancestors
      @persistent_flags.each { |f| extra[f.name] ||= f }
      @flags.parse(argv, remaining, extra)

      # Help short-circuit
      if bool_flag("help")
        print_help
        return
      end

      # Run persistent_pre_run hooks from root to leaf (after flag parsing)
      run_persistent_pre_runs(remaining)

      # Invoke hooks and runner
      @on_pre_run.try(&.call(self, remaining))
      if r = @on_run
        r.call(self, remaining)
      else
        # No runner → print help (like a bare `cobra` invocation)
        print_help
      end
    end

    # ------------------------------------------------------------------
    # Private helpers
    # ------------------------------------------------------------------

    private def find_flag(name : String) : Flag
      @flags.lookup(name) ||
        @persistent_flags.lookup(name) ||
        collect_persistent_flags_from_ancestors[name]? ||
        raise Error.new("unknown flag: --#{name}")
    end

    # Walk ancestors collecting their persistent flags (closest wins)
    private def collect_persistent_flags_from_ancestors : Hash(String, Flag)
      result = {} of String => Flag
      cmd = @parent
      while c = cmd
        c.@persistent_flags.each do |f|
          result[f.name] ||= f
        end
        cmd = c.@parent
      end
      result
    end

    # Persistent flags visible to THIS command's *children* (self + ancestors)
    private def collect_persistent_flags_from_parents : Array(Flag)
      flags = [] of Flag
      cmd = @parent
      while c = cmd
        c.@persistent_flags.each { |f| flags << f }
        cmd = c.@parent
      end
      flags
    end

    private def run_persistent_pre_runs(args : Array(String)) : Nil
      chain = [] of Command
      cmd : Command? = self
      while c = cmd
        chain.unshift(c)
        cmd = c.@parent
      end
      chain.each { |c| c.@on_persistent_pre_run.try(&.call(c, args)) }
    end

    private def full_use_line : String
      parts = [] of String
      cmd : Command? = self
      while c = cmd
        parts.unshift(c.use)
        cmd = c.@parent
      end
      parts.join(" ")
    end

    private def full_command_path : String
      parts = [] of String
      cmd : Command? = self
      while c = cmd
        parts.unshift(c.name)
        cmd = c.@parent
      end
      parts.join(" ")
    end

    private def root_command : Command
      cmd = self
      while p = cmd.@parent
        cmd = p
      end
      cmd
    end

    protected def reset_tree_state! : Nil
      @flags.reset!
      @persistent_flags.reset!
      @subcommands.each_value(&.reset_tree_state!)
    end

    protected def validate_tree_flag_collisions! : Nil
      validate_visible_flag_collisions!
      @subcommands.each_value(&.validate_tree_flag_collisions!)
    end

    private def validate_visible_flag_collisions! : Nil
      by_name = {} of String => Flag
      by_shorthand = {} of Char => Flag

      visible_sets = [@flags, @persistent_flags] of FlagSet
      cmd = @parent
      while c = cmd
        visible_sets << c.@persistent_flags
        cmd = c.@parent
      end

      visible_sets.each do |set|
        set.each do |flag|
          if other = by_name[flag.name]?
            raise DuplicateFlagError.new("flag already defined in visible scope: --#{flag.name}")
          end

          by_name[flag.name] = flag

          next unless sh = flag.shorthand
          if other = by_shorthand[sh]?
            raise DuplicateFlagError.new("shorthand already defined in visible scope: -#{sh}")
          end

          by_shorthand[sh] = flag
        end
      end
    end

    private def print_flag(flag : Flag, io : IO) : Nil
      shorthand_part = flag.shorthand ? "  -#{flag.shorthand}, " : "      "
      type_part = flag.is_a?(BoolFlag) ? "" : " #{flag.type_label}"
      default_part = build_default_part(flag)
      io.printf "%s--%-20s %s%s\n",
        shorthand_part,
        "#{flag.name}#{type_part}",
        flag.usage,
        default_part
    end

    private def build_default_part(flag : Flag) : String
      return "" if flag.is_a?(BoolFlag) && !flag.as(BoolFlag).default
      return "" if flag.is_a?(StringFlag) && flag.as(StringFlag).default.empty?
      return "" if flag.is_a?(IntFlag) && flag.as(IntFlag).default == 0
      " (default #{flag.value_string})"
    end

    protected def set_parent(cmd : Command) : Nil
      @parent = cmd
    end

    # Instance state
    @flags = FlagSet.new
    @persistent_flags = FlagSet.new
    @subcommands = {} of String => Command
    @aliases = [] of String
    @parent : Command? = nil
    @on_run : (Command, Array(String) ->)? = nil
    @on_pre_run : (Command, Array(String) ->)? = nil
    @on_persistent_pre_run : (Command, Array(String) ->)? = nil
  end
end
