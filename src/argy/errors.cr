module Argy
  # Base for all argy errors
  class Error < Exception; end

  # Raised when an unrecognised flag is passed
  class UnknownFlagError < Error; end

  # Raised when a flag that requires a value is given none
  class MissingFlagValueError < Error; end

  # Raised when a flag value cannot be coerced to the expected type
  class InvalidFlagValueError < Error; end

  # Raised when a subcommand name is not found
  class UnknownCommandError < Error; end

  # Raised when a flag or shorthand is registered more than once
  class DuplicateFlagError < Error; end
end
