# require "./registrar"
# require "./resolver"
# require "./verifier"
require "../types/*"
require "../environment/*"
require "./*"

module DoisC
  module TypeChecking
    # The TypeChecker is the top-level entry point for type checking an AST.
    # It orchestrates the various stages of type analysis:
    #   1. Registrar: registers all types and function signatures in the global environment.
    #   2. Resolver: resolves type references and populates detailed type information.
    #   3. Verifier: walks the AST to check type correctness and enforce type rules.
    # The TypeChecker maintains a global environment that holds type definitions,
    # function definitions, and any other context needed during verification.
    class TypeChecker
      @global : Environment::Global = Environment::Global.new

      # Checks the given AST for type correctness.
      # This method runs the AST through all stages: registration, resolution, and verification.
      # It returns nothing, but will raise exceptions if type errors are detected.
      def check(ast : ASTData::AST)
        Registrar.new(@global).register_all(ast)
        Resolver.new(@global).resolve_all(ast)

        Verifier.new(
          Environment::VerificationContext.new(@global)
        ).verify_all(ast)
      end
    end
  end
end
