require "../ast_data/ast"
require "./type_error"

module DoisC
  module TypeChecking
    # The Registrar is responsible for the initial registration of all type declarations
    # found in the AST. Its main role is to create stubs for atomic, product, and union types
    # in the global environment before full type resolution occurs. This allows the resolver
    # and verifier to safely reference types that may appear later in the AST.
    class Registrar
      include ASTData

      # Initializes a Registrar with a reference to the global environment.
      # The environment will be updated with type stubs during registration.
      def initialize(@env : Environment::Global)
      end

      # Traverses the AST and registers all named type declarations.
      # Adds type stubs to the global environment to ensure that type references
      # can be resolved later, even if the full definition is not yet populated.
      def register_all(ast : AST)
        ast.module_decl.body.each do |stmt|
          case stmt
          when TypeDeclaration
            register_type(stmt)
          end
        end
      end

      # Register a new atomic, union, or product type declaration (struct-like type)
      def register_type(decl : TypeDeclaration) : Nil
        # TODO ensure type name (capital)
        @env.register_type(decl.name)
      end

      private def error(message : String, source_location : SourceLocation)
        TypeRegistrationError.new(
          "#{source_location.line}:#{source_location.column} : #{message}",
          source_location.line,
          source_location.column
        )
      end
    end
  end
end
