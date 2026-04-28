module Argy
  # ---------------------------------------------------------------------------
  # Abstract base
  # ---------------------------------------------------------------------------

  abstract class Flag
    getter name : String
    getter shorthand : Char?
    getter usage : String
    property changed : Bool = false

    def initialize(@name : String, @shorthand : Char?, @usage : String)
    end

    # Human-readable current value (used in help output)
    abstract def value_string : String

    # The type label shown in help (e.g. "string", "int")
    abstract def type_label : String

    # Set the flag value from a raw string; raises InvalidFlagValueError on failure
    abstract def set_from_string(raw : String) : Nil

    # Reset the flag to its declared default and clear changed-state.
    abstract def reset! : Nil
  end

  # ---------------------------------------------------------------------------
  # Concrete flag types
  # ---------------------------------------------------------------------------

  class StringFlag < Flag
    property value : String
    getter default : String

    def initialize(name, shorthand, usage, @default : String = "")
      super(name, shorthand, usage)
      @value = @default
    end

    def value_string : String
      @value
    end

    def type_label : String
      "string"
    end

    def set_from_string(raw : String) : Nil
      @value = raw
    end

    def reset! : Nil
      @value = @default
      @changed = false
    end
  end

  class BoolFlag < Flag
    property value : Bool
    getter default : Bool

    def initialize(name, shorthand, usage, @default : Bool = false)
      super(name, shorthand, usage)
      @value = @default
    end

    def value_string : String
      @value.to_s
    end

    def type_label : String
      "bool"
    end

    def set_from_string(raw : String) : Nil
      @value = case raw.downcase
               when "true", "1", "yes", "on"  then true
               when "false", "0", "no", "off" then false
               else
                 raise InvalidFlagValueError.new(
                   "invalid boolean value \"#{raw}\" for flag --#{@name}"
                 )
               end
    end

    def reset! : Nil
      @value = @default
      @changed = false
    end
  end

  class IntFlag < Flag
    property value : Int32
    getter default : Int32

    def initialize(name, shorthand, usage, @default : Int32 = 0)
      super(name, shorthand, usage)
      @value = @default
    end

    def value_string : String
      @value.to_s
    end

    def type_label : String
      "int"
    end

    def set_from_string(raw : String) : Nil
      parsed = raw.to_i?
      raise InvalidFlagValueError.new(
        "invalid integer value \"#{raw}\" for flag --#{@name}"
      ) unless parsed
      @value = parsed
    end

    def reset! : Nil
      @value = @default
      @changed = false
    end
  end

  class Float64Flag < Flag
    property value : Float64
    getter default : Float64

    def initialize(name, shorthand, usage, @default : Float64 = 0.0)
      super(name, shorthand, usage)
      @value = @default
    end

    def value_string : String
      @value.to_s
    end

    def type_label : String
      "float"
    end

    def set_from_string(raw : String) : Nil
      parsed = raw.to_f?
      raise InvalidFlagValueError.new(
        "invalid float value \"#{raw}\" for flag --#{@name}"
      ) unless parsed
      @value = parsed
    end

    def reset! : Nil
      @value = @default
      @changed = false
    end
  end
end
