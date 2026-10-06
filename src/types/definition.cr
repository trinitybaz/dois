require "./reference"

module DoisC
  module Types
    # Base class for all type definitions in the system:
    # Full definition of a type, such as atomic, product, union, or function types.
    abstract class TypeDefinition
      abstract def name : String
    end

    # An atomic type, such as Int, Float, Bool, etc:
    # Provides a mapping from internal enum Atomic to raw string atomic name.
    class AtomicTypeDefinition < TypeDefinition
      getter atomic : Atomic

      def initialize(@atomic : Atomic)
      end

      def name : String
        case atomic
        when Atomic::INT   ; "Int"
        when Atomic::FLOAT ; "Float"
        when Atomic::NIL   ; "Nil"
        when Atomic::CHAR  ; "Char"
        when Atomic::STRING; "String"
        when Atomic::BOOL  ; "Bool"
        when Atomic::ARRAY ; "Array"
        when Atomic::TUPLE ; "Tuple"
        when Atomic::MAP   ; "Map"
        else                 raise Exception.new
        end
      end
    end

    # Enumerates all atomic types recognized by the type system.
    enum Atomic
      INT; FLOAT; NIL; CHAR; STRING; BOOL; ARRAY; TUPLE; MAP
    end

    # A constructor for a instantiating a type, i.e. `let x = MyType()`
    class ConstructorDefinition
      getter name : String
      getter type_ref : FunctionTypeReference

      def initialize(@name : String, fields : Hash(String, NominalTypeReference), return_type_ref : TypeReference, generics : Array(String))
        @type_ref = FunctionTypeReference.new(fields, return_type_ref, generics)
      end

      def generics : Array(String)
        @type_ref.generics
      end
    end

    # A product type with named fields and optional generic parameters:
    # Wraps constructor definition for instantiation with field values.
    class ProductTypeDefinition < TypeDefinition
      getter name : String
      getter generics : Array(String)
      getter fields : Hash(String, NominalTypeReference)
      getter constructor : ConstructorDefinition

      def initialize(@name : String, @generics : Array(String), @fields : Hash(String, NominalTypeReference), type_ref : NominalTypeReference)
        @constructor = ConstructorDefinition.new(@name, @fields, type_ref, @generics)
      end

      def generics
        @constructor.generics
      end
    end

    # A union type composed of multiple variants:
    # Supports generics for parameterized unions.
    class UnionTypeDefinition < TypeDefinition
      getter name : String
      getter generics : Array(String)
      getter variants : Array(NominalTypeReference)

      def initialize(@name : String, @generics : Array(String), @variants : Array(NominalTypeReference))
      end
    end

    # A function declaration with generics and a type reference for parameters and return type.
    class FunctionDefinition
      getter name : String
      getter type_ref : FunctionTypeReference

      def initialize(@name : String, @type_ref : FunctionTypeReference)
      end

      def generics
        @type_ref.generics
      end
    end

    # A procedure, which is a function expected to return a `Result` type.
    class ProcedureDefinition < FunctionDefinition
    end
  end
end
