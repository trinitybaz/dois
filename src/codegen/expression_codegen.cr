require "../ast_data/*"
require "../types/*"

module DoisC
  module Codegen
    class ExpressionCodegen < BaseCodegen
      def initialize(@emitter : Emitter)
      end

      def emit(expr : ASTData::Expression)
        case expr
        when ASTData::IntLiteral
          write expr.value.to_s
        when ASTData::FloatLiteral
          write expr.value.to_s
        when ASTData::BoolLiteral
          write expr.value ? "true" : "false"
        when ASTData::StringLiteral
          emit_string_literal(expr)
        when ASTData::BinaryExpression
          emit_binary(expr)
        when ASTData::IdentifierExpression
          emit_identifier_expression(expr)
        when ASTData::FunctionCall
          emit_call(expr)
        when ASTData::ProcedureCall
          emit_call(expr)
        when ASTData::Reassignment
          emit_reassignment(expr)
        when ASTData::IfExpression
          emit_if_expression(expr)
        else
          raise "Unsupported expression codegen for #{expr.class}"
        end
      end

      private def emit_if_expression(expr : ASTData::IfExpression)
        expr.branches.each do |branch|
          write("(")
          emit(branch.condition)
          write(") ? ")
          emit(branch.body)
          write(" : ")
        end
        if body = expr.else_body
          emit(body)
        end
      end

      private def emit_binary(expr : ASTData::BinaryExpression)
        write "("
        emit(expr.left)
        write " "
        write expr.operator.to_s
        write " "
        emit(expr.right)
        write ")"
        # write "(#{left} #{expr.operator.to_s} #{right})"
      end

      private def emit_string_literal(expr : ASTData::StringLiteral)
        escaped = expr.value.gsub("\\", "\\\\").gsub("\"", "\\\"")
        write "\"#{escaped}\""
      end

      private def emit_identifier_expression(expr : ASTData::IdentifierExpression)
        identifier = expr.identifier

        base_name = if symbol_ref = identifier.symbol_ref
                      sanitize_name(symbol_ref.mangled_name)
                    else
                      sanitize_name(identifier.name)
                    end

        write base_name

        identifier.accessor_names.each do |accessor|
          write "."
          write sanitize_name(accessor)
        end
      end

      private def emit_call(expr : ASTData::Call)
        if constructor_call?(expr)
          emit_constructor_call(expr)
          return
        end

        emit(expr.callee)
        write "("
        expr.arguments.each_with_index do |arg, index|
          write ", " if index > 0
          emit(arg)
        end
        write ")"
      end

      private def constructor_call?(expr : ASTData::Call) : Bool
        callee = expr.callee
        return false unless callee.is_a?(ASTData::IdentifierExpression)

        resolved_type = expr.resolved_type
        return false unless resolved_type.is_a?(Types::NominalType)

        callee.identifier.name == resolved_type.definition.name
      end

      private def emit_constructor_call(expr : ASTData::Call)
        resolved_type = expr.resolved_type.as(Types::NominalType)
        struct_name = sanitize_name(resolved_type.definition.name)

        write "(struct #{struct_name}){"
        expr.arguments.each_with_index do |arg, index|
          write ", " if index > 0
          emit(arg)
        end
        write "}"
      end

      private def emit_reassignment(expr : ASTData::Reassignment)
        write sanitize_name(expr.identifier.to_s)
        write " = "
        emit(expr.value)
      end

      private def sanitize_name(name : String) : String
        name.gsub(/[^a-zA-Z0-9_]/, "_")
      end
    end
  end
end
