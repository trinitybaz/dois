module DoisC
  module ASTData
    # Semantic reference to a resolved symbol.
    #
    # This is backend-neutral semantic metadata attached during
    # resolution / verification. It identifies a symbol by its
    # module path and local name, and can later be lowered into
    # backend-specific names (such as C mangled identifiers).
    class SymbolRef
      getter module_path : Array(String)
      getter local_name : String

      def initialize(@module_path : Array(String), @local_name : String)
      end

      def fully_qualified_name : String
        (@module_path + [@local_name]).join("::")
      end

      def mangled_name : String
        (@module_path + [@local_name]).join("__")
      end

      def to_s : String
        fully_qualified_name
      end
    end
  end
end
