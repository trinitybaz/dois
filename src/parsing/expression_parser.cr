require "./literal_parser"
require "./pattern_parser"

module DoisC
  module Parsing
    module ExpressionParser
      include LiteralParser
      include PatternParser

      private def parse_expression(precedence = 0) : Expression
        left = parse_prefix

        until eof?
          # Chained field / property access
          if match?(TokenType::PERIOD)
            field = parse_variable_identifier
            left = AccessExpression.new(left, field, field.source_location)
            next
          end
          # Procedure call
          if peek.type == TokenType::L_PAREN
            left = parse_procedure_call(left, left.source_location)
          end
          # Function call
          if match?(TokenType::FN_APPLY)
            left = parse_function_call(left, left.source_location)
          end

          break unless binary_operator?(peek) || assign_operator?(peek)
          break if precedence > precedence_of(peek.type)

          operator = advance
          right = parse_expression(precedence_of(operator.type))
          left = parse_binary_expression(left, operator, right)
        end

        left
      end

      private def parse_variable_identifier : Identifier
        token = consume(TokenType::IDENTIFIER, "expected identifier")
        first_name = token.lexeme
        module_names = [] of String
        accessor_names = [] of String
        name = first_name

        if peek.type == TokenType::DOUBLE_COLON # if we have module names to parse...
          module_names << first_name
          while match?(TokenType::DOUBLE_COLON)
            next_name = consume(TokenType::IDENTIFIER, "expect identifier").lexeme
            if peek.type == TokenType::DOUBLE_COLON
              module_names << next_name
            else
              name = next_name # last id after :: is the identifier name
            end
          end
        end

        while match?(TokenType::PERIOD)
          accessor_names << consume(TokenType::IDENTIFIER, "expect identifier for accessor name").lexeme
        end
        Identifier.new(name, module_names, accessor_names, location(token))
      end

      private def parse_binary_expression(left : Expression, operator : Token, right : Expression) : Expression
        if assign_operator?(operator)
          var_expr = begin
            left.as(IdentifierExpression)
          rescue
            raise error("left side of assignment operator must be a variable", operator)
          end
          var_id = var_expr.identifier
          if operator.type == TokenType::EQ
            Reassignment.new(var_id, right, var_id.source_location)
          else
            operator.type = desugar_assign_operator(operator.type)
            parsed_operator = parse_operator(operator)
            binary_expr = BinaryExpression.new(var_expr, parsed_operator, right, var_id.source_location)
            Reassignment.new(var_id, binary_expr, var_id.source_location)
          end
        else
          BinaryExpression.new(left, parse_operator(operator), right, left.source_location)
        end
      end

      private def parse_operator(operator : Token) : Operator
        operator_type = case operator.type
                        when TokenType::ADD
                          OperatorType::ADD
                        when TokenType::SUB
                          OperatorType::SUB
                        when TokenType::MUL
                          OperatorType::MULT
                        when TokenType::DIV
                          OperatorType::DIV
                        when TokenType::COMP_EQ
                          OperatorType::EQ
                        when TokenType::COMP_LT
                          OperatorType::LT
                        else
                          raise error("unsupported operator '#{operator.lexeme}'", operator)
                        end

        Operator.new(operator_type)
      end

      private def parse_prefix : Expression
        case peek.type
        when TokenType::INT_LITERAL, TokenType::FLOAT_LITERAL, TokenType::STRING_LITERAL,
             TokenType::CHAR_LITERAL, TokenType::TRUE, TokenType::FALSE, TokenType::NIL,
             TokenType::L_BRACK, TokenType::L_BRACE
          parse_literal
        when TokenType::IDENTIFIER
          parse_identifier_expression
        when TokenType::IF
          parse_if_expression
        when TokenType::MATCH
          parse_match_expression
        when TokenType::NOT, TokenType::SUB
          operator = advance
          right = parse_expression(EXPR_PRECEDENCE[:UNARY])
          UnaryExpression.new(operator.type, right, location(operator))
        when TokenType::L_PAREN
          l_paren_token = advance
          expr = parse_expression
          if match?(TokenType::COMMA)
            expr = parse_tuple_literal(expr, location(l_paren_token))
          else
            consume(TokenType::R_PAREN, "expected ')' to match '(' in expression")
            expr
          end
        else
          raise error("invalid token in expression", peek)
        end
      end

      private def parse_identifier_expression : Expression
        variable = parse_variable_identifier
        identifier_expr = IdentifierExpression.new(variable, variable.source_location)

        if peek.type == TokenType::L_PAREN
          parse_procedure_call(identifier_expr, variable.source_location)
        elsif match?(TokenType::FN_APPLY)
          parse_function_call(identifier_expr, variable.source_location)
        else
          identifier_expr
        end
      end

      private def desugar_assign_operator(type : TokenType) : TokenType
        token_type = DESUGARED_ASSIGN_OPERATORS[type]?
        return token_type if token_type
        TokenType::EOF # fallback so we have some tokentype to return, should never happen
      end

      private def parse_procedure_call(callee : Expression, location : SourceLocation) : ProcedureCall
        arguments = parse_arguments
        ProcedureCall.new(callee, arguments, location)
      end

      private def parse_function_call(callee : Expression, location : SourceLocation) : FunctionCall
        arguments = parse_arguments
        FunctionCall.new(callee, arguments, location)
      end

      private def parse_arguments : Array(Expression)
        arguments = [] of Expression
        if match?(TokenType::L_PAREN)
          unless peek.type == TokenType::R_PAREN
            arguments << parse_expression
            while match?(TokenType::COMMA)
              arguments << parse_expression
            end
          end
          consume(TokenType::R_PAREN, "expected ')' to end args in expression")
        end
        arguments
      end

      private def parse_if_expression : IfExpression
        branches = [] of IfBranch(Expression)

        if_token = consume(TokenType::IF, "expected 'if' to start if expression")
        condition = parse_expression
        then_token = consume(TokenType::THEN, "expected 'then' after if condition")
        body = parse_expression
        branches << IfBranch.new(condition, body, location(then_token))

        while peek.type == TokenType::ELIF
          advance # TokenType::ELIF
          condition = parse_expression
          then_token = consume(TokenType::THEN, "expected 'then' after elif condition")
          body = parse_expression
          branches << IfBranch.new(condition, body, location(then_token))
        end

        else_body = if peek.type == TokenType::ELSE
                      advance # TokenType::ELSE
                      parse_expression
                    end

        consume(TokenType::END, "expected 'end' to end if expression")

        IfExpression.new(branches, else_body, location(if_token))
      end

      private def parse_infix(left : Expression) : Expression
        operator = advance
        precedence = EXPR_PRECEDENCE[operator.type]
        right = parse_expression(precedence)

        BinaryExpression.new(left, parse_operator(operator), right, left.source_location)
      end

      private def precedence_of(type : TokenType) : Int32
        EXPR_PRECEDENCE[type]? || 0
      end

      private def binary_operator?(token : Token) : Bool
        BINARY_OPERATORS.includes?(token.type)
      end

      private def assign_operator?(token : Token) : Bool
        ASSIGN_OPERATORS.includes?(token.type)
      end
    end
  end
end
