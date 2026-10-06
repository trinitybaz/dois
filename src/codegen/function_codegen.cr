module DoisC
  module Codegen
    class FunctionCodegen < BaseCodegen
      def initialize(@type_codegen : TypeCodegen, @expression_codegen : ExpressionCodegen, @emitter : Emitter)
      end

      def emit_function_declaration(fn : ASTData::FunctionDeclaration)
        return_type = @type_codegen.c_type(fn.resolved_type.not_nil!)
        params = fn.params.map do |param|
          "#{@type_codegen.c_type(param.resolved_type.not_nil!)} #{param.name}"
        end.join(", ")

        writeln "#{return_type} #{fn.name}(#{params}) {"
        with_indent do
          write "return "
          @expression_codegen.emit(fn.body)
          writeln ";"
        end
        writeln "}"
      end

      def emit_procedure_declaration(pc : ASTData::ProcedureDeclaration)
        return_type = "void"
        params = pc.params.map do |param|
          "#{@type_codegen.c_type(param.resolved_type.not_nil!)} #{param.name}"
        end.join(", ")

        writeln "#{return_type} #{pc.name}(#{params}) {"
        with_indent do
          emit_statements(pc.body.statements)
        end
        writeln "}"
      end

      def emit_statements(stmts : Array(ASTData::Statement))
        stmts.each do |stmt|
          emit_statement(stmt)
        end
      end

      def emit_statement(stmt : ASTData::Statement)
        case stmt
        when ASTData::Binding
          type = @type_codegen.c_type(stmt.resolved_type.not_nil!)
          write "const #{type} #{stmt.name} = "
          @expression_codegen.emit(stmt.value)
        when ASTData::VarDeclaration
          type = @type_codegen.c_type(stmt.resolved_type.not_nil!)
          write "#{type} #{stmt.name}"
          if value = stmt.value
            write(" = ")
            @expression_codegen.emit(value)
          end
        when ASTData::ExpressionStatement
          if emit_builtin_print_statement(stmt.expression)
            return
          end
          @expression_codegen.emit(stmt.expression)
        when ASTData::WhileLoop
          emit_while_loop(stmt)
        when ASTData::IfStatement
          emit_if_statement(stmt)
        else
          writeln "/* unsupported statement: #{stmt.class} */"
        end
        writeln ";"
      end

      def emit_while_loop(stmt : DoisC::ASTData::WhileLoop)
        write("while (")
        @expression_codegen.emit(stmt.condition)
        write(") {")
        newline
        with_indent do
          emit_statements(stmt.body.statements)
        end
        write("}")
      end

      def emit_if_statement(stmt : ASTData::IfStatement)
        stmt.branches.each do |branch|
          write("if ")
          @expression_codegen.emit(branch.condition)
          write(" {")
          emit_statements(branch.body.statements)
          write("}")
        end
        if body = stmt.else_body
          write("else {")
          emit_statements(body.statements)
          write("}")
        end
      end

      private def emit_builtin_print_statement(expr : ASTData::Expression) : Bool
        call = case expr
               when ASTData::FunctionCall
                 expr
               when ASTData::ProcedureCall
                 expr
               else
                 return false
               end

        callee = call.callee
        return false unless callee.is_a?(ASTData::IdentifierExpression)
        return false unless callee.identifier.name == "print"
        return false unless call.arguments.size == 1

        arg = call.arguments.first
        arg_type = arg.resolved_type
        return false unless arg_type.is_a?(Types::NominalType)

        runtime_fn = case arg_type.definition.name
                     when "Int"
                       "dois_print_int"
                     when "Float"
                       "dois_print_float"
                     when "Bool"
                       "dois_print_bool"
                     when "String"
                       "dois_print_string"
                     else
                       raise "Unsupported print codegen for type #{arg_type.definition.name}"
                     end

        write "#{runtime_fn}("
        @expression_codegen.emit(arg)
        writeln ");"
        true
      end
    end
  end
end
