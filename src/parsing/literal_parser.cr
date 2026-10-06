# require "../ast_data/token"
require "../ast_data/ast"

module DoisC
  module Parsing
    module LiteralParser
      private def parse_literal : Literal
        token = advance

        case token.type
        when TokenType::INT_LITERAL
          value = token.lexeme.to_i128
          IntLiteral.new(value, location(token))
        when TokenType::FLOAT_LITERAL
          value = token.lexeme.to_f64
          FloatLiteral.new(value, location(token))
        when TokenType::STRING_LITERAL
          StringLiteral.new(token.lexeme, location(token))
        when TokenType::CHAR_LITERAL
          CharLiteral.new(token.lexeme[0], location(token))
        when TokenType::TRUE
          BoolLiteral.new(true, location(token))
        when TokenType::FALSE
          BoolLiteral.new(false, location(token))
        when TokenType::NIL
          NilLiteral.new(nil, location(token))
        when TokenType::L_BRACK
          parse_array_literal(location(token))
        when TokenType::L_BRACE
          parse_map_literal(location(token))
        else
          raise error("unexpected literal type #{token.lexeme}", token)
        end
      end

      def parse_array_literal(location : SourceLocation) : ArrayLiteral
        items = [] of Expression
        unless peek.type == TokenType::R_BRACK
          items << parse_expression
          while match?(TokenType::COMMA)
            items << parse_expression
          end
        end
        consume(TokenType::R_BRACK, "expected ] to end array literal")
        ArrayLiteral.new(items, location)
      end

      def parse_map_literal(location : SourceLocation) : MapLiteral
        mapping = Hash(Expression, Expression).new
        unless peek.type == TokenType::R_BRACE
          key = parse_expression
          consume(TokenType::ARROW, "expected =>, set literals not supported")
          mapping[key] = parse_expression

          while match?(TokenType::COMMA)
            key = parse_expression
            consume(TokenType::ARROW, "expected =>, set literals not supported")
            mapping[key] = parse_expression
          end
        end
        consume(TokenType::R_BRACE, "expected } to end map literal")
        MapLiteral.new(mapping, location)
      end

      def parse_tuple_literal(first_expression : Expression, location : SourceLocation) : TupleLiteral
        items = [first_expression]
        unless peek.type == TokenType::R_PAREN
          items << parse_expression
          while match?(TokenType::COMMA)
            items << parse_expression
          end
        end
        consume(TokenType::R_PAREN, "expected ')' to end tuple literal")

        TupleLiteral.new(items, location)
      end
    end
  end
end
