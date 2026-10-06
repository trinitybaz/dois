require "../compilation_error"

module DoisC
  module TypeChecking
    # Base class for all type-related errors.
    # Inherits from CompilationError to integrate with the compiler error handling.
    class TypeError < CompilationError
    end

    # Raised when a type cannot be registered properly in the global environment.
    class TypeRegistrationError < TypeError
    end

    # Raised when a type reference cannot be resolved to a concrete type.
    class TypeResolutionError < TypeError
    end

    # Raised when a type check fails during AST verification.
    class TypeVerificationError < TypeError
    end
  end
end
