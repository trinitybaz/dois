require "../ast_data/ast"
require "../types/reference"

module DoisC
  module TypeChecking
    # The Resolver is responsible for filling in detailed type information
    # for all registered type stubs in the global environment. After the Registrar
    # has created stubs for all product, union, and atomic types, the Resolver
    # populates field types, variant types, and function signatures so that
    # verification can safely check type correctness.
    class Resolver
      include ASTData
      include Types

      def initialize(@env : Environment::Global)
      end

      # Entry point — traverses the AST and resolves all type declarations
      # This includes products, unions, functions, and procedures
      def resolve_all(ast : AST)
        ast.module_decl.body.each do |stmt|
          case stmt
          when ProductTypeDeclaration
            resolve_product(stmt)
          when UnionTypeDeclaration
            resolve_union(stmt)
          when FunctionDeclaration
            resolve_function(stmt)
          when ProcedureDeclaration
            resolve_procedure(stmt)
          end
        end
      end

      # Resolves field types and constructor type for a product type
      def resolve_product(decl : ProductTypeDeclaration)
        ref = @env.type_reference(decl.name) || raise error("Unregistered type reference #{decl.name}", decl.source_location)

        fields = decl.fields.to_h do |field|
          {field.name, parse_type_identifier(field.type_id, decl.generics)}
        end

        product_def = ProductTypeDefinition.new(decl.name, decl.generics, fields, ref)

        @env.define_type(ref, product_def)
      end

      # Resolves variant references for a union type.
      def resolve_union(decl : UnionTypeDeclaration)
        name = decl.name
        ref = @env.type_reference(name).as?(TypeReference) ||
              raise error("Unregistered type reference #{name}", decl.source_location)

        variants = decl.variants.map do |variant|
          variant = variant.as?(TypeID) || raise "Union expected variant type id"
          @env.type_reference(variant.name) ||
            raise error("Unregistered variant type reference #{variant.name}", decl.source_location)
        end

        union_def = UnionTypeDefinition.new(name, decl.generics, variants)
        @env.define_type(ref, union_def)
      end

      # Resolves function parameter and return types.
      def resolve_function(decl : FunctionDeclaration)
        name = decl.name
        param_refs = decl.params.to_h { |p| {p.name, parse_type_identifier(p.type_id, decl.generics)} }
        return_ref = NominalTypeReference.new(decl.return_type_id.name)
        function_type_ref = FunctionTypeReference.new(param_refs, return_ref, decl.generics)
        definition = FunctionDefinition.new(name, function_type_ref)

        @env.define_function(name, definition)
      end

      # Resolves procedure parameters and sets the return type to Result.
      # Procedures are stored as functions with a Result return type.
      def resolve_procedure(decl : ProcedureDeclaration)
        name = decl.name
        param_refs = decl.params.to_h { |p| {p.name, parse_type_identifier(p.type_id)} }
        return_ref = NominalTypeReference.new("Result")
        # TODO improve result stubbing for procedures to be woven in between type checker layers better
        procedure_type_ref = FunctionTypeReference.new(param_refs, return_ref, decl.generics)

        definition = ProcedureDefinition.new(name, procedure_type_ref)

        @env.define_function(name, definition)
      end

      # Converts a TypeID from the AST into an internal TypeReference,
      # handling generics and looking up type references in the environment.
      def parse_type_identifier(type_id : TypeID, generics = [] of String) : TypeReference
        name = type_id.name

        if generics.includes?(name)
          return NominalTypeReference.new(name)
        end
        # Look up the reference by name in the environment
        ref = @env.type_reference(name)
        raise error("Undefined type: #{name}", type_id.source_location) unless ref

        # We ignore inner_type_ids for now, concrete types will be handled by the verifier
        ref
      end

      private def error(message : String, source_location : SourceLocation)
        TypeResolutionError.new(
          "#{source_location.line}:#{source_location.column} : #{message}",
          source_location.line,
          source_location.column
        )
      end
    end
  end
end
