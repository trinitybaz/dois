require "./declaration_parser"
require "./pattern_parser"

# require "../ast_data/token"

module DoisC
  module Parsing
    module ProcedureParser
      include DeclarationParser
      include PatternParser

      private def parse_procedure(*delimiters) : Procedure
        statements = [] of Statement
        until delimiters.includes?(peek.type)
          statement = parse_statement
          statements << statement if statement
        end
        Procedure.new(statements, location(peek))
      end

      private def parse_statement : Statement?
        return parse_binding if match?(TokenType::LET)
        return parse_var_declaration if match?(TokenType::VAR)
        return parse_while_loop if peek.type == TokenType::WHILE
        return parse_function_declaration if peek.type == TokenType::FN
        return parse_type_declaration if peek.type == TokenType::TYPE
        return parse_module_declaration if peek.type == TokenType::MODULE

        if token = match?(TokenType::IF)
          if match?(TokenType::LET)
            return parse_if_let_statement(location(token))
          else
            return parse_if_statement(location(token))
          end
        end

        # special handle syntactic sugar making 'proc' before main optional
        if match?(TokenType::PROC) || peek.lexeme == "main"
          return parse_procedure_declaration
        end

        if token = match?(TokenType::BREAK) && match?(TokenType::SEMICOLON)
          Break.new(location(token))
        end

        parse_expression_statement
      end

      private def parse_expression_statement : ExpressionStatement
        expr = parse_expression
        consume(TokenType::SEMICOLON, "expected ';' after expression statement")
        ExpressionStatement.new(expr, expr.source_location)
      end

      private def parse_var_reassignment : ExpressionStatement
        variable = parse_variable
        consume(TokenType::EQ, "expected '=' for variable reassignment")
        value_expr = parse_expression
        consume(TokenType::SEMICOLON, "expected ';' after assigning value")
        ExpressionStatement.new(
          VarReassignment.new(variable, value_expr)
        )
      end

      private def parse_if_statement(location : SourceLocation) : IfStatement
        branches = [] of IfBranch(Procedure)

        condition = parse_expression
        do_token = consume(TokenType::DO, "expected 'do' after if condition")
        body = parse_procedure(TokenType::ELSE, TokenType::ELIF, TokenType::END)
        branches << IfBranch.new(condition, body, location(do_token))

        while peek.type == TokenType::ELIF
          advance # TokenType::ELIF
          condition = parse_expression
          do_token = consume(TokenType::DO, "expected 'do' after elif condition")
          body = parse_procedure(TokenType::ELSE, TokenType::ELIF, TokenType::END)
          branches << IfBranch.new(condition, body, location(do_token))
        end

        else_body = if peek.type == TokenType::ELSE
                      advance # TokenType::ELSE
                      parse_procedure(TokenType::END)
                    end
        consume(TokenType::END, "expected 'end' to end if statement")

        IfStatement.new(branches, else_body, location)
      end

      private def parse_while_loop
        token = consume(TokenType::WHILE, "expected `while` to begin while loop`")
        condition = parse_expression
        consume(TokenType::DO, "expected 'do' after condition")
        body = parse_procedure(TokenType::END)
        consume(TokenType::END, "expected 'end' to end while loop")
        WhileLoop.new(condition, body, location(token))
      end
    end
  end
end
