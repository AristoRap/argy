module Argy
  # FlagSet holds a named collection of flags and knows how to parse argv tokens.
  # Each Command has two FlagSets: one for local flags and one for persistent flags.
  class FlagSet
    # Iterate over every registered flag
    def each(&block : Flag ->) : Nil
      @by_name.each_value { |f| block.call(f) }
    end

    def empty? : Bool
      @by_name.empty?
    end

    def reset! : Nil
      @by_name.each_value(&.reset!)
    end

    # ------------------------------------------------------------------
    # Registration helpers
    # ------------------------------------------------------------------

    def string(name : String, shorthand : Char?, default : String, usage : String) : StringFlag
      register StringFlag.new(name, shorthand, usage, default)
    end

    def bool(name : String, shorthand : Char?, default : Bool, usage : String) : BoolFlag
      register BoolFlag.new(name, shorthand, usage, default)
    end

    def int(name : String, shorthand : Char?, default : Int32, usage : String) : IntFlag
      register IntFlag.new(name, shorthand, usage, default)
    end

    def float(name : String, shorthand : Char?, default : Float64, usage : String) : Float64Flag
      register Float64Flag.new(name, shorthand, usage, default)
    end

    # ------------------------------------------------------------------
    # Lookup
    # ------------------------------------------------------------------

    def lookup(name : String) : Flag?
      @by_name[name]?
    end

    def lookup_shorthand(ch : Char) : Flag?
      name = @by_shorthand[ch]?
      name ? @by_name[name]? : nil
    end

    # ------------------------------------------------------------------
    # Argv parsing
    #
    # Consumes flag tokens from *args*, appending non-flag tokens to
    # *remaining*.  Unknown flags raise UnknownFlagError unless
    # *ignore_unknown* is true (used when merging with parent sets).
    # ------------------------------------------------------------------

    def parse(args : Array(String), remaining : Array(String),
              extra : Hash(String, Flag) = {} of String => Flag,
              ignore_unknown : Bool = false) : Nil
      i = 0
      while i < args.size
        arg = args[i]

        if arg == "--"
          # Everything after bare "--" is positional
          remaining.concat(args[(i + 1)..])
          break
        elsif arg.starts_with?("--")
          key, inline_val = split_long(arg[2..])
          flag = lookup(key) || extra[key]?
          unless flag
            raise UnknownFlagError.new("unknown flag: --#{key}") unless ignore_unknown
            remaining << arg
            i += 1
            next
          end

          value, i = consume_flag_value(flag, inline_val, args, i, "--#{key}")
          flag.set_from_string(value)
          flag.changed = true
        elsif arg.starts_with?("-") && arg.size > 1 && arg[1] != '-'
          ch = arg[1]
          flag = lookup_shorthand(ch) || find_shorthand_in_extra(ch, extra)
          unless flag
            raise UnknownFlagError.new("unknown shorthand flag: -#{ch}") unless ignore_unknown
            remaining << arg
            i += 1
            next
          end

          rest = arg[2..] # characters after -X
          inline_val = if rest.starts_with?("=")
                         rest[1..]
                       elsif rest.empty?
                         nil
                       else
                         # -Xvalue shorthand style is treated as an inline value
                         rest
                       end

          value, i = consume_flag_value(flag, inline_val, args, i, "-#{ch}")
          flag.set_from_string(value)

          flag.changed = true
        else
          remaining << arg
        end

        i += 1
      end
    end

    # ------------------------------------------------------------------
    # Private
    # ------------------------------------------------------------------

    private def register(flag : Flag)
      if @by_name.has_key?(flag.name)
        raise DuplicateFlagError.new("flag already defined: --#{flag.name}")
      end

      if sh = flag.shorthand
        if @by_shorthand.has_key?(sh)
          raise DuplicateFlagError.new("shorthand already defined: -#{sh}")
        end
      end

      @by_name[flag.name] = flag
      if sh = flag.shorthand
        @by_shorthand[sh] = flag.name
      end
      flag
    end

    private def consume_flag_value(flag : Flag, inline_val : String?, args : Array(String), i : Int32, label : String) : {String, Int32}
      if inline_val
        {inline_val, i}
      elsif i + 1 < args.size && value_token?(args[i + 1], flag)
        {args[i + 1], i + 1}
      elsif flag.is_a?(BoolFlag)
        # Boolean flags default to true when present without any explicit value
        {"true", i}
      else
        raise MissingFlagValueError.new("flag needs an argument: #{label}")
      end
    end

    private def value_token?(token : String, flag : Flag) : Bool
      case flag
      when BoolFlag
        bool_value_literal?(token)
      when IntFlag
        return true unless token.starts_with?("-")
        !!(token =~ /\A-\d+\z/)
      when Float64Flag
        return true unless token.starts_with?("-")
        !!(token =~ /\A-\d+(?:\.\d+)?\z/)
      else
        !token.starts_with?("-")
      end
    end

    private def bool_value_literal?(token : String) : Bool
      case token.downcase
      when "true", "1", "yes", "on", "false", "0", "no", "off"
        true
      else
        false
      end
    end

    private def split_long(s : String) : {String, String?}
      idx = s.index('=')
      idx ? {s[0...idx], s[(idx + 1)..]} : {s, nil}
    end

    private def find_shorthand_in_extra(ch : Char, extra : Hash(String, Flag)) : Flag?
      extra.each_value do |f|
        return f if f.shorthand == ch
      end
      nil
    end

    @by_name = {} of String => Flag
    @by_shorthand = {} of Char => String
  end
end
