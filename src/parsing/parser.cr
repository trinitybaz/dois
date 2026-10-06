# require "./expression_parser"
# require "./procedure_parser"
# require "../ast_data/token"
# require "../ast_data/ast"
# require "./parse_error"
# require "./lexer"
require "../ast_data/ast"
require "./lexer"
require "./parse_error"
require "./expression_parser"
require "./procedure_parser"

module DoisC
  module Parsing
    include ASTData

    class Parser
      include ExpressionParser
      include ProcedureParser
      # TODO this getter is here for peeking at tokens from lexer output / debugging
      getter tokens : Array(Token)

      def initialize(source : String)
        @tokens = Lexer.new(source).lex
        @current = 0
      end

      def parse : ASTData::AST
        ASTData::AST.new(parse_module_declaration)
      end

      private def match?(type : TokenType) : Token?
        advance unless eof? || peek.type != type
      end

      private def consume(type : TokenType, message : String) : Token
        if peek.type == type
          advance
        else
          bad_token = peek
          raise error(message, bad_token)
        end
      end

      private def advance : Token
        token = @tokens[@current]
        @current += 1
        token
      end

      private def location(token : Token) : SourceLocation
        SourceLocation.new(token.line, token.column)
      end

      private def peek : Token
        @tokens[@current]
      end

      private def eof?
        peek.type == TokenType::EOF
      end

      # wrapper for passing line and column info on from token to node
      private def new_node(node : Node, token : Token) : Node
        node.line = token.line
        node.column = token.column
        node
      end

      private def error(message, bad_token : Token) : ParseError
        ParseError.new("#{bad_token.line}:#{bad_token.column} : unexpected #{bad_token.lexeme}, #{message}", bad_token.line, bad_token.column)
      end
    end
  end
end
