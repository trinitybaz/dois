# require "../ast_data/token"
# require "../ast_data/pattern"

module DoisC
  module Parsing
    module PatternParser
      private def parse_if_let_statement(location : SourceLocation) : IfLetStatement
        pattern = parse_pattern
        consume(TokenType::EQ, "expected `=` to pattern match in `if let`")
        scrutinee = parse_expression
        consume(TokenType::DO, "expected `do` in before `if let` body")
        body = parse_procedure(TokenType::ELSE, TokenType::END)
        else_body = if match?(TokenType::ELSE)
                      parse_procedure(TokenType::END)
                    end
        consume(TokenType::END, "expected `end` to end `if let` statement")

        IfLetStatement.new(pattern, scrutinee, body, else_body, location)
      end

      private def parse_match_expression : MatchExpression
        match_token = consume(TokenType::MATCH, "expected `match` to begin match expression")
        scrutinee = parse_expression

        then_token = consume(TokenType::THEN, "expected `then` before branches in match expression")
        branches = [] of MatchBranch
        branches << parse_match_branch(location(then_token))
        while comma_token = match?(TokenType::COMMA)
          branches << parse_match_branch(location(comma_token))
        end
        consume(TokenType::END, "expected `end` to end `match` expression")
        MatchExpression.new(scrutinee, branches, location(match_token))
      end

      private def parse_match_branch(location : SourceLocation) : MatchBranch
        pattern = parse_pattern
        consume(TokenType::ARROW, "expected `=>` after pattern match")
        body = parse_expression
        MatchBranch.new(pattern, body, location)
      end

      private def parse_pattern : Pattern
        token = peek
        case token.type
        when TokenType::INT_LITERAL, TokenType::FLOAT_LITERAL, TokenType::STRING_LITERAL,
             TokenType::CHAR_LITERAL, TokenType::TRUE, TokenType::FALSE, TokenType::NIL,
             TokenType::L_BRACK, TokenType::L_BRACE
          literal = parse_literal
          LiteralPattern.new(literal, literal.source_location)
        when TokenType::UNDERSCORE
          WildCardPattern.new(location(advance))
        when TokenType::L_PAREN
          parse_tuple_pattern
        when TokenType::IDENTIFIER
          name = token.lexeme
          if name[0].ascii_uppercase? # type variant like (value = Nil)
            parse_variant_pattern
          else # binding like (value = x)
            BindingPattern.new(token.lexeme, location(advance))
          end
        else
          raise error("expected pattern", peek)
        end
      end

      private def parse_tuple_pattern : TuplePattern
        token = consume(TokenType::L_PAREN, "expected '(' to begin tuple match expression")
        patterns = [] of Pattern
        patterns << parse_pattern
        while match?(TokenType::COMMA)
          patterns << parse_pattern
        end
        consume(TokenType::R_PAREN, "expected ')' to end tuple match expression")
        TuplePattern.new(patterns, location(token))
      end

      private def parse_variant_pattern : VariantPattern
        token = consume(TokenType::IDENTIFIER, "expected type variant name in if let pattern match")
        variant_name = token.lexeme
        field_patterns = parse_field_patterns
        VariantPattern.new(variant_name, field_patterns, location(token))
      end

      private def parse_field_patterns : Array(NamedFieldPattern)
        field_patterns = [] of NamedFieldPattern
        if match?(TokenType::L_PAREN)
          field_patterns << parse_field_pattern
          while match?(TokenType::COMMA)
            field_patterns << parse_field_pattern
          end
          consume(TokenType::R_PAREN, "expected `)` to end field patterns")
        end
        field_patterns
      end

      private def parse_field_pattern : NamedFieldPattern
        field_token = consume(TokenType::IDENTIFIER, "expected field name in pattern match")
        field_name = field_token.lexeme

        token = consume(TokenType::EQ, "expected `=` after pattern in field deconstruction")
        pattern = parse_pattern
        NamedFieldPattern.new(field_name, pattern, location(token))
      end
    end
  end
end
