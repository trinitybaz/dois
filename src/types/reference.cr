module DoisC
  module Types
    # Base class for all type references in the system.
    # Used to represent a type in the AST before it is fully resolved.
    abstract class TypeReference
    end

    # Represents a named type, optionally parameterized with type arguments.
    # Examples: Int, Point(T), Maybe(T)
    class NominalTypeReference < TypeReference
      getter name : String
      getter type_args : Array(TypeReference)

      def initialize(@name : String, @type_args : Array(TypeReference) = [] of TypeReference)
      end

      # Returns a string representation including generic parameters if present
      def to_s : String
        return name if type_args.empty?
        inner = "(#{generics.join(", ")})"
        "#{name}#{inner}"
      end

      def_equals_and_hash @name, @type_args
    end

    # Base class for structural type references (e.g., function types).
    abstract class StructuralTypeReference < TypeReference
    end

    # Represents a function type in the AST.
    # param_type_refs maps parameter names to their type references.
    # return_type_ref is the type reference for the return type.
    # generics lists any type parameters declared for the function.
    class FunctionTypeReference < StructuralTypeReference
      # TODO higher level functions require param and return typerefs to be any typeref not just nominal
      getter param_type_refs : Hash(String, NominalTypeReference)
      getter return_type_ref : NominalTypeReference
      getter generics : Array(String)

      def initialize(@param_type_refs : Hash(String, NominalTypeReference), @return_type_ref : NominalTypeReference, @generics : Array(String))
      end
    end
  end
end
