require "./global"
require "../types/type"
require "../ast_data/symbol_ref"

module DoisC
  module Environment

    # Holds context as verifier traverses AST's concrete types
    class VerificationContext

      record LocalBinding,
        type : Types::Type,
        symbol_ref : ASTData::SymbolRef?

      getter globals : Global

      @scopes : Array(Hash(String, LocalBinding))

      @generic_scopes : Array(Hash(String, Types::GenericTypeParameter))

      @current_return_type : Types::Type?

      @module_scope : Array(String)

      @loop_depth : Int32

      def initialize(@globals : Global)
        @scopes = [{} of String => LocalBinding]
        @generic_scopes = [{} of String => Types::GenericTypeParameter]
        @current_return_type = nil
        @module_scope = [] of String
        @loop_depth = 0
      end

      def enter_scope
        @scopes.push({} of String => LocalBinding)
      end

      def exit_scope
        @scopes.pop
      end

      def declare(name : String, type : Types::Type, symbol_ref : ASTData::SymbolRef? = nil)
        @scopes.last[name] = LocalBinding.new(type, symbol_ref)
      end

      def lookup_binding(name : String) : LocalBinding?
        @scopes.reverse_each do |scope|
          return scope[name]? if scope.has_key?(name)
        end
        nil
      end

      def lookup(name : String) : Types::Type?
        binding = lookup_binding(name)
        binding ? binding.type : nil
      end

      def enter_generic_scope
        @generic_scopes.push({} of String => Types::GenericTypeParameter)
      end

      def exit_generic_scope
        @generic_scopes.pop
      end

      def bind_generic(name : String, param : Types::GenericTypeParameter)
        @generic_scopes.last[name] = param
      end

      def lookup_generic(name : String) : Types::GenericTypeParameter?
        @generic_scopes.reverse_each do |scope|
          return scope[name]? if scope.has_key?(name)
        end
        nil
      end

      def current_generic_scope : Hash(String, Types::GenericTypeParameter)
        @generic_scopes.last || {} of String => Types::GenericTypeParameter
      end

      def push_module(name : String)
        @module_scope << name
      end

      def pop_module
        @module_scope.pop
      end

      def current_module_scope : Array(String)
        @module_scope.dup
      end

      def enter_loop
        @loop_depth += 1
      end

      def exit_loop
        @loop_depth -= 1
      end

      def inside_loop? : Bool
        @loop_depth > 0
      end

      def with_return_type(type : Types::Type)
        old = @current_return_type
        @current_return_type = type
        yield
        @current_return_type = old
      end

      def current_return_type : Types::Type?
        @current_return_type
      end
    end

  end
end