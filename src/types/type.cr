require "./definition"

module DoisC
  module Types
    abstract class Type
      abstract def ==(other : Type) : Bool
    end

    class NominalType < Type
      getter definition : TypeDefinition
      getter type_args : Array(Type)

      def initialize(@definition : TypeDefinition, @type_args : Array(Type))
      end

      def name : String
        @definition.name
      end

      def to_s : String
        if type_args.empty?
          name
        else
          "#{name}(#{type_args.map(&.to_s).join(", ")})"
        end
      end

      def ==(other : Type) : Bool
        other.is_a?(NominalType) &&
          definition == other.definition &&
          type_args == other.type_args
      end
    end

    class FunctionType < Type
      getter param_types : Array(Type)
      getter return_type : Type

      def initialize(@param_types : Array(Type), @return_type : Type)
      end

      def to_s : String
        "(#{param_types.map(&.to_s).join(", ")}) -> #{return_type.to_s}"
      end

      def ==(other : Type) : Bool
        other.is_a?(FunctionType) &&
          return_type == other.return_type &&
          param_types == other.param_types
      end
    end

    # Generic type parameter (unbound, semi-concrete type)
    class GenericTypeParameter < Type
      getter name : String

      def initialize(@name : String)
      end

      def to_s : String
        name
      end

      def ==(other : Type) : Bool
        other.is_a?(GenericTypeParameter) && other.name == name
      end
    end

    # Type var for HM inference
    class TypeVariable < Type
      getter id : Int32
      property instance : Type? = nil

      def initialize(@id : Int32)
      end

      def ==(other : Type) : Bool
        other.is_a?(TypeVariable) && other.id == id
      end

      def to_s : String
        instance ? instance.not_nil!.to_s : "T#{id}"
      end
    end
  end
end
