require "../types/reference"
require "../types/definition"

module DoisC
  module Environment
    # Global semantic environment for predeclared types, builtin symbols,
    # and user-defined top-level type/function/procedure declarations.
    class Global
      # Canonical references
      @type_refs : Hash(String, Types::NominalTypeReference)

      # Resolved definitions
      @type_defs : Hash(Types::NominalTypeReference, Types::TypeDefinition)

      # Functions and procedures unified
      @func_defs : Hash(String, Types::FunctionDefinition)

      # Builtin procedures/functions provided by the compiler prelude.
      # These may still need special verifier/codegen handling, but they
      # should be registered here as part of the global semantic environment.
      @builtins : Set(String)

      getter func_defs : Hash(String, Types::FunctionDefinition)
      getter builtins : Set(String)

      def initialize
        @type_refs = {} of String => Types::NominalTypeReference
        @type_defs = {} of Types::NominalTypeReference => Types::TypeDefinition
        @func_defs = {} of String => Types::FunctionDefinition
        @builtins = Set(String).new

        register_prelude
      end

      private def register_prelude
        register_atomic_types
        register_builtin_types
        register_builtin_prelude
      end

      private def register_atomic_types
        Types::Atomic.each do |atomic|
          register_atomic_type(atomic)
        end
      end

      private def register_atomic_type(atomic)
        defn = Types::AtomicTypeDefinition.new(atomic)
        ref = Types::NominalTypeReference.new(defn.name)
        @type_refs[defn.name] = ref
        @type_defs[ref] = defn
      end

      private def register_builtin_type(name : String, defn : Types::TypeDefinition)
        ref = Types::NominalTypeReference.new(name)
        @type_refs[name] = ref
        @type_defs[ref] = defn
      end

      private def register_builtin_product_type(name : String, defn : Types::ProductTypeDefinition)
        register_builtin_type(name, defn)
      end

      private def register_builtin_union_type(name : String, defn : Types::UnionTypeDefinition)
        register_builtin_type(name, defn)
      end

      private def register_builtin_types
        register_result_prelude_types
      end

      private def register_result_prelude_types
        err_ref = Types::NominalTypeReference.new("Err")
        result_ref = Types::NominalTypeReference.new("Result")
        int_ref = Types::NominalTypeReference.new("Int")
        nil_ref = Types::NominalTypeReference.new("Nil")

        err_def = Types::ProductTypeDefinition.new(
          "Err",
          [] of String,
          {"message" => int_ref},
          err_ref,
        )

        result_def = Types::UnionTypeDefinition.new(
          "Result",
          [] of String,
          [err_ref, nil_ref],
        )

        register_builtin_product_type("Err", err_def)
        register_builtin_union_type("Result", result_def)
      end

      private def result_type_ref : Types::NominalTypeReference
        @type_refs["Result"]
      end

      # Register compiler-provided names that exist without being declared in
      # user source. This is the current prelude hook for builtins and can later
      # be expanded to include predeclared types like Result, Ok, Err, etc.
      private def register_builtin_prelude
        register_builtin_proc("print")
      end

      private def register_builtin(name : String)
        @builtins << name
      end

      private def register_builtin_proc(name : String)
        register_builtin(name)
      end

      # Returns true if the given name belongs to the compiler-provided prelude.
      def builtin?(name : String) : Bool
        @builtins.includes?(name)
      end

      # Register a user-defined nominal type name before its full definition is
      # resolved. This is distinct from builtin/prelude type registration.
      def register_type(name : String)
        raise "Type #{name} already defined" if @type_refs.has_key?(name)
        @type_refs[name] = Types::NominalTypeReference.new(name)
      end

      def define_type(ref : Types::NominalTypeReference, defn : Types::TypeDefinition)
        @type_defs[ref] = defn
      end

      def get_or_create_type_ref(name : String)
        @type_refs[name] ||= Types::NamedTypeReference.new(name)
      end

      def type_reference(name : String) : Types::TypeReference?
        @type_refs[name]?
      end

      def type_definition(ref : Types::NominalTypeReference)
        @type_defs[ref]?
      end

      def define_function(name : String, defn : Types::FunctionDefinition)
        @func_defs[name] = defn
      end

      # Procedures are currently stored in the same global function table.
      # Their semantic distinction is preserved elsewhere in the compiler.
      def define_procedure(name : String, defn : Types::FunctionDefinition)
        define_function(name, defn)
      end

      def function_definition(name : String)
        @func_defs[name]?
      end
    end
  end
end
