require "./*"

module DoisC
  module Codegen
    # Transpiles the typed Dois AST into final C source text.
    #
    # This layer should NOT walk expressions itself anymore.
    # It should only orchestrate the specialized emitters.
    class Transpiler < BaseCodegen
      def initialize(io : IO::Memory)
        @emitter = Emitter.new(io)
        @type_codegen = TypeCodegen.new(@emitter)
        @expression_codegen = ExpressionCodegen.new(@emitter)
        @function_codegen = FunctionCodegen.new(@type_codegen, @expression_codegen, @emitter)
        @declaration_codegen = DeclarationCodegen.new(@type_codegen, @function_codegen, @emitter)
      end

      # Main compiler entry point.
      # main.cr currently calls `generate`, so keep that stable.
      def generate(ast : ASTData::AST) : String
        transpile(ast)
      end

      def transpile(ast : ASTData::AST) : String
        clear
        emit_c_include_runtime
        emit_c_declarations(ast)
        emit_c_main
        out
      end

      private def emit_c_declarations(ast : ASTData::AST)
        found_main = false
        ast.module_decl.body.each do |stmt|
          # Special case: skip 'proc main', will be emitted in dois_main
          if stmt.is_a?(ASTData::ProcedureDeclaration) && stmt.name == "main"
            emit_c_dois_main(stmt)
            found_main = true
          elsif stmt.is_a?(ASTData::Declaration)
            @declaration_codegen.emit(stmt)
            newline
          end
        end
        unless found_main
          raise "Error: module '#{ast.module_decl.name}' does not define a 'proc main'"
        end
      end

      private def emit_c_dois_main(main_proc : ASTData::ProcedureDeclaration)
        writeln "void dois_main(void) {"
        with_indent do
          main_proc.body.statements.each do |main_stmt|
            @function_codegen.emit_statement(main_stmt)
          end
        end
        writeln "}"
        newline
      end

      private def emit_c_main
        writeln "int main(void) {"
        with_indent do
          writeln "dois_runtime_init();"
          writeln "dois_main();"
          writeln "dois_runtime_shutdown();"
          writeln "return 0;"
        end
        writeln "}"
      end

      private def emit_c_include_runtime
        writeln "#include \"src/codegen/runtime/runtime.h\""
        newline
      end
    end
  end
end
